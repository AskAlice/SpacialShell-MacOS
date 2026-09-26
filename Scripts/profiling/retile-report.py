#!/usr/bin/env python3
"""The #140 (G13) table from one run of Scripts/e2e/scenarios/perf/retile.scn.

    Scripts/profiling/retile-report.py .build/e2e/vm-<stamp>/retile [--pprof docs/perf]

Reads, per N, what the scenario left in its artefact directory:
  retile-N<n>.log         the app's `retile N=…` lines (RetileProbe), one per measured re-tile
  retile-N<n>-screen/     a 60 fps ScreenCaptureKit recording (record.swift: frames + times.txt)
  retile-N<n>.trace       Instruments' Time Profiler, if the guest had xctrace
and prints a markdown table (median and worst of each measure). With --pprof, each trace becomes
DIR/retile-N<n>.pb.gz through xctrace2pprof.py: SpacialShell's samples inside the `retile`
signposts (command to landing), every thread, labelled by thread.

Dropped frames, two ways:
  app      the overlay's display link during the flight: a gap of k refresh periods between two
           ticks is k-1 frames the main thread did not get to (RetileProbe's `dropped`).
  screen   what the window server showed: the recording's frames arrive only when the screen
           changes, so one re-tile is one burst; at 60 Hz a 250 ms flight is 15 frames, and every
           gap longer than 1.5 periods inside a burst is a frame the display repeated.
"""
import argparse
import hashlib
import os
import re
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LINE = re.compile(r"retile N=(\d+) (.*)$")
FIELD = re.compile(r"([\w.]+)=(-?[\d.]+)")


def lines(path, n):
    """The pass's re-tiles that moved all `n` windows, and how many moved some other number (a
    layout that paged windows away under the size floor moves fewer, and would pass for cheap)."""
    out, other = [], 0
    for l in open(path, errors="replace"):
        m = LINE.search(l)
        if m and "abandoned" not in l:
            if int(m.group(1)) != n:
                other += 1
                continue
            out.append({k: float(v) for k, v in FIELD.findall(m.group(2))})
    return out, other


def abandoned(path):
    return sum(1 for l in open(path, errors="replace") if "retile N=" in l and "abandoned" in l)


def flights(times_txt, quiet=6, shortest=0.25, settle=0.9):
    """[(new frames, span s)] per flight in a record.swift recording.

    The guest's virtual display sends a frame about every refresh even when nothing moves, and an
    unchanged screen arrives byte for byte the same, so a flight is a run of frames whose content
    changes, ended by `quiet` unchanged frames in a row. Inside it, every unchanged frame is one
    the window server showed twice: a dropped frame at 60 Hz. Not flights: runs shorter than
    `shortest` (the overlay going up alone, the apps redrawing their resized windows after the
    landing, 150-170 ms), and anything starting in the first `settle` seconds (the recorder
    starting; the scenario waits 1 s before acting)."""
    d = os.path.dirname(times_txt)
    rows = [l.split() for l in open(times_txt) if l.strip()]
    prev, changes = None, []
    for name, t in rows:
        h = hashlib.md5(open(os.path.join(d, name), "rb").read()).digest()
        if h != prev:
            changes.append(float(t))
        prev = h
    out, cur = [], []
    for t in changes:
        if cur and t - cur[-1] > quiet / 60:
            out.append(cur)
            cur = []
        cur.append(t)
    if cur:
        out.append(cur)
    return [(len(c), c[-1] - c[0]) for c in out if c[-1] - c[0] >= shortest and c[0] >= settle]


