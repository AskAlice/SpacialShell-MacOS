# Peer window-manager feature survey — which user-facing features are common, and how common (verified 2026-09-12)

Legend: [H]=high, [M]=medium, [L]=low confidence. Cells: ✅ the peer itself has it · ➖ partial, plugin-only,
paid-tier-only, or delegated to the host environment with explicit peer integration (the note says which) ·
❌ absent from the peer's docs and source · ❓ could not be verified from primary sources.

Facts only. This note makes no judgement about SpacialShell adopting any of these features; that classification is a
later human decision. material-shell itself is inventoried separately and is not a column here.

---

## Method

- **Primary sources only.** Each open-source peer's repository was downloaded as a source tarball at the commit below
  and read locally (docs, man pages, config schemas, source). Every ✅/➖ carries a line-anchored link pinned to that
  commit (§6). Closed-source peers (Magnet, Rectangle Pro) are cited to the vendor's own site, docs and Mac App Store
  listing only. No blogs, awesome-lists, Reddit or video.
- **Fixed taxonomy first.** 70 feature rows in 10 groups were defined before any peer was read (§1) and applied
  identically to every peer. Survey work was split across six parallel readers, one per peer group, all working from
  the same taxonomy file; claims that looked surprising were re-checked against source by hand (AeroSpace
  focus-follows-mouse and socket protocol, Hyprland's Lua config and built-in scrolling/monocle layouts).
- **Scope rule for host features.** A feature the host environment provides and the peer does not touch (GNOME Shell's
  Activities overview for a GNOME extension, plasmashell's panel for KWin, macOS Mission Control for a macOS app) is ❌
  for that peer. If the peer explicitly drives or integrates it, it is ➖ with a note. This rule moves counts for the
  GNOME/KDE extension columns and for yabai; see §4.
- **Rectangle Pro** is folded into the Rectangle column: a feature only the paid Pro tier has is ➖ with the note
  "Rectangle Pro only".
- **Counts.** "✅" counts peers that have the feature outright; "✅+➖" adds partial / plugin / Pro / host-integrated.
  Magnet's ❓ cells count as neither.

## Peers surveyed (15)

| Group | Peer | Version | Commit (date) | Primary source |
|---|---|---|---|---|
| macOS tiler | AeroSpace | HEAD (source reports `0.0.0-SNAPSHOT`) | [`39e51904`](https://github.com/nikitabobko/AeroSpace/tree/39e51904) (2026-09-05) | repo `docs/*.adoc`, `Sources/` |
| macOS tiler | yabai + skhd | yabai 7.1.25 (+Unreleased); skhd maintenance mode | [`dd845723`](https://github.com/asmvik/yabai/tree/dd845723) (2026-06-14); skhd [`a7105d5b`](https://github.com/koekeishiya/skhd/tree/a7105d5b) (2025-12-09) | `doc/yabai.asciidoc`, CHANGELOG, official wiki |
| macOS tiler | Amethyst | 0.24.3 | [`6508ee2c`](https://github.com/ianyh/Amethyst/tree/6508ee2c) (2026-08-19) | README, `docs/`, source |
| macOS snapper | Rectangle (+ Rectangle Pro) | 1.100; Pro 3.90 | [`10fd8ae5`](https://github.com/rxhanson/Rectangle/tree/10fd8ae5) (2026-09-12); Pro closed | README, `TerminalCommands.md`, source; [rectangleapp.com/pro/docs](https://rectangleapp.com/pro/docs/) |
| macOS snapper | Magnet | 3.0.7 (App Store, 2025-04-12) | closed source | [magnet.crowdcafe.com](https://magnet.crowdcafe.com/), [FAQ](https://magnet.crowdcafe.com/faq.html), [App Store](https://apps.apple.com/app/magnet/id441258766) |
| Linux tiler (X11) | i3 | 4.25 | [`9be3249a`](https://github.com/i3/i3/tree/9be3249a) (2026-07-28) | `docs/userguide`, `docs/ipc`, `docs/layout-saving`, source |
| Linux tiler (Wayland) | sway | 1.13-dev (wlroots 0.21) | [`793a1f0c`](https://github.com/swaywm/sway/tree/793a1f0c) (2026-09-11) | `sway*.5.scd`, `sway-ipc.7.scd`, source |
| Linux tiler (Wayland) | Hyprland | 0.56.0 | [`c31b90c5`](https://github.com/hyprwm/Hyprland/tree/c31b90c5) (2026-09-12); wiki [`507259eb`](https://github.com/hyprwm/hyprland-wiki/tree/507259eb) | official wiki source, compositor source |
| Scrolling (Wayland) | niri | 26.4.0 | [`849c576f`](https://github.com/YaLTeR/niri/tree/849c576f) (2026-09-12) | `docs/wiki/*.md`, `default-config.kdl`, `niri-ipc` |
| Scrolling (GNOME ext.) | PaperWM | 50.0.1 (GNOME 45–50) | [`8bf6dd26`](https://github.com/paperwm/PaperWM/tree/8bf6dd26) (2026-05-03) | README, gschema, source |
| Spatial (Wayland shell) | Veshell | pre-release; no tag checked (`0.1.0` / `0.2.0+1` / `25.05.1` in-tree) | [`95639217`](https://github.com/free-explorers/veshell/tree/95639217) (2026-09-10) | source (Rust + Flutter), `docs/specifications` |
| DE tiling: GNOME | Pop Shell | metadata v2 (GNOME 45–50) | [`7898b65c`](https://github.com/pop-os/shell/tree/7898b65c) (2026-03-31) | README, gschema, source |
| DE tiling: GNOME | Forge | no version field (GNOME 45–50.1) | [`46736af6`](https://github.com/forge-ext/forge/tree/46736af6) (2026-06-25) | README, gschema, source |
| DE tiling: KDE | KWin built-in tiling (Plasma 6) | 6.7.90 (dev) | [`c1ca390b`](https://invent.kde.org/plasma/kwin/-/tree/c1ca390b) (2026-09-13 UTC) | source (official KDE mirror) |
| DE tiling: KDE | Polonium (KWin script) | 1.2.2 | [`227967ed`](https://github.com/zeroxoneafour/polonium/tree/227967ed) (2026-09-08) | readme, docs site source, source |

GNOME is represented by **Pop Shell and Forge** (extensions); GNOME's built-in edge tiling is summarised in §4 but is
not a column. KDE is represented by **KWin's own built-in tiling** and **Polonium**; Bismuth is archived (§4).

---

## 1. Feature taxonomy (70 rows, fixed before surveying)

| # | Definition |
|---|---|
| L01 | Automatic tiling — new windows are placed into a tiling layout with no user action |
| L02 | Manual split tree — user chooses split direction / nests containers (i3-style tree) |
| L03 | BSP — automatic binary space partitioning layout (alternating/dwindle splits) |
| L04 | Tabbed or stacked containers — several windows share one tile, one visible |
| L05 | Monocle / maximize-in-layout — one window fills the tiling area while others stay managed |
| L06 | Master–stack layout (tall/wide/centered-master family) |
| L07 | Grid layout (built-in) |
| L08 | Fixed multi-column layout (e.g. three-column, "columns" layout) — NOT an infinite strip |
| L09 | Scrolling strip — windows on an unbounded strip wider/taller than the screen that the view scrolls along |
| L10 | User-defined / scriptable custom layouts (user writes a layout: plugin, script, or declarative tile template) |
| L11 | Floating windows coexisting with tiled ones |
| L12 | Per-window toggle between floating and tiled |
| L13 | Resize windows/tiles by keyboard |
| L14 | Move/swap a window within the layout by keyboard |
| L15 | Gaps between windows / screen edges (configurable) |
| L16 | Balance / equalize tile sizes command |
| L17 | Keyboard snap presets (halves/thirds/quarters/center/maximize to fixed screen regions) |
| L18 | Drag-to-screen-edge snap zones (drag window to edge/corner to snap) |
| W01 | Multiple workspaces / virtual desktops managed by the peer |
| W02 | Dynamic workspaces (created/destroyed on demand, not a fixed count) |
| W03 | Named workspaces |
| W04 | Per-monitor workspaces (each monitor has its own independent workspace set/active workspace) |
| W05 | Move window to workspace |
| W06 | Workspace back-and-forth (jump to previously focused workspace) |
| W07 | Scratchpad / special (hidden, summonable) workspace |
| W08 | Move whole workspace to another monitor |
| W09 | Workspace state persists across peer restart (names/assignments/layout come back) |
| M01 | Focus monitor by direction (or next/prev) |
| M02 | Move window to monitor by direction (or next/prev) |
| M03 | Per-monitor configuration (per-output layout/gaps/scale/workspace assignment) |
| F01 | Focus window by direction |
| F02 | Focus follows mouse |
| F03 | Mouse warping (cursor moves to newly focused window/monitor) |
| F04 | Window hints / labels (jump to a window by an on-screen label or picker) |
| F05 | Urgency handling (urgent/attention windows flagged, focusable, or ruled) |
| F06 | Focus previous window / MRU window switcher (back-and-forth or alt-tab-style within the WM) |
| R01 | Per-app window rules (match on app id / bundle id / WM_CLASS) |
| R02 | Per-title window rules (match on window title) |
| R03 | Assign app to workspace by rule |
| R04 | Float by rule |
| R05 | Exclude/ignore app from management by rule |
| I01 | Built-in configurable keybindings (the peer itself binds keys, not only via an external hotkey daemon) |
| I02 | Modes / submaps (keybinding layers, e.g. i3 resize mode) |
| I03 | Mouse modifier-drag to move/resize windows |
| I04 | Drag windows between workspaces or monitors with the mouse |
| I05 | Touchpad / mouse gestures |
| U01 | Status bar / panel shipped by the peer |
| U02 | Workspace indicator shipped by the peer (in bar, menu bar, or panel) |
| U03 | Visible tab bar / title strip for grouped windows |
| U04 | Window previews / thumbnails |
| U05 | Overview / exposé (zoomed-out view of workspaces/windows) |
| U06 | Launcher shipped or integrated by the peer |
| U07 | Notification daemon/center shipped by the peer |
| U08 | Graphical settings UI |
| V01 | Window borders / focus indicator drawn by the peer |
| V02 | Animations (window open/close/move/workspace switch) |
| V03 | Opacity / inactive-window dimming |
| V04 | Blur |
| V05 | Shadows |
| V06 | Rounded corners |
| C01 | CLI or IPC to query and command the WM |
| C02 | Scripting / plugin API (third-party code extends behaviour: plugins, scripts, extensions API) |
| C03 | Event subscription (external process gets a stream of WM events) |
| C04 | Config live reload (config changes apply without restarting the peer) |
| C05 | Declarative text config file |
| C06 | Autostart / exec on startup (peer launches commands at start) |
| X01 | Re-adopts / restores existing windows into their layout positions after the peer restarts |
| X02 | Save & restore layouts / sessions on demand (layout files, snapshots) |
| X03 | Native/OS fullscreen handling (explicit support for app fullscreen state) |
| X04 | Minimized / hidden window handling (explicit behaviour for minimized/hidden windows) |

---

## 2. The matrix

Columns are peers; the last two columns count peers with ✅ and with ✅ or ➖. Citations for every ✅/➖ are in §6, one table per peer.

| # | Feature | AeroSpace | yabai | Amethyst | Rectangle | Magnet | i3 | sway | Hyprland | niri | PaperWM | Veshell | Pop Shell | Forge | KWin | Polonium | ✅ | ✅+➖ |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | **Layout** | | | | | | | | | | | | | | | | | |
| L01 | Automatic tiling | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | 12 | 12 |
| L02 | Manual split tree | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ➖ | ❌ | ➖ | ❌ | ✅ | ✅ | ✅ | ❌ | 7 | 9 |
| L03 | BSP / dwindle | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ➖ | ❌ | ✅ | 5 | 6 |
| L04 | Tabbed / stacked containers | ✅ | ✅ | ➖ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | 8 | 9 |
| L05 | Monocle / maximize-in-layout | ✅ | ✅ | ✅ | ❌ | ❌ | ➖ | ➖ | ✅ | ✅ | ➖ | ✅ | ➖ | ❌ | ❌ | ❌ | 6 | 10 |
| L06 | Master–stack | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | 3 | 3 |
| L07 | Grid layout | ❌ | ❌ | ❌ | ➖ | ❓ | ❌ | ❌ | ➖ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ➖ | 0 | 3 |
| L08 | Fixed multi-column layout | ❌ | ❌ | ✅ | ➖ | ❓ | ❌ | ❌ | ➖ | ❌ | ❌ | ➖ | ❌ | ❌ | ❌ | ✅ | 2 | 5 |
| L09 | Scrolling strip | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | 4 | 4 |
| L10 | User-defined / scriptable layouts | ❌ | ❌ | ✅ | ➖ | ❓ | ➖ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ➖ | 3 | 6 |
| L11 | Floating alongside tiled | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 13 | 13 |
| L12 | Per-window float toggle | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 13 | 13 |
| L13 | Resize by keyboard | ✅ | ✅ | ✅ | ✅ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | 13 | 13 |
| L14 | Move/swap window by keyboard | ✅ | ✅ | ✅ | ➖ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ➖ | ✅ | 11 | 13 |
| L15 | Gaps | ✅ | ✅ | ✅ | ✅ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | 12 | 12 |
| L16 | Balance / equalize sizes | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ➖ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 2 | 3 |
| L17 | Keyboard snap presets (halves, thirds…) | ❌ | ➖ | ❌ | ✅ | ✅ | ➖ | ➖ | ❌ | ➖ | ➖ | ❌ | ❌ | ✅ | ✅ | ❌ | 4 | 9 |
| L18 | Drag-to-edge snap zones | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | 3 | 3 |
| | **Workspaces** | | | | | | | | | | | | | | | | | |
| W01 | Multiple workspaces | ✅ | ➖ | ➖ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ❌ | ✅ | ➖ | 8 | 12 |
| W02 | Dynamic workspaces | ✅ | ➖ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ➖ | ❌ | ➖ | ❌ | 6 | 10 |
| W03 | Named workspaces | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | 8 | 8 |
| W04 | Per-monitor workspaces | ➖ | ➖ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | 7 | 9 |
| W05 | Move window to workspace | ✅ | ✅ | ✅ | ➖ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ➖ | 11 | 13 |
| W06 | Workspace back-and-forth | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | 7 | 7 |
| W07 | Scratchpad / special workspace | ❌ | ➖ | ❌ | ➖ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | 4 | 6 |
| W08 | Move workspace to monitor | ✅ | ➖ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | 6 | 7 |
| W09 | Workspace state survives restart | ❌ | ❌ | ➖ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ➖ | ✅ | ❌ | ❌ | ✅ | ➖ | 3 | 6 |
| | **Multi-monitor** | | | | | | | | | | | | | | | | | |
| M01 | Focus monitor by direction | ✅ | ✅ | ✅ | ❌ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ➖ | ✅ | ✅ | ❌ | 10 | 11 |
| M02 | Move window to monitor | ✅ | ✅ | ✅ | ✅ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ❓ | ✅ | ✅ | ✅ | ❌ | 12 | 12 |
| M03 | Per-monitor config | ✅ | ➖ | ➖ | ➖ | ❓ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | 8 | 11 |
| | **Focus & navigation** | | | | | | | | | | | | | | | | | |
| F01 | Focus by direction | ✅ | ✅ | ➖ | ❌ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 12 | 13 |
| F02 | Focus follows mouse | ✅ | ✅ | ✅ | ❌ | ❓ | ✅ | ✅ | ✅ | ✅ | ❌ | ➖ | ❌ | ✅ | ✅ | ❌ | 9 | 10 |
| F03 | Mouse warping | ✅ | ✅ | ✅ | ✅ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ➖ | ❌ | 11 | 12 |
| F04 | Window hints / labels | ❌ | ❌ | ❌ | ➖ | ❓ | ➖ | ➖ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | 2 | 5 |
| F05 | Urgency handling | ❌ | ❌ | ❌ | ❌ | ❓ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | 5 | 5 |
| F06 | Focus previous / MRU switcher | ✅ | ✅ | ❌ | ❌ | ❓ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ➖ | ✅ | ❌ | 6 | 7 |
| | **Rules** | | | | | | | | | | | | | | | | | |
| R01 | Per-app rules | ✅ | ✅ | ✅ | ✅ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | 13 | 13 |
| R02 | Per-title rules | ✅ | ✅ | ✅ | ➖ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | 12 | 13 |
| R03 | Assign app to workspace | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ➖ | 8 | 9 |
| R04 | Float by rule | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | 11 | 11 |
| R05 | Ignore app by rule | ❌ | ➖ | ➖ | ✅ | ❓ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ➖ | ❌ | ❌ | ✅ | 2 | 5 |
| | **Input** | | | | | | | | | | | | | | | | | |
| I01 | Built-in keybindings | ✅ | ➖ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 14 | 15 |
| I02 | Modes / submaps | ✅ | ➖ | ❌ | ❌ | ❓ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | 5 | 6 |
| I03 | Modifier-drag move/resize | ➖ | ✅ | ➖ | ➖ | ❓ | ✅ | ✅ | ✅ | ✅ | ➖ | ❌ | ❌ | ➖ | ✅ | ❌ | 6 | 11 |
| I04 | Drag between workspaces/monitors | ➖ | ➖ | ❌ | ❌ | ❌ | ➖ | ➖ | ✅ | ✅ | ✅ | ✅ | ➖ | ❌ | ✅ | ➖ | 5 | 11 |
| I05 | Gestures | ❌ | ❌ | ❌ | ➖ | ❓ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | 6 | 7 |
| | **UI furniture** | | | | | | | | | | | | | | | | | |
| U01 | Status bar / panel | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ➖ | ✅ | ❌ | ❌ | ❌ | ❌ | 3 | 4 |
| U02 | Workspace indicator | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | 5 | 5 |
| U03 | Tab bar for grouped windows | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | 7 | 7 |
| U04 | Window previews | ❌ | ❌ | ❌ | ❌ | ❓ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | 3 | 3 |
| U05 | Overview / exposé | ❌ | ➖ | ❌ | ❌ | ❓ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | 3 | 4 |
| U06 | Launcher | ❌ | ❌ | ❌ | ❌ | ❓ | ➖ | ➖ | ➖ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | 3 | 6 |
| U07 | Notification daemon | ❌ | ❌ | ❌ | ❌ | ❓ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | 1 | 1 |
| U08 | Settings GUI | ❌ | ❌ | ✅ | ✅ | ❓ | ➖ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 8 | 9 |
| | **Visual** | | | | | | | | | | | | | | | | | |
| V01 | Borders / focus indicator | ❌ | ❌ | ❌ | ❌ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | ➖ | 7 | 10 |
| V02 | Animations | ❌ | ➖ | ❌ | ❌ | ❓ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | 5 | 6 |
| V03 | Opacity / dim inactive | ❌ | ➖ | ❌ | ❌ | ❓ | ❌ | ✅ | ✅ | ✅ | ➖ | ❌ | ❌ | ❌ | ✅ | ❌ | 4 | 6 |
| V04 | Blur | ❌ | ❌ | ❌ | ❌ | ❓ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | 4 | 4 |
| V05 | Shadows | ❌ | ➖ | ❌ | ❌ | ❓ | ❌ | ❌ | ✅ | ✅ | ❌ | ➖ | ❌ | ❌ | ✅ | ❌ | 3 | 5 |
| V06 | Rounded corners | ❌ | ❌ | ❌ | ❌ | ❓ | ❌ | ❌ | ✅ | ✅ | ❌ | ➖ | ❌ | ❌ | ✅ | ❌ | 3 | 4 |
| | **Control & integration** | | | | | | | | | | | | | | | | | |
| C01 | CLI / IPC | ✅ | ✅ | ❌ | ➖ | ❓ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | 8 | 9 |
| C02 | Scripting / plugin API | ➖ | ➖ | ➖ | ❌ | ❓ | ➖ | ➖ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ➖ | 2 | 8 |
| C03 | Event subscription | ✅ | ✅ | ❌ | ❌ | ❓ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ➖ | ❌ | 6 | 7 |
| C04 | Config live reload | ✅ | ❌ | ❌ | ❌ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ✅ | ✅ | ➖ | 9 | 11 |
| C05 | Declarative text config | ✅ | ➖ | ✅ | ➖ | ❓ | ✅ | ✅ | ➖ | ✅ | ➖ | ✅ | ➖ | ➖ | ✅ | ❌ | 7 | 13 |
| C06 | Autostart / exec on start | ✅ | ➖ | ❌ | ❌ | ❓ | ✅ | ✅ | ✅ | ✅ | ❌ | ➖ | ❌ | ❌ | ✅ | ❌ | 6 | 8 |
| | **Lifecycle** | | | | | | | | | | | | | | | | | |
| X01 | Re-adopt layout after restart | ❌ | ➖ | ➖ | ❌ | ❓ | ✅ | ❌ | ❌ | ❌ | ➖ | ✅ | ➖ | ➖ | ❌ | ❓ | 2 | 7 |
| X02 | Save / restore layouts | ❌ | ❌ | ❌ | ➖ | ❓ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ➖ | ❌ | 1 | 3 |
| X03 | Native fullscreen handling | ✅ | ✅ | ❌ | ➖ | ❓ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 12 | 13 |
| X04 | Minimized-window handling | ✅ | ✅ | ➖ | ➖ | ❓ | ✅ | ➖ | ➖ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | 8 | 12 |

---

## 2a. Prevalence ranking (the headline output)

All 70 features, ranked by the number of the 15 peers that have the feature outright (✅), ties broken by ✅+➖. Peers with the feature outright are listed.

| Rank | # | Feature | ✅ | ✅+➖ | ❓ | Peers with ✅ |
|---|---|---|---|---|---|---|
| 1 | I01 | Built-in keybindings | 14 | 15 | 0 | AeroSpace, Amethyst, Rectangle, Magnet, i3, sway, Hyprland, niri, PaperWM, Veshell, Pop Shell, Forge, KWin, Polonium |
| 2 | L11 | Floating alongside tiled | 13 | 13 | 0 | AeroSpace, yabai, Amethyst, i3, sway, Hyprland, niri, PaperWM, Veshell, Pop Shell, Forge, KWin, Polonium |
| 2 | L12 | Per-window float toggle | 13 | 13 | 0 | AeroSpace, yabai, Amethyst, i3, sway, Hyprland, niri, PaperWM, Veshell, Pop Shell, Forge, KWin, Polonium |
| 2 | L13 | Resize by keyboard | 13 | 13 | 1 | AeroSpace, yabai, Amethyst, Rectangle, i3, sway, Hyprland, niri, PaperWM, Pop Shell, Forge, KWin, Polonium |
| 2 | R01 | Per-app rules | 13 | 13 | 1 | AeroSpace, yabai, Amethyst, Rectangle, i3, sway, Hyprland, niri, PaperWM, Pop Shell, Forge, KWin, Polonium |
| 6 | F01 | Focus by direction | 12 | 13 | 1 | AeroSpace, yabai, i3, sway, Hyprland, niri, PaperWM, Veshell, Pop Shell, Forge, KWin, Polonium |
| 6 | R02 | Per-title rules | 12 | 13 | 1 | AeroSpace, yabai, Amethyst, i3, sway, Hyprland, niri, PaperWM, Pop Shell, Forge, KWin, Polonium |
| 6 | X03 | Native fullscreen handling | 12 | 13 | 1 | AeroSpace, yabai, i3, sway, Hyprland, niri, PaperWM, Veshell, Pop Shell, Forge, KWin, Polonium |
| 9 | L01 | Automatic tiling | 12 | 12 | 0 | AeroSpace, yabai, Amethyst, i3, sway, Hyprland, niri, PaperWM, Veshell, Pop Shell, Forge, Polonium |
| 9 | L15 | Gaps | 12 | 12 | 1 | AeroSpace, yabai, Amethyst, Rectangle, i3, sway, Hyprland, niri, PaperWM, Pop Shell, Forge, KWin |
| 9 | M02 | Move window to monitor | 12 | 12 | 2 | AeroSpace, yabai, Amethyst, Rectangle, i3, sway, Hyprland, niri, PaperWM, Pop Shell, Forge, KWin |
| 12 | L14 | Move/swap window by keyboard | 11 | 13 | 1 | AeroSpace, yabai, Amethyst, i3, sway, Hyprland, niri, PaperWM, Pop Shell, Forge, Polonium |
| 12 | W05 | Move window to workspace | 11 | 13 | 0 | AeroSpace, yabai, Amethyst, i3, sway, Hyprland, niri, PaperWM, Veshell, Pop Shell, KWin |
| 14 | F03 | Mouse warping | 11 | 12 | 1 | AeroSpace, yabai, Amethyst, Rectangle, i3, sway, Hyprland, niri, PaperWM, Pop Shell, Forge |
| 15 | R04 | Float by rule | 11 | 11 | 0 | AeroSpace, yabai, Amethyst, i3, sway, Hyprland, niri, PaperWM, Pop Shell, Forge, Polonium |
| 16 | M01 | Focus monitor by direction | 10 | 11 | 1 | AeroSpace, yabai, Amethyst, i3, sway, Hyprland, niri, PaperWM, Forge, KWin |
| 17 | C04 | Config live reload | 9 | 11 | 1 | AeroSpace, i3, sway, Hyprland, niri, PaperWM, Veshell, Forge, KWin |
| 18 | F02 | Focus follows mouse | 9 | 10 | 1 | AeroSpace, yabai, Amethyst, i3, sway, Hyprland, niri, Forge, KWin |
| 19 | W01 | Multiple workspaces | 8 | 12 | 0 | AeroSpace, i3, sway, Hyprland, niri, PaperWM, Veshell, KWin |
| 19 | X04 | Minimized-window handling | 8 | 12 | 1 | AeroSpace, yabai, i3, PaperWM, Pop Shell, Forge, KWin, Polonium |
| 21 | M03 | Per-monitor config | 8 | 11 | 1 | AeroSpace, i3, sway, Hyprland, niri, Veshell, KWin, Polonium |
| 22 | C01 | CLI / IPC | 8 | 9 | 1 | AeroSpace, yabai, i3, sway, Hyprland, niri, Pop Shell, KWin |
| 22 | L04 | Tabbed / stacked containers | 8 | 9 | 0 | AeroSpace, yabai, i3, sway, Hyprland, niri, Pop Shell, Forge |
| 22 | R03 | Assign app to workspace | 8 | 9 | 0 | AeroSpace, yabai, i3, sway, Hyprland, niri, PaperWM, KWin |
| 22 | U08 | Settings GUI | 8 | 9 | 1 | Amethyst, Rectangle, PaperWM, Veshell, Pop Shell, Forge, KWin, Polonium |
| 26 | W03 | Named workspaces | 8 | 8 | 0 | AeroSpace, yabai, i3, sway, Hyprland, niri, PaperWM, KWin |
| 27 | C05 | Declarative text config | 7 | 13 | 1 | AeroSpace, Amethyst, i3, sway, niri, Veshell, KWin |
| 28 | V01 | Borders / focus indicator | 7 | 10 | 1 | i3, sway, Hyprland, niri, PaperWM, Pop Shell, Forge |
| 29 | L02 | Manual split tree | 7 | 9 | 0 | AeroSpace, yabai, i3, sway, Pop Shell, Forge, KWin |
| 29 | W04 | Per-monitor workspaces | 7 | 9 | 0 | i3, sway, Hyprland, niri, PaperWM, Veshell, KWin |
| 31 | U03 | Tab bar for grouped windows | 7 | 7 | 0 | i3, sway, Hyprland, niri, Veshell, Pop Shell, Forge |
| 31 | W06 | Workspace back-and-forth | 7 | 7 | 0 | AeroSpace, yabai, i3, sway, Hyprland, niri, PaperWM |
| 33 | I03 | Modifier-drag move/resize | 6 | 11 | 1 | yabai, i3, sway, Hyprland, niri, KWin |
| 34 | L05 | Monocle / maximize-in-layout | 6 | 10 | 0 | AeroSpace, yabai, Amethyst, Hyprland, niri, Veshell |
| 34 | W02 | Dynamic workspaces | 6 | 10 | 0 | AeroSpace, i3, sway, Hyprland, niri, Veshell |
| 36 | C06 | Autostart / exec on start | 6 | 8 | 1 | AeroSpace, i3, sway, Hyprland, niri, KWin |
| 37 | C03 | Event subscription | 6 | 7 | 1 | AeroSpace, yabai, i3, sway, Hyprland, niri |
| 37 | F06 | Focus previous / MRU switcher | 6 | 7 | 1 | AeroSpace, yabai, Hyprland, niri, PaperWM, KWin |
| 37 | I05 | Gestures | 6 | 7 | 1 | sway, Hyprland, niri, PaperWM, Veshell, KWin |
| 37 | W08 | Move workspace to monitor | 6 | 7 | 0 | AeroSpace, i3, sway, Hyprland, niri, PaperWM |
| 41 | I04 | Drag between workspaces/monitors | 5 | 11 | 0 | Hyprland, niri, PaperWM, Veshell, KWin |
| 42 | I02 | Modes / submaps | 5 | 6 | 1 | AeroSpace, i3, sway, Hyprland, Pop Shell |
| 42 | L03 | BSP / dwindle | 5 | 6 | 0 | yabai, Amethyst, Hyprland, Pop Shell, Polonium |
| 42 | V02 | Animations | 5 | 6 | 1 | Hyprland, niri, PaperWM, Veshell, KWin |
| 45 | F05 | Urgency handling | 5 | 5 | 1 | i3, sway, Hyprland, niri, KWin |
| 45 | U02 | Workspace indicator | 5 | 5 | 0 | AeroSpace, i3, sway, PaperWM, Veshell |
| 47 | L17 | Keyboard snap presets (halves, thirds…) | 4 | 9 | 0 | Rectangle, Magnet, Forge, KWin |
| 48 | V03 | Opacity / dim inactive | 4 | 6 | 1 | sway, Hyprland, niri, KWin |
| 48 | W07 | Scratchpad / special workspace | 4 | 6 | 0 | i3, sway, Hyprland, PaperWM |
| 50 | L09 | Scrolling strip | 4 | 4 | 0 | Hyprland, niri, PaperWM, Veshell |
| 50 | V04 | Blur | 4 | 4 | 1 | Hyprland, niri, Veshell, KWin |
| 52 | L10 | User-defined / scriptable layouts | 3 | 6 | 1 | Amethyst, Hyprland, KWin |
| 52 | U06 | Launcher | 3 | 6 | 1 | Veshell, Pop Shell, KWin |
| 52 | W09 | Workspace state survives restart | 3 | 6 | 0 | i3, Veshell, KWin |
| 55 | V05 | Shadows | 3 | 5 | 1 | Hyprland, niri, KWin |
| 56 | U01 | Status bar / panel | 3 | 4 | 0 | i3, sway, Veshell |
| 56 | U05 | Overview / exposé | 3 | 4 | 1 | niri, PaperWM, KWin |
| 56 | V06 | Rounded corners | 3 | 4 | 1 | Hyprland, niri, KWin |
| 59 | L06 | Master–stack | 3 | 3 | 0 | Amethyst, Hyprland, Polonium |
| 59 | L18 | Drag-to-edge snap zones | 3 | 3 | 0 | Rectangle, Magnet, KWin |
| 59 | U04 | Window previews | 3 | 3 | 1 | niri, PaperWM, KWin |
| 62 | C02 | Scripting / plugin API | 2 | 8 | 1 | Hyprland, KWin |
| 63 | X01 | Re-adopt layout after restart | 2 | 7 | 2 | i3, Veshell |
| 64 | F04 | Window hints / labels | 2 | 5 | 1 | Pop Shell, KWin |
| 64 | L08 | Fixed multi-column layout | 2 | 5 | 1 | Amethyst, Polonium |
| 64 | R05 | Ignore app by rule | 2 | 5 | 1 | Rectangle, Polonium |
| 67 | L16 | Balance / equalize sizes | 2 | 3 | 0 | AeroSpace, yabai |
| 68 | X02 | Save / restore layouts | 1 | 3 | 1 | i3 |
| 69 | U07 | Notification daemon | 1 | 1 | 1 | Veshell |
| 70 | L07 | Grid layout | 0 | 3 | 1 | — |

---

## 3. Platform notes — features whose presence tracks display-server / compositor control

Stated as the missing capability, with the source that states it. Where the only source is a peer's own
documentation (not Apple's), that is said.

- [H] **Compositing effects on other apps' windows (V02 animations, V03 opacity, V04 blur, V05 shadows, V06 rounded
  corners).** On Wayland the window manager *is* the compositor, so it renders every window and can apply these:
  Hyprland, niri and KWin have all five or nearly all (§2). GNOME extensions run inside GNOME Shell's compositor process,
  which is how PaperWM animates. On X11 the WM and the compositor are separate programs: i3 provides none of these, and
  a separate compositor (picom) would. Upstream sway also has none of V04–V06; the SwayFX fork adds them and was not
  surveyed. **On macOS**, yabai's official wiki gives the missing capability as: Dock.app "owns the sole connection to
  the macOS window server", so window transparency, removing shadows and window animations need SIP partially disabled
  so yabai can inject a scripting addition into Dock.app
  ([yabai wiki, Disabling SIP](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection), edited
  2026-04-18). No surveyed macOS peer offers blur or rounded corners on other apps' windows at all; AeroSpace points
  users to the third-party JankyBorders for borders
  ([goodies.adoc L36-L48](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/goodies.adoc#L36-L48)).
- [H] **Workspace creation, deletion and reordering (W02, W07, W08) under the OS's own virtual desktops.** AeroSpace's
  guide: "Apple doesn't provide public API to communicate with Spaces (create/delete/reorder/switch Space and move
  windows between Spaces)", and Spaces cannot be created, deleted or reordered by hotkey
  ([guide.adoc L427-L436](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L427-L436)). The two
  answers on macOS are (a) **emulation**: AeroSpace keeps one macOS Space and parks inactive-workspace windows
  off-screen in a bottom corner, with a documented residue ("macOS doesn't allow to place windows outside the visible
  area entirely … a 1 pixel vertical line") and a monitor-arrangement constraint (every monitor needs a free bottom
  corner) ([L438-L474](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L438-L474)); or
  (b) **driving native Spaces through the SIP-disabled scripting addition**: yabai's space create/destroy/move,
  scratchpad windows and sticky windows are on the wiki's SIP-required list. Amethyst uses native Spaces and does not
  create them. Linux compositors own workspaces outright (i3, sway, Hyprland, niri, KWin all create/destroy/move them
  natively).
- [H] **Window layers / sticky / picture-in-picture.** On the same yabai SIP-required list ("control window layers",
  "sticky windows", "toggle picture-in-picture"). Not a taxonomy row; recorded because it is the same missing
  capability.
- [M] **Compositor-rendered overview and live window previews (U04, U05).** The three peers with a real
  overview/preview (niri, KWin, PaperWM inside GNOME Shell) all render it from inside the compositor. yabai's U05 ➖
  only *triggers* macOS Mission Control / Exposé. No surveyed macOS peer draws its own previews. Which macOS API a third
  party would need (and its permission prompt) was not established from an Apple primary source here — see §4.
- [H] **Restart without losing windows (X01) is an X11 property, absent on Wayland.** i3's in-place `restart`
  serialises the tree and re-execs because X clients outlive the WM
  ([util.c L289-L311](https://github.com/i3/i3/blob/9be3249a/src/util.c#L289-L311)); sway has only `reload`, and on
  Wayland clients do not outlive the compositor (sway, Hyprland, niri all ❌). On macOS the WM is an ordinary app and
  windows survive its restart; yabai adopts them but does not restore the split tree, Amethyst restores per-Space layout
  choice only, AeroSpace restores neither (§2 / §6).
- [H] **Notification daemon (U07).** Veshell's one ✅ is an implementation of the freedesktop
  `org.freedesktop.Notifications` D-Bus server
  ([dbus_notification_server.dart L6-L8](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/notification/model/dbus_notification_server.dart#L6-L8)),
  a Linux desktop protocol. No macOS equivalent was examined.
- [H] **Not platform-bound, by the evidence.** Rows that exist on both sides in this survey, so no missing capability is
  implied: focus follows mouse and mouse warping (AeroSpace, yabai, Amethyst), modifier-drag move/resize (yabai),
  trackpad gestures (Rectangle Pro), per-app/per-title rules, CLI/IPC and event subscription (AeroSpace, yabai),
  native fullscreen and minimize handling, emulated or native multiple workspaces.

---

## 4. Gaps in this survey

**Unverified or thin cells**

- [H] **Magnet** is closed source with a homepage, a 7-question FAQ and an App Store description as its only primary
  sources. 42 of its 70 cells are ❓; its ❌ cells rest on the vendor's own scoping (e.g. FAQ: arranges windows only
  within the active Space). Treat its column as a floor.
- [M] **Rectangle Pro** cells come from rectangleapp.com/pro/docs, not source. Rows where the Pro docs say nothing are
  left at the free-Rectangle value, not confirmed absent.
- [M] **Veshell M02** (move window to another monitor) ❓: per-monitor Flutter views make it undeterminable from code.
  Veshell's `docs/specifications` are mostly stubs; a spec'd `Layout currentLayout` has no code counterpart, so L10 is ❌
  on code evidence. Veshell carries three different version strings and no tags were inspected; its README makes no
  stability claim.
- [M] **Polonium X01** ❓: could not confirm from source whether KWin's `windowAdded` fires for pre-existing windows
  when the script loads.
- [M] **macOS capability statements in §3** rest on AeroSpace's and yabai's own documentation. Apple's developer
  documentation pages for the Accessibility API returned 404 / empty bodies to the fetcher and are not cited.
- [M] GNOME's built-in **edge tiling** is not a column. From GNOME Help
  ([Tile windows](https://help.gnome.org/users/gnome-help/stable/shell-windows-tiled.html.en)) and mutter's
  `org.gnome.mutter.gschema.xml.in` (`edge-tiling`, `toggle-tiled-left`/`right` = Super+Left/Right): half-screen tiling by
  keyboard or by dragging to a vertical edge, maximize by dragging to the top. Neither source mentions quarter/corner
  tiling; mutter's `MetaTileMode` enum was not read to confirm.

**Abandoned, moved, or maintenance status**

- [H] **Bismuth** — GitHub repo `Bismuth-Forge/bismuth` is archived (API: `archived: true`, last push 2024-05-23); its
  README still targets Plasma 5.20+. Not surveyed; Polonium describes itself as "an (unofficial) spiritual successor to
  Bismuth built on KWin 6".
- [H] **Forge** — README L1: "# Forge needs a NEW MAINTAINER"; README points to a fork (`jcrussell/forge`), which was not
  surveyed.
- [H] **skhd** — README: "in maintenance mode".
- [H] **yabai** has moved: `koekeishiya/yabai` resolves to `asmvik/yabai`; links here use the new path at the same commit.
- [M] **PaperWM user scripting** has been broken since GNOME 45 ("user.js is not working in Gnome 45"), which is why its
  C02/L10 are ❌.

**Version-dependent**

- [H] **Hyprland 0.56** replaced hyprlang with a Lua config (`hyprland.lua`, `hl.*` API) and now builds scrolling and
  monocle layouts in (`src/layout/algorithm/tiled/{dwindle,master,monocle,scrolling}`); grid and columns ship only as
  example Lua layouts. Cells describe 0.56; older releases differ. The official `hyprland-plugins` manifest at survey
  time lists no overview plugin (hyprexpo appears only in a stale Nix snippet), so U04/U05 are ❌; third-party plugins
  were not surveyed.
- [H] **yabai's SIP requirements move between releases** (7.1.25 re-enabled moving windows between Spaces with SIP on).
  yabai removed its built-in status bar and, in 6.0.0, window borders — both ❌ now.
- [H] **niri** gained blur/background effects in 26.04 and per-output layout overrides in 25.11.
- [M] **i3** gaps (4.22) and tiling drag (4.21) are recent upstream additions.
- [M] **KWin** was read at 6.7.90, a development version; Plasma 6.x releases may lag it. Panel, pager and notifications
  are plasmashell and are ❌ for KWin by the scope rule.
- [M] **AeroSpace** was read at HEAD, not a release tag; its source reports `0.0.0-SNAPSHOT`.
- [M] **Pop Shell** auto-tiling is off by default (`tile-by-default` false); cells describe the feature set, not
  defaults. GNOME 46+ users are directed to the `master_noble` branch; HEAD of the default branch was read.

**Method limits**

- [M] The host-feature scope rule (§Method) decides several extension-column cells (Pop Shell W01/W02, Polonium
  W01/W05/R03, KWin U01/U02/U07). A different rule would shift those counts by ±1–2.
- [M] Row boundaries are judgement calls made once and applied uniformly, e.g. i3/sway fullscreen counted as ➖ for
  monocle; niri's preset column widths ➖ for snap presets; Veshell's sliding strip ✅ for scrolling strip.
- [L] Out of scope, not surveyed: material-shell (separate inventory), SwayFX, Krohnkite, the Forge fork,
  GNOME's own tiling assistant, Rectangle's Stage Manager handling, third-party Hyprland plugins.

---

## 5. Per-peer notes (observations with no taxonomy row)

- **AeroSpace** — i3-like command language with `;`, `||`, `&&`, `|`; dialog-detection heuristic floats dialogs;
  `enable off` suspends management; `summon-workspace`; sticky windows unsupported (default-config L214 → issue #2).
- **yabai** — sticky windows, picture-in-picture, window sub-layers, tree `--mirror`/`--rotate`, `menubar_opacity`.
- **Amethyst** — adjustable main-pane count; `window-max-count` auto-minimize; custom JS layouts are beta; source has
  fourColumn and widescreenTallRight layouts the README does not describe.
- **Rectangle** — Todo mode (one app pinned to a sidebar, others reflow); repeat-to-cycle sizes; cascade; Stage
  Manager strip awareness; several hidden `defaults` settings absent from its own TerminalCommands index. **Pro:**
  Window Throw, custom snap targets/panel, iCloud config sync, layouts that auto-apply on display change or window open.
- **Magnet** — zoom-button menu, iCloud settings sync, "infinite number of custom commands" (unspecified).
- **i3** — sticky floating windows; `move … to mark`; global fullscreen across outputs; `popup_during_fullscreen`.
- **sway** — `bindswitch` (lid/tablet); rich per-output options (adaptive sync, HDR, colour profiles, tearing);
  `focus_on_window_activation` defaults to `urgent` (i3: `smart`); no `append_layout`/`restart`.
- **Hyprland** — pseudotiling, pinned floating windows, window swallowing, tags, a permission system for plugins and
  screencopy, per-workspace layout by rule.
- **niri** — `maximize-window-to-edges`; windowed fullscreen; workspaces return to their original monitor on
  reconnect; top-left hot corner opens the overview; consume/expel windows into columns; screencast block-out rules.
- **PaperWM** — "take window" to carry windows across workspaces; focus modes (default/center/edge); per-workspace
  background and colour; swap workspace with monitor; disables GNOME edge-tiling, workspaces-only-on-primary and
  attach-modal-dialogs while running.
- **Veshell** — windows persist as relaunchable placeholders across reboot; workspaces auto-categorised by desktop
  entry category; a monitor can be split into several Screens; "game" display mode; built-in control centre (Wi-Fi,
  Bluetooth, audio, resource monitor) and polkit agent. Only 8 hotkey actions exist in total.
- **Pop Shell** — snap-to-grid for floating windows; hide title bars (X11 only); `max-window-width`; shortcut overlay.
- **Forge** — tiling toggled per workspace; drop-on-centre creates a tabbed/stacked group; `auto-exit-tabbed`;
  always-on-top floating windows.
- **KWin** — tiling is template-based: layouts drawn per output and per desktop (Meta+T), windows placed by Shift-drag
  or Custom Quick Tile, never automatically; Activities as a second grouping axis with rule support; per-window
  shortcut; Peek at Desktop. Repeating a quick-tile toward an occupied side moves the window to the next screen.
- **Polonium** — ultrawide single-window custom size; "Cycle Engine" shortcut; per-Activity layouts; Pager engine.
  Changelog lists a Monocle layout, but the FAQ now says monocle "is fundamentally incompatible with KWin tiles" and
  the shortcut is commented out.

---

## 6. Citations (every ✅ and ➖, plus notes on selected ❌/❓)

#### AeroSpace (39e51904)

Base: `https://github.com/nikitabobko/AeroSpace/blob/39e51904/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [docs/config-examples/default-config.toml#L29-L35](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/config-examples/default-config.toml#L29-L35) |  |
| L02 | ✅ | [docs/guide.adoc#L312-L321](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L312-L321) |  |
| L04 | ✅ | [docs/guide.adoc#L326-L339](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L326-L339) | accordion layouts, analog of i3 tabbed/stacked |
| L05 | ✅ | [docs/aerospace-fullscreen.adoc#L5-L24](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-fullscreen.adoc#L5-L24) | AeroSpace fullscreen, distinct from macOS fullscreen |
| L11 | ✅ | [docs/guide.adoc#L416-L425](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L416-L425) |  |
| L12 | ✅ | [docs/aerospace-layout.adoc#L52-L60](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-layout.adoc#L52-L60) |  |
| L13 | ✅ | [docs/aerospace-resize.adoc#L5-L28](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-resize.adoc#L5-L28) |  |
| L14 | ✅ | [docs/aerospace-swap.adoc#L5-L23](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-swap.adoc#L5-L23) |  |
| L15 | ✅ | [docs/config-examples/default-config.toml#L68-L81](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/config-examples/default-config.toml#L68-L81) | per-monitor values allowed |
| L16 | ✅ | [docs/aerospace-balance-sizes.adoc#L5](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-balance-sizes.adoc#L5) |  |
| W01 | ✅ | [docs/guide.adoc#L427-L446](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L427-L446) | emulated workspaces; inactive windows parked off-screen, not macOS Spaces |
| W02 | ✅ | [docs/aerospace-workspace-back-and-forth.adoc#L24-L25](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-workspace-back-and-forth.adoc#L24-L25) |  |
| W03 | ✅ | [docs/aerospace-workspace-back-and-forth.adoc#L24](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-workspace-back-and-forth.adoc#L24) |  |
| W04 | ➖ | [docs/guide.adoc#L720-L725](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L720-L725) | one workspace pool shared by all monitors; each monitor shows one |
| W05 | ✅ | [docs/aerospace-move-node-to-workspace.adoc#L5](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-move-node-to-workspace.adoc#L5) |  |
| W06 | ✅ | [docs/aerospace-workspace-back-and-forth.adoc#L4](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-workspace-back-and-forth.adoc#L4) |  |
| W08 | ✅ | [docs/aerospace-move-workspace-to-monitor.adoc#L5](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-move-workspace-to-monitor.adoc#L5) |  |
| M01 | ✅ | [docs/aerospace-focus-monitor.adoc#L5](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-focus-monitor.adoc#L5) |  |
| M02 | ✅ | [docs/aerospace-move-node-to-monitor.adoc#L5](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-move-node-to-monitor.adoc#L5) |  |
| M03 | ✅ | [docs/guide.adoc#L750-L763](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L750-L763) |  |
| F01 | ✅ | [docs/aerospace-focus.adoc#L80-L81](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-focus.adoc#L80-L81) |  |
| F02 | ✅ | [docs/config-examples/default-config.toml#L62](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/config-examples/default-config.toml#L62) |  |
| F03 | ✅ | [docs/guide.adoc#L629-L634](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L629-L634) | via `on-focus-changed` callback + `move-mouse` |
| F06 | ✅ | [docs/aerospace-focus-back-and-forth.adoc#L4-L25](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-focus-back-and-forth.adoc#L4-L25) | one previous window only |
| R01 | ✅ | [docs/guide.adoc#L596-L609](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L596-L609) |  |
| R02 | ✅ | [docs/guide.adoc#L587-L588](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L587-L588) |  |
| R03 | ✅ | [docs/guide.adoc#L592-L609](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L592-L609) |  |
| R04 | ✅ | [docs/guide.adoc#L810-L818](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L810-L818) |  |
| I01 | ✅ | [docs/guide.adoc#L145-L153](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L145-L153) |  |
| I02 | ✅ | [docs/guide.adoc#L116-L136](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L116-L136) |  |
| I03 | ➖ | [Sources/AppBundle/mouse/moveWithMouse.swift#L49-L73](https://github.com/nikitabobko/AeroSpace/blob/39e51904/Sources/AppBundle/mouse/moveWithMouse.swift#L49-L73) | plain drag swaps/resizes tiles; no modifier-drag |
| I04 | ➖ | [Sources/AppBundle/mouse/moveWithMouse.swift#L58-L70](https://github.com/nikitabobko/AeroSpace/blob/39e51904/Sources/AppBundle/mouse/moveWithMouse.swift#L58-L70) | between monitors only |
| U02 | ✅ | [docs/guide.adoc#L444](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L444) | menu-bar tray icon |
| C01 | ✅ | [docs/guide.adoc#L826-L829](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L826-L829) |  |
| C02 | ➖ | [docs/guide.adoc#L540-L560](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L540-L560) | command/shell callbacks and socket clients; no plugin API |
| C03 | ✅ | [docs/aerospace-subscribe.adoc#L4-L22](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-subscribe.adoc#L4-L22) |  |
| C04 | ✅ | [docs/config-examples/default-config.toml#L16-L18](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/config-examples/default-config.toml#L16-L18) |  |
| C05 | ✅ | [docs/guide.adoc#L81](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L81) | TOML |
| C06 | ✅ | [docs/guide.adoc#L242-L254](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/guide.adoc#L242-L254) |  |
| X03 | ✅ | [docs/aerospace-macos-native-fullscreen.adoc#L5](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-macos-native-fullscreen.adoc#L5) |  |
| X04 | ✅ | [docs/aerospace-macos-native-minimize.adoc#L5](https://github.com/nikitabobko/AeroSpace/blob/39e51904/docs/aerospace-macos-native-minimize.adoc#L5) |  |

#### yabai + skhd (yabai dd845723, skhd a7105d5b)

Base: `https://github.com/asmvik/yabai/blob/dd845723/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [doc/yabai.asciidoc#L31](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L31) |  |
| L02 | ✅ | [doc/yabai.asciidoc#L407-L409](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L407-L409) | `--insert` preselects split direction |
| L03 | ✅ | [doc/yabai.asciidoc#L235-L242](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L235-L242) |  |
| L04 | ✅ | [doc/yabai.asciidoc#L403-L405](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L403-L405) | `stack` layout / `--stack` |
| L05 | ✅ | [doc/yabai.asciidoc#L426](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L426) | `zoom-parent`, `zoom-fullscreen` |
| L11 | ✅ | [doc/yabai.asciidoc#L662-L664](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L662-L664) |  |
| L12 | ✅ | [doc/yabai.asciidoc#L426](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L426) |  |
| L13 | ✅ | [doc/yabai.asciidoc#L418-L424](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L418-L424) |  |
| L14 | ✅ | [doc/yabai.asciidoc#L397-L401](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L397-L401) |  |
| L15 | ✅ | [doc/yabai.asciidoc#L244-L257](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L244-L257) |  |
| L16 | ✅ | [doc/yabai.asciidoc#L331-L337](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L331-L337) |  |
| L17 | ➖ | [doc/yabai.asciidoc#L411-L412](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L411-L412) | `--grid rows:cols:x:y:w:h` on one window; presets are user skhd bindings |
| W01 | ➖ | [doc/yabai.asciidoc#L285-L359](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L285-L359) | drives native macOS Spaces; create/destroy/move needs SIP partially disabled (scripting addition) |
| W02 | ➖ | [doc/yabai.asciidoc#L306-L314](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L306-L314) | needs SIP partially disabled (scripting addition) |
| W03 | ✅ | [doc/yabai.asciidoc#L357-L359](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L357-L359) | space labels |
| W04 | ➖ | [doc/yabai.asciidoc#L276-L279](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L276-L279) | macOS per-display Spaces; `display --space` needs SIP partially disabled (scripting addition) |
| W05 | ✅ | [doc/yabai.asciidoc#L394-L395](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L394-L395) | works with SIP enabled again as of 7.1.25 (CHANGELOG) |
| W06 | ✅ | [doc/yabai.asciidoc#L108](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L108) | `recent` space selector |
| W07 | ➖ | [doc/yabai.asciidoc#L450-L459](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L450-L459) | scratchpad windows; needs SIP partially disabled (scripting addition) |
| W08 | ➖ | [doc/yabai.asciidoc#L327-L329](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L327-L329) | needs SIP partially disabled (scripting addition) |
| M01 | ✅ | [doc/yabai.asciidoc#L273-L274](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L273-L274) |  |
| M02 | ✅ | [doc/yabai.asciidoc#L391-L392](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L391-L392) |  |
| M03 | ➖ | [doc/yabai.asciidoc#L131-L144](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L131-L144) | per-space settings; no per-display config keys |
| F01 | ✅ | [doc/yabai.asciidoc#L372-L374](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L372-L374) |  |
| F02 | ✅ | [doc/yabai.asciidoc#L154-L155](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L154-L155) |  |
| F03 | ✅ | [doc/yabai.asciidoc#L151-L152](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L151-L152) |  |
| F06 | ✅ | [doc/yabai.asciidoc#L104](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L104) | `window --focus recent` |
| R01 | ✅ | [doc/yabai.asciidoc#L644-L645](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L644-L645) | matches app name regex |
| R02 | ✅ | [doc/yabai.asciidoc#L647-L648](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L647-L648) |  |
| R03 | ✅ | [doc/yabai.asciidoc#L659-L660](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L659-L660) |  |
| R04 | ✅ | [doc/yabai.asciidoc#L662-L664](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L662-L664) |  |
| R05 | ➖ | [doc/yabai.asciidoc#L662-L664](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L662-L664) | `manage=off` floats the window; not fully ignored |
| I01 | ➖ | [README.md#L40](https://github.com/asmvik/yabai/blob/dd845723/README.md#L40) | yabai binds no keys; skhd (same author) does |
| I02 | ➖ | [github.com/koekeishiya/skhd/blob/a7105d5b/README.md#L155-L163](https://github.com/koekeishiya/skhd/blob/a7105d5b/README.md#L155-L163) | skhd modes, not yabai |
| I03 | ✅ | [doc/yabai.asciidoc#L220-L227](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L220-L227) |  |
| I04 | ➖ | [src/event_loop.c#L1178-L1187](https://github.com/asmvik/yabai/blob/dd845723/src/event_loop.c#L1178-L1187) | drop onto a window on another display; not between spaces |
| U01 | ❌ | [CHANGELOG.md#L596](https://github.com/asmvik/yabai/blob/dd845723/CHANGELOG.md#L596) | built-in status bar was removed |
| U05 | ➖ | [doc/yabai.asciidoc#L351](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L351) | triggers macOS Mission Control / Exposé |
| V01 | ❌ | [CHANGELOG.md#L330](https://github.com/asmvik/yabai/blob/dd845723/CHANGELOG.md#L330) | borders removed in 6.0.0 |
| V02 | ➖ | [doc/yabai.asciidoc#L203-L211](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L203-L211) | needs SIP partially disabled (scripting addition); also Screen Recording permission |
| V03 | ➖ | [doc/yabai.asciidoc#L187-L201](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L187-L201) | needs SIP partially disabled (scripting addition) |
| V05 | ➖ | [doc/yabai.asciidoc#L183-L185](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L183-L185) | toggles macOS shadows only; needs SIP partially disabled (scripting addition) |
| C01 | ✅ | [doc/yabai.asciidoc#L464-L480](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L464-L480) |  |
| C02 | ➖ | [doc/yabai.asciidoc#L729-L742](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L729-L742) | shell actions on signals; no plugin API |
| C03 | ✅ | [doc/yabai.asciidoc#L740-L742](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L740-L742) | runs a command per event, not a stream |
| C05 | ➖ | [doc/yabai.asciidoc#L67-L70](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L67-L70) | config is an executed shell script, not declarative |
| C06 | ➖ | [doc/yabai.asciidoc#L67-L70](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L67-L70) | config script runs at launch; no dedicated autostart key |
| X01 | ➖ | [doc/yabai.asciidoc#L587-L593](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L587-L593) | adopts existing windows; previous split tree not restored |
| X03 | ✅ | [doc/yabai.asciidoc#L426](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L426) |  |
| X04 | ✅ | [doc/yabai.asciidoc#L381-L389](https://github.com/asmvik/yabai/blob/dd845723/doc/yabai.asciidoc#L381-L389) |  |

#### Amethyst 0.24.3 (6508ee2c)

Base: `https://github.com/ianyh/Amethyst/blob/6508ee2c/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [README.md#L130-L132](https://github.com/ianyh/Amethyst/blob/6508ee2c/README.md#L130-L132) |  |
| L03 | ✅ | [README.md#L196-L198](https://github.com/ianyh/Amethyst/blob/6508ee2c/README.md#L196-L198) |  |
| L04 | ➖ | [README.md#L144-L150](https://github.com/ianyh/Amethyst/blob/6508ee2c/README.md#L144-L150) | Two Pane layout shows one secondary window at a time; not user-built containers |
| L05 | ✅ | [README.md#L180-L182](https://github.com/ianyh/Amethyst/blob/6508ee2c/README.md#L180-L182) | Fullscreen layout |
| L06 | ✅ | [README.md#L130-L140](https://github.com/ianyh/Amethyst/blob/6508ee2c/README.md#L130-L140) | Tall, Tall-Right, Wide |
| L08 | ✅ | [README.md#L156-L166](https://github.com/ianyh/Amethyst/blob/6508ee2c/README.md#L156-L166) | 3Column-*, Column layouts |
| L10 | ✅ | [docs/custom-layouts.md#L1-L7](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/custom-layouts.md#L1-L7) | JavaScript layouts, labelled beta |
| L11 | ✅ | [docs/configuration-files.md#L20-L24](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L20-L24) |  |
| L12 | ✅ | [docs/configuration-files.md#L89](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L89) |  |
| L13 | ✅ | [docs/configuration-files.md#L64-L65](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L64-L65) | main-pane ratio only |
| L14 | ✅ | [docs/configuration-files.md#L81-L83](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L81-L83) |  |
| L15 | ✅ | [docs/configuration-files.md#L15-L19](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L15-L19) |  |
| W01 | ➖ | [README.md#L33](https://github.com/ianyh/Amethyst/blob/6508ee2c/README.md#L33) | uses native macOS Spaces; does not create them |
| W05 | ✅ | [docs/configuration-files.md#L86-L88](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L86-L88) | throw to native Space |
| W09 | ➖ | [Amethyst/Managers/ScreenManager.swift#L142-L151](https://github.com/ianyh/Amethyst/blob/6508ee2c/Amethyst/Managers/ScreenManager.swift#L142-L151) | per-Space layout choice restored (`restore-layouts-on-launch`) |
| M01 | ✅ | [docs/configuration-files.md#L77-L84](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L77-L84) |  |
| M02 | ✅ | [docs/configuration-files.md#L79-L85](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L79-L85) |  |
| M03 | ➖ | [docs/configuration-files.md#L42](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L42) | only `disable-padding-on-builtin-display` |
| F01 | ➖ | [docs/configuration-files.md#L74-L76](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L74-L76) | cycle order (cw/ccw/main), not directional |
| F02 | ✅ | [docs/configuration-files.md#L26](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L26) |  |
| F03 | ✅ | [docs/configuration-files.md#L25](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L25) |  |
| R01 | ✅ | [docs/configuration-files.md#L20-L21](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L20-L21) |  |
| R02 | ✅ | [Amethyst/Preferences/UserConfiguration.swift#L542-L546](https://github.com/ianyh/Amethyst/blob/6508ee2c/Amethyst/Preferences/UserConfiguration.swift#L542-L546) | title regex inside float rules only |
| R04 | ✅ | [docs/configuration-files.md#L20-L21](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L20-L21) |  |
| R05 | ➖ | [docs/configuration-files.md#L20-L21](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L20-L21) | listed apps float; no full ignore |
| I01 | ✅ | [docs/configuration-files.md#L47-L52](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L47-L52) |  |
| I03 | ➖ | [docs/configuration-files.md#L27-L28](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L27-L28) | plain drag swaps/resizes; no modifier-drag |
| U08 | ✅ | [README.md#L206](https://github.com/ianyh/Amethyst/blob/6508ee2c/README.md#L206) |  |
| C02 | ➖ | [docs/custom-layouts.md#L11-L29](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/custom-layouts.md#L11-L29) | JS API limited to custom layouts |
| C05 | ✅ | [docs/configuration-files.md#L3](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L3) | YAML |
| X01 | ➖ | [Amethyst/AppDelegate.swift#L70-L73](https://github.com/ianyh/Amethyst/blob/6508ee2c/Amethyst/AppDelegate.swift#L70-L73) | restores per-Space layout choice, then re-tiles |
| X04 | ➖ | [docs/configuration-files.md#L14](https://github.com/ianyh/Amethyst/blob/6508ee2c/docs/configuration-files.md#L14) | `window-max-count` auto-minimizes extras; no documented handling of user-minimized windows |

#### Rectangle 1.100 (10fd8ae5); Rectangle Pro 3.90 deltas marked

Base: `https://github.com/rxhanson/Rectangle/blob/10fd8ae5/`

| # | | Source | Note |
|---|---|---|---|
| L07 | ➖ | [TerminalCommands.md#L283-L298](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/TerminalCommands.md#L283-L298) | one-shot `tileAll` grid action (hidden defaults setting), not a persistent layout |
| L08 | ➖ | [README.md#L38-L46](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/README.md#L38-L46) | one-shot rows/columns action, not a persistent layout |
| L10 | ➖ | [rectangleapp.com/pro/docs/layouts/](https://rectangleapp.com/pro/docs/layouts/) | Rectangle Pro only: saved per-app layouts |
| L13 | ✅ | [Rectangle/WindowAction.swift#L20-L21](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/WindowAction.swift#L20-L21) |  |
| L14 | ➖ | [Rectangle/WindowAction.swift#L35-L38](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/WindowAction.swift#L35-L38) | moves one window to a screen edge; no layout to swap within |
| L15 | ✅ | [TerminalCommands.md#L423-L443](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/TerminalCommands.md#L423-L443) |  |
| L17 | ✅ | [README.md#L57-L61](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/README.md#L57-L61) |  |
| L18 | ✅ | [README.md#L27-L36](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/README.md#L27-L36) |  |
| W01 | ❌ | [README.md#L91-L93](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/README.md#L91-L93) | cannot move windows to other Spaces |
| W05 | ➖ | [rectangleapp.com/pro/docs/keyboard-shortcuts/](https://rectangleapp.com/pro/docs/keyboard-shortcuts/) | Rectangle Pro only: next/previous macOS Space |
| W07 | ➖ | [rectangleapp.com/pro/docs/stash/](https://rectangleapp.com/pro/docs/stash/) | Rectangle Pro only: edge stash, not a workspace |
| M02 | ✅ | [Rectangle/WindowAction.swift#L18-L19](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/WindowAction.swift#L18-L19) |  |
| M03 | ➖ | [TerminalCommands.md#L434-L443](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/TerminalCommands.md#L434-L443) | only screen-edge gaps vary per screen (hidden defaults) |
| F03 | ✅ | [Rectangle/WindowManager.swift#L273-L290](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/WindowManager.swift#L273-L290) |  |
| F04 | ➖ | [TerminalCommands.md#L632-L638](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/TerminalCommands.md#L632-L638) | stack badge lists windows stacked at one position (hidden defaults setting) |
| R01 | ✅ | [Rectangle/ApplicationToggle.swift#L52-L69](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/ApplicationToggle.swift#L52-L69) |  |
| R02 | ➖ | [rectangleapp.com/pro/docs/layouts/](https://rectangleapp.com/pro/docs/layouts/) | Rectangle Pro only: title match inside layouts |
| R05 | ✅ | [README.md#L48-L55](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/README.md#L48-L55) |  |
| I01 | ✅ | [Rectangle/ShortcutManager.swift](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/ShortcutManager.swift) |  |
| I03 | ➖ | [rectangleapp.com/pro/docs/cursor-movement/](https://rectangleapp.com/pro/docs/cursor-movement/) | Rectangle Pro only |
| I05 | ➖ | [rectangleapp.com/pro/docs/cursor-movement/](https://rectangleapp.com/pro/docs/cursor-movement/) | Rectangle Pro only: trackpad Window Throw |
| U08 | ✅ | [Rectangle/PrefsWindow/SettingsViewController.swift#L8-L90](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/PrefsWindow/SettingsViewController.swift#L8-L90) |  |
| C01 | ➖ | [Rectangle/AppDelegate.swift#L623-L700](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/AppDelegate.swift#L623-L700) | `rectangle://` URL scheme runs actions; no state query (Pro adds layout actions) |
| C05 | ➖ | [Rectangle/PrefsWindow/Config.swift#L95-L104](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/PrefsWindow/Config.swift#L95-L104) | JSON import at launch; live settings in UserDefaults |
| X02 | ➖ | [rectangleapp.com/pro/docs/layouts/](https://rectangleapp.com/pro/docs/layouts/) | Rectangle Pro only: save/restore layouts, launches closed apps |
| X03 | ➖ | [Rectangle/Snapping/SnappingManager.swift#L87-L100](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/Snapping/SnappingManager.swift#L87-L100) | drag-snapping suppressed for fullscreen windows only |
| X04 | ➖ | [Rectangle/WindowManager+CooperativeCornerResize.swift#L113-L118](https://github.com/rxhanson/Rectangle/blob/10fd8ae5/Rectangle/WindowManager+CooperativeCornerResize.swift#L113-L118) | skips minimized windows; Pro layouts can minimize/unminimize apps |

#### Magnet 3.0.7 (Mac App Store, 2025-04-12; closed source)


| # | | Source | Note |
|---|---|---|---|
| L17 | ✅ | [magnet.crowdcafe.com/](https://magnet.crowdcafe.com/) | “Fullscreen, halves, quarters & thirds” |
| L18 | ✅ | [magnet.crowdcafe.com/](https://magnet.crowdcafe.com/) |  |
| W01 | ❌ | [magnet.crowdcafe.com/faq.html](https://magnet.crowdcafe.com/faq.html) | “You can not do it across different Spaces.” |
| I01 | ✅ | [apps.apple.com/app/magnet/id441258766](https://apps.apple.com/app/magnet/id441258766) |  |

#### i3 4.25 (9be3249a)

Base: `https://github.com/i3/i3/blob/9be3249a/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [docs/userguide#L42-L52](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L42-L52) |  |
| L02 | ✅ | [docs/userguide#L2335-L2354](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2335-L2354) |  |
| L04 | ✅ | [docs/userguide#L86-L103](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L86-L103) |  |
| L05 | ➖ | [docs/userguide#L107-L113](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L107-L113) | no monocle mode; per-window fullscreen or a tabbed container |
| L10 | ➖ | [docs/layout-saving#L38-L72](https://github.com/i3/i3/blob/9be3249a/docs/layout-saving#L38-L72) | static JSON tree templates (`append_layout`), no layout engine |
| L11 | ✅ | [docs/userguide#L179-L197](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L179-L197) |  |
| L12 | ✅ | [docs/userguide#L188-L192](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L188-L192) |  |
| L13 | ✅ | [docs/userguide#L2816-L2836](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2816-L2836) |  |
| L14 | ✅ | [docs/userguide#L2509-L2523](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2509-L2523) |  |
| L15 | ✅ | [docs/userguide#L1459-L1502](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L1459-L1502) | upstream since 4.22 |
| L17 | ➖ | [docs/userguide#L2524-L2536](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2524-L2536) | `move position center` + `resize set … ppt` for floating windows; no named presets |
| W01 | ✅ | [docs/userguide#L136-L141](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L136-L141) |  |
| W02 | ✅ | [src/workspace.c#L525-L535](https://github.com/i3/i3/blob/9be3249a/src/workspace.c#L525-L535) |  |
| W03 | ✅ | [docs/userguide#L2657-L2662](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2657-L2662) |  |
| W04 | ✅ | [docs/userguide#L147-L150](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L147-L150) | names share one global namespace |
| W05 | ✅ | [docs/userguide#L152-L157](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L152-L157) |  |
| W06 | ✅ | [docs/userguide#L2640-L2643](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2640-L2643) |  |
| W07 | ✅ | [docs/userguide#L3103-L3113](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L3103-L3113) |  |
| W08 | ✅ | [docs/userguide#L2764-L2766](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2764-L2766) |  |
| W09 | ✅ | [src/util.c#L289-L311](https://github.com/i3/i3/blob/9be3249a/src/util.c#L289-L311) | in-place `restart` only |
| M01 | ✅ | [docs/userguide#L2450-L2461](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2450-L2461) |  |
| M02 | ✅ | [docs/userguide#L2764-L2765](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2764-L2765) |  |
| M03 | ✅ | [docs/userguide#L1057-L1068](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L1057-L1068) | workspace→output assignment; modes/scale via xrandr |
| F01 | ✅ | [docs/userguide#L2431-L2432](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2431-L2432) |  |
| F02 | ✅ | [docs/userguide#L1183-L1195](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L1183-L1195) |  |
| F03 | ✅ | [docs/userguide#L1202-L1214](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L1202-L1214) |  |
| F04 | ➖ | [docs/userguide#L2873-L2886](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2873-L2886) | user-assigned marks; no automatic hint overlay |
| F05 | ✅ | [docs/userguide#L2245-L2248](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2245-L2248) |  |
| R01 | ✅ | [docs/userguide#L2219-L2226](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2219-L2226) |  |
| R02 | ✅ | [docs/userguide#L2241-L2244](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L2241-L2244) |  |
| R03 | ✅ | [docs/userguide#L917-L925](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L917-L925) |  |
| R04 | ✅ | [docs/userguide#L805-L819](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L805-L819) |  |
| I01 | ✅ | [docs/userguide#L488-L551](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L488-L551) |  |
| I02 | ✅ | [docs/userguide#L593-L641](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L593-L641) |  |
| I03 | ✅ | [docs/userguide#L645-L657](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L645-L657) |  |
| I04 | ➖ | [src/tiling_drag.c#L53-L62](https://github.com/i3/i3/blob/9be3249a/src/tiling_drag.c#L53-L62) | visible workspaces/monitors only |
| U01 | ✅ | [docs/userguide#L1533-L1544](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L1533-L1544) | i3bar |
| U02 | ✅ | [docs/userguide#L1924-L1929](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L1924-L1929) |  |
| U03 | ✅ | [docs/userguide#L95-L100](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L95-L100) |  |
| U06 | ➖ | [etc/config#L62-L67](https://github.com/i3/i3/blob/9be3249a/etc/config#L62-L67) | binds external dmenu; ships i3-dmenu-desktop wrapper |
| U08 | ➖ | [man/i3-config-wizard.man#L36-L39](https://github.com/i3/i3/blob/9be3249a/man/i3-config-wizard.man#L36-L39) | first-run modifier chooser only |
| V01 | ✅ | [docs/userguide#L735-L753](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L735-L753) |  |
| C01 | ✅ | [docs/userguide#L1157-L1181](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L1157-L1181) |  |
| C02 | ➖ | [docs/userguide#L1159-L1161](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L1159-L1161) | external IPC clients only; no in-process plugins |
| C03 | ✅ | [docs/ipc#L943-L952](https://github.com/i3/i3/blob/9be3249a/docs/ipc#L943-L952) |  |
| C04 | ✅ | [docs/userguide#L3088-L3099](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L3088-L3099) |  |
| C05 | ✅ | [docs/userguide#L335-L342](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L335-L342) |  |
| C06 | ✅ | [docs/userguide#L1027-L1043](https://github.com/i3/i3/blob/9be3249a/docs/userguide#L1027-L1043) |  |
| X01 | ✅ | [src/main.c#L923-L926](https://github.com/i3/i3/blob/9be3249a/src/main.c#L923-L926) | in-place restart serialises and reloads the tree |
| X02 | ✅ | [docs/layout-saving#L14-L72](https://github.com/i3/i3/blob/9be3249a/docs/layout-saving#L14-L72) | placeholders swallow windows; apps not relaunched |
| X03 | ✅ | [src/handlers.c#L681-L690](https://github.com/i3/i3/blob/9be3249a/src/handlers.c#L681-L690) |  |
| X04 | ✅ | [src/handlers.c#L847-L858](https://github.com/i3/i3/blob/9be3249a/src/handlers.c#L847-L858) | iconify requests rejected; scratchpad fills the role |

#### sway 1.13-dev (793a1f0c)

Base: `https://github.com/swaywm/sway/blob/793a1f0c/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [sway/tree/view.c#L896-L901](https://github.com/swaywm/sway/blob/793a1f0c/sway/tree/view.c#L896-L901) |  |
| L02 | ✅ | [sway/sway.5.scd#L353-L367](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L353-L367) |  |
| L04 | ✅ | [sway/sway.5.scd#L178-L185](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L178-L185) |  |
| L05 | ➖ | [sway/sway.5.scd#L154-L157](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L154-L157) | no monocle mode; fullscreen or tabbed |
| L11 | ✅ | [sway/sway.5.scd#L706-L709](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L706-L709) |  |
| L12 | ✅ | [sway/sway.5.scd#L119-L120](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L119-L120) |  |
| L13 | ✅ | [sway/sway.5.scd#L309-L337](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L309-L337) |  |
| L14 | ✅ | [sway/sway.5.scd#L234-L237](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L234-L237) |  |
| L15 | ✅ | [sway/sway.5.scd#L784-L790](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L784-L790) |  |
| L17 | ➖ | [sway/sway.5.scd#L239-L248](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L239-L248) | `move position … ppt` for floating windows; no named presets |
| W01 | ✅ | [sway/sway.5.scd#L927-L939](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L927-L939) |  |
| W02 | ✅ | [sway/tree/workspace.c#L314-L332](https://github.com/swaywm/sway/blob/793a1f0c/sway/tree/workspace.c#L314-L332) |  |
| W03 | ✅ | [sway/sway.5.scd#L927-L930](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L927-L930) |  |
| W04 | ✅ | [sway/sway.5.scd#L941-L946](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L941-L946) | names share one global namespace |
| W05 | ✅ | [sway/sway.5.scd#L255-L258](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L255-L258) |  |
| W06 | ✅ | [sway/sway.5.scd#L948-L949](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L948-L949) |  |
| W07 | ✅ | [sway/sway.5.scd#L338-L340](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L338-L340) |  |
| W08 | ✅ | [sway/sway.5.scd#L281-L291](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L281-L291) |  |
| M01 | ✅ | [sway/sway.5.scd#L139-L143](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L139-L143) |  |
| M02 | ✅ | [sway/sway.5.scd#L271-L276](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L271-L276) |  |
| M03 | ✅ | [sway/sway-output.5.scd#L73-L79](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway-output.5.scd#L73-L79) |  |
| F01 | ✅ | [sway/sway.5.scd#L125-L127](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L125-L127) |  |
| F02 | ✅ | [sway/sway.5.scd#L731-L734](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L731-L734) |  |
| F03 | ✅ | [sway/sway.5.scd#L842-L845](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L842-L845) |  |
| F04 | ➖ | [sway/sway.5.scd#L826-L832](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L826-L832) | user-assigned marks; no automatic hint overlay |
| F05 | ✅ | [sway/sway.5.scd#L1076-L1078](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L1076-L1078) |  |
| R01 | ✅ | [sway/sway.5.scd#L1025-L1035](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L1025-L1035) |  |
| R02 | ✅ | [sway/sway.5.scd#L1071-L1074](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L1071-L1074) |  |
| R03 | ✅ | [sway/sway.5.scd#L421-L426](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L421-L426) |  |
| R04 | ✅ | [sway/sway.5.scd#L780-L782](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L780-L782) |  |
| I01 | ✅ | [sway/sway.5.scd#L435-L440](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L435-L440) |  |
| I02 | ✅ | [sway/sway.5.scd#L834-L840](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L834-L840) |  |
| I03 | ✅ | [sway/sway.5.scd#L725-L729](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L725-L729) |  |
| I04 | ➖ | [sway/sway.5.scd#L880-L885](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L880-L885) | visible outputs/workspaces only |
| I05 | ✅ | [sway/sway.5.scd#L542-L547](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L542-L547) |  |
| U01 | ✅ | [sway/sway-bar.5.scd#L7-L19](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway-bar.5.scd#L7-L19) | swaybar |
| U02 | ✅ | [sway/sway-bar.5.scd#L138-L139](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway-bar.5.scd#L138-L139) |  |
| U03 | ✅ | [sway/sway.5.scd#L106-L109](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L106-L109) |  |
| U06 | ➖ | [config.in#L74-L74](https://github.com/swaywm/sway/blob/793a1f0c/config.in#L74-L74) | default config binds external wmenu |
| V01 | ✅ | [sway/sway.5.scd#L601-L605](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L601-L605) |  |
| V03 | ✅ | [sway/sway.5.scd#L297-L299](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L297-L299) | per-window opacity; no automatic dimming |
| C01 | ✅ | [sway/sway.5.scd#L40-L41](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L40-L41) |  |
| C02 | ➖ | [sway/sway-ipc.7.scd#L169-L178](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway-ipc.7.scd#L169-L178) | external IPC clients only |
| C03 | ✅ | [sway/sway-ipc.7.scd#L1473-L1478](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway-ipc.7.scd#L1473-L1478) |  |
| C04 | ✅ | [sway/sway.5.scd#L301-L304](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L301-L304) |  |
| C05 | ✅ | [sway/sway.5.scd#L9-L12](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L9-L12) |  |
| C06 | ✅ | [sway/sway.5.scd#L711-L715](https://github.com/swaywm/sway/blob/793a1f0c/sway/sway.5.scd#L711-L715) |  |
| X03 | ✅ | [sway/desktop/xdg_shell.c#L395-L415](https://github.com/swaywm/sway/blob/793a1f0c/sway/desktop/xdg_shell.c#L395-L415) |  |
| X04 | ➖ | [sway/desktop/xwayland.c#L622-L635](https://github.com/swaywm/sway/blob/793a1f0c/sway/desktop/xwayland.c#L622-L635) | XWayland minimize requests only |

#### Hyprland 0.56.0 (c31b90c5; wiki 507259eb)

Base: `https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [github.com/hyprwm/Hyprland/blob/c31b90c5/src/layout/supplementary/WorkspaceAlgoMatcher.cpp#L22](https://github.com/hyprwm/Hyprland/blob/c31b90c5/src/layout/supplementary/WorkspaceAlgoMatcher.cpp#L22) | default layout is dwindle |
| L02 | ➖ | [configuring/layouts/dwindle-layout.md#L72-L77](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/layouts/dwindle-layout.md#L72-L77) | dwindle preselect/togglesplit only; no nested i3-style containers |
| L03 | ✅ | [configuring/layouts/dwindle-layout.md#L6](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/layouts/dwindle-layout.md#L6) |  |
| L04 | ✅ | [configuring/core/dispatchers.md#L164-L169](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L164-L169) | groups |
| L05 | ✅ | [configuring/layouts/monocle-layout.md#L6](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/layouts/monocle-layout.md#L6) |  |
| L06 | ✅ | [configuring/layouts/master-layout.md#L6-L7](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/layouts/master-layout.md#L6-L7) |  |
| L07 | ➖ | [github.com/hyprwm/Hyprland/blob/c31b90c5/example/layouts/grid.lua#L1-L12](https://github.com/hyprwm/Hyprland/blob/c31b90c5/example/layouts/grid.lua#L1-L12) | example Lua layout, user-registered |
| L08 | ➖ | [configuring/layouts/custom-layouts.md#L11-L26](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/layouts/custom-layouts.md#L11-L26) | example Lua layout, user-registered |
| L09 | ✅ | [configuring/layouts/scrolling-layout.md#L6](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/layouts/scrolling-layout.md#L6) |  |
| L10 | ✅ | [configuring/layouts/custom-layouts.md#L6-L7](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/layouts/custom-layouts.md#L6-L7) | Lua `hl.layout.register` |
| L11 | ✅ | [configuring/core/dispatchers.md#L101](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L101) |  |
| L12 | ✅ | [configuring/core/dispatchers.md#L45](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L45) |  |
| L13 | ✅ | [configuring/core/dispatchers.md#L127](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L127) |  |
| L14 | ✅ | [configuring/core/dispatchers.md#L105-L114](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L105-L114) |  |
| L15 | ✅ | [configuring/core/config-options.md#L73-L74](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/config-options.md#L73-L74) |  |
| L16 | ➖ | [configuring/layouts/scrolling-layout.md#L47](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/layouts/scrolling-layout.md#L47) | scrolling layout only |
| W01 | ✅ | [configuring/core/rules/workspace-rules.md#L24-L41](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/rules/workspace-rules.md#L24-L41) |  |
| W02 | ✅ | [configuring/core/rules/workspace-rules.md#L37](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/rules/workspace-rules.md#L37) |  |
| W03 | ✅ | [configuring/core/rules/workspace-rules.md#L47](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/rules/workspace-rules.md#L47) |  |
| W04 | ✅ | [configuring/core/advanced-configuration/events.md#L56](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/advanced-configuration/events.md#L56) |  |
| W05 | ✅ | [configuring/core/dispatchers.md#L106](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L106) |  |
| W06 | ✅ | [configuring/core/config-options.md#L680](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/config-options.md#L680) |  |
| W07 | ✅ | [configuring/core/dispatchers.md#L175-L181](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L175-L181) | special workspace |
| W08 | ✅ | [configuring/core/dispatchers.md#L137](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L137) |  |
| M01 | ✅ | [configuring/core/dispatchers.md#L61](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L61) |  |
| M02 | ✅ | [configuring/core/dispatchers.md#L107](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L107) |  |
| M03 | ✅ | [configuring/core/monitors/_index.md#L10-L17](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/monitors/_index.md#L10-L17) |  |
| F01 | ✅ | [configuring/core/dispatchers.md#L60](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L60) |  |
| F02 | ✅ | [configuring/core/config-options.md#L371](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/config-options.md#L371) |  |
| F03 | ✅ | [configuring/core/config-options.md#L747-L754](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/config-options.md#L747-L754) |  |
| F05 | ✅ | [configuring/core/dispatchers.md#L64](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L64) |  |
| F06 | ✅ | [configuring/core/dispatchers.md#L65](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L65) |  |
| R01 | ✅ | [configuring/core/rules/window-rules.md#L28](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/rules/window-rules.md#L28) |  |
| R02 | ✅ | [configuring/core/rules/window-rules.md#L41](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/rules/window-rules.md#L41) |  |
| R03 | ✅ | [configuring/core/rules/window-rules.md#L85](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/rules/window-rules.md#L85) |  |
| R04 | ✅ | [configuring/core/rules/window-rules.md#L70](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/rules/window-rules.md#L70) |  |
| I01 | ✅ | [configuring/core/binds/_index.md#L22](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/binds/_index.md#L22) |  |
| I02 | ✅ | [configuring/core/binds/submaps.md#L8-L10](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/binds/submaps.md#L8-L10) |  |
| I03 | ✅ | [configuring/core/binds/devices/mouse.md#L47-L52](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/binds/devices/mouse.md#L47-L52) |  |
| I04 | ✅ | [github.com/hyprwm/Hyprland/blob/c31b90c5/src/layout/supplementary/DragController.cpp#L485-L490](https://github.com/hyprwm/Hyprland/blob/c31b90c5/src/layout/supplementary/DragController.cpp#L485-L490) |  |
| I05 | ✅ | [configuring/core/binds/gestures.md#L8-L22](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/binds/gestures.md#L8-L22) |  |
| U03 | ✅ | [configuring/core/config-options.md#L550-L556](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/config-options.md#L550-L556) | groupbar |
| U06 | ➖ | [configuring/core/_index.md#L144](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/_index.md#L144) | hyprlauncher is a separate hyprwm app |
| V01 | ✅ | [configuring/core/config-options.md#L90](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/config-options.md#L90) |  |
| V02 | ✅ | [configuring/core/animations.md#L8](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/animations.md#L8) |  |
| V03 | ✅ | [configuring/core/config-options.md#L116-L121](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/config-options.md#L116-L121) |  |
| V04 | ✅ | [configuring/core/config-options.md#L148-L154](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/config-options.md#L148-L154) |  |
| V05 | ✅ | [configuring/core/config-options.md#L299-L305](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/config-options.md#L299-L305) |  |
| V06 | ✅ | [configuring/core/config-options.md#L122](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/config-options.md#L122) |  |
| C01 | ✅ | [configuring/core/advanced-configuration/using-hyprctl.md#L6-L7](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/advanced-configuration/using-hyprctl.md#L6-L7) |  |
| C02 | ✅ | [hyprland-plugins/using-plugins.md#L10-L21](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/hyprland-plugins/using-plugins.md#L10-L21) | C++ plugins + Lua config API |
| C03 | ✅ | [ipc/_index.md#L25-L30](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/ipc/_index.md#L25-L30) |  |
| C04 | ✅ | [configuring/core/_index.md#L19-L20](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/_index.md#L19-L20) |  |
| C05 | ➖ | [configuring/core/_index.md#L10](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/_index.md#L10) | `hyprland.lua` is an executed Lua script, not declarative |
| C06 | ✅ | [configuring/core/autostart.md#L6-L13](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/autostart.md#L6-L13) |  |
| X03 | ✅ | [configuring/core/dispatchers.md#L225-L242](https://github.com/hyprwm/hyprland-wiki/blob/507259eb/content/configuring/core/dispatchers.md#L225-L242) |  |
| X04 | ➖ | [github.com/hyprwm/Hyprland/blob/c31b90c5/src/desktop/view/window/WaylandBackend.cpp#L364-L366](https://github.com/hyprwm/Hyprland/blob/c31b90c5/src/desktop/view/window/WaylandBackend.cpp#L364-L366) | minimize requests ignored, exposed only as an event |

#### niri 26.4.0 (849c576f)

Base: `https://github.com/YaLTeR/niri/blob/849c576f/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [README.md#L17](https://github.com/YaLTeR/niri/blob/849c576f/README.md#L17) |  |
| L04 | ✅ | [docs/wiki/Tabs.md#L5-L6](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Tabs.md#L5-L6) | tabbed columns |
| L05 | ✅ | [docs/wiki/Fullscreen-and-Maximize.md#L6-L9](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Fullscreen-and-Maximize.md#L6-L9) | `maximize-column` |
| L09 | ✅ | [README.md#L17-L20](https://github.com/YaLTeR/niri/blob/849c576f/README.md#L17-L20) |  |
| L11 | ✅ | [docs/wiki/Floating-Windows.md#L5-L7](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Floating-Windows.md#L5-L7) |  |
| L12 | ✅ | [docs/wiki/Floating-Windows.md#L10](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Floating-Windows.md#L10) |  |
| L13 | ✅ | [niri-ipc/src/lib.rs#L761](https://github.com/YaLTeR/niri/blob/849c576f/niri-ipc/src/lib.rs#L761) |  |
| L14 | ✅ | [resources/default-config.kdl#L413](https://github.com/YaLTeR/niri/blob/849c576f/resources/default-config.kdl#L413) |  |
| L15 | ✅ | [docs/wiki/Configuration:-Layout.md#L102-L116](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Layout.md#L102-L116) |  |
| L17 | ➖ | [docs/wiki/Configuration:-Layout.md#L177-L182](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Layout.md#L177-L182) | preset column widths on the strip, not screen regions |
| W01 | ✅ | [docs/wiki/Workspaces.md#L3-L6](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Workspaces.md#L3-L6) |  |
| W02 | ✅ | [docs/wiki/Workspaces.md#L7-L10](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Workspaces.md#L7-L10) |  |
| W03 | ✅ | [docs/wiki/Configuration:-Named-Workspaces.md#L5-L15](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Named-Workspaces.md#L5-L15) |  |
| W04 | ✅ | [docs/wiki/Workspaces.md#L5](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Workspaces.md#L5) |  |
| W05 | ✅ | [niri-ipc/src/lib.rs#L508](https://github.com/YaLTeR/niri/blob/849c576f/niri-ipc/src/lib.rs#L508) |  |
| W06 | ✅ | [niri-ipc/src/lib.rs#L484](https://github.com/YaLTeR/niri/blob/849c576f/niri-ipc/src/lib.rs#L484) |  |
| W07 | ❌ | [docs/wiki/FAQ.md#L86-L91](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/FAQ.md#L86-L91) | no scratchpad; sticky windows “Not yet” |
| W08 | ✅ | [docs/wiki/Workspaces.md#L23](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Workspaces.md#L23) |  |
| M01 | ✅ | [niri-ipc/src/lib.rs#L607](https://github.com/YaLTeR/niri/blob/849c576f/niri-ipc/src/lib.rs#L607) |  |
| M02 | ✅ | [niri-ipc/src/lib.rs#L625](https://github.com/YaLTeR/niri/blob/849c576f/niri-ipc/src/lib.rs#L625) |  |
| M03 | ✅ | [docs/wiki/Configuration:-Outputs.md#L332-L350](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Outputs.md#L332-L350) |  |
| F01 | ✅ | [resources/default-config.kdl#L404](https://github.com/YaLTeR/niri/blob/849c576f/resources/default-config.kdl#L404) |  |
| F02 | ✅ | [docs/wiki/Configuration:-Input.md#L338-L345](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Input.md#L338-L345) |  |
| F03 | ✅ | [docs/wiki/Configuration:-Input.md#L311-L313](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Input.md#L311-L313) |  |
| F05 | ✅ | [docs/wiki/Configuration:-Window-Rules.md#L311-L316](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Window-Rules.md#L311-L316) |  |
| F06 | ✅ | [docs/wiki/Configuration:-Recent-Windows.md#L5-L30](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Recent-Windows.md#L5-L30) |  |
| R01 | ✅ | [docs/wiki/Configuration:-Window-Rules.md#L174-L177](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Window-Rules.md#L174-L177) |  |
| R02 | ✅ | [docs/wiki/Configuration:-Window-Rules.md#L174-L177](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Window-Rules.md#L174-L177) |  |
| R03 | ✅ | [docs/wiki/Configuration:-Window-Rules.md#L408-L412](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Window-Rules.md#L408-L412) |  |
| R04 | ✅ | [docs/wiki/Configuration:-Window-Rules.md#L481-L485](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Window-Rules.md#L481-L485) |  |
| I01 | ✅ | [docs/wiki/Configuration:-Key-Bindings.md#L3-L15](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Key-Bindings.md#L3-L15) |  |
| I03 | ✅ | [docs/wiki/Gestures.md#L9-L23](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Gestures.md#L9-L23) |  |
| I04 | ✅ | [docs/wiki/Overview.md#L26-L35](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Overview.md#L26-L35) |  |
| I05 | ✅ | [docs/wiki/Gestures.md#L53-L67](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Gestures.md#L53-L67) |  |
| U03 | ✅ | [docs/wiki/Tabs.md#L22](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Tabs.md#L22) |  |
| U04 | ✅ | [docs/wiki/Configuration:-Recent-Windows.md#L99-L101](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Recent-Windows.md#L99-L101) | previews in the recent-windows switcher |
| U05 | ✅ | [docs/wiki/Overview.md#L5-L6](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Overview.md#L5-L6) |  |
| V01 | ✅ | [docs/wiki/Configuration:-Layout.md#L252-L257](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Layout.md#L252-L257) |  |
| V02 | ✅ | [docs/wiki/Configuration:-Animations.md#L3](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Animations.md#L3) |  |
| V03 | ✅ | [docs/wiki/Configuration:-Window-Rules.md#L627-L629](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Window-Rules.md#L627-L629) |  |
| V04 | ✅ | [docs/wiki/Window-Effects.md#L3-L19](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Window-Effects.md#L3-L19) | since 26.04 |
| V05 | ✅ | [docs/wiki/Configuration:-Layout.md#L382-L386](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Layout.md#L382-L386) |  |
| V06 | ✅ | [docs/wiki/Configuration:-Window-Rules.md#L848-L852](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Window-Rules.md#L848-L852) |  |
| C01 | ✅ | [docs/wiki/IPC.md#L1-L2](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/IPC.md#L1-L2) |  |
| C02 | ❌ | [docs/wiki/FAQ.md#L101](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/FAQ.md#L101) | no plugin API; FAQ points to IPC scripting |
| C03 | ✅ | [docs/wiki/IPC.md#L11-L19](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/IPC.md#L11-L19) |  |
| C04 | ✅ | [docs/wiki/Configuration:-Introduction.md#L25-L27](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Introduction.md#L25-L27) |  |
| C05 | ✅ | [docs/wiki/Configuration:-Introduction.md#L38-L40](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Introduction.md#L38-L40) | KDL |
| C06 | ✅ | [docs/wiki/Configuration:-Miscellaneous.md#L67-L74](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Configuration:-Miscellaneous.md#L67-L74) |  |
| X03 | ✅ | [docs/wiki/Fullscreen-and-Maximize.md#L32-L43](https://github.com/YaLTeR/niri/blob/849c576f/docs/wiki/Fullscreen-and-Maximize.md#L32-L43) |  |
| X04 | ❌ | [src/protocols/foreign_toplevel.rs#L574-L575](https://github.com/YaLTeR/niri/blob/849c576f/src/protocols/foreign_toplevel.rs#L574-L575) | minimize requests ignored |

#### PaperWM 50.0.1 (8bf6dd26)

Base: `https://github.com/paperwm/PaperWM/blob/8bf6dd26/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [README.md#L90](https://github.com/paperwm/PaperWM/blob/8bf6dd26/README.md#L90) |  |
| L02 | ➖ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L365-L375](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L365-L375) | one level only: slurp/barf windows into a column |
| L05 | ➖ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L433-L435](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L433-L435) | maximize width within the strip |
| L09 | ✅ | [README.md#L5](https://github.com/paperwm/PaperWM/blob/8bf6dd26/README.md#L5) |  |
| L10 | ❌ | [extension.js#L162-L177](https://github.com/paperwm/PaperWM/blob/8bf6dd26/extension.js#L162-L177) | user.js loading disabled since GNOME 45 |
| L11 | ✅ | [README.md#L204-L205](https://github.com/paperwm/PaperWM/blob/8bf6dd26/README.md#L204-L205) | scratch layer |
| L12 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L168-L170](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L168-L170) |  |
| L13 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L378-L395](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L378-L395) |  |
| L14 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L348-L362](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L348-L362) |  |
| L15 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L520-L537](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L520-L537) |  |
| L17 | ➖ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L620-L627](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L620-L627) | cycle width/height ratios + center; no screen-region presets |
| L18 | ❌ | [README.md#L379](https://github.com/paperwm/PaperWM/blob/8bf6dd26/README.md#L379) | disables GNOME edge tiling |
| W01 | ✅ | [README.md#L164](https://github.com/paperwm/PaperWM/blob/8bf6dd26/README.md#L164) |  |
| W02 | ➖ | [patches.js#L583-L596](https://github.com/paperwm/PaperWM/blob/8bf6dd26/patches.js#L583-L596) | uses GNOME dynamic-workspaces setting; enforces a minimum count |
| W03 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L459-L461](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L459-L461) |  |
| W04 | ✅ | [README.md#L5](https://github.com/paperwm/PaperWM/blob/8bf6dd26/README.md#L5) |  |
| W05 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L68-L74](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L68-L74) |  |
| W06 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L30-L32](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L30-L32) |  |
| W07 | ✅ | [README.md#L204-L217](https://github.com/paperwm/PaperWM/blob/8bf6dd26/README.md#L204-L217) |  |
| W08 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L124-L138](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L124-L138) |  |
| W09 | ➖ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L453-L491](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L453-L491) | names/colours persist in gsettings; window order only via in-memory state |
| M01 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L107-L121](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L107-L121) |  |
| M02 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L90-L104](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L90-L104) |  |
| F01 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L220-L245](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L220-L245) |  |
| F03 | ✅ | [tiling.js#L2535-L2544](https://github.com/paperwm/PaperWM/blob/8bf6dd26/tiling.js#L2535-L2544) |  |
| F06 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L12-L18](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L12-L18) |  |
| R01 | ✅ | [settings.js#L362-L372](https://github.com/paperwm/PaperWM/blob/8bf6dd26/settings.js#L362-L372) |  |
| R02 | ✅ | [settings.js#L373-L378](https://github.com/paperwm/PaperWM/blob/8bf6dd26/settings.js#L373-L378) |  |
| R03 | ✅ | [tiling.js#L4048-L4056](https://github.com/paperwm/PaperWM/blob/8bf6dd26/tiling.js#L4048-L4056) |  |
| R04 | ✅ | [tiling.js#L4040-L4043](https://github.com/paperwm/PaperWM/blob/8bf6dd26/tiling.js#L4040-L4043) |  |
| I01 | ✅ | [keybindings.js#L396](https://github.com/paperwm/PaperWM/blob/8bf6dd26/keybindings.js#L396) |  |
| I03 | ➖ | [tiling.js#L4500-L4507](https://github.com/paperwm/PaperWM/blob/8bf6dd26/tiling.js#L4500-L4507) | handles GNOME's own move grabs; no modifier binding of its own |
| I04 | ✅ | [grab.js#L407-L415](https://github.com/paperwm/PaperWM/blob/8bf6dd26/grab.js#L407-L415) |  |
| I05 | ✅ | [README.md#L221-L227](https://github.com/paperwm/PaperWM/blob/8bf6dd26/README.md#L221-L227) |  |
| U01 | ➖ | [topbar.js#L65-L73](https://github.com/paperwm/PaperWM/blob/8bf6dd26/topbar.js#L65-L73) | extends and restyles GNOME's top bar; no bar of its own |
| U02 | ✅ | [topbar.js#L701-L716](https://github.com/paperwm/PaperWM/blob/8bf6dd26/topbar.js#L701-L716) |  |
| U04 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L555-L597](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L555-L597) | minimap, edge previews |
| U05 | ✅ | [tiling.js#L2949-L2957](https://github.com/paperwm/PaperWM/blob/8bf6dd26/tiling.js#L2949-L2957) | workspace stack |
| U08 | ✅ | [prefs.js#L17](https://github.com/paperwm/PaperWM/blob/8bf6dd26/prefs.js#L17) |  |
| V01 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L540-L552](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L540-L552) |  |
| V02 | ✅ | [schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L721-L723](https://github.com/paperwm/PaperWM/blob/8bf6dd26/schemas/org.gnome.shell.extensions.paperwm.gschema.xml#L721-L723) |  |
| V03 | ➖ | [minimap.js#L32](https://github.com/paperwm/PaperWM/blob/8bf6dd26/minimap.js#L32) | shade only during minimap navigation |
| C02 | ❌ | [config/user.js#L5-L10](https://github.com/paperwm/PaperWM/blob/8bf6dd26/config/user.js#L5-L10) | “user.js is not working in Gnome 45” |
| C04 | ✅ | [tiling.js#L144-L146](https://github.com/paperwm/PaperWM/blob/8bf6dd26/tiling.js#L144-L146) |  |
| C05 | ➖ | [extension.js#L183-L187](https://github.com/paperwm/PaperWM/blob/8bf6dd26/extension.js#L183-L187) | only user.css; settings live in gsettings |
| X01 | ➖ | [tiling.js#L186-L191](https://github.com/paperwm/PaperWM/blob/8bf6dd26/tiling.js#L186-L191) | rebuilds tiling order when gnome-shell restarts / extension re-enables |
| X03 | ✅ | [tiling.js#L3488-L3496](https://github.com/paperwm/PaperWM/blob/8bf6dd26/tiling.js#L3488-L3496) |  |
| X04 | ✅ | [tiling.js#L4720-L4727](https://github.com/paperwm/PaperWM/blob/8bf6dd26/tiling.js#L4720-L4727) | minimized windows move to scratch layer |

#### Veshell (95639217; pre-release, no tagged version)

Base: `https://github.com/free-explorers/veshell/blob/95639217/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [src/shell/lib/window/provider/window_manager/window_manager.dart#L133-L142](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/window/provider/window_manager/window_manager.dart#L133-L142) |  |
| L05 | ✅ | [src/shell/lib/workspace/provider/workspace_state.dart#L74-L79](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/workspace/provider/workspace_state.dart#L74-L79) | default one visible tile; others stay in the list |
| L08 | ➖ | [src/shell/lib/workspace/widget/workspace_panel.dart#L31-L35](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/workspace/widget/workspace_panel.dart#L31-L35) | N visible equal tiles inside the sliding strip |
| L09 | ✅ | [src/shell/lib/shared/widget/sliding_container.dart#L27-L60](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/shared/widget/sliding_container.dart#L27-L60) |  |
| L11 | ✅ | [src/shell/lib/window/widget/window.dart#L153-L159](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/window/widget/window.dart#L153-L159) |  |
| L12 | ✅ | [src/shell/lib/workspace/widget/tileable/persistent_window/persistent_window.dart#L221-L239](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/workspace/widget/tileable/persistent_window/persistent_window.dart#L221-L239) | per-window menu, not a hotkey |
| W01 | ✅ | [src/shell/lib/screen/model/screen.serializable.dart#L16-L21](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/screen/model/screen.serializable.dart#L16-L21) |  |
| W02 | ✅ | [src/shell/lib/screen/provider/screen_state.dart#L95-L121](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/screen/provider/screen_state.dart#L95-L121) |  |
| W04 | ✅ | [src/shell/lib/screen/model/screen.serializable.dart#L10-L21](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/screen/model/screen.serializable.dart#L10-L21) |  |
| W05 | ✅ | [src/shell/lib/screen/widget/workspace_list.dart#L224-L230](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/screen/widget/workspace_list.dart#L224-L230) | by dragging a tab |
| W09 | ✅ | [src/shell/lib/workspace/provider/workspace_state.dart#L45-L57](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/workspace/provider/workspace_state.dart#L45-L57) |  |
| M02 | ❓ | — | could not determine from code |
| M03 | ✅ | [src/shell/lib/settings/model/types/monitor_setting.serializable.dart#L11-L16](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/settings/model/types/monitor_setting.serializable.dart#L11-L16) |  |
| F01 | ✅ | [src/shell/lib/shortcut_manager/provider/hotkeys_activator.dart#L15-L18](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/shortcut_manager/provider/hotkeys_activator.dart#L15-L18) | left/right tile, workspace up/down |
| F02 | ➖ | [src/shell/lib/screen/widget/screen.dart#L57-L60](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/screen/widget/screen.dart#L57-L60) | per screen, not per window |
| I01 | ✅ | [src/shell/lib/shortcut_manager/provider/hotkeys_activator.dart#L36-L51](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/shortcut_manager/provider/hotkeys_activator.dart#L36-L51) | 8 hotkey actions total |
| I04 | ✅ | [src/shell/lib/workspace/widget/tileable_list.dart#L135](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/workspace/widget/tileable_list.dart#L135) |  |
| I05 | ✅ | [src/shell/lib/shared/widget/sliding_container.dart#L70-L75](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/shared/widget/sliding_container.dart#L70-L75) |  |
| U01 | ✅ | [src/shell/lib/screen/widget/screen_panel.dart#L20-L56](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/screen/widget/screen_panel.dart#L20-L56) |  |
| U02 | ✅ | [src/shell/lib/screen/widget/workspace_list.dart#L42-L61](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/screen/widget/workspace_list.dart#L42-L61) |  |
| U03 | ✅ | [src/shell/lib/workspace/widget/workspace_panel.dart#L28-L35](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/workspace/widget/workspace_panel.dart#L28-L35) |  |
| U05 | ❌ | [src/shell/lib/overview/widget/overview_content.dart#L14-L49](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/overview/widget/overview_content.dart#L14-L49) | “Overview” is launcher + control centre, not exposé |
| U06 | ✅ | [src/shell/lib/workspace/widget/tileable/persistent_application_launcher/app_drawer/app_drawer.dart#L7](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/workspace/widget/tileable/persistent_application_launcher/app_drawer/app_drawer.dart#L7) |  |
| U07 | ✅ | [src/shell/lib/notification/model/dbus_notification_server.dart#L6-L8](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/notification/model/dbus_notification_server.dart#L6-L8) |  |
| U08 | ✅ | [src/shell/lib/overview/widget/search/settings/settings_search_result.dart#L206](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/overview/widget/search/settings/settings_search_result.dart#L206) |  |
| V01 | ➖ | [src/shell/lib/workspace/widget/tileable_list.dart#L85](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/workspace/widget/tileable_list.dart#L85) | selected-tab underline; no window border |
| V02 | ✅ | [src/shell/lib/workspace/widget/tileable_list.dart#L36-L40](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/workspace/widget/tileable_list.dart#L36-L40) |  |
| V04 | ✅ | [src/shell/lib/overview/widget/overview.dart#L136-L137](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/overview/widget/overview.dart#L136-L137) | overview backdrop |
| V05 | ➖ | [src/shell/lib/meta_window/widget/meta_surface_decoration.dart#L39-L45](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/meta_window/widget/meta_surface_decoration.dart#L39-L45) | decorated surfaces only |
| V06 | ➖ | [src/shell/lib/meta_window/widget/meta_surface_decoration.dart#L38](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/meta_window/widget/meta_surface_decoration.dart#L38) | decorated surfaces only |
| C04 | ✅ | [src/shell/lib/settings/provider/util/configured_settings_json.dart#L32-L34](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/settings/provider/util/configured_settings_json.dart#L32-L34) |  |
| C05 | ✅ | [extra/settings/README.md#L1-L6](https://github.com/free-explorers/veshell/blob/95639217/extra/settings/README.md#L1-L6) | JSON |
| C06 | ➖ | [extra/assets/veshell.service.in#L8-L9](https://github.com/free-explorers/veshell/blob/95639217/extra/assets/veshell.service.in#L8-L9) | delegated to systemd XDG autostart |
| X01 | ✅ | [src/shell/lib/meta_window/provider/meta_window_manager.dart#L111](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/meta_window/provider/meta_window_manager.dart#L111) | matching engine refills saved placeholders |
| X03 | ✅ | [src/shell/lib/window/model/persistent_window.serializable.dart#L10-L15](https://github.com/free-explorers/veshell/blob/95639217/src/shell/lib/window/model/persistent_window.serializable.dart#L10-L15) |  |

#### Pop Shell (7898b65c)

Base: `https://github.com/pop-os/shell/blob/7898b65c/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [src/extension.ts#L2235-L2262](https://github.com/pop-os/shell/blob/7898b65c/src/extension.ts#L2235-L2262) | auto-tile off by default (schema L72-75) |
| L02 | ✅ | [README.md#L176](https://github.com/pop-os/shell/blob/7898b65c/README.md#L176) |  |
| L03 | ✅ | [src/forest.ts#L356](https://github.com/pop-os/shell/blob/7898b65c/src/forest.ts#L356) | fork orientation from area aspect |
| L04 | ✅ | [src/stack.ts#L123-L143](https://github.com/pop-os/shell/blob/7898b65c/src/stack.ts#L123-L143) | stacks |
| L05 | ➖ | [src/extension.ts#L1571-L1580](https://github.com/pop-os/shell/blob/7898b65c/src/extension.ts#L1571-L1580) | GNOME maximize; tree kept and re-tiled |
| L11 | ✅ | [README.md#L180-L194](https://github.com/pop-os/shell/blob/7898b65c/README.md#L180-L194) |  |
| L12 | ✅ | [schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L145-L148](https://github.com/pop-os/shell/blob/7898b65c/schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L145-L148) |  |
| L13 | ✅ | [schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L203-L221](https://github.com/pop-os/shell/blob/7898b65c/schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L203-L221) |  |
| L14 | ✅ | [schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L224-L242](https://github.com/pop-os/shell/blob/7898b65c/schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L224-L242) |  |
| L15 | ✅ | [schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L21-L29](https://github.com/pop-os/shell/blob/7898b65c/schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L21-L29) |  |
| W01 | ➖ | [src/extension.ts#L1298-L1404](https://github.com/pop-os/shell/blob/7898b65c/src/extension.ts#L1298-L1404) | GNOME Shell workspaces; Pop Shell integrates |
| W02 | ➖ | [src/extension.ts#L1373-L1395](https://github.com/pop-os/shell/blob/7898b65c/src/extension.ts#L1373-L1395) | appends workspace when GNOME dynamic workspaces are on |
| W05 | ✅ | [schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L246-L254](https://github.com/pop-os/shell/blob/7898b65c/schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L246-L254) |  |
| M01 | ➖ | [src/focus.ts#L46-L50](https://github.com/pop-os/shell/blob/7898b65c/src/focus.ts#L46-L50) | side effect of directional window focus; no focus-monitor command |
| M02 | ✅ | [schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L256-L274](https://github.com/pop-os/shell/blob/7898b65c/schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L256-L274) |  |
| F01 | ✅ | [schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L88-L106](https://github.com/pop-os/shell/blob/7898b65c/schemas/org.gnome.shell.extensions.pop-shell.gschema.xml#L88-L106) |  |
| F03 | ✅ | [src/window.ts#L710-L719](https://github.com/pop-os/shell/blob/7898b65c/src/window.ts#L710-L719) |  |
| F04 | ✅ | [src/launcher.ts#L60-L79](https://github.com/pop-os/shell/blob/7898b65c/src/launcher.ts#L60-L79) | launcher lists and switches to open windows |
| R01 | ✅ | [src/config.ts#L120-L138](https://github.com/pop-os/shell/blob/7898b65c/src/config.ts#L120-L138) |  |
| R02 | ✅ | [src/config.ts#L120-L138](https://github.com/pop-os/shell/blob/7898b65c/src/config.ts#L120-L138) |  |
| R04 | ✅ | [src/config.ts#L25-L62](https://github.com/pop-os/shell/blob/7898b65c/src/config.ts#L25-L62) |  |
| R05 | ➖ | [src/config.ts#L140-L163](https://github.com/pop-os/shell/blob/7898b65c/src/config.ts#L140-L163) | skip-taskbar hiding rules only; no full ignore |
| I01 | ✅ | [src/keybindings.ts#L65-L77](https://github.com/pop-os/shell/blob/7898b65c/src/keybindings.ts#L65-L77) |  |
| I02 | ✅ | [README.md#L116-L138](https://github.com/pop-os/shell/blob/7898b65c/README.md#L116-L138) | Window Management Mode |
| I04 | ➖ | [src/extension.ts#L1136-L1152](https://github.com/pop-os/shell/blob/7898b65c/src/extension.ts#L1136-L1152) | cross-monitor drop only |
| U03 | ✅ | [src/stack.ts#L229-L259](https://github.com/pop-os/shell/blob/7898b65c/src/stack.ts#L229-L259) |  |
| U06 | ✅ | [README.md#L146-L148](https://github.com/pop-os/shell/blob/7898b65c/README.md#L146-L148) | pop-launcher |
| U08 | ✅ | [src/prefs.ts#L26-L30](https://github.com/pop-os/shell/blob/7898b65c/src/prefs.ts#L26-L30) |  |
| V01 | ✅ | [src/window.ts#L73-L74](https://github.com/pop-os/shell/blob/7898b65c/src/window.ts#L73-L74) | active hint |
| C01 | ✅ | [src/dbus_service.ts#L3-L23](https://github.com/pop-os/shell/blob/7898b65c/src/dbus_service.ts#L3-L23) | D-Bus methods |
| C04 | ➖ | [src/extension.ts#L1908-L1934](https://github.com/pop-os/shell/blob/7898b65c/src/extension.ts#L1908-L1934) | GSettings live; config.json only reloaded by its own dialog |
| C05 | ➖ | [src/config.ts#L87-L98](https://github.com/pop-os/shell/blob/7898b65c/src/config.ts#L87-L98) | config.json holds float rules only; rest is GSettings |
| X01 | ➖ | [src/extension.ts#L2255-L2262](https://github.com/pop-os/shell/blob/7898b65c/src/extension.ts#L2255-L2262) | re-tiles existing windows; prior positions not restored |
| X03 | ✅ | [src/extension.ts#L370-L385](https://github.com/pop-os/shell/blob/7898b65c/src/extension.ts#L370-L385) |  |
| X04 | ✅ | [src/extension.ts#L1585-L1600](https://github.com/pop-os/shell/blob/7898b65c/src/extension.ts#L1585-L1600) |  |

#### Forge (46736af6)

Base: `https://github.com/forge-ext/forge/blob/46736af6/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [lib/extension/window.js#L1409-L1430](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L1409-L1430) |  |
| L02 | ✅ | [lib/extension/keybindings.js#L336-L353](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/keybindings.js#L336-L353) |  |
| L03 | ➖ | [lib/extension/window.js#L1410-L1420](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L1410-L1420) | `auto-split-enabled` splits along longer side; no separate BSP layout |
| L04 | ✅ | [lib/extension/window.js#L639-L687](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L639-L687) |  |
| L11 | ✅ | [lib/extension/window.js#L2775-L2826](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L2775-L2826) |  |
| L12 | ✅ | [schemas/org.gnome.shell.extensions.forge.gschema.xml#L264-L272](https://github.com/forge-ext/forge/blob/46736af6/schemas/org.gnome.shell.extensions.forge.gschema.xml#L264-L272) |  |
| L13 | ✅ | [schemas/org.gnome.shell.extensions.forge.gschema.xml#L322-L352](https://github.com/forge-ext/forge/blob/46736af6/schemas/org.gnome.shell.extensions.forge.gschema.xml#L322-L352) |  |
| L14 | ✅ | [lib/extension/window.js#L507-L559](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L507-L559) |  |
| L15 | ✅ | [schemas/org.gnome.shell.extensions.forge.gschema.xml#L30-L54](https://github.com/forge-ext/forge/blob/46736af6/schemas/org.gnome.shell.extensions.forge.gschema.xml#L30-L54) |  |
| L17 | ✅ | [lib/extension/keybindings.js#L396-L434](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/keybindings.js#L396-L434) | thirds, two-thirds, center |
| W01 | ❌ | [README.md#L94-L100](https://github.com/forge-ext/forge/blob/46736af6/README.md#L94-L100) | leaves workspaces to GNOME Shell |
| M01 | ✅ | [lib/extension/tree.js#L1031-L1068](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/tree.js#L1031-L1068) | directional focus crosses monitors |
| M02 | ✅ | [lib/extension/tree.js#L964-L981](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/tree.js#L964-L981) |  |
| F01 | ✅ | [schemas/org.gnome.shell.extensions.forge.gschema.xml#L244-L262](https://github.com/forge-ext/forge/blob/46736af6/schemas/org.gnome.shell.extensions.forge.gschema.xml#L244-L262) |  |
| F02 | ✅ | [lib/extension/window.js#L76-L96](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L76-L96) |  |
| F03 | ✅ | [lib/extension/window.js#L1878-L1899](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L1878-L1899) |  |
| F06 | ➖ | [lib/extension/window.js#L704-L717](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L704-L717) | swaps with last active window, does not focus it |
| R01 | ✅ | [lib/extension/window.js#L2816-L2823](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L2816-L2823) |  |
| R02 | ✅ | [lib/extension/window.js#L2798-L2814](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L2798-L2814) |  |
| R04 | ✅ | [config/windows.json#L1-L52](https://github.com/forge-ext/forge/blob/46736af6/config/windows.json#L1-L52) |  |
| I01 | ✅ | [lib/prefs/keyboard.js#L41](https://github.com/forge-ext/forge/blob/46736af6/lib/prefs/keyboard.js#L41) |  |
| I03 | ➖ | [lib/extension/keybindings.js#L156-L174](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/keybindings.js#L156-L174) | modifier for drop-to-tile; the drag itself is GNOME's |
| U03 | ✅ | [lib/extension/tree.js#L455-L516](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/tree.js#L455-L516) |  |
| U08 | ✅ | [prefs.js#L42-L52](https://github.com/forge-ext/forge/blob/46736af6/prefs.js#L42-L52) |  |
| V01 | ✅ | [lib/extension/window.js#L1241-L1330](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L1241-L1330) |  |
| C04 | ✅ | [lib/extension/window.js#L290-L300](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L290-L300) |  |
| C05 | ➖ | [README.md#L89-L92](https://github.com/forge-ext/forge/blob/46736af6/README.md#L89-L92) | windows.json overrides + CSS only; rest is GSettings |
| X01 | ➖ | [lib/extension/window.js#L851-L855](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L851-L855) | re-tiles existing windows; prior positions not restored |
| X03 | ✅ | [lib/extension/window.js#L202-L204](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L202-L204) |  |
| X04 | ✅ | [lib/extension/window.js#L224-L248](https://github.com/forge-ext/forge/blob/46736af6/lib/extension/window.js#L224-L248) |  |

#### KWin 6.7.90 built-in tiling (c1ca390b)

Base: `https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/`

| # | | Source | Note |
|---|---|---|---|
| L02 | ✅ | [src/tiles/customtile.h#L41-L44](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/tiles/customtile.h#L41-L44) | tile editor splits; windows placed into tiles manually |
| L10 | ✅ | [src/plugins/tileseditor/metadata.json#L4](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/plugins/tileseditor/metadata.json#L4) | Meta+T tile-layout editor |
| L11 | ✅ | [src/window.cpp#L1100-L1102](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/window.cpp#L1100-L1102) |  |
| L12 | ✅ | [src/useractions.cpp#L927-L934](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L927-L934) | Shift-drag or Custom Quick Tile shortcuts |
| L13 | ✅ | [src/useractions.cpp#L878-L887](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L878-L887) |  |
| L14 | ➖ | [src/useractions.cpp#L927-L934](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L927-L934) | move to neighbouring tile; no swap |
| L15 | ✅ | [src/tiles/tile.h#L54-L56](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/tiles/tile.h#L54-L56) | tile padding |
| L17 | ✅ | [src/useractions.cpp#L864-L865](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L864-L865) | Quick Tile halves/quarters, center, maximize |
| L18 | ✅ | [src/window.cpp#L2494-L2530](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/window.cpp#L2494-L2530) |  |
| W01 | ✅ | [src/virtualdesktops.cpp#L448-L476](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/virtualdesktops.cpp#L448-L476) | virtual desktops |
| W02 | ➖ | [src/org.kde.KWin.VirtualDesktopManager.xml#L38-L48](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/org.kde.KWin.VirtualDesktopManager.xml#L38-L48) | runtime create/remove; not automatic |
| W03 | ✅ | [src/virtualdesktops.cpp#L697-L698](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/virtualdesktops.cpp#L697-L698) |  |
| W04 | ✅ | [src/kwin.kcfg#L109-L111](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/kwin.kcfg#L109-L111) | `PerOutputVirtualDesktops` |
| W05 | ✅ | [src/useractions.cpp#L944-L958](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L944-L958) |  |
| W09 | ✅ | [src/virtualdesktops.cpp#L718-L748](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/virtualdesktops.cpp#L718-L748) | desktops and tile layouts saved to config |
| M01 | ✅ | [src/useractions.cpp#L996-L1009](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L996-L1009) |  |
| M02 | ✅ | [src/useractions.cpp#L970-L985](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L970-L985) |  |
| M03 | ✅ | [src/outputconfigurationstore.cpp#L176](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/outputconfigurationstore.cpp#L176) |  |
| F01 | ✅ | [src/useractions.cpp#L906-L915](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L906-L915) |  |
| F02 | ✅ | [src/options.h#L220-L242](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/options.h#L220-L242) |  |
| F03 | ➖ | [src/useractions.cpp#L1017-L1018](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L1017-L1018) | manual center-pointer shortcuts only |
| F04 | ✅ | [src/plugins/windowview/windowvieweffect.cpp#L50-L68](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/plugins/windowview/windowvieweffect.cpp#L50-L68) | Present Windows picker with search |
| F05 | ✅ | [src/useractions.cpp#L860-L861](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L860-L861) |  |
| F06 | ✅ | [src/tabbox/tabbox.cpp#L328-L345](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/tabbox/tabbox.cpp#L328-L345) |  |
| R01 | ✅ | [src/rulesettings.kcfg#L23-L32](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/rulesettings.kcfg#L23-L32) |  |
| R02 | ✅ | [src/rulesettings.kcfg#L47-L50](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/rulesettings.kcfg#L47-L50) |  |
| R03 | ✅ | [src/rulesettings.kcfg#L175-L190](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/rulesettings.kcfg#L175-L190) |  |
| I01 | ✅ | [src/useractions.cpp#L817-L834](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L817-L834) |  |
| I03 | ✅ | [src/options.h#L578-L582](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/options.h#L578-L582) |  |
| I04 | ✅ | [src/plugins/overview/qml/DesktopBar.qml#L173-L186](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/plugins/overview/qml/DesktopBar.qml#L173-L186) |  |
| I05 | ✅ | [src/virtualdesktops.cpp#L811-L815](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/virtualdesktops.cpp#L811-L815) |  |
| U01 | ❌ | — | panel is plasmashell, not KWin |
| U02 | ❌ | — | pager is plasmashell, not KWin |
| U04 | ✅ | [src/scripting/windowthumbnailitem.h#L70](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/scripting/windowthumbnailitem.h#L70) |  |
| U05 | ✅ | [src/plugins/overview/metadata.json#L4](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/plugins/overview/metadata.json#L4) |  |
| U06 | ✅ | [src/plugins/overview/qml/Main.qml#L795-L804](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/plugins/overview/qml/Main.qml#L795-L804) | KRunner results in Overview |
| U07 | ❌ | — | notifications are plasmashell |
| U08 | ✅ | [src/kcms/CMakeLists.txt#L5-L19](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/kcms/CMakeLists.txt#L5-L19) |  |
| V01 | ➖ | [src/decorations/decorationbridge.cpp#L40](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/decorations/decorationbridge.cpp#L40) | frames from decoration plugin (Breeze, separate project) |
| V02 | ✅ | [src/plugins/glide/metadata.json#L4](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/plugins/glide/metadata.json#L4) |  |
| V03 | ✅ | [src/plugins/diminactive/metadata.json#L4](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/plugins/diminactive/metadata.json#L4) |  |
| V04 | ✅ | [src/plugins/blur/metadata.json#L4](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/plugins/blur/metadata.json#L4) |  |
| V05 | ✅ | [src/shadow.h#L50](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/shadow.h#L50) |  |
| V06 | ✅ | [src/window.cpp#L392](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/window.cpp#L392) |  |
| C01 | ✅ | [src/org.kde.KWin.xml#L5-L44](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/org.kde.KWin.xml#L5-L44) | D-Bus |
| C02 | ✅ | [src/scripting/scripting.h#L115-L145](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/scripting/scripting.h#L115-L145) | JS/QML KWin scripts |
| C03 | ➖ | [src/org.kde.KWin.VirtualDesktopManager.xml#L12-L36](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/org.kde.KWin.VirtualDesktopManager.xml#L12-L36) | only desktop signals reach external processes |
| C04 | ✅ | [src/dbusinterface.cpp#L64-L66](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/dbusinterface.cpp#L64-L66) |  |
| C05 | ✅ | [src/kwin.kcfg#L1-L12](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/kwin.kcfg#L1-L12) | KConfig INI (kwinrc, kwinrulesrc) |
| C06 | ✅ | [src/main_wayland.cpp#L247-L248](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/main_wayland.cpp#L247-L248) |  |
| X02 | ➖ | [src/sm.cpp#L150-L170](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/sm.cpp#L150-L170) | X11 logout session management only |
| X03 | ✅ | [src/useractions.cpp#L852-L853](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L852-L853) |  |
| X04 | ✅ | [src/useractions.cpp#L838-L839](https://invent.kde.org/plasma/kwin/-/blob/c1ca390b/src/useractions.cpp#L838-L839) |  |

#### Polonium 1.2.2 (227967ed)

Base: `https://github.com/zeroxoneafour/polonium/blob/227967ed/`

| # | | Source | Note |
|---|---|---|---|
| L01 | ✅ | [src/controller/handlers/workspace.ts#L35-L57](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/workspace.ts#L35-L57) |  |
| L03 | ✅ | [src/engine/layouts/btree.ts#L79-L83](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/engine/layouts/btree.ts#L79-L83) |  |
| L05 | ❌ | [docs/src/routes/faq/+page.svx#L10-L11](https://github.com/zeroxoneafour/polonium/blob/227967ed/docs/src/routes/faq/+page.svx#L10-L11) | “Monocle is fundamentally incompatible with KWin tiles” |
| L06 | ✅ | [docs/src/routes/configuration/+page.svx#L19-L20](https://github.com/zeroxoneafour/polonium/blob/227967ed/docs/src/routes/configuration/+page.svx#L19-L20) |  |
| L07 | ➖ | [docs/src/routes/configuration/+page.svx#L50-L59](https://github.com/zeroxoneafour/polonium/blob/227967ed/docs/src/routes/configuration/+page.svx#L50-L59) | Pillars engine gives a grid-like result |
| L08 | ✅ | [src/engine/layouts/threecolumn.ts#L14-L21](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/engine/layouts/threecolumn.ts#L14-L21) |  |
| L10 | ➖ | [docs/src/routes/configuration/+page.svx#L68-L70](https://github.com/zeroxoneafour/polonium/blob/227967ed/docs/src/routes/configuration/+page.svx#L68-L70) | templates via KWin's tile editor; new engines need source edits |
| L11 | ✅ | [src/driver/index.ts#L362-L388](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/driver/index.ts#L362-L388) |  |
| L12 | ✅ | [src/controller/handlers/shortcuts.ts#L117-L135](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/shortcuts.ts#L117-L135) |  |
| L13 | ✅ | [src/controller/handlers/shortcuts.ts#L258-L310](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/shortcuts.ts#L258-L310) |  |
| L14 | ✅ | [src/controller/handlers/shortcuts.ts#L196-L256](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/shortcuts.ts#L196-L256) |  |
| W01 | ➖ | [src/controller/event.ts#L9-L24](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/event.ts#L9-L24) | via KWin virtual desktops |
| W05 | ➖ | [src/controller/handlers/window.ts#L31-L33](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/window.ts#L31-L33) | via KWin; retiles on desktop change |
| W09 | ➖ | [src/controller/handlers/dbus.ts#L32-L66](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/dbus.ts#L32-L66) | optional polonium-saver D-Bus service; engine settings only |
| M03 | ✅ | [src/controller/handlers/shortcuts.ts#L137-L147](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/shortcuts.ts#L137-L147) | engine per desktop/activity/screen |
| F01 | ✅ | [src/qml/shortcuts.qml#L87-L122](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/qml/shortcuts.qml#L87-L122) |  |
| R01 | ✅ | [src/controller/config.ts#L125-L142](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/config.ts#L125-L142) |  |
| R02 | ✅ | [docs/src/routes/configuration/+page.svx#L94-L97](https://github.com/zeroxoneafour/polonium/blob/227967ed/docs/src/routes/configuration/+page.svx#L94-L97) |  |
| R03 | ➖ | [src/controller/handlers/window.ts#L31-L33](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/window.ts#L31-L33) | via KWin window rules |
| R04 | ✅ | [src/controller/handlers/window.ts#L67-L72](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/window.ts#L67-L72) |  |
| R05 | ✅ | [src/controller/handlers/workspace.ts#L35-L41](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/workspace.ts#L35-L41) |  |
| I01 | ✅ | [src/qml/shortcuts.qml#L15-L17](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/qml/shortcuts.qml#L15-L17) |  |
| I04 | ➖ | [src/controller/handlers/window.ts#L31-L49](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/window.ts#L31-L49) | KWin drags; Polonium retiles on landing |
| U08 | ✅ | [src/qml/settings.qml#L7-L24](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/qml/settings.qml#L7-L24) |  |
| V01 | ➖ | [src/driver/index.ts#L362-L388](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/driver/index.ts#L362-L388) | toggles KWin decorations as a hint; draws nothing |
| C02 | ➖ | [src/engine/engine.ts#L12-L24](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/engine/engine.ts#L12-L24) | engines compiled in; no runtime plugins |
| C04 | ➖ | [src/controller/handlers/settings.ts#L10-L15](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/settings.ts#L10-L15) | in-session engine settings only |
| X01 | ❓ | [src/index.ts#L7-L10](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/index.ts#L7-L10) | could not confirm existing-window adoption at script load |
| X03 | ✅ | [src/controller/handlers/window.ts#L87-L128](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/window.ts#L87-L128) |  |
| X04 | ✅ | [src/controller/handlers/window.ts#L130-L150](https://github.com/zeroxoneafour/polonium/blob/227967ed/src/controller/handlers/window.ts#L130-L150) |  |
