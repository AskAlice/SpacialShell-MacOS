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
Scripts/e2e/e2e.sh --vm --suite snapshots       # the visual snapshot suite (#81), scenarios/snapshots/
```

No scenario argument means all of `scenarios/*.scn` (`--suite NAME` adds `scenarios/NAME/*.scn`). Exit status is non-zero when any check
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

Provisioning is idempotent. After a change to it, `Scripts/e2e/golden.sh --update` runs it again
on the existing golden image without pulling anything, and keeps the previous image as
`spacial-e2e-golden-prev`: delete that once an `e2e.sh --vm` run passes on the new one (or
`tart delete` the golden and `tart rename` the backup back to roll back).

`golden.sh` clones the base image (Homebrew, Command Line Tools, `tart-guest-agent`, auto-login as
`admin`/`admin`, SIP disabled), gives it 4 CPUs, 8 GB, one 1920x1080 display and 60 GB of disk,
then runs `guest/provision.sh` inside it:

- checks SIP is off (the per-run grants below write the system TCC database) and the Swift
  toolchain is present, installing the Command Line Tools if not
- turns off sleep, the screen saver, window restoration and Dock visibility, and sets a
  plain desktop, so nothing interrupts a scenario or changes a screenshot
- marks Notes' "Welcome to Notes" sheet as shown (#154): Notes shows it until its container
  prefs hold `hasShownWelcomeScreen` and `lastShownStartupVersion-1` = the running macOS
  version (the second is the one that gates it). Rebuilding the guest on a new macOS brings the
  sheet back until the image is provisioned again
- **bakes in the runner's TCC grants**: Accessibility and Screen Recording for
  `tart-guest-agent` (the per-user LaunchAgent, `--run-agent`, is every `tart exec` command's
  responsible process). This follows the Cirrus templates' `update-tcc-database.sh`, which already
  grants both. There is deliberately no Apple Events grant: tccd ignores a written
  `kTCCServiceAppleEvents` row for the agent, prompts anyway, and rewrites the row as denied, so
  anything that sends Apple Events from `tart exec` times out (-1712). The runner sends none.

The **app's** grants (Accessibility and Screen Recording for `sh.emu.SpacialShell`) cannot be
baked in. The guest has no signing certificate, so `bundle.sh` signs ad hoc, and an ad-hoc
designated requirement is the cdhash, which changes on every build (see `Scripts/README`). So
`guest/run.sh` writes both rows on every run, using the build's own `csreq`, and then restarts
`tccd`.

TCC rows are not the whole Screen Recording story on macOS 15+: replayd separately asks whether a
client may "bypass the system private window picker", and asks again every month
(`~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist`). For the app
that dialog would sit in every screenshot, and for `tart-guest-agent` it comes due a month after
the golden image was provisioned. `guest/run.sh` marks both (`sh.emu.SpacialShell` by bundle id,
the agent by real path) as alerted in the year 3000 and restarts `replayd`.

`guest/run.sh` also switches off `tipsd` before anything else: macOS's Tips daemon posts a
persistent "See what's new in macOS" banner about half an hour after boot, into whatever is on
screen then.

## What a VM run does

1. `tart clone spacial-e2e-golden spacial-e2e-<pid>`
2. `tart run --no-graphics --dir=repo:<checkout>:ro --dir=out:<artefacts> --dir=cache:<cache>`.
   The repo goes in read-only, and artefacts come out through the writable share, so nothing
   needs copying back.
3. `tart exec … guest/run.sh`, which copies the repo into the guest, unpacks the build cache,
   runs `Scripts/bundle.sh`, packs the cache again, installs the app to `/Applications`, writes
   the TCC rows, launches the app, waits for the control socket, then runs `runner.py --mode vm`
4. With `--record`, copies the new references into `Scripts/e2e/references/vm/`
5. `tart stop` and `tart delete` the clone (`--keep` leaves it for `tart run` / debugging)

### The build cache

Every clone starts from the golden image with no `.build`, and a cold release build (the
OpenTelemetry packages most of all) took 1030 s of a run. So the guest's `.build` is kept between
runs in `.build/e2e/guest-cache/` on the host (`SPACIAL_E2E_CACHE`), as one tar (about 1.4 GB)
keyed by the guest's macOS build and Swift version: a rebuilt golden image never reuses foreign
products, and the older key is deleted. `run.sh` unpacks it before `bundle.sh` and packs it
after. SwiftPM's own incremental build decides what is stale; the rsync keeps the checkout's
mtimes, so that is exactly what changed. Measured: 285 s with a few app files changed, 662 s
after changes to Kit (the release whole-module builds of every target that depends on it).
Delete the directory to force a cold build.

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
- The `fullscreen` step sets `AXFullScreen` directly (`axfullscreen.swift`, compiled once into
  `.build/e2e/`), so the terminal needs Accessibility only. `tabs.scn` does not need it.

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

Driving the shell like a person, and the guest (VM only where noted):

```
input move 23 121           # pointer (input.swift, posted at the HID tap: hover, tracking areas)
input click X Y             # also: key fn-comma, key cmd-m, flags fn / flags none (hold Fn)
input axclick shell Layout  # click the AX element titled "Layout" in SpacialShell's windows
input drag 23 121 23 80 4   # press, glide, hold 4 s, release; the steps after it run mid-drag
sh LINE                     # the rest of the line through /bin/sh, unparsed (VM only)
relaunch                    # quit and reopen SpacialShell, wait for its socket (VM only)
appearance dark             # the session's appearance, live (appearance.swift; VM only)
slide NAME CMD 9 [shot options]  # run CMD, shoot 9 s after the switch overlay appears
record NAME SECS            # frames of the screen to NAME/ in the background (record.swift)
shot NAME [TOL] [region=X,Y,W,H] [1x] [thr=N]
```

`shot` options: `region` is in points, top-left origin; `1x` stores one pixel per point (a
quarter of the bytes of a Retina capture); `thr` is imgdiff's per-channel threshold. A failed
`shot` or `slide` fails the scenario, and the run goes on to the next shot. Before every shot,
a VM run presses Allow on replayd's "bypass the system private window picker" alert if one is
up. `guest/run.sh` pre-approves it, yet after an hour or so of captures in one guest it can still
appear, and it would sit in every shot after it. The log says `WARN` when that happens.

Checks: `tab`, `focused`, `active`, `workspace W N`, `same-workspace`, `workspace-count`,
`layout`, `parked`, `not-parked`, `fullscreen`, `not-fullscreen`, `differs`, `frame`, `onscreen`
(model says unparked and unhidden, and the window server has it on screen), `panels-hidden`
(no SpacialShell panel window intersects W's on-screen window).

Screenshot diffs are done by `imgdiff.swift`, compiled once into `.build/e2e/`. Both images are
scaled to 480 px wide. A pixel counts as different when a channel moves more than the threshold
(default 24/255), and the check fails when more than the tolerance (default 1%) of pixels differ.

## Scenarios

- `fullscreen.scn` covers #38's acceptance: native fullscreen hides the panels on that display,
  the window keeps its tab, and it stays on screen across `focus-workspace-down`/`up` (Fn+S /
  Fn+W), twice. The switch takes it out of fullscreen first (#49, m1 spec §"Native fullscreen"),
  so it comes back windowed. Then it goes fullscreen again and is taken out by hand.
- `tabs.scn`: three windows in one maximize row; `focus-window-right` three times. Each step
  moves focus to a new window with the full tile frame and parks the previous one, and the third
  step wraps back to the first.

## The snapshot suite (#81)

`Scripts/e2e/e2e.sh --vm --suite snapshots` runs `scenarios/snapshots/*.scn` against
`references/vm/<scenario>/`. Stories (`Tests/ShellStoryTests`) snapshot views in isolation; this
snapshots the real app on a real desktop: layout, window levels, and panels over real windows.

| Scenario | Shots |
|---|---|
| `rail.scn` | the rail; the hover card with window previews; the tray (#73) and its list; the drag-reorder insertion line (#75), mid-drag; the rail after the drop |
| `tabbar.scn` | tabs in `fit` and `equal` sizing; the layout switcher with split, column, half and grid selected (whole tiling area); overflow past the 88 pt floor, scrolled to the focused tab (#14) |
| `cheatsheets.scn` | the empty-workspace cheat sheet (#29); the hold-Fn cheat sheet |
| `settings.scn` | every Settings pane: General, Appearance, Layout, Workspaces (#74), Keybindings |
| `fullscreen-panels.scn` | native fullscreen with the panels hidden (#72) |
| `slides.scn` | a mid-slide frame of Fn+D and of Fn+S (#77) |
| `dark.scn` | dark appearance: the shell, the hover card, the empty cheat sheet, Settings (General, Appearance) |

Every scenario starts from the same place: light appearance, full-speed motion, no
`config.toml`, a flat Stone desktop, no desktop widgets (their live clock and date show through
the translucent panels), Full Keyboard Access off (the base image turns it on, and it puts a
focus ring on a layout button at random), then a fresh shell. Windows are one TextEdit instance
each, opened in turn. One instance opening several files adopts them in whatever order AX
reports them, and the tab order would change from run to run.

Shots are crops, in points, stored at 1x: 27 references, about 1.8 MB together. The rail and
the `fit` tab bar are compared strictly (`thr=0`, tolerance 0): any change to a panel's colour
fails them. The hover cards allow 5% (the previews are live window captures), the slides 10%, and
everything else the default 1% at 24/255.

**The mid-slide frames.** A guest has no GPU, and ScreenCaptureKit cannot catch a 200 ms slide in
it. So `slides.scn` stretches the motion 300x with a test-only default that the switch overlay
reads (`defaults write sh.emu.SpacialShell SpacialMotionScale 300`, like the Simulator's slow
animations). It shoots 9 s into the 60 s flight, then relaunches the shell to end the flight.

**When to re-record.** When a change to a surface is intended: run the suite, look at every
`*.diff.png` it wrote, and when the new pictures are the right ones, re-record just those
scenarios (`e2e.sh --vm --record scenarios/snapshots/<name>.scn`) and commit the references with
the change. Re-record everything after rebuilding the golden image or changing the guest's macOS.
A failure you did not intend is the suite doing its job: the diff shows where.

**Guest quirks it works around**, so they are not rediscovered:

- A long-lived guest's virtiofs share goes stale: files the host rewrote read as their old size,
  or with NUL bytes. `e2e.sh` boots a fresh clone per run, which never sees this. To iterate in a
  kept guest, push files with `tar … | tart exec -i <vm> tar -x` instead.
- `defaults write -g AppleInterfaceStyle Dark` changes nothing before the next login. The
  `appearance` step uses SkyLight's switch, as System Settings does.
- A button that a synthetic drag holds down is only down while the posting process lives. So a
  held drag is a long-lived `input` process, and it re-points at the target before it lets go:
  otherwise AppKit sometimes drops nothing after a still hold.

## Screen recordings for the docs (#8)

`Scripts/e2e/e2e.sh --vm --suite media` runs `scenarios/media/*.scn`, which drive the shell while
a `record` step captures the screen through ScreenCaptureKit (`record.swift`, frames plus their
times). No references; the frames land in the artefacts. Then, per recording:

```sh
Scripts/e2e/media.sh .build/e2e/vm-…/overview/overview docs/media/live-overview 720
Scripts/e2e/media.sh .build/e2e/vm-…/rail-apps/rail-apps docs/media/live-rail-apps 512 12 512:384:0:0
GIF_COLORS=64 WEBP_Q=38 Scripts/e2e/media.sh .build/e2e/vm-…/spatialisation/spatialisation \
    docs/media/spatialisation 720 12 "" 0.6 9.6      # #154: eight slides, under the old sizes
```

| Scenario | Loop in `docs/media/` | Shows |
|---|---|---|
| `spatialisation.scn` | `spatialisation` | workspaces as rows of real apps; `Fn+S`/`Fn+W` between rows, `Fn+D`/`Fn+A` along one |
| `tiling.scn` | `tiling-showcase` | `Fn+Space` through maximize, split, column, half, grid |
| `tab-drag.scn` | `live-tab-drag` | a tab dragged along the bar, then onto a rail row |
| `rail-apps.scn` | `live-rail-apps` | the rail with real apps, hover cards with live previews |
| `overview.scn`, `settings.scn` | `live-overview`, `live-settings` | the whole shell; Settings pane by pane |

`media.sh` holds each frame until the next one's time, so the loop plays at recorded speed, and
writes a gif (ffmpeg) and a webp (`img2webp`: Homebrew's ffmpeg has no libwebp). Its optional
START and LENGTH cut the loop to the action (docs loops stay at or under 10 s); `WEBP_Q` and
`GIF_COLORS` (default 60 and 128) trade quality for size. Recording speed
is real, so a switch's first capture in the GPU-less guest (1–4 s) shows as a pause before the
slide: the scenarios do each move once off camera before the `record` step. The guest has one
display: multi-display features are not in these recordings. None of these are renders
(`Scripts/render-m2-media.py` no longer writes `spatialisation` or `tiling-showcase`).

**Pointer motion** (`input.swift`, #149) is meant to read as a hand: each move bows slightly to
one side (a quadratic Bézier), follows a minimum-jerk speed profile, takes 250–600 ms by a
Fitts-like curve of its distance, posts at about 100 Hz, and rests 80–150 ms before a click or a
drop. A drag presses, nudges a few points past the drag threshold, then glides.

**When the guest never answers.** `e2e.sh` bounds every wait for the guest (default 600 s,
`SPACIAL_E2E_BOOT_TIMEOUT`) and stops with the reason and `tart-run.log`, rather than spinning.
A `tart-run.log` line `Failed to run control socket: NIOFcntlFailedError()` means tart's
control socket is dead until `tart run` restarts: a client that disconnected before tart
accepted it made the accept's `fcntl` fail, and tart 2.38 ends its accept loop on that one
error. Repeated `tart exec` probes against a booting guest were such clients, so the boot probe
is now a plain connection that waits for the agent's first bytes (so it never leaves before
tart has accepted it), and `tart exec` runs only once the agent answers. If the socket dies anyway, `e2e.sh` restarts the VM once during boot, and a watchdog
ends a run whose socket dies midway.

## Status

- `--host`: `tabs.scn` passes on this Mac. `fullscreen.scn` has not been run on the host (it
  takes over the screen).
- `--vm --suite snapshots`: all 7 scenarios (27 shots) pass against `references/vm/` (macOS 26.6
  guest). The suite itself takes about 7.5 minutes, and the whole run 16 with a cached build.
  Proven sensitive: with the panel material overlaid by one step of red (1/255), `rail` and
  `tabs-fit` fail (96% and 97% of pixels) while every default-threshold shot still passes. On
  the day it was recorded, the suite also caught two real changes that landed on main between
  runs: the cheat sheets starting to wrap (#87), and a different tab focused after `focus`.
- `--vm`: both scenarios pass against the references in `references/vm/` (macOS 26.6 guest).
  `tabs.scn` fails intermittently on a real shell race, #84: a late native focus report pulls
  focus back to the tab just left. Screenshot diffs run well under tolerance (at most 0.5% of
  pixels differ; the menu-bar clock and the desktop widgets account for it).
