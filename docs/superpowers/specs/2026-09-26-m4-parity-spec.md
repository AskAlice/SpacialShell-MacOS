# M4 spec: parity with material-shell and peer window managers

Date: 2026-09-26. Status: **accepted**. Written from the #24 / #25 decision session (2026-09-26)
under the #26 map. Input: `2026-09-25-m4-parity-classification-draft.md` (the classification
tables, G1–G38, and the evidence for every row stay there; this spec does not repeat them).
The M3 roadmap (`2026-08-25-m3-roadmap.md`) stays as written; M4 cites its task ids and keeps
their relative order.

## 1. Positioning

SpacialShell is **material-shell's paradigm and feature set, drawn Apple-native on macOS**. M1's
"Apple-native, not Material Design" ruling stands. material-shell is GPL-3, like SpacialShell; the lineage is
design inspiration only, never code.

- A **parity gap** is a peer feature compatible with the row/tab paradigm. M4 closes them.
- A **paradigm conflict** is a feature that is not, and is ruled out (§3).
- M4 does not add differentiators, features macOS does not expose to third parties (compositor
  blur and opacity, title-bar removal, Spaces control, tray or menu-bar replacement; window
  animations are the exception), or material-shell's settings overrides and telemetry.

## 2. Recorded decisions (#24, #25, 2026-09-26)

| # | Decision |
|---|---|
| P1 | **Per-display workspace stacks** stay, with a rail on each display. material-shell's primary-only model is a GNOME constraint, not adopted. |
| P2 | **The category is the workspace's identity.** M3 B3's "rename" becomes **"set category"** (G1). Names remain only on pinned `[[workspace]]` seeds. |
| P3 | **Resizable portions with keyboard resize**: weights per workspace per layout, persisted; 5% steps; snaps at 25/50/75%; a balance command. **Mouse border drag ships in the same item** (G9 + G10). |
| P4 | **No rail clock.** Struck from M3 B3. The macOS menu-bar clock stays. |
| P5 | M4 carries an explicit **"deliberately not doing" list** (§3). |
| P6 | **Hotkey grammar:** Fn = navigate, +Shift = move, +Ctrl = resize, +Alt = monitor. On the `ctrl-alt` preset, resize is `⌃⌥⌘`. |
| — | **Split** becomes an **N-column sliding view**, count set per workspace (default 2). |
| — | **Layout names:** keep SpacialShell's (`column`, not `simple`); material-shell's names only for new layouts (`ratio`). |
| — | **Back-and-forth:** `Fn+N` on the active workspace returns to the previous one. No new chord. |
| — | **Pointer warp:** on by default, can be switched off. |
| — | **Focus follows mouse:** an **opt-in** gap, not on the not-doing list. |
| — | **Window drag to swap tiles:** in M4, **early**. |
| Q12 | Defaulted: the **trust floor** gates only open M3a / I6 items. M3a is complete, so it binds nothing today; any reopened I6 bug gates every placement-touching M4 item until fixed. Open M3b/M3c tasks gate only the M4 items that depend on them. |
| Q15 | Defaulted: **measure** the layout-change animation's multi-window cost before scoring it (G13). |
| — | New gaps from the user: #95 (tab dropped on another workspace moves without switching), #96 (sidebar autohide), #98 (move all of an app's windows). |

