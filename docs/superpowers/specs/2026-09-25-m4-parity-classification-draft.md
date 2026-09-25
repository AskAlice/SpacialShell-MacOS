# M4 parity classification: draft for the #24 / #25 session

Date: 2026-09-25. Status: **draft input for a decision session. Nothing here is decided.** It
feeds #24 (classify) and #25 (score and order) under the #26 map. Every status and score below is
a proposal for the user to accept or overturn.

Sources: the material-shell inventory (#21,
`2026-09-12-material-shell-feature-inventory.md`, row ids W/Y/P/K/M/X/S/A/E), the peer survey
(#22, `2026-09-12-peer-wm-feature-survey.md`, row ids L/W/M/F/R/I/U/V/C/X, with ✅ counts out of 15),
the window-animation feasibility study (#23, `2026-09-12-window-animation-feasibility.md`), and the
attention-signals study (`2026-09-14-attention-signals-feasibility.md`). What ships today was read
from `main` at `7301fef`: the code (`Command.swift`, `Config.swift`, the UI views), `docs/config.md`,
`docs/keybindings.md`, closed issues and git log.

## Legend

| Status | Meaning |
|---|---|
| **S** | Shipped. Cites the issue or commit. |
| **M3** | An M3 roadmap task that has **not** landed. Cites the task id (`2026-08-25-m3-roadmap.md`). |
| **G** | Parity gap: fits the row/tab paradigm. Scored and given a `G#` id for the ordering. |
| **C** | Paradigm conflict: ruled out, either by the row/tab model or by a binding ruling (cited). |
| **O** | Out of scope under #26: macOS does not expose it, or it is a material-shell override or telemetry #26 excludes. This is a fifth status, added to keep "conflict" honest. |

**Scores:** I = impact, F = paradigm fit, C = build cost, each L/M/H (1/2/3). Rank = I × F ÷ C.

**M3 state as of `7301fef`.** M3a is complete: A1 `8397145`, A2 #54, A3 #48/#71, A4 #52,
A5 #35/#40, A6 #55, A7 #56. So **the trust floor binds no M4 item today.** It comes back into force
if an I6 bug reopens. Open M3 tasks with no code yet:

- B1: error channel. There is no `CommandError` in the code.
- B2: snapshot feed and **window titles in tabs**. `ShellSnapshot` is "not yet emitted", and tabs
  show the app name.
- B3: menus and quit, which covers workspace rename, set symbol, remove, and the **stacked clock**.
- B4, second half: window↔placeholder matching. The first half shipped as #5.
- B7: onboarding.
- B8: IPC contract. Partly shipped: #88 routes the app-layer verbs.
- B9: the spatialisation view.
- M3c: warn on unknown config keys, and attach sheets to their owner visually.

## 1. Classification

### 1. Spatial model and workspaces

| Feature (source) | St | Reason | I/F/C | Deps |
|---|---|---|---|---|
| Row of windows per workspace (W1) | S | M1 model | | |
| Insert new window after the focused one (W2) | C | M1 ruling "new windows append". Dialogs already insert after their owner. | | |
| Workspaces on primary only (W3, X1) | C? | **Positioning call P1**. SpacialShell gives every display a stack. | | |
| Multiple and dynamic workspaces, one trailing empty (W4, W6, peer W01 8, W02 6) | S | M1 invariant 4 | | |
| Static workspaces (W5) | S | Pinned `[[workspace]]` seeds | | |
| New workspace above the first (W7) | S | #78 | | |
| Unnamed workspaces with category identity (W8, W9, W11; peer W03 named 8/15) | S / M3 | Categories and routing shipped (#74). B3 plans **renaming**: **positioning call P2**. | | |
| Per-workspace category override (W10) | G1 | No override. A category comes from the app only (`app-categories` is per app). | M/H/L | B3 workspace menu; P2 |
| Reorder workspaces by drag (W12, M8) | S | #75 | | |
| Middle-click closes a workspace (W13) | M3 | B3 "remove per the removeWorkspace ruling" | | |
| Per-workspace layout (W14) | S | `setWorkspaceLayout`, `[[workspace]] layout` | | |
| Per-workspace layout state: ratios, column count (W14) | G | Folded into G2 and G9 | | |
| Focus history of 5, and MRU switching (W15, peer F06 6) | G2 | No history. ⌘Tab is the OS MRU. | L/M/L | — |
| Focus goes to a spatial neighbour on close (W16) | S | Left neighbour, else right (`keybindings.md`) | | |
| Wrap window focus (W17) | S | `Fn+A`/`Fn+D` wrap | | |
| Wrap workspace focus (W17) | G3 | Workspaces do not wrap | L/H/L | — |
| Guard against a window changing workspace just after creation (W18) | S | Equivalent guards: #62, #69, #84 | | |
| Move window to workspace (peer W05 11) | S | `Fn+⇧W`/`Fn+⇧S` | | |
| Workspace back-and-forth (K47, K48 re-press, peer W06 7) | G4 | `focusWorkspaceIndex` returns early on the active workspace. No last-workspace command. | M/H/L | — |
| Scratchpad workspace (peer W07 4) | C | A hidden place breaks the one-address rule and I6. Visitors plus the tray (#73) cover the need. | | |
| Workspace state survives restart (peer W09 3) | S | #5, `state.json` | | |

### 2. Layouts

| Feature (source) | St | Reason | I/F/C | Deps |
|---|---|---|---|---|
| Maximize / monocle (Y1, peer L05 6) | S | M1 | | |
| Split: sliding view of 2 (Y2) | S | Focused window plus its neighbour | | |
| Split with N columns and a +/− picker (Y2, peer L09 4) | G5 | Split is fixed at 2 | M/H/M | per-workspace layout state (shared with G9) |
| Half / master–stack (Y3, peer L06 3) | S | `half` | | |
| Grid (Y7, peer L07 0) | S | `grid` | | |
| Simple, i.e. equal columns (Y9, peer L08 2) | S | `column` | | |
| Forced and aspect-aware variants for portrait displays (Y4, Y5, Y10, Y11) | G6 | Built-ins ignore display aspect. Drawn layouts cannot express N windows. | L/H/L | — |
| Ratio / dwindle (Y6, peer L03 5) | G7 | No generator | L/H/L | — |
| Float as a layout (Y8) | G8 | Per-window float ships. A whole-row float fights "always tiled". | L/L/L | — |
| Float per window, float alongside tiled (peer L11 13, L12 13) | S | `Fn+G`, `[[float]]` | | |
| Resizable portions with 25/50/75 snaps (Y12, peer L16 balance 2) | G9 | Every size is computed. **Positioning call P3.** | H/H/M | #9 (shipped); P3 |
| Keyboard resize by 5% steps (Y15, K17–K20, peer L13 **13/15**) | G9 | Same item as the row above | | |
| Mouse resize: drag a tile border, or a native edge-drag redirected (Y13, Y14, M9, A6 cursor) | G10 | None | M/H/H | G9 |
| User-defined layouts (peer L10 3) | S | #9, #10, #11 | | |
| Manual split tree (peer L02 7) | C | A row is an ordered list, and layouts own geometry | | |
| Keyboard snap presets (peer L17 4) and drag-to-edge snap zones (L18 3) | C | Snapper paradigm: per-window screen regions. Drawn layouts are the in-paradigm answer. | | |
| Gaps (Y16, peer L15 12) | S | `gap` | | |
| Separate outer screen gap (Y16 `screen-gap`) | G11 | One value covers inner and outer | L/H/L | — |
| Focus effect: dim or border (Y17, peer V01 7) | C | Ruled out by the user (#60, #64): no highlight stands in for motion | | |
| Fullscreen yields when it loses focus (Y18) | C | Opposite ruling in #28: only human input leaves fullscreen | | |
| Title bars hidden while tiled (Y19) | O | #26 out of scope | | |
| Hidden tiles minimized (Y20) | S | Parking does the same job (M1) | | |
| Fixed-size windows centred in their tile (Y21) | G12 | Only the #54 minimum clamp exists. Centring was not found in the code. | L/H/L | — |
| Layout-switch animation (Y22) | G13 | See §10, E1 | | |

### 3. Panels

| Feature (source) | St | Reason | I/F/C | Deps |
|---|---|---|---|---|
| Rail search button (P1) | S | Search glyph → `launcher-url` / overview | | |
| Workspace list with a trailing "+" (P2, peer U02 5) | S | M2 rail | | |
| Rail icon style: hybrid, category or app, plus colour (P3, P4) | G14 | App icons only (a 2×2 grid) | L/H/L | P2 |
| Active indicator (P5) | S | M2 rail | | |
| Rail clicks: left, drop a tab (P6) | S | M2, `d72be6a` | | |
| Rail right-click and middle-click menu (P6) | M3 | B3 | | |
| Scroll: rail switches workspace, bar switches window, layout icon cycles (P7, P16, P19, M10) | G15 | No scroll handling | L/H/L | — |
| Status area that absorbs the system top bar (P8, peer U01) | O | Tray and menu-bar replacement are out of scope (#26). The #73 tray is hidden windows, not this. | | |
| **Rail clock and notification bell (P9, P18)** | M3? | B3 lists "stacked clock". #26 says it is unsettled: **positioning call P4**. | | |
| Search drawer: apps and windows (P10, E8, peer U06 3) | S | Overview on `Fn+Tab` (M2) | | |
| Search: system actions, remote providers, recents (P10, P11) | G16 | Raycast via `launcher-url` covers this | L/M/M | — |
| Bare Super toggles the drawer (P12) | C | A bare Fn tap belongs to macOS. Holding Fn shows the cheat sheet. | | |
| Rail side left or right (P13) | S | `rail-side` | | |
| One tab per window, sliding indicator (P14, peer U03 7) | S | M2 tab bar, #14 | | |
| Tab shows the window title (P15) | M3 | B2 | | |
| Tab style full / name / icon, and tooltips (P15, E7) | G17 | — | L/H/L | B2 |
| Tab close button (P16) | S | `closeWindowRef` | | |
| Tab right-click menu (Pin / Close) and middle-click close (P16) | G18 | None | L/H/L | Pin needs B4 |
| Pinned placeholder tab (P17, P25, S8) | M3 | B4, second half | | |
| Layout switcher (P19) | S | Layout popover and editor, #10 | | |
| Per-workspace list of layouts to cycle (P20) | G19 | `layout-bar` is global | L/M/M | — |
| Tab bar at top or bottom (P21) | G20 | Top only | L/H/M | — |
| Panel size (P22) | S | `panel-width`, `panel-height` | | |
| Per-workspace launcher tile (P23, P24) | S | "+" opens the overview. An empty row shows the cheat sheet (#29). | | |
| Dialogs attach to their parent tile (P26) | M3 | M3c "sheets attach to their owner". They already join the owner's row. | | |
| Window previews (peer U04 3) | S | Hover cards #6, cached #90 | | |
| Overview / exposé (peer U05 3) | M3 | B9 spatialisation view | | |
| Settings GUI (peer U08 8) | S | Settings window, 5 panes (`4119843`, `104539e`) | | |

### 4. Hotkeys

| Feature (source) | St | Reason | I/F/C | Deps |
|---|---|---|---|---|
| Previous and next window (K1, K2) | S | `Fn+A`/`Fn+D` | | |
| App launcher (K3) | S | `Fn+Tab` | | |
| Close window (K4) | S | `Fn+Q` | | |
| Swap window left/right (K5, K6, peer L14 11) | S | `Fn+⇧A`/`Fn+⇧D` | | |
| Move window to workspace up/down (K7, K8) | S | `Fn+⇧W`/`Fn+⇧S` | | |
| Focus monitor (K9–K12, peer M01 10) | S | Previous/next only (`Fn+[`, `Fn+]`) | | |
| Focus or move by monitor *direction* (K9–K16) | G21 | Previous/next, not left/up/right/down | L/H/L | — |
| Pointer warps to the focused monitor (K9, peer F03 **11/15**) | G22 | No warp | M/H/L | — |
| Move window to monitor (K13–K16, peer M02 12) | S | `Fn+⇧[`/`Fn+⇧]`, #33 | | |
| Resize (K17–K20) | G9 | — | | |
| Move window to workspace N (K21–K30) | G23 | No verb | M/H/L | chord measurement |
| Cycle layout (K31) | S | `Fn+Space` | | |
| Reverse cycle, and direct layout commands (K32, K34–K44) | G24 | Only `spacialctl set-layout` | L/H/L | — |
| Zen mode (K33) | S | `Fn+Esc`, persisted | | |
| Workspaces up/down and 1…10 (K45, K46, K48) | S | `Fn+W`/`Fn+S`, `Fn+1…0` | | |
| Last workspace, re-press returns (K47, K48) | G4 | — | | |
| Blank conflicting system chords (§4 note) | S | The tap consumes bound chords (#37, #41) | | |
| Built-in, rebindable keys and a hotkeys pane (peer I01 14, U08) | S | M1, `104539e` | | |
| Modes / submaps (peer I02 5) | G25 | None | L/M/M | — |

### 5. Mouse, touch and drag

| Feature (source) | St | Reason | I/F/C | Deps |
|---|---|---|---|---|
| Drag a window to swap tiles; modifier-drag (M1, peer I03 6) | G26 | None. The README has promised "Fn+Drag reordering" since M2. | M/H/H | — |
| Drag a placeholder (M2) | G26 | Same item | | B4 |
| Carry a dragged window with `Fn+W`/`Fn+S` (M3) | G26 | Same item | | |
| Drag a window across monitors (M4, peer I04 5) | S | #57 `9883dea`, #72 | | |
| Tab reorder, tab to another bar, tab onto the rail (M5–M7) | S | `d72be6a`, #32 | | |
| Touch long-press (M11) | O | No touch-screen Macs | | |
| Trackpad gestures (peer I05 6) | G27 | None. Whether a third party can see swipes macOS gives Spaces is **unmeasured**. | M/H/H | measure first |
| Focus follows mouse (peer F02 9) | G28 | material-shell lacks it. Under maximize there is no other tile to hover. | M/L/M | — |

### 6. Multi-monitor

| Feature (source) | St | Reason | I/F/C | Deps |
|---|---|---|---|---|
| One fixed workspace per secondary; rail on primary only (X2, X3) | C? | **P1**. SpacialShell draws a rail and a stack on every display. | | |
| Per-monitor tiling (X4, peer W04 7) | S | M1 | | |
| Hotplug: display removed or added (X5, X6) | S | Stacks keyed by display UUID (#5, #13, spec §7.8) | | |
| Window follows its monitor (X7) | S | #57, #72 | | |
| Fullscreen hides the panels (X9) | S | #34, #72 | | |
| Mixed-DPI note (X10) | O | macOS handles it | | |
| Move a whole workspace to another display (peer W08 6) | G29 | None | M/M/M | — |
| Per-display config: layout, gap (peer M03 8) | G30 | Global only | L/M/M | — |

### 7. Persistence

| Feature (source) | St | Reason | I/F/C | Deps |
|---|---|---|---|---|
| State store, saved per workspace and globally, restore order, save debounce (S1, S3, S5–S7, S10) | S | `state.json` (M1, #5) | | |
| Unpinned workspaces survive relaunch (S3) | M3 | B4 | | |
| App → workspace memory (S4) | S | #5 | | |
| Placeholders and window re-association (S4, S8, S9, peer X01 2) | M3 | B4, second half. Builds on #18 window identity. | | |
| Persistence toggle (S2) | G31 | None | L/M/L | — |
| Lock screen keeps state (S11) | S | The tap re-enables on unlock (`keybindings.md`) | | |
| Documented reset (S12) | G31 | Same trivial item: a docs line | | |
| Save and restore layouts on demand (peer X02 1) | G32 | None | L/M/M | — |

### 8. Settings UI

| Feature (source) | St | Reason | I/F/C | Deps |
|---|---|---|---|---|
| Settings and hotkeys panes (§8) | S | Settings window, 5 panes, chord recorder | | |
| Primary colour and panel opacity | S | Colour well with opacity (#76) | | |
| Dark / light / primary themes (A1) | C | M1 ruling: Apple-native, follows the system appearance | | |
| Default layout; enable each layout | S | `default-layout`, `layout-bar` | | |
| Gap | S | `gap` | | |
| Excluded window classes and roles | S | `[[ignore]]` with `title-regex` | | |
| Cycle through workspaces | G3 | — | | |
| Animation duration (`tween-time`, unused upstream) | — | Not a real material-shell feature (Y22) | | |
| Disable notifications | O | Pairs with E3 | | |
| Declarative config with live reload (peer C04 9, C05 7) | S | TOML, watched | | |

### 9. Theming and appearance

| Feature (source) | St | Reason | I/F/C | Deps |
|---|---|---|---|---|
| Runtime theming (A2) | S | Panel colour (#76) | | |
| Blurred wallpaper (A3, peer V04 4) | O | #26 compositor blur | | |
| Material widgets (A4) | C | M1 "Apple-native, not Material Design" | | |
| Layout icon set (A5) | S | SF Symbols, `LayoutGlyph` | | |
| Cursor feedback during drag and resize (A6) | — | Comes with G10 and G26 | | |
| Window buttons forced to close only (A8) | O | #26 | | |
| Opacity, dimming, shadows, rounded corners (peer V03, V05, V06) | O | #26: macOS does not expose them | | |

### 10. Everything else

| Feature (source) | St | Reason | I/F/C | Deps |
|---|---|---|---|---|
| Workspace and tab switch motion (E1, peer V02 5) | S | #64–#67, #77: screenshot proxies (#23 verdict) | | |
| Layout-change and open/close re-tiling animated (E1, Y22) | G13 | Only switches animate. Several windows at once is **unmeasured** (#23 gap). | M/H/H | measure; #65 mechanism |
| Startup splash (E2) | G33 | — | L/L/L | — |
| Update notifications sent to a server (E3) | O | #26. Sparkle updates ship instead (#58, `bb848d9`). | | |
| Block conflicting extensions (E4) | G34 | Detect AeroSpace, yabai or skhd running and warn | L/M/L | — |
| Window scope: normal, dialog, utility (E5) | S | Classifier: tiled, floating, ephemeral, ignored | | |
| Focus behaviour and anti-theft (E6) | S | #28, #62, #69, #84 | | |
| Per-app and per-title rules; float, ignore (peer R01 13, R02 12, R04 11, R05 2) | S | `[[float]]`, `[[ignore]]`, `[[ephemeral]]`, `[[tile]]` with `title-regex` | | |
| Assign an app to a workspace (peer R03 8) | S | Category routing plus `app-categories` (#74, #13) | | |
| Urgency / attention on the rail (peer F05 5) | G35 | Measured feasible: Dock AX poll, heuristic (attention study) | M/H/M | — |
| Window hints / picker (peer F04 2) | S | Overview search over open windows | | |
| CLI / IPC (peer C01 8) | S | `spacialctl`, Raycast extension | | |
| Event subscription (peer C03 6) | G36 | The push channel is "not yet emitted" | M/H/M | B2 |
| Plugin / scripting API (peer C02 2) | G37 | None | L/M/H | — |
| Exec commands on start (peer C06 6) | G38 | None. Start-at-login is packaging (#47), not parity. | L/L/L | — |
| Native fullscreen handling (peer X03 12) | S | #28, #34, #35, #40, #72 | | |
| Minimized and hidden windows (peer X04 8) | S | #48, #71, tray #73 | | |
| Notification daemon (peer U07 1) | O | Owned by macOS | | |
| App-change re-label, quick-close, polkit pause (E9–E11) | — | Unverified here. Not user-facing; left out. | | |

## 2. Proposed order of the parity gaps

Rank = I × F ÷ C. Dependencies come before scores. No M4 item touching placement may land while
an I6 bug is open (the trust floor). Items that depend on an M3 task go after that task.

| # | Gap | Rank | Why here |
|---|---|---|---|
| 1 | G23 move window to workspace N | 6 | Cheap. 11/15 peers (W05). Material-shell default. |
| 2 | G4 back-and-forth / last workspace | 6 | Cheap. Material-shell default. |
| 3 | G22 pointer warp on screen focus and move | 6 | Cheap. 11/15 peers. Public `CGWarpMouseCursorPosition`. |
| 4 | **G9 keyboard resize, portions, snaps, balance** | 4.5 | The biggest single parity hole (13/15). Gated on P3. Adds per-workspace layout state that G5 reuses. |
| 5 | G1 per-workspace category override | 6* | *After M3 B3, which provides the workspace menu. Gated on P2. |
| 6 | G14 rail icon style | 3 | Rides with G1 |
| 7 | G5 N-column split | 3 | Reuses G9's per-workspace state |
| 8 | G24 reverse cycle and direct layout keys; G3 workspace wrap; G21 directional monitors | 3 | One small hotkey PR |
| 9 | G15 scroll on rail, bar and layout icon | 3 | Independent |
| 10 | G6 portrait-aware built-ins; G7 ratio; G11 outer gap; G12 centre fixed-size windows | 3 | Kit-pure `LayoutEngine` work, batchable |
| 11 | G35 attention on the rail | 3 | Measured feasible. Independent. |
| 12 | G36 event subscription; G17 tab styles and tooltips | 3 | After M3 B2 |
| 13 | G18 tab context menu | 3 | Close now. Pin after B4. |
| 14 | G10 mouse border resize | 2 | After G9 |
| 15 | G26 window drag to swap | 2 | High cost. Placement-touching, so under the trust floor. |
| 16 | G13 layout-change animation | 2 | Measure several windows at once first (evidence standard) |
| 17 | G27 trackpad gestures | 2 | Measure first |
| 18 | G29 move workspace to display; G2 focus history; G34 WM conflict warning | 2 | — |
| 19 | G28 focus follows mouse, and everything ranked ≤1.5 (G8, G16, G19, G20, G25, G30–G33, G37, G38) | ≤2 | Candidates for the "not doing" list (P5) |

## 3. Positioning calls (#24, plus the unsettled items in #26)

**P1. Where workspace stacks live: per display, or primary only?**
- (a) Keep per-display stacks, with a rail on each display.
- (b) Adopt material-shell's model: primary only, one fixed workspace per secondary.

Evidence:
- material-shell forces `workspaces-only-on-primary`. That is a GNOME constraint it inherited
  (X1–X3).
- 7 of 15 peers do per-monitor workspaces (W04).
- SpacialShell already keys stacks by display UUID (#5, #13). #74 routes categories per display,
  and #32/#57 move tabs between displays.

**Recommend (a).** Reversing it would undo shipped M2 and M3 work.

**P2. What identifies a workspace: its category, or a name?**
- (a) An unnamed row whose identity is its category: icons come from its apps, with a
  per-workspace override (G1). Names stay only on pinned `[[workspace]]` seeds.
- (b) Every row is renamable, as M3 B3 plans.

Evidence:
- material-shell has no name field at all (W8–W10).
- #74 now routes and sorts rows by category, so a category row is already its identity.
- 8 of 15 peers name workspaces (W03).

**Recommend (a).** That means amending B3's "rename" to "set category". This is the user's call:
M3 stays as written unless the user amends it.

**P3. How are tile sizes set: keyboard resize, or automatic only?**
- (a) Resizable portions:
  - weights per workspace per layout, persisted;
  - 5% keyboard steps;
  - snaps at 25/50/75%;
  - a balance command.
- (b) Layouts compute every size.

Evidence:
- 13 of 15 peers resize by keyboard (L13).
- material-shell ships it in every layout except maximize and float (Y12, Y15).
- It is Kit-pure: the reconciler still owns geometry, and the weights are data.

**Recommend (a).** It is material-shell's own paradigm, not a conflict.

**P4. A clock in the rail?**
- (a) No. The macOS menu-bar clock stays, so strike the "stacked clock" from B3.
- (b) A stacked rail clock, as B3 plans.
- (c) Only while the menu bar is auto-hidden.

Evidence: material-shell needs its clock because it hides GNOME's top bar (P8, P9). SpacialShell
does not hide the macOS menu bar, and #26 already rules out tray and menu-bar replacement.

**Recommend (a).**

**P5. Should M4 carry a "deliberately not doing" list?**
- (a) Yes: every **C** and **O** row, plus the gaps ranked ≤1.5, each with a one-line reason.
- (b) No.

Evidence: several conflicts rest on rulings (#28, #60, M1) that are easy to re-litigate if they
are not written down.

**Recommend (a).**

**P6. Which material-shell defaults to adopt?**
- **Hotkey grammar:** Shift moves, Ctrl resizes, Alt picks the monitor. Adopt it on the Fn base.
  Resize becomes `Fn+⌃` plus A/D/W/S. The ⌃⌥ preset needs `⌃⌥⌘` for resize, because Ctrl is
  already in the base there.
- **Layout names:** keep SpacialShell's five (`column` stays, not `simple`), and add `ratio` under
  its material-shell name.
- **Split's sliding N-window view:** adopt it as G5, with 2 as the default.
- **25/50/75 snaps:** adopt them inside G9.

## 4. Questions for the session

1. **P1 stacks:** keep per-display workspace stacks (a), or adopt primary-only (b)?
   *Recommend (a).*
2. **P2 identity:** make the category the workspace's identity and re-scope B3's rename to "set
   category" (a), or keep B3's rename for every row (b)? *Recommend (a).*
3. **P3 resize:** adopt resizable portions with keyboard resize, 5% steps and 25/50/75 snaps (a),
   or keep sizes automatic (b)? *Recommend (a).*
4. **Mouse resize:** dragging a tile border is a separate, later item after keyboard resize (a),
   or ships with it (b)? *Recommend (a).*
5. **P4 clock:** no rail clock, and strike it from B3 (a); a stacked rail clock (b); or a clock
   only while the menu bar auto-hides (c)? *Recommend (a).*
6. **P5 not-doing list:** does M4 carry an explicit "deliberately not doing" list (a), or not
   (b)? *Recommend (a).*
7. **Hotkey grammar:** adopt Shift = move, Ctrl = resize, Alt = monitor on the Fn base (a), or
   assign chords case by case (b)? *Recommend (a).*
8. **Layout names:** keep SpacialShell's names and add material-shell's where new, such as
   `ratio` (a), or rename to material-shell's (`column` → `simple`) (b)? *Recommend (a).*
9. **Split:** make split an N-column sliding view with a per-workspace picker (a), or keep it
   fixed at 2 (b)? *Recommend (a).*
10. **Back-and-forth:** pressing `Fn+N` on the active workspace returns to the previous one, as
    material-shell does (a), or give it a separate last-workspace chord (b)?
    *Recommend (a): no new chord.*
11. **Pointer warp:** warp to the focused screen by default, with an off switch (a), or make it
    opt-in (b)? *Recommend (a).* It is material-shell's default and 11/15 peers have it.
12. **Trust floor scope:** only open I6 / M3a bugs gate M4, and open M3b/M3c tasks gate only the
    M4 items that depend on them (a); or all of M3 finishes first (b)? *Recommend (a).* This is
    #26's wording.
13. **Window drag to swap tiles:** in M4, late in the order (a), or deferred past M4 (b)?
    *Recommend (a).* The README has promised it since M2.
14. **Focus follows mouse:** put it on the not-doing list (a), or make it an opt-in gap (b)?
    *Recommend (a).* material-shell lacks it, and it has nothing to hover under maximize.
15. **Layout-change animation:** measure multi-window overlay cost before scoring it (a), or
    score it now as high cost (b)? *Recommend (a).* That is the evidence standard.

## Caveats

- The README is stale in places. It still says "focus glow" is coming, which #60 removed, and it
  describes M2 as in progress. The statuses above come from the code, not the README.
- No build or run was done for this draft. "Not found in the code" (Y21, E9–E11) means grep found
  nothing. It is not a measurement.
