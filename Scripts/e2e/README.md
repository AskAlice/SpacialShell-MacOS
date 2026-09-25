# End-to-end scenarios (#38)

Runs the real shell, drives it through `spacialctl run <command>` (the same path a hotkey takes),
and checks three things: the model (`spacialctl state` JSON), the window server (on-screen windows
via CGWindowList), and screenshots diffed against references. The same scenarios run in two places:

| Mode | Where | Use it for |
|---|---|---|
| `--host` | the SpacialShell installed and running on this Mac | quick checks while developing; no references by default |
| `--vm` | a throwaway clone of a golden macOS guest under [Tart](https://tart.run) | deterministic screenshots, reference diffs, nothing on your screen |

```sh
Scripts/e2e/e2e.sh --check                      # parse every scenario, run nothing
Scripts/e2e/e2e.sh --host Scripts/e2e/scenarios/tabs.scn   # against the app running here
Scripts/e2e/e2e.sh --vm                         # every scenario, in a fresh guest
Scripts/e2e/e2e.sh --vm --record                # same, and write the screenshots as references
Scripts/e2e/e2e.sh --vm --dry-run               # print the tart commands only
```

No scenario argument means all of `scenarios/*.scn`. Exit status is non-zero when any check
fails. Artefacts go to `.build/e2e/<mode>-<timestamp>/<scenario>/`:

- `*.png` screenshots, and `*.diff.png` (differing pixels in red) when a reference exists
- `state.ndjson`: a `spacialctl state` snapshot after every step, labelled with the step
- `shell.log`: the unified log for `sh.emu.SpacialShell` while the scenario ran

## Decisions (the issue's open questions)

- **Local only.** No CI runner for now. `e2e.sh --vm` is one command, so a self-hosted runner
  could call it later.
- **Single display.** A Tart guest has one virtual display (set to 1920x1080 by `golden.sh`).
  Multi-display behaviour (#32, #33) stays with the manual checklist in `docs/testing.md`.
- **`TART_HOME` is configurable.** Tart keeps images and VMs under `TART_HOME` (default
  `~/.tart`). Point it at an external volume and both scripts follow it, including the disk
  check.
- **Licensing.** Apple's licence allows at most two macOS VMs per Mac. `e2e.sh --vm` runs one
  clone at a time and refuses to start when two VMs are already running.

## Disk

| What | Size |
|---|---|
| Base image pull (`ghcr.io/cirruslabs/macos-tahoe-base`), kept in `TART_HOME/cache` | ~25–30 GB compressed download, more once unpacked |
| Golden VM (`spacial-e2e-golden`) | disk file up to 60 GB, sparse |
| One run's clone | APFS copy-on-write, so only what the guest writes: a Swift build plus screenshots, a few GB. Deleted after the run unless `--keep` |

`golden.sh` refuses to pull with less than **80 GB** free under `TART_HOME`
(`SPACIAL_E2E_GOLDEN_MIN_FREE_GB`). `e2e.sh --vm` wants **15 GB** (`SPACIAL_E2E_MIN_FREE_GB`).
The pull can be deleted after `golden.sh` succeeds (`tart prune --entries=caches`); the golden VM
does not depend on it.

## Setup, VM mode (once)

```sh
brew install cirruslabs/cli/tart
TART_HOME=/Volumes/<external>/tart Scripts/e2e/golden.sh     # or omit TART_HOME with 80 GB free
```

`golden.sh` clones the base image (Homebrew, Command Line Tools, `tart-guest-agent`, auto-login as
`admin`/`admin`, SIP disabled), gives it 4 CPUs, 8 GB, one 1920x1080 display and 60 GB of disk,
then runs `guest/provision.sh` inside it:

- checks SIP is off (the per-run grants below write the system TCC database) and the Swift
  toolchain is present, installing the Command Line Tools if not
- turns off sleep, the screen saver, window restoration and Dock visibility, and sets a
  plain desktop, so nothing interrupts a scenario or changes a screenshot
- **bakes in the runner's TCC grants**: Accessibility and Screen Recording for
  `tart-guest-agent` (every `tart exec` command's responsible process), plus Apple Events from the
  agent and `osascript` to System Events for the `fullscreen` step. This follows the
  Cirrus templates' `update-tcc-database.sh`, which already grants most of these.

The **app's** grants (Accessibility and Screen Recording for `sh.emu.SpacialShell`) cannot be
baked in. The guest has no signing certificate, so `bundle.sh` signs ad hoc, and an ad-hoc
designated requirement is the cdhash, which changes on every build (see `Scripts/README`). So
`guest/run.sh` writes both rows on every run, using the build's own `csreq`, and then restarts
`tccd`.

## What a VM run does

1. `tart clone spacial-e2e-golden spacial-e2e-<pid>`
2. `tart run --no-graphics --dir=repo:<checkout>:ro --dir=out:<artefacts>`. The repo goes in
   read-only, and artefacts come out through the writable share, so nothing needs copying back.
3. `tart exec … guest/run.sh`, which copies the repo into the guest, runs `Scripts/bundle.sh`,
   installs the app to `/Applications`, writes the TCC rows, launches the app, waits for the
   control socket, then runs `runner.py --mode vm`
4. With `--record`, copies the new references into `Scripts/e2e/references/vm/`
5. `tart stop` and `tart delete` the clone (`--keep` leaves it for `tart run` / debugging)

## Host mode, and how it stays safe

`--host` uses the app already installed and running (`SPACIALCTL` overrides the `spacialctl` path)
and touches nothing of yours:

- Each `open` launches a **separate TextEdit instance** (`open -n -F`) on scratch files in a temp
  directory. Your own TextEdit and its documents are never touched, and cleanup kills exactly the
  pids it launched, then deletes the files.
- `require` checks stop a scenario before it drives focus through a row holding your windows
  (for example `require workspace-count t1 3`).
- At the end, even after a failure, the focused screen and focused workspace are put back by id.
- Screenshots are of the main display, so they contain whatever is on it. They stay in `.build/`
  (git-ignored). There are no host references unless you record some. Host screens differ too
  much between sessions for diffs to be useful, so visual regression is a VM-mode job.
- The `fullscreen` step drives AX through System Events, so the terminal needs Accessibility and
  Automation → System Events. `tabs.scn` does not need either.

## Scenario format

One step per line, `#` for comments, shell-style quoting. The full list is in `runner.py`'s
docstring. In short:

```
open 3 as t            # TextEdit instance with windows t1 t2 t3
focus t1               # bring t1's workspace forward (focus-screen-next / focus-workspace-N)
run focus-window-right # any spacialctl command name (KeyBindings.commandNames)
settle                 # wait until two state reads agree
fullscreen f1 on       # native fullscreen via AX
note focused as A      # bind the focused window; `note frame A as full` binds a frame
expect frame B full    # a check; failures are collected and the run goes on
require active t1      # a check that stops the scenario if it fails
shot fullscreen 0.01   # screenshot; diff against references/<mode>/<scenario>/<name>.png
```

Checks: `tab`, `focused`, `active`, `workspace W N`, `same-workspace`, `workspace-count`,
`layout`, `parked`, `not-parked`, `fullscreen`, `not-fullscreen`, `differs`, `frame`, `onscreen`
(model says unparked and unhidden, and the window server has it on screen), `panels-hidden`
(no SpacialShell panel window intersects W's on-screen window).

Screenshot diffs are done by `imgdiff.swift`, compiled once into `.build/e2e/`. Both images are
scaled to 480 px wide. A pixel counts as different when a channel moves more than 24/255, and the
check fails when more than the tolerance (default 1%) of pixels differ.

## Scenarios

- `fullscreen.scn` covers #38's acceptance: native fullscreen hides the panels on that display,
  the window keeps its tab, and it stays on screen across `focus-workspace-down`/`up` (Fn+S /
  Fn+W), twice, then exits cleanly.
- `tabs.scn`: three windows in one maximize row; `focus-window-right` three times. Each step
  moves focus to a new window with the full tile frame and parks the previous one, and the third
  step wraps back to the first.

## Status

- `--host`: `tabs.scn` passes on this Mac. `fullscreen.scn` has not been run on the host (it
  takes over the screen and needs the terminal's Automation grant).
- `--vm`: written and dry-run only. It needs a golden image, which needs the disk above.
- Not verified: whether a TCC row with `csreq` is enough for Screen Recording on macOS 26 without
  the periodic re-approval prompt (`ScreenCaptureApprovals`). If the shell's motion proxies show
  a prompt in the guest, that is the next thing to bake in.