Resolved here, from the grammar: `Fn+⌥⇧W/S` belongs to #98 (whole app), so moving a window to
the display above/below is a bindable but **unbound** command (#118). `Fn+[ / ]` stay as aliases
of the monitor chords.

## 3. Deliberately not doing (P5)

Paradigm conflicts (**C**) and out-of-scope rows (**O**) from the draft, plus the gaps whose rank
is ≤ 1.5.

| Feature | Source | Why not |
|---|---|---|
| Insert new window after the focused one | W2 | M1 ruling: new windows append. Dialogs already insert after their owner. |
| Workspaces on the primary display only; one fixed workspace per secondary | W3, X1–X3 | P1: per-display stacks. |
| Scratchpad workspace | peer W07 | A hidden place breaks the one-address rule and I6. Visitors and the tray (#73) cover it. |
| Manual split tree | peer L02 | A row is an ordered list; layouts own geometry. |
| Keyboard snap presets, drag-to-edge snap zones | peer L17, L18 | Snapper paradigm. Drawn layouts are the in-paradigm answer. |
| Focus effect: dim or border | Y17, peer V01 | Ruled out by the user (#60, #64): motion, not highlight. |
| Fullscreen yields when it loses focus | Y18 | #28: only human input leaves fullscreen. |
| Title bars hidden while tiled; window buttons forced to close only | Y19, A8 | #26: material-shell overrides, and macOS does not expose them. |
| Status area absorbing the system top bar | P8, peer U01 | #26: menu-bar replacement is out of scope. |
| Rail clock and notification bell | P9, P18 | P4. |
| Bare Super toggles the drawer | P12 | A bare Fn tap belongs to macOS; holding Fn shows the cheat sheet. |
| Touch long-press | M11 | No touch-screen Macs. |
| Mixed-DPI handling | X10 | macOS does it. |
| Dark / light / primary themes | A1 | M1: follows the system appearance. |
| Material widgets | A4 | M1: Apple-native, not Material Design. |
| Blurred wallpaper; opacity, dimming, shadows, rounded corners | A3, peer V03–V06 | #26: compositor effects macOS does not expose. |
| Update notifications sent to a server; disable-notifications setting | E3 | #26 telemetry. Sparkle updates ship instead (#58). |
| Notification daemon | peer U07 | Owned by macOS. |
| Float as a whole-row layout (G8) | Y8 | Rank 1. Per-window float ships; a floating row fights "always tiled". |
| Search: system actions, remote providers, recents (G16) | P10, P11 | Rank 1. Raycast via `launcher-url` covers it. |
| Per-workspace list of layouts to cycle (G19) | P20 | Rank 1. The global `layout-bar` plus direct layout keys (#119) cover it. |
| Tab bar at the bottom (G20) | P21 | Rank 1.5. |
| Modes / submaps (G25) | peer I02 | Rank 1. The grammar keeps every verb one chord away. |
| Per-display config: layout, gap (G30) | peer M03 | Rank 1. Per-workspace layout already exists. |
| Save and restore layouts on demand (G32) | peer X02 | Rank 1. State persists automatically. |
| Startup splash (G33) | E2 | Rank 1. |
| Plugin / scripting API (G37) | peer C02 | Rank 0.7. `spacialctl` and event subscription (#117) serve scripts. |
| Exec commands on start (G38) | peer C06 | Rank 1. Start-at-login is packaging (#47). |

## 4. Ordered parity gaps

Rank = impact × fit ÷ cost, each L/M/H = 1/2/3 (#26). Order is by rank, bounded by dependencies,
with the user's overrides applied: **#95 and drag-swap early**, **keyboard and mouse resize as one
item**, **focus follows mouse opt-in**. M3 carry-overs are not scored; they keep M3's relative order
(B1, B2, B3, B4, B7, B8, B9, M3c) and sit where their dependants need them.

Score changes from the draft: G9 absorbs G10, so cost rises to H (rank 3). G28 is opt-in, so its
fit rises from L to M (rank 2). G31 is L/M/L = 2, not ≤ 1.5 as the draft's row 19 implied, so it
stays a gap.

| # | Issue | Item | I/F/C | Rank | Ready | Blocked by | Epic |
|---|---|---|---|---|---|---|---|
| 1 | #95 | Tab drop moves without switching workspace | M/H/L | 6 | ✅ | — | #101 |
| 2 | #105 | G23 move window to workspace N (`Fn+⇧1…0`) | M/H/L | 6 | ✅ | — | #100 |
| 3 | #106 | G4 back-and-forth on `Fn+N` re-press | M/H/L | 6 | ✅ | — | #100 |
| 4 | #107 | G22 pointer warp, on by default | M/H/L | 6 | ✅ | — | #102 |
| 5 | #108 | G26 drag a window onto a tile to swap (early, per decision) | M/H/H | 2 | ✅ | — | #101 |
| 6 | #98 | Move all of an app's windows | M/H/M | 3 | ✅ | #95 | #101 |
| 7 | #109 | M3 B1 error channel | — | M3 | ✅ | — | #104 |
| 8 | #110 | M3 B2 snapshot feed, titles in tabs | — | M3 | ✅ | — | #103 |
| 9 | #111 | M3 B3 rail app menu and Quit (no clock) | — | M3 | ✅ | — | #103 |
| 10 | #112 | M3 B3 workspace menu: **set category** (G1) | M/H/L | 6 | ✅ | — | #103 |
| 11 | #113 | G9 + G10 resize by keyboard and mouse | H/H/H | 3 | ✅ | — | #99 |
| 12 | #114 | G5 N-column split | M/H/M | 3 | ✅ | #113 | #99 |
| 13 | #115 | G14 rail icon style | L/H/L | 3 | ✅ | #112 | #103 |
| 14 | #116 | G17 tab style and tooltips | L/H/L | 3 | ✅ | #110 | #103 |
| 15 | #117 | G36 event subscription | M/H/M | 3 | ✅ | #110 | #104 |
| 16 | #118 | G21 monitor chords on the grammar, directional | L/H/L | 3 | ✅ | — | #102 |
| 17 | #119 | G24 reverse cycle, direct layout commands | L/H/L | 3 | ✅ | — | #100 |
| 18 | #120 | G3 optional workspace wrap | L/H/L | 3 | ✅ | — | #100 |
| 19 | #121 | G15 scroll on rail, tab bar, layout icon | L/H/L | 3 | ✅ | — | #102 |
| 20 | #122 | G6 portrait-aware built-ins | L/H/L | 3 | ✅ | — | #99 |
| 21 | #123 | G7 `ratio` layout | L/H/L | 3 | ✅ | — | #99 |
| 22 | #124 | G11 `screen-gap` | L/H/L | 3 | ✅ | — | #99 |
| 23 | #125 | G12 centre fixed-size windows | L/H/L | 3 | ✅ | — | #99 |
| 24 | #126 | G35 attention on the rail | M/H/M | 3 | ✅ | — | #103 |
| 25 | #127 | G18 tab context menu, middle-click close | L/H/L | 3 | ✅ | — | #103 |
| 26 | #96 | Rail autohide | M/H/M | 3 | ✅ | — | #103 |
| 27 | #128 | M3 B4 placeholder tabs | — | M3 | ✅ | — | #103 |
| 28 | #129 | Pin tabs, drag placeholders (P17, M2) | L/H/L | 3 | ✅ | #128, #127, #108 | #103 |
| 29 | #130 | M3 B7 onboarding | — | M3 | ✅ | — | #104 |
| 30 | #131 | M3 B8 rest of the IPC contract | — | M3 | ✅ | #109 | #104 |
| 31 | #132 | M3 B9 spatialisation view | — | M3 | ✅ | — | #103 |
| 32 | #133 | M3c unknown config keys warn | — | M3 | ✅ | — | #104 |
| 33 | #134 | M3c sheets attach to their owner | — | M3 | ✅ | — | #103 |
| 34 | #135 | G28 focus follows mouse, opt-in | M/M/M | 2 | ✅ | — | #102 |
| 35 | #136 | G29 move a workspace to another display | M/M/M | 2 | needs-info | — | #102 |
| 36 | #137 | G2 focus history | L/M/L | 2 | needs-info | — | #100 |
| 37 | #138 | G34 warn when another WM runs | L/M/L | 2 | ✅ | #130 | #104 |
| 38 | #139 | G31 persistence toggle, documented reset | L/M/L | 2 | ✅ | — | #104 |
| 39 | #140 | G13 layout-change animation (measured, §7: gate not met in the VM) | M/H/M | 3 if built with limits | measured | — | #99 |
| 40 | #141 | G27 trackpad gestures (measure first) | M/H/H | 2 | needs-info | — | #102 |

Open bugs in the milestone: #93 (focus ring on a tab-bar button, needs-info) under #103; #97
(switch latency) stays under its M3b epic #64.

## 5. Dependencies

| Item | Depends on | Why |
|---|---|---|
| #98 | #95 | Drops use the non-following move. |
| #114 G5 | #113 G9 | Reuses the per-workspace layout state resize introduces. |
| #115 G14 | #112 (M3 B3) | The category icon includes the "set category" override. |
| #116 G17, #117 G36 | #110 (M3 B2) | Titles and the snapshot feed. |
| #129 | #128 (M3 B4), #127 G18, #108 G26 | Pin lives in the tab menu; placeholder drag reuses drag-swap. |
| #131 (M3 B8) | #109 (M3 B1) | "Unknown workspace" is a B1 error. |
| #138 G34 | #130 (M3 B7) | Uses B7's user-visible alert surface. |
| #108, #113, #98, #128 | Trust floor | Placement-touching: gated by any reopened I6 bug (M3a). |
| #140 G13, #141 G27 | Measurement | Scored only after the measurement in the issue (evidence standard, #26). |

## 6. Epics

| Epic | Outcome |
|---|---|
| #99 Resize and layouts | Keyboard and mouse resize; layout set at parity. |
| #100 Keyboard grammar and navigation | Every navigation verb on the adopted grammar. |
| #101 Windows and drag | Rearrange by mouse as freely as by keyboard. |
| #102 Multi-monitor and pointer | Pointer and monitors follow the keyboard. |
| #103 Rail, tabs and menus | M3's remaining surface plus material-shell's panel parity. |
| #104 Onboarding, errors and control | Nothing fails silently; a truthful IPC contract. |
| #47 Packaging (existing) | Notarised DMG (#16), CI and auto-update (#58). #20 closed as not planned. |

## 7. G13 measured: re-tile motion on the switch overlay (#140)

Q15 asked for the multi-window cost before scoring. The gate (#140 triage): keep re-tile motion
only if **8 windows stay under the 80 ms capture budget** that switches use (#97) **and no frame
drops at 60 Hz**; otherwise record why here and close as not planned.

### What already happens today

`Transition.moves` already plans a move for every window that is on screen before and after a
pass with a different frame, so a layout change (or a neighbour opening or closing) already goes
through `SwitchOverlay.prepare` with the switch rules: 200 ms, cached pictures if any, and
instant placement when the capture overruns 80 ms. Windows that arrive from a parked page are not
moves and pop in when the overlay drops. Nobody had measured it; that is what this section does.

### The prototype

`SPACIAL_PROTO_RETILE=1` (off by default; `RetileProbe.swift`). A pass whose transitions are all
re-tiles (`Transition.isRetile`: every move starts and ends inside the tiling area) is:

1. captured fresh and in full: no cached pictures and no budget, so every re-tile animates and
   every capture is timed;
2. covered with the pictures at their old frames while the store commits the real AX writes
   underneath (the switch hand-off, #65: the real windows are always at real frames);
3. slid and scaled to the reconciler's new frames over **250 ms**;
4. uncovered on landing.

### Method

- **Where:** the Tart guest (`e2e.sh --vm`), macOS 26.6.2, 4 vCPU, 8 GB, **no GPU**. Its tiling
  area is 960 × 687 pt at 1x. Nothing ran on the host's own session.
- **Trigger:** `Scripts/e2e/scenarios/perf/retile.scn`. One row of N TextEdit windows switches
  between `grid` and `wide` (a drawn 4 × 2 layout). All 8 fit above the 120 × 80 pt floor in both,
  so every re-tile moves all N windows. Per N: two re-tiles off the clock, then ten measured,
  4–5 s apart, then four under a 60 fps screen recording. The report counts only re-tiles that
  moved exactly N windows.
- **In the app** (`RetileProbe`, one log line per re-tile):
  - each `SCScreenshotManager` capture, timed;
  - command to the first display-link tick of the flight;
  - the overlay's `CADisplayLink` over the flight: a gap of k refresh periods is k − 1 dropped
    frames;
  - main-thread CPU (`thread_info`) from `prepare` to landing.
- **Signposts** on `sh.emu.SpacialShell` / Points of Interest: `retile`, `retile.capture`,
  `retile.shot`, `retile.play`, and events `retile.shown` and `retile.firstFrame`.
- **Profiles:** Instruments' Time Profiler (`xctrace record --attach`, from the host's Xcode
  shared into the guest; `SPACIAL_E2E_XCODE`) over the ten measured re-tiles. Converted by
  `Scripts/profiling/xctrace2pprof.py` to `docs/perf/retile-N{2,4,8}.pb.gz`: SpacialShell's
  samples inside the `retile` intervals, every thread, labelled by thread. Validated with
  `go tool pprof -top`. `-tagfocus 'thread=Main Thread'` narrows to the main thread.
- **On screen:** a 60 fps ScreenCaptureKit recording. The guest's display sends a frame every
  refresh, and an unchanged screen arrives byte-identical, so every unchanged frame inside a
  flight is one the window server showed twice.
- **Baseline:** today's tab switch (Fn+D / Fn+A, 200 ms), under the same recorder.
- **Reproduce:**

  ```sh
  SPACIAL_E2E_XCODE=/Applications/Xcode.app Scripts/e2e/e2e.sh --vm --suite perf
  Scripts/profiling/retile-report.py .build/e2e/vm-…/retile --pprof docs/perf
  ```

### Results (2026-09-26, ten re-tiles per N; median / worst)

| N | Capture, total ms | Capture per window ms (mean) | Slowest window ms | Backdrop ms | Over 80 ms | Command → first frame ms | App display-link drops | On screen per flight | Main-thread CPU per re-tile | All SpacialShell threads (Time Profiler) |
|---|---|---|---|---|---|---|---|---|---|---|
| 2 | 44 / 48 | 15 / 28 | 17 / 30 | 27 / 32 | 0 of 10 | 85 / 126 | 0 / 1 (1 of 10 re-tiles) | 48 fps, 5 / 9 repeated | 14 / 49 ms (4% / 13% of the pass) | 17 ms |
| 4 | 50 / 82 | 20 / 43 | 33 / 64 | 30 / 59 | 1 of 10 (82) | 94 / 138 | 0 / 1 (1 of 10) | 47 fps, 5 / 6 repeated | 13 / 17 ms (3% / 4%) | 21 ms |
| 8 | 72 / 112 | 28 / 53 | 52 / 80 | 45 / 72 | 2 of 10 (84, 112; one at 80) | 116 / 137 | 0 / 1 (1 of 10) | 47 fps, 4 / 5 repeated | 16 / 23 ms (4% / 6%) | 34 ms |
| Switch as it ships | — | — | — | — | — | — | — | 46 fps, 5 / 6 repeated | — | — |

Notes on the table:

- **Captures run in parallel.** The total grows with N, not N times: 44 → 72 ms from 2 to 8
  windows.
- **Command to first frame** includes the capture and one 16 ms composite before the flight.
- **Main-thread CPU** from the Time Profiler agrees with the app's own counter: 16.6, 13.1 and
  16.8 ms per re-tile.
- **Where the CPU goes at N = 8:** 20% of SpacialShell's samples inside the re-tiles are
  `WindowThumbnails.downscale`, the rail-thumbnail ingest (#90) re-scaling every captured
  picture on a worker thread. The main thread's share is AppKit and SwiftUI panel updates, not
  the overlay.
- **N = 1 reference:** a first run whose layout paged the other windows away moved one window
  per re-tile. Over 30 of those: capture 46 ms median (140 worst), first frame 84 ms.

### Gate verdict: not met as written

- **Capture budget: not met at N = 8.** The median (72 ms) is under 80 ms, but 2 of 10 re-tiles
  went over (84, 112 ms). At N = 4, 1 of 10 did (82 ms).
- **No drops at 60 Hz: not met, and not measurable in this guest.** The app's display link lost
  one frame in 1 of 10 re-tiles at every N. On screen, every flight runs at about 47 fps, and
  the switch that ships today does exactly the same (46 fps). The GPU-less guest's compositor
  cannot hold 60 Hz for any motion, so this criterion needs bare metal.
- **The guest cuts both ways.** Captures here are CPU-bound, with no GPU. But the windows are
  small: 960 × 687 pt at 1x, against a Retina display's 4× the pixels per point. So these
  numbers are neither a floor nor a ceiling for real hardware.

### Recommendation: build with limits, after one bare-metal run

Read literally, the gate says close as not planned. The recommendation is to keep it only in this
bounded form, because re-tiles already take this path today, under the same budget:

- **The 80 ms budget stays a hard cutoff for re-tiles.** Over it, place instantly, as switches
  do. The measured tail then costs an instant re-tile, never a late one; the prototype's "no
  budget" rule was only there to measure.
- **250 ms, instant under Reduce Motion,** as #140's acceptance says.
- **Re-tile captures skip the thumbnail ingest,** or defer it to after landing: it is the largest
  cost off the main thread at N = 8.
- **Arriving windows** (a parked page coming on screen) get pictures too, or the feature stays
  limited to windows visible before and after, as today.

Before building, run the same benchmark once on a real Mac. The scenario uses VM-only steps
(`sh`, `relaunch`), so this means a spare Mac or account, with the same steps by hand or through
a host variant of the scenario. If 8 windows still overrun 80 ms in more than 1 of 10 re-tiles there, or
flights drop frames that switches do not, close #140 as not planned with this section as the
reason.
