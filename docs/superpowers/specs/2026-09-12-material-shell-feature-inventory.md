# material-shell feature inventory: what the GNOME extension actually ships

Date: 2026-09-12. Scope: the feature set of material-shell as it exists **in its own source**, not
as remembered or described second-hand. This feeds a later step that classifies each feature against
SpacialShell. That classification is deliberately **not** done here.

**Legal note.** material-shell is GPL-3, as is SpacialShell; its lineage is design inspiration
only (M1 spec + plan: "No code from material-shell or Veshell (GPL-3)"). This document describes
behaviour in our own words and cites file and line. Setting keys, keybinding names and layout keys
are quoted because they are facts. No implementation is transcribed.

## Source pinned

| Item | Value |
|---|---|
| Repository | `https://github.com/material-shell/material-shell` (not archived; last push 2024-07-22) |
| Commit read | `4c0cfcf370b0b1168f4a52de90ba954fed81ac50` ("Gnome 46 compatibility (#993)", 2024-07-22), tip of `main` |
| Release | **untagged**. This is 7 commits after the last tag/GitHub release `44` (2023-04-03). Those 7 commits are the GNOME 45 and 46 ports (#984, #993) plus fixes. |
| GNOME versions at this commit | `metadata.json` `shell-version`: **45, 46 only**. Tag `44` declared 40–44, tag `12` declared 3.34–3.38. |
| Project status | Discontinued in favour of Veshell (`README.md:1-2`, `documentation/letter_for_material_shell_users.md`) |
| material-shell.com | Single-page app. The fetch returned only "Loading…", so **no claim in this document rests on the site**. `README.md` is the only paradigm-level prose we used. |

Citations are `path:line` at the pinned SHA. Schema shorthands:
**B** = `schemas/org.gnome.shell.extensions.materialshell.bindings.gschema.xml`,
**L** = `…layouts.gschema.xml`, **T** = `…theme.gschema.xml`, **W** = `…tweaks.gschema.xml`.
Where `README.md` and the source disagree, the source wins and the row says so.

### What shipped in which release (GitHub release notes)

Features that exist only in some versions are flagged here once. The rest of the document describes
the pinned commit.

| Release (date) | GNOME | Notable additions per its notes |
|---|---|---|
| `v1` (2020-03) | 3.36 | First official release |
| `2-beta` (2020-06) | 3.34+ | Persistence, app placeholders, per-workspace in-place app launcher, engine rewrite |
| `3` (2020-08) | 3.34–3.36 | First stable; synced with extensions.gnome.org |
| `4`–`7` (2020-09) | +3.38 | Multi-monitor fixes; update notifications; `last-workspace` and `app-launcher` hotkeys (`5`); real maximize (`6`) |
| `8` (2020-10) | 3.34–3.38 | New settings UI; disable persistence; vertical panel left/right; horizontal panel top/bottom; clock in launcher; horizontal clock mode |
| `9` (2020-10) | 3.34–3.38 | Layout switcher becomes a menu with per-workspace layout list; scroll to switch layouts; split column count; tooltips; scroll on panels; insert-after-focused window workflow |
| `10` (2020-11) | 3.34–3.38 | Static (fixed-count) workspaces; long-press context menus on touch |
| `12` (2021-01) | 3.34–3.38 | Resizable tiling; multi-monitor hotkeys; focus effect (dim/border) |
| `40.a` (2021-05) | 40 | "New Overview"; GTK4 settings |
| `42` (2022-04), `summer_update_2022` (2022-07) | 40+ | Compatibility; stability rewrite |
| `43` (2022-10) | 40+ | Full app list in the side panel; filter windows by role; search panel reworked |
| `43b` (2023-01), `44` (2023-04) | 40–44 | Recent-search provider; focus-history improvements; multi-monitor fixes |
| pinned HEAD (2024-07) | **45–46** | Ports only (`git log 44..HEAD`) |

Sources: `gh release view <tag> -R material-shell/material-shell`, plus `metadata.json` at tags `12`, `40.a`, `43`, `44`.
Schema history (`git log -- schemas`) agrees: resize hotkeys arrive with "Resize v2" (2020-12),
`roles-excluded` in 2022-10, and `panel-icon-color` in 2021-02.

---

## 1. Spatial model and workspaces

The model is a grid: each workspace is a row, windows are cells. Up and down change workspace, left
and right change window (`README.md:54-69`). In source, a "workspace" (`MsWorkspace`) is an ordered
**tileable list**: its windows followed by exactly one application launcher, which is always last.

| # | Feature | Behaviour at pinned SHA | Cite |
|---|---|---|---|
| W1 | Tileable list per workspace | Ordered list of windows plus one app launcher, always last | `src/layout/msWorkspace/msWorkspace.ts:52,117-119` |
| W2 | New window insertion | Opened while a window is focused: inserted **right after** the focused one. Otherwise appended before the launcher. | `msWorkspace.ts:308-313`; `src/manager/msWindowManager.ts:371-378` |
| W3 | Workspaces are 1:1 with GNOME workspaces on the primary monitor | Each primary-monitor GNOME workspace gets an `MsWorkspace`. Workspaces are forced primary-only. | `src/manager/msWorkspaceManager.ts:501-519`; `src/module/requiredSettingsModule.ts:68-74`; `src/module/overrideModule.ts:13-16` |
| W4 | Dynamic workspaces | GNOME's workspace tracker is replaced. It keeps **exactly one empty workspace at the end**, removes other empty ones, and never removes the active one. | `msWorkspaceManager.ts:62-164` |
| W5 | Static workspaces | Honoured when GNOME dynamic workspaces are off. `MsWorkspace`s are trimmed to the GNOME count. | `msWorkspaceManager.ts:71-93`; release `10` |
| W6 | Creation | Implicit only. Putting a window in the trailing empty workspace makes it real, and a new empty one appears. There is no explicit "new workspace" command. | `msWorkspaceManager.ts:136-143` |
| W7 | Create a workspace above the first | Moving a window "up" from workspace 1 (with >1 window, or cycling on) sends it to the trailing empty workspace and reorders that workspace to index 0 | `src/module/hotKeysModule.ts:162-190` |
| W8 | Naming | **None.** Workspaces have no name field in state or UI. | `msWorkspace.ts:38-46` |
| W9 | Category (icon identity) | Auto-derived from the `.desktop` `Categories` of the workspace's apps. Scored over 15 main categories, with a bonus for `IDE`/`WebBrowser`/`Player`; ties go to the more specific category. | `src/layout/msWorkspace/msWorkspaceCategory.ts:9-27,53-106` |
| W10 | Category override | Per-workspace forced category from the rail button's context menu: "Determined automatically" or any of the 15. Persisted. | `src/layout/verticalPanel/workspaceList.ts:379-408`; `msWorkspaceCategory.ts:43-47` |
| W11 | Category icon set | 15 symbolic SVGs (game, development, video, audio, audiovideo, graphics, office, science, education, filemanager, instantmessaging, network, settings, system, utility) | `assets/icons/category/` |
| W12 | Reordering | Drag workspace buttons in the rail. The trailing empty workspace is not draggable. | `workspaceList.ts:47-50,283-290`; `msWorkspaceManager.ts:579-593` |
| W13 | Removal | Middle-click a rail button closes **all its windows**, then switches away. Not allowed on the last one. Empty workspaces are then reaped by W4. | `workspaceList.ts:257-267`; `msWorkspace.ts:266-277`; `msWorkspaceManager.ts:532-546` |
| W14 | Per-workspace settings | Current layout, the list of layouts available to cycle, per-layout state (split ratios, split column count), forced category, focused index | `msWorkspace.ts:38-46,215-242` |
| W15 | Focus history | Per workspace, up to 5 previously focused windows (launcher excluded). Used to pick focus when a window closes. Not persisted. | `msWorkspace.ts:23-30,64-77,329-396,491-518` |
| W16 | Focus-on-close policy | Per layout: "chronological" (last focused) by default; "spatial" (a neighbour, avoiding the launcher) for Split | `src/layout/msWorkspace/tilingLayouts/baseTiling.ts:52-63`; `tilingLayouts/split.ts:59-61` |
| W17 | Cycling | `cycle-through-windows` / `cycle-through-workspaces` wrap navigation at the ends | W`:3-12`; `msWorkspace.ts:450-473`; `msWorkspaceManager.ts:834-858` |
| W18 | Window capture guard | A window changing workspace within 2 s of creation is snapped back. Monitor hops within 200 ms are debounced. | `msWorkspaceManager.ts:711-722,759-798` |

## 2. Layouts

Layouts are **per workspace**. Each workspace has its own current layout and its own list of layouts
it cycles through (`msWorkspace.ts:44-45,565-606`). The global booleans in schema **L** seed that list
for new workspaces, and `default-layout` seeds the current layout (`src/manager/layoutManager.ts:131-139`;
`msWorkspace.ts:95-101`). Cycle order is fixed by the registry: maximize, split, grid, half,
half-horizontal, half-vertical, ratio, simple, simple-horizontal, simple-vertical, float
(`layoutManager.ts:52-64`).

| # | Layout key (label) | Default enabled | What it does | Options | Cite |
|---|---|---|---|---|---|
| Y1 | `maximize` (Maximize) | yes; also the default `default-layout` | One window fills the area. Changing focus slides horizontally between neighbours. The launcher is never hidden. | none | L`:3-7,83-87`; `tilingLayouts/maximize.ts:13-145` |
| Y2 | `split` (Split) | yes | Shows a sliding window of N adjacent tiles side by side. Moving focus past the edge scrolls the strip with a slide. Orientation comes from monitor aspect (portrait stacks vertically). Resizable. | `nbOfColumns` per workspace, default 2, min 2, set via a +/− picker in the top panel | L`:8-12`; `split.ts:18-48,99-150,179-183,222-233`; `src/widget/material/numberPicker.ts` |
| Y3 | `half` (Half) | yes | First window takes one portion; the rest stack in the second. Main axis follows the container's aspect ratio. Resizable. | none | L`:13-17`; `tilingLayouts/custom/half.ts:7-45` |
| Y4 | `half-horizontal` | no | Half, forced side-by-side | none | L`:18-22`; `custom/halfHorizontal.ts:12-14` |
| Y5 | `half-vertical` | no | Half, forced stacked | none | L`:23-27`; `custom/halfVertical.ts:12-14` |
| Y6 | `ratio` (Ratio) | no | Recursive split: each new window halves the remaining last portion, alternating axis (a spiral/dwindle shape). Resizable. | `ratio-value` (default 0.618…) exists in schema and settings UI but **is never consumed** by the layout: it is read into `LayoutManager.ratio` and used nowhere else, so new portions start equal | L`:28-37`; `custom/ratio.ts:11-27`; `layoutManager.ts:115-120`; `portion.ts:17-21` |
| Y7 | `grid` (Grid) | no | ceil(√n) columns, rows filled evenly, last column holds the remainder. Resizable. | none | L`:38-42`; `custom/grid.ts:10-53` |
| Y8 | `float` (Float) | yes | No tiling. Windows keep their own geometry, show their title bars, and stack in the order the window manager reports. | none | L`:43-47`; `tilingLayouts/float.ts:13-132`; `src/utils/windows.ts:8-20` |
| Y9 | `simple` (Simple) | no | All windows in one row or column (auto by aspect), equal shares. Resizable. | none | L`:48-52`; `custom/simple.ts:8-36` |
| Y10 | `simple-horizontal` | no | Simple, forced one row | none | L`:53-57`; `custom/simpleHorizontal.ts` |
| Y11 | `simple-vertical` | no | Simple, forced one column | none | L`:58-62`; `custom/simpleVertical.ts` |

Cross-layout behaviour:

| # | Feature | Behaviour | Cite |
|---|---|---|---|
| Y12 | Resizable tiling (portion tree) | Every layout except maximize and float is a tree of weighted portions. Borders between tiles can be dragged. Each side is clamped to ≥10%, and the split snaps to 25/50/75% within ±1%. Ratios persist per workspace per layout. | `tilingLayouts/baseResizeableTiling.ts:23-183`; `portion.ts:3,11-42,406-436` |
| Y13 | Drag handles only without gaps | Draggable border actors exist **only when all gaps are 0**. With gaps, resizing is by keyboard or native window-edge drag only. | `baseResizeableTiling.ts:72-89,378-419` |
| Y14 | Native edge-resize is redirected | Starting a window-manager resize on a tiled window resizes the corresponding portion border instead | `src/manager/msResizeManager.ts:55-95,161-201` |
| Y15 | Keyboard resize | `resize-window-*` moves the focused tile's border by 5% | `hotKeysModule.ts:288-353`; `msResizeManager.ts:203-220` |
| Y16 | Gaps | `gap` between tiles; `use-screen-gap` + `screen-gap` for a separate outer margin. No gaps when the launcher is the only tile. With gap 0, a 2 px border seam remains. | L`:63-77`; `baseTiling.ts:295-357`; `baseResizeableTiling.ts:21,152-163` |
| Y17 | Focus effect | `focus-effect`: `none`, `default` (dim unfocused tiles), or `border` (2 px primary-colour outline on the focused tile). Resizable layouts only. | T`:25-29,96-100`; `baseResizeableTiling.ts:256-368,421-499` |
| Y18 | Fullscreen yields on blur | In resizable layouts, a fullscreen window is un-fullscreened when it loses focus | `baseResizeableTiling.ts:269-282` |
| Y19 | Title bars hidden while tiled | Server-side title bars are hidden in every layout except float, via X11 Motif hints. No-op for client-decorated windows and windows without an X id. | `src/utils/windows.ts:8-53` |
| Y20 | Hidden tiles are minimized | Tiles not currently shown (other slides of maximize/split, inactive workspaces) have their real window **minimized** and restored when shown | `src/layout/msWorkspace/msWindow.ts:1296-1309` |
| Y21 | Fixed-size windows | Non-resizable windows are centred in their tile at native size | `msWindow.ts:623-651` |
| Y22 | Layout switch animation duration | Slide transitions are hard-coded to 250 ms. `tween-time` exists in schema and UI but is **never consumed** (read into `LayoutManager.tweenTime` only). | L`:78-82`; `layoutManager.ts:112-124`; `src/utils/transition.ts:213-214` |

## 3. Panels

Two surfaces (`README.md:77-102`): a **vertical "system" panel** (the rail) on the primary monitor
only, and a **horizontal "workspace" panel** (the tab bar) belonging to each workspace, and therefore
present on every monitor. GNOME's own top bar is hidden (`src/layout/verticalPanel/verticalPanel.ts:145-146,182-190`).

### 3a. Vertical panel (left by default)

Top to bottom:

| # | Element | Behaviour | Configurable | Cite |
|---|---|---|---|---|
| P1 | Search button | Magnifier icon at the top. Toggles the search drawer (P9). Becomes a close icon while open. | — | `verticalPanel.ts:48-69,109-124` |
| P2 | Workspace list | One button per primary workspace, including the trailing empty one | — | `workspaceList.ts:105-142` |
| P3 | Workspace button icon | Category icon, app icons, or "+" when empty. Up to 3 app icons, ordered by instance count and laid out in an overlapping arrangement. | `panel-icon-style` = `hybrid` (category icon if >1 distinct app, else the app icon) / `category` / `application`; forced category always shows the category icon | T`:7-11,61-65`; `workspaceList.ts:541-654` |
| P4 | Icon colour | Desaturated unless `panel-icon-color` | T`:66-70` | `workspaceList.ts:522-539` |
| P5 | Active indicator | Bar that eases to the active button (250 ms) | — | `workspaceList.ts:144-160,657-668` |
| P6 | Button interactions | Left: activate. Right or long-press: context menu (icon style radio, category override). Middle: close workspace (W13). Drag: reorder (W12). Drop a tab: move that window here (M4). | — | `workspaceList.ts:251-267,292-456`; `src/widget/material/button.ts:32-34,70-79,97-120` |
| P7 | Scroll on list | Wheel up/down: previous/next workspace | — | `workspaceList.ts:89-98` |
| P8 | Status area (bottom) | **Takes every actor from GNOME's top bar** (left box except Activities/app menu, centre, right) and stacks it vertically. Order: extension indicators, then system menu (quick settings), then date menu. Icons are scaled to the panel. Menus open sideways toward the screen. Overrides AppIndicator extensions' `icon-size`. | size follows `panel-size` | `src/layout/verticalPanel/statusArea.ts:123-244,269-356,83-121` |
| P9 | Clock and notifications | GNOME's date-menu button is replaced by a vertical clock (hours, minutes, AM/PM each on its own line). It turns primary-coloured when notifications are pending, unless Do Not Disturb is on. With `clock-horizontal`, the rail shows a bell / ringing bell / muted bell instead and the clock moves to the tab bar. Clicking opens GNOME's date/notification menu. | `clock-horizontal` | T`:86-90`; `statusArea.ts:129-153,387-533` |
| P10 | Search drawer ("overview") | Expands the rail to 448 px with a search entry. Empty query: every installed app, alphabetical. With terms: Recent, Applications (incl. system actions such as power-off), and GNOME remote search providers honouring `org.gnome.desktop.search-providers` (enabled/disabled/sort-order/disable-external). 5 results per provider, then "N more". Tab/↑↓ select, Enter activates, Esc closes. The workspace behind dims. Clicking outside closes. | — | `verticalPanel.ts:211-292`; `src/layout/verticalPanel/extendedPanelContent.ts:13-70`; `searchResultList.ts:152-161,188-243,269-295,428-485`; `search/ProviderResultList.ts:67-103`; `search/searchProvider/RemoteSearchProvider.ts:160-180`; `src/layout/main.ts:133-163,321-359` |
| P11 | Recent-search provider | Remembers up to 100 activations (calculator excluded) with their terms and context, ranks suggestions with a decision tree, and persists them | `search/searchProvider/RecentSearchProvider.ts:14-16,58-80,120-141,232` |
| P12 | Super key | The overlay key toggles the drawer. GNOME's Activities overview is disabled. | `main.ts:125-131`; `src/extension.ts:113,215-216` |
| P13 | Position | `vertical-panel-position` `left`/`right`. The drawer opens from that side. | T`:17-20,41-45`; `main.ts:608-668`; `verticalPanel.ts:192-204,217-252` |

### 3b. Horizontal panel (top by default), one per workspace

Left to right: task bar, optional clock, layout switcher (`src/layout/msWorkspace/horizontalPanel/horizontalPanel.ts:43-47,126-158`).

| # | Element | Behaviour | Configurable | Cite |
|---|---|---|---|---|
| P14 | Tabs (task bar) | One tab per window in workspace order, plus a final "+" icon tab for the app launcher. Sliding active indicator (250 ms). | — | `horizontalPanel/taskBar.ts:40-130,141-167,210-233,270-306` |
| P15 | Tab content | App icon, then title, then close button (or a pin icon if pinned). `full` shows title plus a dimmed "– App name"; `name` shows the app name; `icon` shows the icon only. Tooltip on hover (200 ms) when the title is truncated. | `taskbar-item-style` | T`:12-16,81-85`; `taskBar.ts:405-612`; `src/manager/tooltipManager.ts:15-84` |
| P16 | Tab interactions | Left: focus. Middle: close window. Close button: close. Right or long-press: menu **Pin tab / Unpin tab / Close**. Drag: reorder, or drop on another tab bar or rail button (M-section). Scroll on bar: previous/next window. | — | `taskBar.ts:113-123,214-231,339-351,426-464` |
| P17 | Pinned ("persistent") tab | Survives its window closing: turns back into a placeholder instead of disappearing, and cannot be closed while it is a placeholder | `msWindow.ts:323-326,1191-1194,1249-1252`; `msWindowManager.ts:388,707-708` |
| P18 | Horizontal clock | Wall clock between tabs and layout switcher | `clock-horizontal` | `horizontalPanel.ts:48-98` |
| P19 | Layout switcher | Current layout's icon. Click opens a menu of that workspace's layouts; choosing one applies it. Wheel cycles layouts. Split's column picker sits beside the icon. | — | `horizontalPanel/layoutSwitcher.ts:36-125` |
| P20 | "Tweak available layouts" | Menu item that toggles edit mode: every layout appears with a switch that adds or removes it from **this workspace's** cycle list. At least one must remain. "Confirm layouts" leaves edit mode. | — | `layoutSwitcher.ts:122-174,189-342` |
| P21 | Position | `horizontal-panel-position` `top`/`bottom` | T`:21-24,46-50`; `main.ts:455-465`; `msWorkspace.ts:700-733` |
| P22 | Size | `panel-size` (default 48) is both rail width and tab-bar height, and is scale-aware. The search drawer and launcher sizes are fixed and scaled. | T`:51-55`; `src/manager/msThemeManager.ts:200-211` |

### 3c. In-workspace surfaces (not panels, but shipped UI)

| # | Element | Behaviour | Cite |
|---|---|---|---|
| P23 | App launcher tile | Every workspace's last tile. Grid of installed apps sorted by usage, with a type-to-filter entry (regex over name/id/description). Tab/arrows/Enter navigation scrolls pages. Optional clock and date header. Esc with nothing typed returns to the previously focused window. Launching opens the app **in this workspace**. | `src/widget/msApplicationLauncher.ts:23-149,173-334,548-664`; `src/manager/appsManager.ts:4-24`; T`:91-95` |
| P24 | Launcher reveal | Shown automatically when a workspace has no windows. Scale-and-fade in/out (250 ms) otherwise. | `baseTiling.ts:197-265,271-282` |
| P25 | App placeholder | Tile for a restored-but-not-running window: big app icon, name, "Click anywhere to launch" (or Enter/Space). Spinner while launching. Gives up after 5 s. | `src/widget/appPlaceholder.ts:11-179`; `msWindowManager.ts:684-712,730-761` |
| P26 | Dialogs | Dialogs, utility and transient windows attach to their parent tile (by ancestry, transient-for, same PID, then same app) and are drawn and focused inside it, clamped to the tile | `msWindowManager.ts:399-523,800-825`; `msWindow.ts:821-869,1016-1081,1128-1158` |

## 4. Hotkeys (schema **B**, all defaults)

Registered with auto-repeat ignored, in normal mode only (`hotKeysModule.ts:559-565`). Modifier
convention: **Super** navigates, **Super+Shift** moves to a workspace or monitor, **Super+Ctrl**
resizes, **Super+Alt** focuses a monitor. On enable, any GNOME keybinding that uses one of these
accelerators is blanked, then restored on disable (`requiredSettingsModule.ts:112-160`).

| # | Key name | Default | Behaviour | Cite |
|---|---|---|---|---|
| K1 | `previous-window` | Super+A | Focus previous tile (wraps if W17) | B`:4`; `hotKeysModule.ts:77-80` |
| K2 | `next-window` | Super+D | Focus next tile | B`:13`; `:82-85` |
| K3 | `app-launcher` | Super+X | Focus this workspace's launcher (no-op if it is the only tile) | B`:22`; `:87-91`; `msWorkspace.ts:475-484` |
| K4 | `kill-focused-window` | Super+Q | Close focused window | B`:31`; `:115-125` |
| K5 | `move-window-left` | Super+Left | Swap focused window with previous tile | B`:40`; `:127-137`; `msWorkspace.ts:424-432` |
| K6 | `move-window-right` | Super+Right | Swap with next tile (never past the launcher) | B`:49`; `:139-149`; `msWorkspace.ts:434-448` |
| K7 | `move-window-top` | Super+Up | Move window to the workspace above and follow it (see W7 at the top edge). Also takes over GNOME's `move-to-workspace-up`. | B`:58`; `:151-211` |
| K8 | `move-window-bottom` | Super+Down | Move to the workspace below and follow. Takes over `move-to-workspace-down`. | B`:67`; `:213-286` |
| K9–K12 | `focus-monitor-{left,up,right,down}` | Alt+Super+arrow | Focus the active workspace of the neighbouring monitor **and warp the pointer to its centre** | B`:76-111`; `:355-374`; `msWorkspaceManager.ts:860-881` |
| K13–K16 | `move-window-monitor-{left,up,right,down}` | Shift+Super+arrow | Move focused window to the neighbouring monitor and focus it. Takes over GNOME `move-to-monitor-*`. | B`:112-147`; `:376-421` |
| K17–K20 | `resize-window-{left,up,right,down}` | Ctrl+Super+arrow | Move the tile border 5% in that direction | B`:148-183`; `:288-353` |
| K21–K30 | `move-window-to-workspace-{1..10}` | Shift+Super+1…9, 0 | Move focused window to workspace N (clamped to the last) and follow it | B`:184-273`; `:424-464` |
| K31 | `cycle-tiling-layout` | Super+Space | Next layout in this workspace's list | B`:275`; `:466-473` |
| K32 | `reverse-cycle-tiling-layout` | Shift+Super+Space | Previous layout | B`:284`; `:475-482` |
| K33 | `toggle-material-shell-ui` | Super+Escape | Hide or show both panels ("zen mode"). Persisted as `panels-visible`. | B`:293`; `:484-489`; `main.ts:284-311` |
| K34–K44 | `use-{maximize,split,half,half-horizontal,half-vertical,grid,ratio,float,simple,simple-horizontal,simple-vertical}-layout` | **unbound** | Jump to that layout | B`:302-400`; `:491-500` (defaults removed in commit `e823990`) |
| K45 | `previous-workspace` | Super+W | Previous workspace (wraps if W17) | B`:402`; `:93-98` |
| K46 | `next-workspace` | Super+S | Next workspace | B`:411`; `:100-102` |
| K47 | `last-workspace` | Super+Z | Jump to the last workspace (the trailing empty one when dynamic) | B`:420`; `:104-113` |
| K48–K57 | `navigate-to-workspace-{1..10}` | Super+1…9, 0 | Go to workspace N (clamped). **Pressing the same key again returns to the workspace you came from.** | B`:429-518`; `:502-548` |

Mouse-modified keys while dragging a window: Super+A/D swap it left/right, Super+W/S carry it to the
previous/next workspace (`src/manager/msDndManager.ts:277-317`).

**README vs source:** `README.md:160-164` lists Super+Shift+A/D/W/S for moving windows. The schema
binds those actions to Super+arrows (B`:40-75`), and Super+Shift+letters are unbound. The source wins.
The README also omits K3, K9–K20, K21–K30, K47 and all layout keys.

## 5. Mouse, touch and drag

| # | Feature | Behaviour | Cite |
|---|---|---|---|
| M1 | Window drag | A window-manager move grab (Super+drag, or title bar drag) on a tiled window lifts it above everything and follows the pointer. Hovering another tile in the same workspace **swaps** them. Release drops it into the tile slot. Not active in float or for fullscreen windows. | `msDndManager.ts:68-84,143-193,205-259`; `msWindow.ts:417-424` |
| M2 | Drag placeholders | Super+button-1 drag also starts on placeholder tiles (no real window to grab) | `msDndManager.ts:125-141` |
| M3 | Drag across workspaces | Switching workspace mid-drag (e.g. Super+W/S, K45/K46) carries the window to the new workspace | `msDndManager.ts:43-66,300-313` |
| M4 | Drag across monitors | Dragging over another monitor re-homes the window to that monitor's workspace live | `msDndManager.ts:208-233` |
| M5 | Tab reorder | Drag a tab within the bar. A placeholder shows the drop slot. The window order changes and the dropped window takes focus. | `taskBar.ts:64-68`; `src/widget/reorderableList.ts:32-221` |
| M6 | Tab to another tab bar | Dropping a tab into another workspace's bar (e.g. another monitor) moves the window there at that index | `taskBar.ts:69-82`; `reorderableList.ts:82-108,193-220` |
| M7 | Tab onto rail button | Dropping a tab on a workspace button moves the window there and activates that workspace | `workspaceList.ts:436-456` |
| M8 | Workspace reorder | Drag rail buttons (W12) | `workspaceList.ts:47-50` |
| M9 | Border resize | Drag between tiles (Y12, Y13) with a resize cursor | `baseResizeableTiling.ts:388-414` |
| M10 | Scroll | Rail: switch workspace. Tab bar: switch window. Layout icon: cycle layout. | P7, P16, P19 |
| M11 | Touch | Long-press equals right-click on material buttons (tabs, rail buttons). Tap and touch-begin activate placeholders and borders. | `button.ts:33-34,79,97-120`; `appPlaceholder.ts:87-104`; release `10` |

## 6. Multi-monitor

| # | Feature | Behaviour | Cite |
|---|---|---|---|
| X1 | Workspaces only on primary | Forced (`workspaces-only-on-primary`). The primary monitor has the full workspace column. | `requiredSettingsModule.ts:68-74`; `overrideModule.ts:13-16` |
| X2 | One workspace per external monitor | Each non-primary monitor holds **exactly one** `MsWorkspace` that does not switch. It has its own tab bar, layout and launcher. | `msWorkspaceManager.ts:262-276,646-658`; `main.ts:71-82` |
| X3 | Vertical panel on primary only | External monitors get only a horizontal panel spacer | `main.ts:381-503` vs `505-669` |
| X4 | Per-monitor tiling | Each monitor's visible workspace tiles independently | `layoutManager.ts:197-222` |
| X5 | Hotplug: monitor removed | Its workspace, windows included, is appended to the primary column as a regular workspace. Its "external" flag is kept for later. | `msWorkspaceManager.ts:422-495` |
| X6 | Hotplug: monitor added | Reuses a stranded "external" workspace if one exists, otherwise creates a new one | `msWorkspaceManager.ts:396-420` |
| X7 | Window follows monitor | A window entering an external monitor joins that monitor's workspace | `msWorkspaceManager.ts:730-757` |
| X8 | Keyboard | K9–K16 | §4 |
| X9 | Fullscreen | A monitor showing a fullscreen window hides its panels and background for that monitor | `main.ts:313-319,430-440,564-569`; `msWorkspace.ts:691-698` |
| X10 | Mixed scaling | README directs users to enable Mutter's `scale-monitor-framebuffer` for mixed-DPI setups (documentation, not code) | `README.md:207-215` |

## 7. Persistence

| # | Feature | Behaviour | Cite |
|---|---|---|---|
| S1 | Store | A single JSON blob under GNOME Shell's persistent-state key `material-shell-state`. There is a one-way fallback read of a legacy `~/.cache/material-shell@papyelgringo-state.json`. | `src/manager/stateManager.ts:14,27-64,89-95` |
| S2 | Toggle | `enable-persistence` (default on). When off, workspaces are rebuilt from the live GNOME state at start. | W`:18-22`; `extension.ts:151-155`; `stateManager.ts:125-132` |
| S3 | Saved per workspace | external-monitor flag, focused index, forced category, layout key, the per-layout state list (portion ratio trees, split column count), window list | `msWorkspace.ts:38-46,215-242`; `baseResizeableTiling.ts:67-71` |
| S4 | Saved per window | app id, matching info (wm class, PID, title, stable sequence), pinned flag, tile x/y/w/h, creation time. Window-backed (no `.desktop`) apps are **not** saved. | `msWindow.ts:43-62,233-278`; `msWorkspace.ts:216-227` |
| S5 | Saved globally | active primary workspace index; `panels-visible` (K33); recent-search history; update-notification UUID and last-check time | `msWorkspaceManager.ts:25-28,595-612`; `main.ts:44,286`; `RecentSearchProvider.ts:15,77-79`; `src/manager/msNotificationManager.ts:35-43,100-103` |
| S6 | Empty workspaces dropped | With dynamic workspaces, workspaces without windows are not saved | `msWorkspaceManager.ts:598-602` |
| S7 | Restore | External monitors first, then primary workspaces in order, then the trailing empty one, then the saved active workspace | `msWorkspaceManager.ts:278-350` |
| S8 | Placeholders on restore | Every saved window comes back as a placeholder tile in its slot (P25) until relaunched | `msWorkspace.ts:122-176`; `README.md:135-143` |
| S9 | Window re-association | Windows that appear (at restore or launch) are matched to placeholders by minimum total cost: wm class must match, then PID, then title, then sequence, preferring placeholders that are waiting for a launch. Matches may re-shuffle for 3 s as titles settle. | `msWindowManager.ts:42-114,172-397` |
| S10 | Save trigger | Debounced to idle on any tile, layout, focus, ratio, pin or category change | `stateManager.ts:108-123`; `msWorkspaceManager.ts:564-578` |
| S11 | Lock screen | Locking does not tear down state: in the `unlock-dialog` session mode, only the status area is handed back to GNOME; unlocking re-takes it | `extension.ts:104-116,171-178` |
| S12 | Reset | Documented manual resets of the state blob and the dconf settings tree | `README.md:217-231` |

## 8. Settings UI (GTK4/Adwaita prefs)

One preferences page (whose group carries a leftover title "Group Title", `src/prefs/prefs.ts:577-584`)
hosts a widget with a header stack switcher offering two panes, **Settings** and **Hotkeys**
(`src/prefs/ui/prefs.ui:7-58`). Integer settings use a 0–1000 spin button. Decimal settings use a
0–1 spin button with step 0.1 (`prefs.ts:415-443`).

### Settings pane → "Theme" (`prefs.ts:488-508`)

| Setting | Key | Type / values | Default | Cite |
|---|---|---|---|---|
| Theme | `theme` | `dark` / `light` / `primary` | `dark` | T`:2-6,31-35` |
| Primary UI color | `primary-color` | colour | `#3f51b5` | T`:36-40` |
| Vertical panel position | `vertical-panel-position` | `left` / `right` | `left` | T`:41-45` |
| Horizontal panel position | `horizontal-panel-position` | `top` / `bottom` | `top` | T`:46-50` |
| Panels size | `panel-size` | int | 48 | T`:51-55` |
| Panel opacity | `panel-opacity` | int (%) | 100 | T`:56-60` |
| Vertical panel icons style | `panel-icon-style` | `hybrid` / `category` / `application` | `hybrid` | T`:61-65` |
| Vertical panel icons color | `panel-icon-color` | bool | false | T`:66-70` |
| Taskbar item style | `taskbar-item-style` | `full` / `name` / `icon` | `full` | T`:81-85` |
| Surface opacity | `surface-opacity` | int (%) | 100 | T`:71-75` |
| Blur background | `blur-background` | bool | false | T`:76-80` |
| Display clock horizontally | `clock-horizontal` | bool | false | T`:86-90` |
| Clock and date in App Launcher | `clock-app-launcher` | bool | true | T`:91-95` |
| Focus effect | `focus-effect` | `none` / `default` / `border` | `default` | T`:96-100` |

### Settings pane → "Tweaks" (`prefs.ts:510-523`)

| Setting | Key | Default | Cite |
|---|---|---|---|
| Cycle through windows | `cycle-through-windows` | false | W`:3-7` |
| Cycle through workspaces | `cycle-through-workspaces` | false | W`:8-12` |
| Disable Material Shell notifications | `disable-notifications` | false | W`:13-17` |
| Enable session persistence | `enable-persistence` | true | W`:18-22` |

### Settings pane → "Tiling layouts" (`prefs.ts:525-564`)

| Setting | Key | Default | Cite |
|---|---|---|---|
| Default layout (combo lists only enabled layouts) | `default-layout` | `maximize` | L`:83-87`; `prefs.ts:49-75` |
| Enable each layout (11 switches, in the order maximize, split, half, half-horizontal, half-vertical, ratio, grid, float, simple, simple-horizontal, simple-vertical) | `maximize` … `simple-vertical` | see §2 | L`:3-62`; `prefs.ts:531-556` |
| Ratio of the ratio layout (shown after `ratio`) | `ratio-value` | 0.618… (unused, Y6) | L`:33-37` |
| Gap size | `gap` | 0 | L`:63-67` |
| Use a different gap size for screen | `use-screen-gap` | false | L`:68-72` |
| Screen gap size | `screen-gap` | 0 | L`:73-77` |
| Animation duration | `tween-time` | 0.25 (unused, Y22) | L`:78-82` |
| Excluded window classes (comma-separated) | `windows-excluded` | '' | L`:88-92`; `msWindowManager.ts:764-773` |
| Excluded window roles (comma-separated) | `roles-excluded` | '' | L`:93-97`; `msWindowManager.ts:774-784` |

### Hotkeys pane

Lists every key in schema **B**, sorted by summary. Activating a row opens a capture dialog that
inhibits system shortcuts: Esc cancels, Backspace sets "Disabled", any valid accelerator is stored
(`prefs.ts:135-313`; `src/prefs/ui/hotkey_list_box_row.ui`, `hotkey_dialog.ui`). Only the first
accelerator of each key is shown and edited (`prefs.ts:165-168,214-216`).

Settings reachable **outside** the prefs window: `panel-icon-style` from the rail context menu (P6);
each workspace's layout list from the layout switcher (P20); each workspace's forced category (W10);
pinned tabs (P16).

## 9. Theming and appearance

| # | Feature | Behaviour | Cite |
|---|---|---|---|
| A1 | Three themes | Dark, light and "primary" (panels tinted with the primary colour), compiled from one SCSS source | `src/styles/{dark,light,primary}-theme.scss`; `src/styles/stylesheet.scss`; `Makefile:14-23` |
| A2 | Runtime theming | Primary colour, panel opacity and surface opacity are substituted into the chosen theme CSS, written to the user cache and hot-reloaded | `msThemeManager.ts:292-317` |
| A3 | Blurred wallpaper | `blur-background` applies a heavy blur and darkening to the wallpaper behind everything | `main.ts:98-123` |
| A4 | Material widgets | Ripple buttons, dividers, number picker, Material typography scale, surface elevations (`surface`, `surface-lighter`, `surface-darker`) | `src/widget/material/*`; `src/styles/typography.scss`; `stylesheet.scss:589-639` |
| A5 | Tiling-layout icon set | One symbolic SVG per layout, plus "native" | `assets/icons/tiling/` |
| A6 | Cursor feedback | Resize, drag and default cursors are set by the shell during resize and drag | `msThemeManager.ts:242-245`; `msDndManager.ts:177,192` |
| A7 | GNOME-theme fallback | Adds a `no-theme` class when no shell stylesheet is loaded | `msThemeManager.ts:97-107` |
| A8 | Window buttons | Forces the WM button layout to app menu plus close only (no minimize/maximize) while enabled | `requiredSettingsModule.ts:75-80`; `README.md:249-253` |

## 10. Everything else it ships

| # | Feature | Behaviour | Cite |
|---|---|---|---|
| E1 | Animations | Vertical slide between workspaces; horizontal slide between maximize/split tiles; scale-and-fade launcher; easing rail and tab indicators; dimmer fades; tooltip scale-in. GNOME's own window animations are disabled. | `main.ts:571-606`; `transition.ts`; `baseTiling.ts:197-234`; `src/module/overrideModule.ts:25-39` |
| E2 | Startup splash | Logo splash on every monitor while the shell starts. Fades after load, with a 5 s cap. | `extension.ts:122-126,234-282` |
| E3 | Update notifications | **Network call** at load to `http://api.material-shell.com/notifications` sending a random UUID, last-check time, GNOME version and extension version. Results appear as GNOME notifications that open a dialog with an optional link. Suppressed by `disable-notifications`. | `msNotificationManager.ts:23-120,129-223` |
| E4 | Incompatible-extension blocker | Disables and prevents enabling desktop-icons, ubuntu-dock, dash-to-dock, ding, pop-shell and improved-workspace-indicator | `src/module/disableIncompatibleExtensionsModule.ts:7-50` |
| E5 | Window management scope | Manages normal, dialog, modal-dialog and utility windows. "Always on top" windows are made sticky and left unmanaged. Excluded classes and roles are left unmanaged. Unmanaged windows go to the top window group. | `msWindowManager.ts:546-574,763-798` |
| E6 | Focus behaviour | Focus follows the tile list. A modal dialog of a tile takes focus first. A 100 ms guard after workspace switches stops focus theft. Activating a workspace briefly grabs to its focused tile so a window on another monitor can't steal focus. | `src/manager/msFocusManager.ts:40-104`; `msWindow.ts:1114-1158`; `msWorkspace.ts:630-652` |
| E7 | Tooltips | Truncated-text tooltips on tabs and launcher items | `tooltipManager.ts:11-201`; `taskBar.ts:480`; `msApplicationLauncher.ts:700` |
| E8 | Search / launcher integration | P10 (drawer with GNOME search providers, system actions, recent history) and P23 (per-workspace launcher). Parental-controls filtering respected. | §3 |
| E9 | App-change tracking | If a window's owning app changes (e.g. a launcher process hands off), the tile re-labels itself | `msWindow.ts:328-381` |
| E10 | Quick-close of transient startup windows | Placeholders created for windows that vanish within 2 s are discarded | `msWindowManager.ts:71-74,382-395` |
| E11 | Authentication dialogs | Launch timeouts are paused while a polkit dialog is showing | `msWindowManager.ts:689-697` |

---

## Counts

Layouts 11 plus 11 cross-layout rows. Workspaces 18. Panels 26 (vertical 13, horizontal 9, in-workspace 4).
Hotkeys 57 keys (46 bound by default, 11 unbound layout keys).
Mouse/touch/drag 11. Multi-monitor 10. Persistence 12. Settings 37 keys in schemas T/W/L (14 + 4 + 19)
on the Settings pane, plus the 57 schema-B keys on the Hotkeys pane.
Theming 8. Other 11.

## Gaps in this inventory

- **unverified: runtime behaviour.** Nothing was executed. Every row describes what the code at the
  pinned SHA is written to do on GNOME 45/46. Behaviour on older tags is inferred from release notes
  only.
- **unverified: Hotkeys pane actually renders on 45/46.** It is declared in the `PrefsWidget` template
  (`prefs.ui:40-58`), and a separate commented-out attempt to add it as its own Adwaita page sits at
  `prefs.ts:586-593`. Whether it displays correctly was not observed.
- **unverified: `material-shell.com` claims.** The site did not render for us. The paradigm is taken
  from `README.md` and the source.
- **unverified: which extensions.gnome.org build corresponds to this SHA.** No tag or version field
  exists after `44`, and `metadata.json` has no `version`.
- **unverified: on-disk location of GNOME Shell's persistent-state store** used by S1. It is a GNOME
  Shell internal, not in this repo.
- **unverified: title-bar hiding on Wayland** (Y19). The mechanism needs an X window id; for native
  Wayland clients it appears to be skipped, but that was not observed.
- **unverified: Y6/Y22 intent.** `ratio-value` and `tween-time` are demonstrably read and never
  consumed at this SHA. Whether they worked in earlier releases was not checked.
