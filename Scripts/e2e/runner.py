#!/usr/bin/env python3
"""SpacialShell end-to-end scenario runner (#38). Stdlib only.

Drives the *running* shell through `spacialctl` and asserts on `spacialctl state` JSON, on-screen
windows (CGWindowList via cgwindows.js) and screenshots compared to references (imgdiff.swift).
It runs identically on this Mac (--mode host) and inside a Tart guest (--mode vm, via
guest/run.sh); the mode only picks the reference set and the artefact labels.

Scenario format (`scenarios/*.scn`): one step per line, `#` comments, shell-style quoting.

    open N as G          launch a fresh TextEdit instance (`open -n -F`) on N scratch files;
                         its windows are G1..GN (by window id), its pid is the group G
    run CMD              spacialctl run CMD
    focus W              bring W's workspace forward (focus-screen-next, focus-workspace-N)
    settle               wait until two consecutive `state` reads agree (animations done)
    wait SECONDS
    fullscreen W on|off  native fullscreen via AX (axfullscreen.swift; needs Accessibility)
    note focused as X    bind X to the focused window
    note frame W as F    bind F to W's current model frame
    shot NAME [TOL] [region=X,Y,W,H] [1x] [thr=N]
                         screencapture the main display (or a region, in points); diff against the
                         reference if one exists. `1x` stores it at one pixel per point (a quarter
                         of the bytes); `thr` is imgdiff's per-channel threshold (default 24/255)
    slide NAME CMD [AT] [shot options]
                         spacialctl run CMD, then a shot AT seconds (default 3) after the switch
                         overlay appears; needs the motion stretched first (SpacialMotionScale)
    record NAME SECS [FPS]  record the screen to NAME/ in the background for SECS (#8);
                         the scenario waits for it at the end
    input ARGS...        synthetic pointer/keys (input.swift); a group name, `shell` or
                         `pid:NAME` as an argument is replaced by that pid; a trailing `?`
                         makes the step best effort
    sh LINE              the rest of the line through /bin/sh, unparsed (config files, defaults) —
                         vm mode only
    relaunch             quit and reopen SpacialShell, wait for its socket — vm mode only
    appearance dark|light  switch the session's appearance (appearance.swift) — vm mode only
    expect CHECK ARGS    see CHECKS below (check_* methods); a failure is recorded, the run goes on
    require CHECK ARGS   the same, but a failure stops the scenario (use before driving focus)

A failed `expect`, `shot` or `slide` fails the scenario and the run goes on; any other failed step
stops it. Either way the runner cleans up: it kills only the TextEdit
instances it launched, deletes its scratch files, and puts the focused screen and workspace back.
"""
import argparse, json, os, shlex, shutil, signal, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CTL = os.environ.get("SPACIALCTL", "/Applications/SpacialShell.app/Contents/MacOS/spacialctl")


class Fail(Exception):
    pass