def med(xs):
    return statistics.median(xs) if xs else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--pprof", help="write retile-N<n>.pb.gz here")
    a = ap.parse_args()

    rows = []
    for n in (2, 4, 8):
        log = os.path.join(a.dir, f"retile-N{n}.log")
        if not os.path.exists(log):
            print(f"retile-report: no {log}", file=sys.stderr)
            continue
        ms, other = lines(log, n)
        if other:
            print(f"retile-report: N={n}: {other} re-tiles moved a different number of windows (not counted)",
                  file=sys.stderr)
        r = {"n": n, "count": len(ms), "abandoned": abandoned(log)}
        for k in ("capture.total.ms", "capture.window.mean.ms", "capture.window.max.ms", "capture.backdrop.ms",
                  "firstFrame.ms", "shown.ms", "frames", "expected", "dropped", "maxGap.ms", "hz",
                  "mainCPU.ms", "wall.ms"):
            xs = [m[k] for m in ms if k in m]
            r[k] = (med(xs), max(xs) if xs else float("nan"))
        cpu = [100 * m["mainCPU.ms"] / m["wall.ms"] for m in ms if m.get("wall.ms")]
        r["mainCPU.%"] = (med(cpu), max(cpu) if cpu else float("nan"))
        rec = os.path.join(a.dir, f"retile-N{n}-screen", "times.txt")
        if os.path.exists(rec):
            fs = flights(rec)
            # A flight spanning s seconds at 60 Hz is round(60 s) + 1 refreshes.
            repeats = [max(0, round(span * 60) + 1 - new) for new, span in fs]
            fps = [(new - 1) / span for new, span in fs if span > 0]
            r["screen"] = (len(fs), med([new for new, _ in fs]), med(fps), med(repeats),
                           max(repeats) if repeats else 0)
        trace = os.path.join(a.dir, f"retile-N{n}.trace")
        if a.pprof and os.path.isdir(trace):
            os.makedirs(a.pprof, exist_ok=True)
            out = os.path.join(a.pprof, f"retile-N{n}.pb.gz")
            subprocess.run([sys.executable, os.path.join(HERE, "xctrace2pprof.py"), trace, out,
                            "--process", "SpacialShell", "--signpost", "retile"], check=True)
            r["pprof"] = out
        rows.append(r)

    def cell(r, k, fmt="{:.0f}"):
        m, w = r[k]
        return f"{fmt.format(m)} / {fmt.format(w)}"

    print("| N | re-tiles | capture total ms | capture per window ms (mean) | slowest window ms | backdrop ms "
          "| command → first frame ms | display-link ticks / expected | dropped (app) | on screen per flight "
          "| repeated frames per flight (screen) | main-thread CPU ms | main-thread CPU % |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        scr = r.get("screen")
        scr_frames = f"{scr[1]:.0f} new frames, {scr[2]:.0f} fps ({scr[0]} flights)" if scr else "—"
        scr_rep = f"{scr[3]:.0f} / {scr[4]}" if scr else "—"
        print(f"| {r['n']} | {r['count']} ({r['abandoned']} dropped) | {cell(r, 'capture.total.ms')} "
              f"| {cell(r, 'capture.window.mean.ms')} | {cell(r, 'capture.window.max.ms')} | {cell(r, 'capture.backdrop.ms')} "
              f"| {cell(r, 'firstFrame.ms')} | {r['frames'][0]:.0f} / {r['expected'][0]:.0f} "
              f"| {cell(r, 'dropped')} | {scr_frames} | {scr_rep} "
              f"| {cell(r, 'mainCPU.ms')} | {cell(r, 'mainCPU.%')} |")
    print("\nCells are median / worst. Refresh rate the display link reported: "
          + ", ".join(f"N={r['n']}: {r['hz'][0]:.0f} Hz" for r in rows))
    base = os.path.join(a.dir, "baseline-switch-screen", "times.txt")
    if os.path.exists(base):
        fs = flights(base)
        repeats = [max(0, round(span * 60) + 1 - new) for new, span in fs]
        fps = [(new - 1) / span for new, span in fs if span > 0]
        print(f"Baseline, a tab switch as it ships (200 ms, one window out, one in), same recorder: "
              f"{med([n for n, _ in fs]):.0f} new frames, {med(fps):.0f} fps per flight, "
              f"{med(repeats):.0f} / {max(repeats) if repeats else 0} repeated frames ({len(fs)} flights)")


if __name__ == "__main__":
    main()
