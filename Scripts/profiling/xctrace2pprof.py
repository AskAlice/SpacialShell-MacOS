#!/usr/bin/env python3
"""Instruments Time Profiler -> pprof (#140). No dependencies beyond Python 3.

    Scripts/profiling/xctrace2pprof.py TRACE_OR_XML OUT.pb.gz [--process NAME] [--thread SUBSTR]
                                       [--signpost NAME [--signposts XML]]

TRACE_OR_XML is a `.trace` from `xctrace record --template 'Time Profiler'` (exported here with
`xcrun xctrace export`), or the XML of its time-profile table, exported by hand:

    xcrun xctrace export --input run.trace \\
        --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > tp.xml

OUT is a gzipped profile.proto (github.com/google/pprof/blob/main/proto/profile.proto), which
`go tool pprof` and speedscope open. Two sample types: `samples/count` and `cpu/nanoseconds` (the
sample's weight, 1 ms per sample by default). Each sample carries `thread` and `state` labels, so
`go tool pprof -tagfocus thread='Main Thread' …` narrows to the main thread.

--process keeps samples whose process matches NAME (e.g. SpacialShell); --thread keeps threads
whose name contains SUBSTR (e.g. 'Main Thread'). --signpost keeps only samples inside that
signpost's intervals (Begin/End pairs from the os-signpost table: from the .trace, or --signposts
with its exported XML), so a profile covers just the work being measured. A summary goes to stderr.
"""
import argparse
import gzip
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

TP_XPATH = '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'
SP_XPATH = '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]'


def export(trace, xpath):
    fd, path = tempfile.mkstemp(suffix=".xml")
    os.close(fd)
    with open(path, "wb") as f:
        subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath], stdout=f, check=True)
    return path


# ---- xctrace XML -------------------------------------------------------------------------------
# Every value is written once with id="N" and referenced after that as <tag ref="N"/>, across the
# whole document, so values are resolved into a table as rows stream past.

def rows(path):
    """Yields each <row> as {tag: value}; values resolved through the id/ref table."""
    table = {}

    def val(el):
        ref = el.get("ref")
        if ref is not None:
            return table[ref]
        tag = el.tag
        if tag == "binary":
            v = (el.get("name") or "?", el.get("path") or el.get("name") or "?", el.get("UUID") or "",
                 int(el.get("load-addr") or "0", 16))
        elif tag == "frame":
            b = next((val(c) for c in el if c.tag == "binary"), None)
            addr = int(el.get("addr") or "0", 16)
            v = (el.get("name") or hex(addr), addr, b)
        elif tag == "backtrace":
            v = [val(c) for c in el if c.tag == "frame"]
        elif tag == "tagged-backtrace":
            v = next((val(c) for c in el if c.tag == "backtrace"), [])
        elif tag in ("thread", "process", "thread-state", "core", "signpost-name", "event-type", "category",
                     "subsystem", "string"):
            for c in el:   # register nested ids (tid, pid, …) for later refs
                val(c)
            v = el.get("fmt") or (el.text or "")
        elif tag in ("sample-time", "event-time", "weight", "os-signpost-identifier", "tid", "pid", "uint64"):
            for c in el:
                val(c)
            v = int(el.text or 0)
        else:
            for c in el:
                val(c)
            v = el.get("fmt") or (el.text or "")
        i = el.get("id")
        if i is not None:
            table[i] = v
        return v

    for _, el in ET.iterparse(path, events=("end",)):
        if el.tag != "row":
            continue
        out = {}
        for c in el:
            if c.tag == "sentinel":
                continue
            out.setdefault(c.tag, val(c))
        yield out
        el.clear()


def intervals(path, name, process):
    """[(start_ns, end_ns)] of every Begin/End pair of signpost NAME."""
    open_, out = {}, []
    for r in rows(path):
        if r.get("signpost-name") != name:
            continue
        if process and process not in str(r.get("process", "")):
            continue
        key = (r.get("os-signpost-identifier"), r.get("process"))
        kind, t = r.get("event-type"), r.get("event-time", 0)
        if kind == "Begin":
            open_[key] = t
        elif kind == "End" and key in open_:
            out.append((open_.pop(key), t))
    return sorted(out)


# ---- profile.proto -----------------------------------------------------------------------------

def varint(n):
    n &= (1 << 64) - 1
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def key(field, wire):
    return varint(field << 3 | wire)


def f_int(field, n):
    return key(field, 0) + varint(n) if n else b""


def f_bytes(field, b):
    return key(field, 2) + varint(len(b)) + b


def f_packed(field, ns):
    return f_bytes(field, b"".join(varint(n) for n in ns)) if ns else b""


