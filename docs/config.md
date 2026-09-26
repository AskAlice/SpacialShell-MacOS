# Config reference

SpacialShell reads `~/.config/spacial-shell/config.toml`. The file is watched for changes and
reloaded live; an invalid config is rejected (the previous one keeps running) and the rejection is
logged and listed under the rail cog's problems badge. An unknown key (a typo, or a key since
removed) does not reject the file: it is skipped, the rest applies, and a warning naming it is
logged and listed the same way. Every key is optional — an empty or missing file gives you `Config()`'s defaults, shown
below.

> **Sandboxed builds read the same path inside the app's container**, i.e.
> `~/Library/Containers/sh.emu.SpacialShell/Data/.config/spacial-shell/config.toml`. See
> [Where the file lives](#where-the-file-lives) — it changes where you hand-edit, and the
> settings window's **Open config.toml…** button is the route you should use rather than typing
> that path.

## Full example

```toml
keybinding-preset = "fn"          # or "ctrl-alt"
gap = 8                           # pt between windows (and to the screen edge, unless screen-gap is set)
# screen-gap = 8                  # pt between the windows and the screen edge; follows gap when unset
default-layout = "maximize"       # maximize | split | column | half | grid | ratio | a [[layout]] id
ax-timeout-ms = 1000
refresh-interval-ms = 2000
start-at-login = false
panel-width = 48
panel-height = 34
rail-side = "left"                # or "right"
tab-sizing = "fit"                # or "equal"
rail-icon-style = "app"           # or "category", "hybrid" — what a rail tile draws
dock-attention = true             # a red dot on the tile and tabs of an app the Dock badges or bounces
launcher-url = "raycast://"
show-panels = true
empty-cheatsheet = true           # dimmed cheat sheet behind an empty workspace
rail-autohide = false             # hide the rail like the Dock; windows take its width
pointer-warp = true               # keyboard focus to another display takes the pointer along
focus-follows-mouse = false       # resting the pointer on another tiled window focuses it
focus-follows-mouse-delay-ms = 150  # how long it has to rest there (50–2000)
workspace-wrap = false            # Fn+W on the first workspace goes to the last, Fn+S back round
gestures = true                   # trackpad swipes navigate like Fn+W/A/S/D
gesture-fingers = 3               # exactly this many fingers (3–5)
gesture-invert = false            # true: swipe the way the keys point instead of natural
crowd-threshold = 8               # an app arriving at launch with more windows gets its own workspace
category-order = ["web", "terminal", "coding", "media", "utilities"]   # [] turns routing off
max-workspaces = 12               # routing never grows a display past this many rows
persist-state = true              # remember workspaces across launches (state.json)
# warn while one of these runs (bundle id or process name); [] turns the warning off
other-window-managers = ["bobko.aerospace", "yabai", "skhd", "com.amethyst.Amethyst", "com.knollsoft.Rectangle", "com.crowdcafe.windowmagnet"]

[[workspace]]                     # pinned, named workspaces seeded on every screen
name = "Code"                     # (material-shell "categories")
symbol = "terminal"               # SF Symbol name
layout = "half"

# [[ephemeral]] (like [[tile]]) REPLACES the default list, it does not add to it: once your file
# has any [[ephemeral]] block, Calculator is ephemeral only if you list it too, as here.
[[ephemeral]]
bundle-id = "com.apple.calculator"

[[float]]
bundle-id = "com.apple.iphonesimulator"

[[ignore]]
bundle-id = "com.apple.some-popup-only-app"
title-regex = "^Picture in Picture$"

[keybindings]                     # optional overrides/additions, same notation as AeroSpace's keysMap
"fn-shift-g" = "toggle-float"
```

## Top-level keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `keybinding-preset` | `"fn"` \| `"ctrl-alt"` | `"fn"` | Which modifier the built-in bindings (`KeyBindings.core`) are prefixed with. `fn` uses the Globe key; `ctrl-alt` (`⌃⌥`) is for keyboards without one. The arrow-key bindings are always on `⌃⌥` regardless of this setting. |
| `gap` | number (pt) | `8` | Space left between tiled windows, in every layout. Also the space to the screen edge unless `screen-gap` is set. Also in the settings window's Layout pane (*Window gap*). |
| `screen-gap` | number (pt) | follows `gap` | Space left between the tiled row and the screen edge (and the rail and tab bar), on all four sides, in every layout — material-shell's `screen-gap`. `0` puts windows flush with the edges while `gap` still separates them. Unset, it follows `gap` (including a gap set in the settings window). Also in the settings window's Layout pane (*Screen edge gap*). |
| `default-layout` | layout id | `"maximize"` | The layout a newly created workspace starts with: one of the six built-ins or a `[[layout]]` id (see below). |
| `ax-timeout-ms` | integer | `1000` | Per-app Accessibility messaging timeout (`AXUIElementSetMessagingTimeout`). A slow or hung app can only delay operations on itself by this long, never other apps. **Needs a relaunch**: it is read when the backend is built. |
| `refresh-interval-ms` | integer | `2000` | Interval for the periodic backstop reconcile — the safety net that catches window changes AX notifications missed. **Needs a relaunch**: it is read when the backend is built. |
| `start-at-login` | boolean | `false` | **Parsed but not implemented in M1** — the key is accepted and validated, and nothing acts on it. Registering a login item needs a real app bundle to point at, so it arrives with the notarized bundle in M4. |
| `panel-width` | number (pt) | `48` | Width of the workspace rail. Windows are inset by this on the rail side. |
| `panel-height` | number (pt) | `34` | Height of the top bar. Windows are inset by this from the top. |
| `tab-sizing` | `"fit"` \| `"equal"` | `"fit"` | How the tab bar spends its width. `fit`: each tab is as wide as its content and they pack left, so a single tab sits at the left edge. `equal`: every tab takes 1/n of the bar and centres its content. |
| `rail-side` | `"left"` \| `"right"` | `"left"` | Which screen edge the rail sits on. An unknown value rejects the whole config (the previous one keeps running). |
| `rail-icon-style` | `"app"` \| `"category"` \| `"hybrid"` | `"app"` | What a rail tile draws (#115). `app`: up to four of the workspace's apps as a 2×2 icon grid. `category`: the workspace's category symbol — its own category (the tile menu's **Set category**, or the one routing gave it), else the one its apps add up to. `hybrid`: that symbol with the workspace's top two apps (most windows first) beneath it. In `category` and `hybrid`, a symbol chosen for the workspace (**Set symbol**, or a `[[workspace]]` seed's `symbol`) beats the category's, and a workspace with neither a category nor a chosen symbol shows its app icons. Also in the settings window's Appearance pane (*Rail icons*). See [`[category-colors]`](#category-colors--rail-symbol-colours). |
| `dock-attention` | boolean | `true` | Mirrors the Dock (#126): when an app's Dock icon has a badge, or is bouncing (the app is asking for attention), a red dot marks the rail tile of every workspace holding one of its windows, and each of its tabs. A bounce's mark goes a few seconds after the Dock stops; a badge's goes once you focus one of the app's windows, and comes back only when the badge changes (a count going up) or goes and returns. The app you are in is never marked. Read by polling the Dock's accessibility tree every 0.5 s — there is no public notification for either signal — which costs about 2 ms of CPU per poll here and about as much in the Dock (~0.4% of a core each); the poll runs only while this is on and the panels are showing. It is a heuristic: a bounce is inferred from the icon's movement, and an app with no Dock icon, or one that posts notifications without a badge, is never marked. Also a toggle (*Attention marks*) in the settings window's Appearance pane. |
| `app-categories` | table of bundle-id → category | `{}` | Overrides the rail's category label per app. Values: `web`, `coding`, `terminal`, `communication`, `media`, `design`, `productivity`, `utilities`. See below — this exists because macOS cannot answer the question. |
| `keybinding-overrides` | table of command \u2192 chord | `{}` | Rebinds a command, *replacing* its default chord. This is what the settings window writes. Distinct from `keybindings` below, which is chord \u2192 command and only ever *adds* a chord \u2014 useful in a hand-edited file, useless for rebinding, since the old chord keeps working. |
| `launcher-url` | string | `"raycast://"` | URL opened by the rail search glyph. If nothing handles it, the built-in overview opens instead. |
| `show-panels` | boolean | `true` | When `false`, panels are not drawn and windows are not inset for them. |
| `empty-cheatsheet` | boolean | `true` | When the focused display's active workspace has no windows, the key-binding cheat sheet (the one holding the bare modifier shows) sits dimmed at the bottom of that screen, behind everything and click-through. It goes as soon as a window arrives or focus moves to another display. Also a toggle in the settings window. |
| `rail-autohide` | boolean | `false` | The rail hides off its screen edge (`rail-side`) like the Dock, and windows tile into its width. Resting the pointer at that edge for a moment slides it back in **over** the windows (nothing re-tiles); it slides away again shortly after the pointer leaves it, but stays while its hover card or a drag from it is open. It never takes focus. With Reduce Motion it appears and goes instantly. The tab bar is unaffected and spans the full width. Also a toggle in the settings window's Appearance pane. |
| `pointer-warp` | boolean | `true` | When a key or `spacialctl run` moves focus to another display (`focus-screen-*`, `move-window-to-screen-*`, or any command that lands on another display), the pointer jumps to the centre of the newly focused window, or of that display when its workspace is empty. Never for a click, a drag or a focus change macOS reports, never within one display, and not when the pointer is already inside that window. Also a toggle (*Pointer follows focus*) in the settings window's General pane. |
| `focus-follows-mouse` | boolean | `false` | Opt-in. Resting the pointer on another **tiled** window for `focus-follows-mouse-delay-ms` focuses it, exactly as clicking its tab would. It has to *rest*: stay within a few points of one spot over that window. Sweeping across windows on the way somewhere else changes nothing, and only pointer movement starts the wait, so a key, swipe or pointer warp (`pointer-warp`) that moves focus under a still pointer is never undone. A key press or a mouse button during the wait cancels it, and so does focus moving by any other route. Never focused this way: floating and ephemeral windows, a tiled window that a floating or ephemeral window overlaps (macOS cannot focus a window without raising it, which would bury the one on top), parked windows, anything on a display showing a fullscreen Space, the rail and tab bar (including an auto-hiding rail's edge), and anything with a menu, popover or other window in front of it. Also a toggle (*Focus follows mouse*) in the settings window's General pane. |
| `focus-follows-mouse-delay-ms` | integer | `150` | How long the pointer has to rest on a window before `focus-follows-mouse` focuses it. Clamped to 50–2000. |
| `workspace-wrap` | boolean | `false` | Focus workspace up/down wraps round the ends of the stack: `Fn+W` on the first workspace goes to the **last non-empty** one, and `Fn+S` on the last non-empty one (or on the empty one below it) goes to the first. The trailing empty workspace is then not stepped onto: reach it with the rail's "+" or by moving a window down (`Fn+⇧S`). Also a toggle (*Wrap workspaces*) in the settings window's General pane. |
| `gestures` | boolean | `true` | Trackpad swipes navigate like `Fn+W/A/S/D`: a swipe up or down runs `focus-workspace-down`/`-up`, left or right runs `focus-window-right`/`-left`, one step per swipe, the same commands the keys run. Content follows the fingers, as with natural scrolling: swipe **left** for the window on the right (`Fn+D`), swipe **up** for the workspace below (`Fn+S`). macOS still sees every swipe (SpacialShell can only watch them), so if macOS also uses that many fingers, both happen: with three fingers, set Mission Control and "Swipe between full-screen apps" to four fingers (or off) in System Settings → Trackpad → More Gestures. SpacialShell lists a warning under the rail cog while they overlap. See [keybindings: trackpad swipes](keybindings.md#trackpad-swipes). Also a toggle (*Trackpad swipes*) in the settings window's General pane. |
| `gesture-fingers` | integer | `3` | How many fingers a swipe takes, exactly: a swipe with more or fewer does nothing. Clamped to 3–5 (two fingers is scrolling). The macOS-conflict warning is checked for 3 only. |
| `gesture-invert` | boolean | `false` | Swipe the way the keys point instead: swipe left runs `Fn+A`, swipe up runs `Fn+W`. Also a toggle (*Invert swipes*) in the settings window's General pane. |
| `crowd-threshold` | integer | `8` | An app arriving **at launch** with *more* windows than this, and no remembered placement, gets a workspace of its own on the display most of its windows are on, instead of piling into the active workspace. See [Where windows land at launch](#where-windows-land-at-launch). |
| `category-order` | list of categories | `["web", "terminal", "coding", "media", "utilities"]` | Where an app's windows go: one row per listed category on each display, shared by every app of that category and kept at the top of the stack in this order. For these apps this beats the remembered workspace. Apps of any other category, or of none, get a row each below them. `[]` turns this off. Category names are the `app-categories` values. Also in the settings window's Workspaces pane. See [Where windows land](#where-windows-land-at-launch). |
| `max-workspaces` | integer | `12` | Category routing never grows a display past this many rows (the empty row at the bottom does not count). Past it, a new app joins the last row. Also in the settings window's Workspaces pane (1–30). |
| `persist-state` | boolean | `true` | Remember workspaces across launches: `state.json` (see [State](#state)) is read at launch and kept written. `false` neither reads nor writes it — every launch starts from `[[workspace]]` seeds and category routing, and an existing file is left as it is, so turning this back on picks up where it was. Putting parked windows back when SpacialShell quits happens either way. Also a toggle (*Save workspaces*) in the settings window's General pane. To start fresh once instead, see [Resetting saved state](#resetting-saved-state). |
| `other-window-managers` | list of strings | AeroSpace, yabai, skhd, Amethyst, Rectangle, Magnet (below) | Window managers that fight SpacialShell over the same windows or keys. While one runs, SpacialShell lists a warning under the rail cog and, once per launch, opens an alert with **Don't warn again**. An entry matches a bundle id exactly (`com.knollsoft.Rectangle`) or a process name ignoring case (`yabai`, for daemons with no app bundle). Checked at launch and whenever an app launches or quits. Setting the key **replaces** the default list; `[]` turns the warning off. Default: `["bobko.aerospace", "yabai", "skhd", "com.amethyst.Amethyst", "com.knollsoft.Rectangle", "com.crowdcafe.windowmagnet"]`. What you silence is kept in `settings.json`, not this file; the settings window's General pane lists it and has **Warn again**. |

Layout names: `maximize` (one window fills the screen), `split` (a sliding view of N consecutive
windows as columns — 2 by default, 2–6 per workspace from the layout popover's −/+ or
`split-columns-more`/`-fewer`; focus moving past either edge slides it by one), `column` (all windows as equal columns), `half` (one window fills the left half, the
rest stack in the right half), `grid` (a roughly-square grid, row-major, last row widened to fill),
`ratio` (material-shell's dwindle: each window takes 0.618 of the space the windows before it left,
cutting across and down in turn, so the first window is the largest and the last takes what
remains; resize a workspace's shares with `Fn+⌃`/border drag). `ratio` is not on the default
`layout-bar`: add it there, or switch it on in the layout popover.

On a display taller than wide (portrait), the built-ins turn to the long axis: `split` and `column`
stack their windows as rows, `half` gives the top half to one window and lays the rest side by
side below it, and `grid` has at least as many rows as columns, and `ratio` makes its first cut across. A square display counts as
landscape. Resized sizes are kept separately for each orientation. Drawn `[[layout]]` zones are
drawn as they are, on any display.

A window that cannot grow to fill its tile (it has a maximum size, or refuses the resize) sits
centred in the tile instead of in its top-left corner, on each axis where it falls short. The
next time its tile changes, it is offered the whole tile again.

## `[[workspace]]` — pinned workspace seeds

Each `[[workspace]]` table seeds one **pinned, named** workspace on every screen at launch — the
material-shell "category" concept (e.g. a permanent "Code" or "Web" row). Pinned workspaces never
get reaped for being empty, unlike ordinary auto-created ones (spec §4.2 invariant 4); that's what
makes a named category usable before window-to-workspace persistence exists (that's M3).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | *(required)* | Display name — "Workspace N" if you don't seed one. |
| `symbol` | string | `"square.grid.2x2"` | SF Symbol name, for the M2 shell UI. |
| `layout` | layout id | `"maximize"` | This workspace's starting layout, independent of `default-layout`. |

Pinned workspaces are restored from `state.json` on launch; which app was in which workspace is
remembered per bundle id — see below.

## `[[layout]]` — drawn layouts

Besides the six built-ins, a layout can be a fixed list of zones (#9). Zones are unit rects —
`0…1`, origin top-left — and their order is the order windows fill them:

```toml
layout-bar = ["maximize", "split", "column", "code-3"]   # what Fn+Space cycles; default the five before ratio, at most 8

[[layout]]
id = "code-3"
name = "Code, three"
# symbol = "sidebar.left"            # optional SF Symbol
zones = [
  { x = 0.0, y = 0.0, w = 0.5, h = 1.0 },
  { x = 0.5, y = 0.0, w = 0.5, h = 0.5 },
  { x = 0.5, y = 0.5, w = 0.5, h = 0.5 },
]
```

`default-layout` and a workspace's `layout` take any id: a built-in or a `[[layout]]`. Built-in
layouts adapt to the number of windows; drawn layouts have a fixed number of zones and, with more
windows than zones, show the page of windows holding the focused one (the rest keep their tabs).
A zone too small for a 120 × 80 pt window on the current display drops out of the page. Fewer
windows than zones leave the trailing zones empty.

Mistakes do not disarm the file: a `[[layout]]` block with no usable zones is skipped (logged),
zones are clamped into `0…1`, a block reusing a built-in's id is ignored, and a layout id nothing
defines — a typo, a deleted layout — keeps the workspace and draws `default-layout` (else
`maximize`) until the layout comes back.

**Upgrade and downgrade:** the five built-in ids have never changed, so a `config.toml` or
`state.json` written before drawn layouts existed loads unchanged, with no migration (the test suite
decodes files captured before #9). A build older than #9 cannot read a `state.json` that names a
drawn layout; it starts with fresh workspaces.

**From `spacialctl`:** `spacialctl state` gives each workspace's `layout` as the id it holds, even
one that does not resolve, and lists every layout the shell knows in a top-level `layouts` array
(`id`, `name`, `symbol`, `builtin`, and `zones` — the zone count, absent for a built-in). A
workspace whose `layout` is missing from `layouts` is drawing its fallback. `capabilities` includes
`"layouts"`; the payload's `v` is still 2. `spacialctl set-layout <id> [--workspace <uuid>]` sets a
workspace's layout (default: the focused display's active one); an id the shell does not know is
refused with exit 1, unlike the config file, which keeps it.

## Where windows land at launch

A window seen for the first time goes to the first of these that applies (#13, #74, #128):

0. **A placeholder's slot**, if its app has a placeholder tab waiting (#128): every window saved
   in `state.json` comes back as a placeholder in its row, and a window of that app takes one —
   the one with the same title, else the one you clicked to open it, else the first in rail
   order. It lands exactly there: same row, same position, floating if it was. Dialogs and popups
   never take a slot.
1. **Its category's row**, for an app whose category (resolved as in
   [Why `app-categories` exists](#why-app-categories-exists)) is in `category-order`, on the
   display the window is on. All apps of that category share the row. App type beats memory
   here: a browser remembered on your second display still takes the web row of the display it
   opened on, and a browser window on each display takes the web row of each. If the display has
   no such row yet, one is created at its place in the order: just below the rows of earlier
   categories, just above rows of later ones, and otherwise at the top.
2. **Its app's remembered workspace**, if that workspace still exists — for every app rule 1
   does not cover. The state file remembers the workspace each app was last in (#5), and each
   workspace lives on a display identified by its UUID, not by arrangement order, so a
   two-monitor arrangement comes back on the right monitors.
3. **A workspace of its own**, for an app arriving at launch with more than `crowd-threshold`
   windows, on the display most of them are on. Its further windows follow it there.
4. **A row of its own**, at the bottom of the stack, for every other app while routing is on: a
   category not in `category-order`, or no category at all.
5. **Otherwise, the active workspace** of the display holding most of the window — unchanged.
   With `category-order = []` this is where every app without a memory lands, as before #74.

Whichever row an app's first window gets becomes the app's remembered workspace, so the later
windows of an app outside the order follow it by rule 2. Rules 1 and 4 never grow a display past
`max-workspaces` rows; past it, the app joins the last row. Dialogs, popups and ephemeral windows
are never routed.

**Sheets and attached dialogs.** A dialog macOS attaches to a window (a sheet, a save panel)
joins that window's row and belongs to its tile: it has no tab of its own (the owner's tab lights
while it has focus), `Fn+A`/`Fn+D` step past it, it moves and parks with its owner at the same
place on it, moving either one to another workspace takes both, and closing it hands focus back
to the owner.

**Order of the rows.** On every display, rows of a category in `category-order` sit at the top,
in that order. Pinned rows and rows without a category keep their own order below them, and are
never re-sorted, so a drag (#75) of one of those sticks. The category rows are sorted each time
SpacialShell starts; during a session a new one is slotted in at its place in the order. So a
category row you drag stays where you put it until the next launch, which puts it back. The row
you are on stays the row you are on through any of this.

"At launch" means the first snapshot after SpacialShell starts, plus any app whose windows first
appear within 10 s of it (login items and macOS's "reopen windows" arrive after the shell is up).
The app is judged on the windows in its first appearance only. Windows that appear later in the
session are never swept into a workspace of their own.

A fullscreen or floating window's display is decided by macOS, not by memory: if its frame is on
another display, it is filed there (#72).

If the displays changed while SpacialShell was not running (spec §7.8): a display that is gone
brings its workspaces to the main display, appended to the bottom of its stack, so their apps
still come back to them; a display that is new starts with an empty stack (just the
`[[workspace]]` seeds).

## `[[ephemeral]]`, `[[float]]`, `[[ignore]]`, `[[tile]]` — app rules

Each entry matches windows by bundle id and, optionally, a regex against the window title:

| Key | Type | Meaning |
|---|---|---|
| `bundle-id` | string, required | Exact match against the owning app's bundle identifier. |
| `title-regex` | string, optional | If present, the window title must also match this regex (`NSString.range(of:options:.regularExpression)`). Omit it to match every window of that app. |

Config rules always win over SpacialShell's own heuristic window classifier (spec §7.3 rule 0),
checked in this order: `ephemeral`, then `float`, then `ignore`, then `tile`.

- **`ephemeral`** — Veshell's "visitor" windows: they belong to no workspace, are centred on the
  focused screen when they appear, are never parked, and `Fn+A`/`Fn+D` skip over them entirely.
  **Default** (used whenever `[[ephemeral]]` is absent from your config entirely):
  `com.apple.calculator`. Note this is a full **replacement**, not a merge — if you add your own
  `[[ephemeral]]` entries, Calculator stops being ephemeral unless you list it yourself. (System
  Settings was in the default until 2026-09-24; it is now tiled like any other window — #70.)
- **`float`** — windows that belong to a workspace and are shown/parked with it, but are excluded
  from tiling and keep their own frame (also toggleable per-window at runtime with `Fn+G`). No
  default entries.
- **`ignore`** — windows SpacialShell never touches at all: no placement, no parking, no tiling.
  No default entries.
- **`tile`** — tile these even when macOS reports them as dialogs. **Default** (used whenever
  `[[tile]]` is absent): `com.apple.systempreferences` — System Settings only resizes vertically,
  so it reads as a dialog, but it belongs in its row. A full replacement, like `ephemeral`.

## `[keybindings]` — overrides and additions

See [`docs/keybindings.md`](keybindings.md) for the cheat-sheet, presets, recipes and conflicts; this section is the reference for the table itself.

A table of `"chord" = "command-name"`. Entries here are layered on top of the preset's built-in
bindings (`KeyBindings.core` + the arrow aliases): a chord you name here **replaces** the built-in
binding for that chord rather than adding a second one, and a chord the preset does not use is
added. There is no way to *unbind* a built-in chord in M1 — only to point it somewhere else.

**Chord notation**: zero or more modifiers, `-`-joined, then a key name — `"fn-shift-g"`,
`"ctrl-alt-shift-leftSquareBracket"`. Recognised modifier tokens: `fn`, `ctrl`/`control`,
`alt`/`option`, `shift`, `cmd`/`command`. The key name is the last token and must be one of the
names below.

### Command names

Generated from `KeyBindings.commandNames`:

| Command name | Command |
|---|---|
| `focus-workspace-up` | Focus the workspace above the active one |
| `focus-workspace-down` | Focus the workspace below the active one |
| `focus-window-left` | Focus the previous window in the active workspace (wraps) — every visible window, floating ones included; minimized and hidden ones are skipped (spec §4.3) |
| `focus-window-right` | Focus the next window in the active workspace (wraps) — every visible window, floating ones included; minimized and hidden ones are skipped (spec §4.3) |
| `close-window` | Close the focused window (app keeps running) |
| `move-window-left` | Swap the focused window with its left neighbour |
| `move-window-right` | Swap the focused window with its right neighbour |
| `move-window-up` | Move the focused window to the workspace above and follow it |
| `move-window-down` | Move the focused window to the workspace below (creates one if needed) and follow it |
| `cycle-layout` | Cycle the active workspace's layout round `layout-bar` (by default maximize → split → column → half → grid → maximize); from a layout not on the bar, go to the bar's first |
| `toggle-shell-ui` | Zen mode: hide/show the shell panels; their edges go back to the layout while hidden |
| `toggle-overview` | Open/close the overview/launcher (search over open windows and installed apps) |
| `open-settings` | Open `~/.config/spacial-shell/config.toml` in its default editor (created empty — all defaults — if missing) |
| `focus-screen-prev` | Focus the previous screen |
| `focus-screen-next` | Focus the next screen |
| `move-window-to-screen-prev` | Move the focused window to the previous screen and follow it |
| `move-window-to-screen-next` | Move the focused window to the next screen and follow it |
| `toggle-float` | Float a tiled window at its current frame, or re-tile a floating one |
| `focus-workspace-1` … `focus-workspace-10` | Jump directly to workspace 1…10 on the focused screen (`focus-workspace-10` is bound to the `0` key by default); on the workspace already active, go back to the previously active one |
| `move-window-to-workspace-1` … `move-window-to-workspace-10` | Move the focused window to workspace 1…10 of its screen and follow it; past the last row, into the trailing empty one |
| `move-app-up` / `move-app-down` | Move every managed window of the focused window's app to the workspace above / below the focused one and follow; the app's new windows land there too, over its category |
| `focus-screen-left` / `-right` / `-up` / `-down` | Focus the display in that direction, by the displays' real arrangement: the nearest display whose centre lies that way (within 45° of the direction if any does, else anywhere on that side) |
| `move-window-to-screen-left` / `-right` / `-up` / `-down` | Move the focused window to the display in that direction (as above), onto its active workspace, and follow it |
| `move-workspace-to-screen-left` / `-right` / `-up` / `-down` | Move the active workspace — its windows, layout, sizes and category — to the display in that direction (as above) and follow it. It lands in its category's place in `category-order`, else just above that display's empty bottom row; the display it left activates the row above it (below, if it was the first). Does nothing with no display that way, on the empty bottom row, or on a display's only workspace |
| `cycle-layout-reverse` | `cycle-layout` backwards; from a layout not on the bar, go to the bar's last |
| `set-layout-<id>` | Set the active workspace's layout to `<id>` — any built-in (`set-layout-grid`) or saved layout (`set-layout-code`). Unbound by default; an id no layout has does nothing |
| `focus-tab-1` … `focus-tab-9` | Focus tab N of the active workspace, in tab-bar order; past the last tab, the last; a minimized or hidden tab is brought back, like a click |
| `shrink-width` / `grow-width` | Move the focused tile's side edge 5 % (stopping on 25/50/75 %) to make it narrower / wider; its neighbour gives or takes the space |
| `shrink-height` / `grow-height` | The same for its top or bottom edge, where the layout has rows (half, grid, drawn layouts) |
| `balance` | Put every layout of the focused workspace back to its designed sizes |
| `split-columns-more` / `split-columns-fewer` | Show one column more / fewer in the focused workspace's *split* (2–6, default 2; remembered per workspace and across relaunch). Unbound by default; does nothing when the layout is not split |

### Key names

Generated from `KeyCodes.byName` (macOS `kVK_ANSI_*` virtual key codes, US layout positions):

`a`, `s`, `d`, `f`, `h`, `g`, `z`, `x`, `c`, `v`, `b`, `q`, `w`, `e`, `r`, `y`, `t`, `1`, `2`, `3`,
`4`, `6`, `5`, `equal` (`=`), `9`, `7`, `minus` (`-`), `8`, `0`, `rightSquareBracket` (`]`), `o`,
`u`, `leftSquareBracket` (`[`), `i`, `p`, `enter`, `l`, `j`, `quote` (`'`), `k`, `semicolon` (`;`),
`backslash` (`\`), `comma` (`,`), `slash` (`/`), `n`, `m`, `period` (`.`), `tab`, `space`,
`backtick` (`` ` ``), `backspace`, `esc`, `left`, `right`, `down`, `up`, `home`, `end`, `pageUp`,
`pageDown`.

`Fn+arrows` never arrive as arrows: the HID layer remaps them to Home/End/Page Up/Page Down (with
the Fn flag set) before the hotkey tap sees them — see `docs/platform-notes.md` check #2. So a
chord with `fn` and an arrow means the key it really is: `"fn-shift-left"` is `"fn-shift-home"`,
`right` is `end`, `up` is `pageUp` and `down` is `pageDown`. That is how the default `Fn+⇧+arrows`
(move window to the display that way) are bound. Without `fn`, the arrow keys are the arrows, and
ship pre-bound to `⌃⌥` in both presets.

## `[category-colors]` — rail symbol colours

Optional (#115). A colour per category tints that category's symbol wherever a rail tile draws it
(`rail-icon-style = "category"` or `"hybrid"`, or an empty workspace's own symbol):

```toml
[category-colors]
web = "#0A84FF"
coding = "#BF5AF2"
communication = "#30D158"
```

Keys are the category names (`web`, `coding`, `terminal`, `communication`, `media`, `design`,
`productivity`, `utilities`); values are `#RRGGBB` or `#RRGGBBAA`. A category left out keeps the
stock secondary glyph. The active workspace's tile ignores its colour: its symbol stays white on the
accent fill, because the accent is what says "you are here". A key that is not a category warns
like any unknown key; a value that is not a hex colour rejects the file, as a bad `panel-color`
does. File only: the settings window does not edit these.

## `[telemetry]` — OpenTelemetry traces (#148)

Off by default. When on, the shell exports traces over OTLP/HTTP (protobuf) to
`<endpoint>/v1/traces`, with an `Authorization: Basic base64(user:token)` header — the shape
Grafana Cloud's OTLP gateway takes (`user` is the stack's instance id, `token` an access-policy
token with `traces:write`).

```toml
[telemetry]
enabled = true
endpoint = "https://otlp-gateway-prod-us-west-0.grafana.net/otlp"
user = "123456"
token = "…"
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. Off means off: no SDK is registered and no network call is made, whatever the environment says. |
| `endpoint` | string | `""` | The OTLP base URL; `/v1/traces` is appended. |
| `user` | string | `""` | The Basic-auth user. |
| `token` | string | `""` | The Basic-auth password. With no token (and no `OTEL_EXPORTER_OTLP_HEADERS`), telemetry stays off even when `enabled = true`. |

> **Warning: this table holds a secret.** Keep the file private — `chmod 600
> ~/.config/spacial-shell/config.toml` — and do not paste it into issues or dotfile repos with the
> token in it. SpacialShell never writes the token back out: a config it renders has the table
> without `token`.

- **Environment overrides.** `OTEL_EXPORTER_OTLP_ENDPOINT` replaces `endpoint`, and
  `OTEL_EXPORTER_OTLP_HEADERS` (`key=value,key=value`, values percent-encoded, e.g.
  `Authorization=Basic%20…`) replaces the Basic header and counts as the credential. Neither can
  turn telemetry on.
- **Read at launch.** Turning it on or off, or changing the endpoint, takes a relaunch.
- **What is sent.** Spans for commands (`command` → `reconcile` → `reconcile.writes` /
  `reconcile.raise` → `animation.prepare` / `animation.play`), snapshots (`snapshot` → `reconcile`),
  hotkey dispatch (`hotkey.dispatch`) and control-socket requests (`ipc.request`). Attributes are
  command names, bundle ids, window ids, display counts, counts and durations — **never window
  titles**. The resource carries `service.name = spacial-shell`, the version, the OS and the host
  name and architecture.
- **Failures.** Spans are batched (one POST every 5 s at most, a bounded queue that drops rather
  than grows). An export that fails is logged under the `telemetry` category and dropped; nothing
  else notices. The first successful export logs `export ok: HTTP 200` at notice:
  `/usr/bin/log show --last 5m --predicate 'subsystem == "sh.emu.SpacialShell" && category == "telemetry"'`.
  Quitting flushes what is queued (bounded by a 5 s timeout).

## Where the file lives

The config file *is* the interface — it is why `Fn+,` opens it and why the settings window layers
over it instead of writing it (see `docs/superpowers/specs/2026-09-12-toml-writeback-research.md`).
That position is unchanged. What changes under the App Sandbox is only the directory it lives in.

| Build | Config | State |
|---|---|---|
| Direct distribution (ships today, unsandboxed) | `~/.config/spacial-shell/config.toml` | `~/Library/Application Support/SpacialShell/` |
| Sandboxed (App Store) | `~/Library/Containers/sh.emu.SpacialShell/Data/.config/spacial-shell/config.toml` | `…/Data/Library/Application Support/SpacialShell/` |

This is one code path, not two: `Paths.swift` derives everything from
`FileManager.default.homeDirectoryForCurrentUser`, and macOS redirects that accessor to the
container when the process is sandboxed — verified by probe on macOS 26.5, tabulated in
`Scripts/README`. Nothing branches on a sandbox check, and the unsandboxed build resolves exactly
the paths it always has.

**The decision, and the position it re-opens.** Issue #19 chose to let the config move into the
container, rather than keep the dotfile behind a security-scoped bookmark the user grants once, or
ship two builds with different config locations. The bookmark option keeps `~/.config` but makes
first launch a file-picker the user has to satisfy before the window manager works at all, and
leaves the config unreadable if the bookmark ever goes stale; two builds means two documented
paths and two support stories. Moving into the container keeps one path per build, keeps the file
hand-editable, and pays for it in discoverability.

**What it costs a hand-editing user, stated rather than glossed:**

- Hand-editing still works, and still round-trips live — the file is a real file in a real
  directory, writable, and the directory watch that drives live reload works inside the container
  (probed). Your editor, your comments, your key order: unchanged.
- The path is no longer guessable, and `~/.config/spacial-shell/` is where you will look first and
  find nothing. **Use the settings window's "Open config.toml…" button** (or `Fn+,`), which opens
  whichever file the running build actually reads. That button is the discoverable route and is
  the reason the loss is survivable rather than fatal.
- Shell tooling that assumed `~/.config/spacial-shell` — dotfile repos, symlinks, `$EDITOR`
  aliases — needs repointing for a sandboxed build. A symlink from `~/.config/spacial-shell` into
  the container works from outside; the app cannot follow one pointing the other way.
- **An existing `~/.config/spacial-shell/config.toml` is unreachable to a sandboxed build**, and
  cannot be migrated automatically: the sandbox refuses to read the real home, so the app cannot
  even see the old file to copy it. A sandboxed build starts at defaults and writes a fresh empty
  config. Moving your settings across is a manual copy, once, into the container path above. No
  import flow exists and #19 deliberately does not add one.

## State

Separately from config, `~/Library/Application Support/SpacialShell/state.json` holds the pinned
workspace shells (name, symbol, layout, id, and any sizes you gave its layouts by resizing, #113)
per screen, and each row's tabs in order — every window's app (bundle id), its last title and
whether it floats (#128) — so they come back as placeholder tabs after a relaunch. Titles are
the only window content it holds, and it never leaves the machine. Written debounced on every
model change. A `state.json` from before #128 has no tabs and loads as it always did.
It is machine-owned — not meant for hand editing — and is not covered by this reference.
`persist-state = false` turns it off (see the table above).

### Resetting saved state

To make SpacialShell forget its saved workspaces, their layouts and sizes, and where each app's
windows go, and start fresh:

1. **Quit SpacialShell** (the rail's app menu › Quit). Quitting
   puts every parked window back and writes `state.json` one last time, which is why it comes first.
2. **Delete `state.json`**: `rm ~/Library/Application\ Support/SpacialShell/state.json` (a sandboxed
   build keeps it under `~/Library/Containers/sh.emu.SpacialShell/Data/Library/Application Support/SpacialShell/`,
   see [Where the file lives](#where-the-file-lives)).
3. **Relaunch SpacialShell.** It starts from your `[[workspace]]` seeds and category routing.

Or, with SpacialShell running, **`spacialctl reset-state`** or the settings window's **Reset saved
state…** button (General pane) does steps 1–2 for you without quitting: it deletes `state.json`
and stops writing it for the rest of the session. The windows stay where they are; the next launch
starts fresh. Until then the rail cog lists a warning saying nothing is being saved.

Neither touches `config.toml` or `settings.json` (what the settings window has set).


## Why `app-categories` exists

The rail labels each workspace with the kind of work it is for. macOS has one piece of metadata
that could answer this, `LSApplicationCategoryType` in each app's `Info.plist`, and it is not good
enough. Measured over a real `/Applications` folder:

- **103 of 190 apps declare it at all.** Chrome and Brave declare nothing.
- **Every browser that does declare it says `productivity`** — Safari, Firefox and Tor alike. So
  "web browsing" cannot be derived from it, at all, ever.
- **It is wrong often enough to matter.** ChatGPT, Claude and a crypto wallet all claim
  `developer-tools`. There is no terminal category in Apple's vocabulary.

So SpacialShell resolves a category in four tiers, first match winning:

1. `app-categories` from this file — your overrides.
2. A curated bundle-id table in `SpacialShellKit` — browsers, terminals, editors, chat clients.
3. `LSApplicationCategoryType`, mapped coarsely — for apps tiers 1 and 2 have never heard of.
4. Nothing. An unlabelled workspace beats a confidently wrong label.

Tier 2 is permanently incomplete by construction, which is what tier 1 is for:

```toml
[app-categories]
"com.example.MyEditor" = "coding"
"com.example.Chatterbox" = "communication"
```