def sh(*cmd, check=True, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if check and r.returncode != 0:
        raise Fail(f"{' '.join(cmd)} -> {r.returncode}: {r.stderr.strip()}")
    return r.stdout


def state():
    return json.loads(sh(CTL, "state"))


def windows(st):
    """Flatten state into {window id: row}, each row tagged with its screen and workspace."""
    out = {}
    for s in st["screens"]:
        for i, ws in enumerate(s["workspaces"]):
            for w in ws["windows"]:
                out[w["id"]] = dict(w, screen=s["display"], wsIndex=i, ws=ws,
                                    screenFocused=s["isFocused"])
    return out


def focused_ws(st):
    s = next(s for s in st["screens"] if s["isFocused"])
    return s["display"], s["workspaces"][s["activeIndex"]]["id"]


def cg_windows():
    return json.loads(sh("osascript", "-l", "JavaScript", os.path.join(HERE, "cgwindows.js")))


def intersects(a, b):
    return (a["X"] < b["X"] + b["Width"] and b["X"] < a["X"] + a["Width"]
            and a["Y"] < b["Y"] + b["Height"] and b["Y"] < a["Y"] + a["Height"])


class Run:
    def __init__(self, name, mode, out, record):
        self.name, self.mode, self.out, self.record = name, mode, out, record
        self.vars = {}          # scenario name -> window id / frame
        self.pids = {}          # group -> pid
        self.tmp = tempfile.mkdtemp(prefix=f"spacial-e2e-{name}-")
        self.transcript = open(os.path.join(out, "state.ndjson"), "w")
        self.failures = []
        self.recordings = []    # background record.swift processes
        self.held = None        # a drag holding the button down (input.swift)

    # --- helpers -------------------------------------------------------------------------------
    def log(self, msg):
        print(f"[{self.name}] {msg}", flush=True)

    def snap(self, label):
        st = state()
        self.transcript.write(json.dumps({"step": label, "t": time.time(), "state": st}) + "\n")
        self.transcript.flush()
        return st

    def win(self, name):
        wid = self.vars.get(name)
        if not isinstance(wid, int):
            raise Fail(f"unknown window {name!r}")
        row = windows(state()).get(wid)
        if row is None:
            raise Fail(f"{name} (id {wid}) is not in the model — it lost its tab")
        return row

    # --- steps ---------------------------------------------------------------------------------
    def step_open(self, n, _as, group):
        n = int(n)
        files = []
        for i in range(1, n + 1):
            p = os.path.join(self.tmp, f"{group}{i}.txt")
            with open(p, "w") as f:
                f.write(f"SpacialShell e2e scratch window {group}{i}\n")
            files.append(p)
        before = set(sh("pgrep", "-x", "TextEdit", check=False).split())
        # -n: a new instance of our own, so the user's TextEdit (and its documents) is never
        # touched and cleanup can kill exactly this pid. -F: no restored windows.
        sh("open", "-n", "-F", "-a", "TextEdit", *files)
        pid = None
        for _ in range(60):
            new = set(sh("pgrep", "-x", "TextEdit", check=False).split()) - before
            if new:
                pid = int(sorted(new)[0])
                break
            time.sleep(0.25)
        if pid is None:
            raise Fail("TextEdit did not launch")
        self.pids[group] = pid
        for _ in range(80):
            mine = sorted(w for w, r in windows(state()).items() if r["pid"] == pid)
            if len(mine) >= n:
                break
            time.sleep(0.25)
        else:
            raise Fail(f"shell adopted {len(mine)}/{n} windows of pid {pid}")
        for i, wid in enumerate(mine[:n], 1):
            self.vars[f"{group}{i}"] = wid
        self.log(f"opened {group}1..{group}{n} = {mine[:n]} (pid {pid})")

    def step_run(self, cmd):
        sh(CTL, "run", cmd)

    def step_focus(self, name):
        """Bring W's workspace forward the way a user would: focus its screen, then Fn+<n>.
        A launched app does not pull its row forward by itself."""
        row = self.win(name)
        for _ in state()["screens"]:
            if focused_ws(state())[0] == row["screen"]:
                break
            sh(CTL, "run", "focus-screen-next")
            time.sleep(0.3)
        # Fn+N on the workspace already active flips back to the previous one (#106), and a
        # freshly opened window has usually brought its workspace forward already.
        if focused_ws(state())[1] == row["ws"]["id"]:
            return
        if row["wsIndex"] >= 10:
            raise Fail(f"{name} is in workspace {row['wsIndex'] + 1}; only 1-10 have a command")
        sh(CTL, "run", f"focus-workspace-{row['wsIndex'] + 1}")

    def step_wait(self, secs):
        time.sleep(float(secs))

    def step_settle(self, timeout="10"):
        time.sleep(0.3)
        prev, deadline = None, time.time() + float(timeout)
        while time.time() < deadline:
            cur = state()["screens"]
            if cur == prev:
                return
            prev = cur
            time.sleep(0.3)
        raise Fail(f"state did not settle within {timeout}s")

    def step_fullscreen(self, name, onoff):
        # Straight AX (axfullscreen.swift), not System Events: needs Accessibility only, no
        # Automation grant (which tccd will not take from a TCC.db row in the Tart guest).
        sh(tool("axfullscreen"), str(self.win(name)["pid"]), onoff)
        time.sleep(1.5)   # the Space transition animation

    def step_note(self, what, *rest):
        if what == "focused" and rest[0] == "as":
            f = [w for w, r in windows(state()).items() if r["isFocused"]]
            if not f:
                raise Fail("nothing focused")
            self.vars[rest[1]] = f[0]
        elif what == "frame" and rest[1] == "as":
            self.vars[rest[2]] = self.win(rest[0])["frame"]
        else:
            raise Fail(f"bad note: {what} {rest}")

    def step_shot(self, name, *opts):
        tol, region, onex, thr = "0.01", None, False, "24"
        for o in opts:
            if o.startswith("region="):
                region = o[len("region="):]
            elif o == "1x":
                onex = True
            elif o.startswith("thr="):
                thr = o[len("thr="):]
            else:
                tol = o
        self.dismiss_capture_prompt()
        png = os.path.join(self.out, f"{name}.png")
        sh("screencapture", "-x", "-m", *(["-R" + region] if region else []), png)
        if onex:   # the capture is at the backing scale; store one pixel per point
            pts = int(region.split(",")[2]) if region else int(self.main_width())
            sh("sips", "--resampleWidth", str(pts), png)
        self.compare(name, png, tol, thr)

    def dismiss_capture_prompt(self):
        """replayd's "bypass the system private window picker" alert for the shell. guest/run.sh
        pre-approves it, yet after an hour or so of captures in one guest it can still come up
        (a CFUserNotification) and would sit in every shot after it. Allow it, and say so."""
        for c in cg_windows():
            if c["owner"] == "UserNotificationCenter" and self.mode == "vm":
                self.log("WARN: a screen-capture alert was up; pressing Allow")
                sh(tool("input"), "axclick", str(c["pid"]), "Allow", check=False)
                sh(tool("input"), "move", "600", "400")
                time.sleep(1)
                return

    def main_width(self):
        return json.loads(sh("osascript", "-l", "JavaScript", "-e",
                             'ObjC.import("AppKit"); JSON.stringify($.NSScreen.mainScreen.frame.size.width)'))

    def step_slide(self, name, cmd, at="3", *opts):
        """A frame from the middle of CMD's switch animation (#77). A guest has no GPU and cannot
        record 200 ms of motion, so the scenario first stretches it (`SpacialMotionScale`, see
        SwitchOverlay) and this shoots AT seconds after the overlay appears."""
        before = {c["id"] for c in cg_windows() if c["owner"] == "SpacialShell"}
        sh(CTL, "run", cmd)
        deadline = time.time() + 15   # a cold capture takes seconds in the guest
        while not any(c["owner"] == "SpacialShell" and c["id"] not in before and c["b"]["Width"] > 400
                      for c in cg_windows()):
            if time.time() > deadline:
                raise Fail(f"slide {name}: no switch overlay appeared — the switch did not animate")
            time.sleep(0.05)
        time.sleep(float(at))
        self.step_shot(name, *opts)

    def step_record(self, name, secs, fps="15"):
        p = subprocess.Popen([tool("record"), os.path.join(self.out, name), secs, fps, "1024"],
                             stdout=subprocess.PIPE, text=True)
        if p.stdout.readline().strip() != "ready":
            p.kill()
            raise Fail("record did not start")
        self.recordings.append(p)

    def step_input(self, *argv):
        """A drag with a hold time runs in the background, so the steps after it (a shot of the
        drop indicator) happen mid-drag; the next `input` waits for it to let go."""
        if self.held:
            self.held.wait(timeout=60)
            self.held = None
        def resolve(a):
            if a == "shell":
                return sh("pgrep", "-x", "SpacialShell").split()[0]
            if a.startswith("pid:"):   # any app by process name, e.g. pid:Notes
                return (sh("pgrep", "-x", a[4:], check=False).split() or ["0"])[0]
            return str(self.pids[a]) if a in self.pids else a
        optional = argv[-1] == "?"   # best effort: `input axclick pid:Notes Continue ?`
        if optional:
            argv = argv[:-1]
        cmd = [tool("input"), *map(resolve, argv)]
        if argv[0] == "drag" and len(argv) == 6:
            self.held = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
            if self.held.stdout.readline().strip() != "holding":
                raise Fail("drag never reached its hold")
        else:
            sh(*cmd, check=not optional)

    def vm_only(self, what):
        if self.mode != "vm":
            raise Fail(f"{what} runs in the VM only: it would change this Mac")

    def step_sh(self, line):
        self.vm_only("sh")
        sh("/bin/sh", "-c", line)

    def step_appearance(self, mode):
        """Light or dark for the whole session, live (appearance.swift) — vm mode only."""
        self.vm_only("appearance")
        sh(tool("appearance"), mode)
        time.sleep(2)   # every app redraws

    def step_relaunch(self):
        self.vm_only("relaunch")
        app = os.path.dirname(os.path.dirname(os.path.dirname(CTL)))
        sh("pkill", "-x", "SpacialShell", check=False)
        for _ in range(40):
            if subprocess.run(["pgrep", "-x", "SpacialShell"], capture_output=True).returncode != 0:
                break
            time.sleep(0.25)
        # LaunchServices answers -600 for a moment after the old instance goes; keep asking.
        for _ in range(60):
            if subprocess.run([CTL, "version"], capture_output=True).returncode == 0:
                break
            subprocess.run(["open", app], capture_output=True)
            time.sleep(1)
        else:
            raise Fail("SpacialShell did not come back")
        time.sleep(2)   # first reconcile

    def compare(self, name, png, tol, thr):
        ref_dir = os.path.join(HERE, "references", self.mode, self.name)
        ref = os.path.join(ref_dir, f"{name}.png")
        if self.record:
            os.makedirs(ref_dir, exist_ok=True)
            shutil.copy(png, ref)
            self.log(f"recorded reference {os.path.relpath(ref, REPO)}")
            return
        if not os.path.exists(ref):
            self.log(f"shot {name}: no {self.mode} reference yet (run with --record)")
            return
        r = subprocess.run([tool("imgdiff"), ref, png, os.path.join(self.out, f"{name}.diff.png"), tol, thr],
                           capture_output=True, text=True)
        self.log(f"shot {name}: {r.stdout.strip()}")
        if r.returncode != 0:
            raise Fail(f"visual regression in {name}: {r.stdout.strip()} {r.stderr.strip()}")

    def step_expect(self, check, *args):
        getattr(self, "check_" + check.replace("-", "_"))(*args)

    step_require = step_expect   # same checks; a failure stops the scenario (guards host safety)

    # --- CHECKS --------------------------------------------------------------------------------
    def check_tab(self, w):
        """W is still a managed window in some workspace (it kept its tab)."""
        self.win(w)

    def check_focused(self, w):
        if not self.win(w)["isFocused"]:
            raise Fail(f"{w} is not focused")

    def check_active(self, w):
        """W's workspace is the active one on its screen."""
        if not self.win(w)["ws"]["isActive"]:
            raise Fail(f"{w}'s workspace is not active")

    def check_workspace(self, w, n):
        """W is in workspace N (1-based) of its screen."""
        if self.win(w)["wsIndex"] + 1 != int(n):
            raise Fail(f"{w} is in workspace {self.win(w)['wsIndex'] + 1}, not {n}")

    def check_same_workspace(self, *ws):
        ids = {self.win(w)["ws"]["id"] for w in ws}
        if len(ids) != 1:
            raise Fail(f"{' '.join(ws)} are split across workspaces")

    def check_workspace_count(self, w, n):
        c = self.win(w)["ws"]["windowCount"]
        if c != int(n):
            raise Fail(f"{w}'s workspace holds {c} windows, not {n} (foreign windows landed there?)")

    def check_layout(self, w, layout):
        got = self.win(w)["ws"]["layout"]
        if got != layout:
            raise Fail(f"{w}'s workspace layout is {got}, not {layout}")

    def check_parked(self, w):
        if not self.win(w)["isParked"]:
            raise Fail(f"{w} is not parked")

    def check_not_parked(self, w):
        if self.win(w)["isParked"]:
            raise Fail(f"{w} is parked")

    def check_fullscreen(self, w):
        if not self.win(w)["isFullscreen"]:
            raise Fail(f"{w} is not fullscreen in the model")

    def check_not_fullscreen(self, w):
        if self.win(w)["isFullscreen"]:
            raise Fail(f"{w} is still fullscreen in the model")

    def check_differs(self, *ws):
        ids = [self.vars[w] for w in ws]
        if len(set(ids)) != len(ids):
            raise Fail(f"{' '.join(ws)} are not distinct windows: {ids}")

    def check_frame(self, w, f, tol="2"):
        got, want = self.win(w)["frame"], self.vars[f]
        if not got or any(abs(a - b) > float(tol) for a, b in zip(got, want)):
            raise Fail(f"{w} frame {got} != {f} {want}")

    def _onscreen(self, w):
        pid = self.win(w)["pid"]
        return [c for c in cg_windows() if c["pid"] == pid
                and c["b"]["Width"] > 100 and c["b"]["Height"] > 100]

    def check_onscreen(self, w):
        """Never vanished: the model shows it and the window server has it on screen."""
        row = self.win(w)
        if row["isParked"] or row["isHidden"]:
            raise Fail(f"{w} is parked/hidden in the model")
        # ponytail: per-pid, not per-window (CG ids are not the model's ids). Exact for groups of
        # one; a multi-window group would need a CG-bounds-to-model-frame match.
        if not self._onscreen(w):
            raise Fail(f"{w}: no on-screen window for pid {row['pid']} — it vanished")

    def check_panels_hidden(self, w):
        """No shell panel (rail, tab bar) is drawn over W's on-screen window."""
        mine = self._onscreen(w)
        if not mine:
            raise Fail(f"{w} is not on screen")
        panels = [c for c in cg_windows() if c["owner"] == "SpacialShell" and c["alpha"] > 0]
        over = [p for p in panels for m in mine if intersects(p["b"], m["b"])]
        if over:
            raise Fail(f"shell panels drawn over fullscreen {w}: {[p['b'] for p in over]}")

    # --- driver --------------------------------------------------------------------------------
    def execute(self, lines):
        origin = focused_ws(self.snap("start"))
        try:
            for no, line in lines:
                words = shlex.split(line)
                self.log(f"{no:>3}: {line}")
                try:
                    if words[0] == "sh":   # the rest of the line goes to /bin/sh as written
                        self.step_sh(line[2:].strip())
                    else:
                        getattr(self, "step_" + words[0])(*words[1:])
                    self.snap(f"{no}: {line}")
                except Fail as e:
                    self.failures.append(f"line {no}: {line}\n      {e}")
                    self.log(f"FAIL {e}")
                    if words[0] not in ("expect", "shot", "slide"):
                        break   # a failed action leaves nothing meaningful to assert on
        finally:
            self.cleanup(origin)
        return not self.failures

    def cleanup(self, origin):
        if self.held:
            self.held.wait(timeout=60)
        for p in self.recordings:
            out, _ = p.communicate()
            self.log(f"recording: {out.strip()}")
        for pid in self.pids.values():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(1)
        for pid in self.pids.values():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        shutil.rmtree(self.tmp, ignore_errors=True)
        try:
            self.step_settle()
            display, wsid = origin
            st = state()
            for _ in st["screens"]:
                if focused_ws(st)[0] == display:
                    break
                sh(CTL, "run", "focus-screen-next")
                time.sleep(0.3)
                st = state()
            s = next(s for s in st["screens"] if s["display"] == display)
            idx = next((i for i, ws in enumerate(s["workspaces"]) if ws["id"] == wsid), None)
            if idx is not None and idx < 10:
                sh(CTL, "run", f"focus-workspace-{idx + 1}")
            self.step_settle()
            if focused_ws(state()) != origin:
                self.log("WARN: could not restore the focused workspace exactly")
            self.snap("restored")
        except Exception as e:
            self.log(f"WARN: restore failed: {e}")
        self.transcript.close()


def tool(name):
    """Compile Scripts/e2e/<name>.swift once into .build/e2e (no dependencies beyond the SDK)."""
    src = os.path.join(HERE, f"{name}.swift")
    exe = os.path.join(REPO, ".build", "e2e", name)
    if not os.path.exists(exe) or os.path.getmtime(exe) < os.path.getmtime(src):
        os.makedirs(os.path.dirname(exe), exist_ok=True)
        sh("swiftc", "-O", src, "-o", exe)
    return exe


def parse(path):
    with open(path) as f:
        return [(i, l.strip()) for i, l in enumerate(f, 1)
                if l.strip() and not l.strip().startswith("#")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["host", "vm"], required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--record", action="store_true", help="write screenshots as the new references")
    ap.add_argument("--check", action="store_true", help="parse scenarios only; touch nothing")
    ap.add_argument("scenarios", nargs="+")
    a = ap.parse_args()

    ok = True
    for path in a.scenarios:
        name = os.path.splitext(os.path.basename(path))[0]
        lines = parse(path)
        for no, line in lines:   # validate every step and check name before driving anything
            w = shlex.split(line)
            target = ("check_" + w[1].replace("-", "_")) if w[0] in ("expect", "require") else "step_" + w[0]
            if not hasattr(Run, target):
                sys.exit(f"{path}:{no}: unknown step {line!r}")
        if a.check:
            print(f"{path}: {len(lines)} steps OK")
            continue
        out = os.path.join(a.out, name)
        os.makedirs(out, exist_ok=True)
        r = Run(name, a.mode, out, a.record)
        with open(os.path.join(out, "shell.log"), "w") as logf:
            logs = subprocess.Popen(["log", "stream", "--style", "compact", "--info", "--predicate",
                                     'subsystem == "sh.emu.SpacialShell"'], stdout=logf,
                                    stderr=subprocess.DEVNULL)
            try:
                passed = r.execute(lines)
            finally:
                logs.terminate()
        print(f"\n== {name}: {'PASS' if passed else 'FAIL'}  (artefacts: {out})")
        for f in r.failures:
            print("   " + f)
        ok &= passed
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