class Profile:
    def __init__(self):
        self.strings = {"": 0}
        self.functions, self.locations, self.mappings = {}, {}, {}
        self.samples = []
        self.fn_msgs, self.loc_msgs, self.map_msgs = [], [], []

    def s(self, text):
        if text not in self.strings:
            self.strings[text] = len(self.strings)
        return self.strings[text]

    def mapping(self, binary):
        if binary is None:
            return 0
        name, path, uuid, load = binary
        k = (path, load)
        if k not in self.mappings:
            mid = len(self.mappings) + 1
            self.mappings[k] = mid
            self.map_msgs.append(f_int(1, mid) + f_int(2, load) + f_int(3, load + (1 << 32)) +
                                 f_int(5, self.s(path)) + f_int(6, self.s(uuid)) + f_int(7, 1))
        return self.mappings[k]

    def function(self, name, binary):
        k = (name, binary[1] if binary else "")
        if k not in self.functions:
            fid = len(self.functions) + 1
            self.functions[k] = fid
            self.fn_msgs.append(f_int(1, fid) + f_int(2, self.s(name)) + f_int(3, self.s(name)) +
                                f_int(4, self.s(k[1])))
        return self.functions[k]

    def location(self, frame):
        name, addr, binary = frame
        k = (addr, binary[1] if binary else "", name)
        if k not in self.locations:
            lid = len(self.locations) + 1
            self.locations[k] = lid
            line = f_int(1, self.function(name, binary))
            self.loc_msgs.append(f_int(1, lid) + f_int(2, self.mapping(binary)) + f_int(3, addr) + f_bytes(4, line))
        return self.locations[k]

    def add(self, stack, weight, labels):
        locs = [self.location(f) for f in stack]
        lab = b"".join(f_bytes(3, f_int(1, self.s(k)) + f_int(2, self.s(v))) for k, v in labels)
        self.samples.append(f_packed(1, locs) + f_packed(2, [1, weight]) + lab)

    def encode(self, duration_ns):
        st = [f_bytes(1, f_int(1, self.s("samples")) + f_int(2, self.s("count"))),
              f_bytes(1, f_int(1, self.s("cpu")) + f_int(2, self.s("nanoseconds")))]
        period_type = f_bytes(11, f_int(1, self.s("cpu")) + f_int(2, self.s("nanoseconds")))
        body = b"".join(st)
        body += b"".join(f_bytes(2, m) for m in self.samples)
        body += b"".join(f_bytes(3, m) for m in self.map_msgs)
        body += b"".join(f_bytes(4, m) for m in self.loc_msgs)
        body += b"".join(f_bytes(5, m) for m in self.fn_msgs)
        strings = sorted(self.strings.items(), key=lambda kv: kv[1])
        body += b"".join(key(6, 2) + varint(len(t.encode())) + t.encode() for t, _ in strings)
        body += f_int(10, duration_ns) + period_type + f_int(12, 1_000_000)
        return body


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--process")
    ap.add_argument("--thread")
    ap.add_argument("--signpost")
    ap.add_argument("--signposts", help="exported os-signpost table XML (when the input is XML)")
    a = ap.parse_args()

    trace = a.input.endswith(".trace")
    tp = export(a.input, TP_XPATH) if trace else a.input
    windows = None
    if a.signpost:
        sp = a.signposts or (export(a.input, SP_XPATH) if trace else None)
        if not sp:
            sys.exit("xctrace2pprof: --signpost needs a .trace input or --signposts XML")
        windows = intervals(sp, a.signpost, a.process)
        if not windows:
            sys.exit(f"xctrace2pprof: no '{a.signpost}' intervals in the trace")

    prof = Profile()
    kept = total = 0
    by_thread = {}
    t_min, t_max = None, None
    for r in rows(tp):
        total += 1
        t = r.get("sample-time", 0)
        proc, thread = str(r.get("process", "")), str(r.get("thread", ""))
        if a.process and not proc.startswith(a.process):
            continue
        if a.thread and a.thread not in thread:
            continue
        if windows is not None and not any(s <= t <= e for s, e in windows):
            continue
        stack = r.get("tagged-backtrace") or r.get("backtrace") or []
        weight = int(r.get("weight", 1_000_000))
        tname = thread.split(" (")[0]
        prof.add(stack, weight, [("thread", tname), ("state", str(r.get("thread-state", "")))])
        kept += 1
        by_thread[tname] = by_thread.get(tname, 0) + weight
        t_min = t if t_min is None else min(t_min, t)
        t_max = t if t_max is None else max(t_max, t)

    span = (sum(e - s for s, e in windows) if windows else (t_max - t_min if kept else 0))
    with gzip.open(a.output, "wb") as f:
        f.write(prof.encode(span))
    print(f"xctrace2pprof: {kept} of {total} samples -> {a.output}", file=sys.stderr)
    if windows:
        print(f"xctrace2pprof: {len(windows)} '{a.signpost}' intervals, {span / 1e6:.1f} ms in all", file=sys.stderr)
    for name, w in sorted(by_thread.items(), key=lambda kv: -kv[1])[:8]:
        share = f", {100 * w / span:.1f}% of the window" if span else ""
        print(f"  {name}: {w / 1e6:.1f} ms cpu{share}", file=sys.stderr)


if __name__ == "__main__":
    main()
