# Keybindings

SpacialShell is keyboard-first. Every verb from material-shell is bound out of the box, on one of
two presets, and everything is rebindable in `~/.config/spacial-shell/config.toml`.

## Which modifier?

material-shell used the **Super** key. macOS has no free Super: `⌘` is load-bearing in every app
(`⌘W` closes, `⌘Q` quits, `⌘S` saves…), so SpacialShell ships two presets:

| Preset | Modifier | Pick it when |
|---|---|---|
| `fn` *(default)* | **Fn / Globe 🌐** — the key at bottom-left of every Apple keyboard, exactly where Super sits on a Linux keyboard | Apple keyboard (built-in, Magic Keyboard, or any keyboard presenting Apple's vendor id) |
| `ctrl-alt` | **⌃⌥** (Control + Option) | Non-Apple keyboards (their firmware handles Fn and never sends it), or if `Fn` conflicts with a macOS shortcut you rely on |

Switch with one line in the config:

```toml
keybinding-preset = "ctrl-alt"
```

> **Fn caveat — read before relying on the default.** macOS 26 reserves several Fn+letter chords
> as system shortcuts (`Fn+A` Dock, `Fn+S` Type-to-Siri, `Fn+Q` Quick Note, `Fn+H` Show Desktop,
> `Fn+F` Full Screen, `Fn+C`/`N`/`M`…), and most of them cannot be changed in System Settings.
> SpacialShell's event tap runs *before* those shortcuts and consumes bound chords, which is how
> `Fn+A`/`Fn+S` are expected to reach us — but this is being verified empirically on real
> hardware (see `docs/platform-notes.md`, check 1). If the check fails, the default preset flips
> to `ctrl-alt` and `fn` stays as an option. Either way `Fn+F` is never bound: Globe+F is Apple's.

## Cheat-sheet

**On-screen version:** hold the bare preset modifier — `Fn` alone (or `⌃⌥` on the `ctrl-alt`
preset) — for about ¾ s and this table appears as an overlay with your *actual* bindings,
including everything you rebound; release to dismiss.

Same shape as material-shell: **W/S move between workspaces (rows), A/D between windows (columns);
Shift moves the window instead of the focus; Option means another display.** Arrow keys are
row/tab aliases and are always on `⌃⌥`, in both presets. With Fn, the arrows mean **displays**:
`Fn+⇧+arrow` moves the window to the display that way, and `Fn+⌥⇧+arrow` the whole workspace. (macOS turns `Fn+arrows` into
Home/End/PgUp/PgDn below the keyboard driver, so that is what those chords are bound to.)

| Command | `fn` preset | `ctrl-alt` preset | material-shell |
|---|---|---|---|
| Focus workspace up / down | `Fn+W` / `Fn+S` | `⌃⌥W` / `⌃⌥S` | Super+W / S |
| Focus window left / right † | `Fn+A` / `Fn+D` | `⌃⌥A` / `⌃⌥D` | Super+A / D |
| Focus the previous window of the workspace; again, back (`focus-previous-window`) | `Fn+P` | `⌃⌥P` | — |
| Switch between the focused app's windows, on every workspace and display — hold, tap `` ` `` (``⇧` `` back), let go (`switch-app-window`, `switch-app-window-reverse`) | ``Fn+` `` / ``Fn+⇧` ``, and ``⌘` `` / ``⌘⇧` `` | ``⌃⌥` `` / ``⌃⌥⇧` ``, and ``⌘` `` / ``⌘⇧` `` | Super+`` ` `` |
| Focus workspace 1…10 (again on the active one: back to the previous) | `Fn+1` … `Fn+9`, `Fn+0` | `⌃⌥1` … `⌃⌥0` | Super+1 … 0 |
| Focus tab 1…9 of the active workspace (past the last: the last; `0`: the first) | `Fn+⌥1` … `Fn+⌥9`, `Fn+⌥0` | unbound ‡ | — |
| Move window to workspace 1…10 | `Fn+⇧1` … `Fn+⇧0` | `⌃⌥⇧1` … `⌃⌥⇧0` | Super+Shift+1 … 0 |
| Move the whole app to the workspace above / below | `Fn+⌥⇧W` / `Fn+⌥⇧S` | unbound ‡ | — |
| Close focused window (app keeps running) | `Fn+Q` | `⌃⌥Q` | Super+Q |
| Move window left / right | `Fn+⇧A` / `Fn+⇧D` | `⌃⌥⇧A` / `⌃⌥⇧D` | Super+Shift+A / D |
| Move window to workspace above / below | `Fn+⇧W` / `Fn+⇧S` | `⌃⌥⇧W` / `⌃⌥⇧S` | Super+Shift+W / S |
| Cycle layout round the layout bar (default: maximize → split → column → half → grid → ratio) | `Fn+Space` | `⌃⌥Space` | Super+Space |
| Cycle layout backwards | `Fn+⇧Space` | `⌃⌥⇧Space` | — |
| Set a specific layout (`set-layout-grid`, `set-layout-<saved id>`) | unbound | unbound | — |
| Split: one column more / fewer (`split-columns-more` / `split-columns-fewer`) | unbound | unbound | — |
| Pin / unpin the focused window's tab (`toggle-pin`) | unbound | unbound | tab menu "Pin" |
| Toggle shell panels (Zen mode) | `Fn+Esc` | `⌃⌥Esc` | Super+Esc |
| Open overview / launcher | `Fn+Tab` | `⌃⌥Tab` | Super (overview) |
| Spatial view: every workspace as a mini-desktop (`toggle-spatial-view`); also by holding `Fn+W` / `Fn+S` | `Fn+Z` | `⌃⌥Z` | — |
| Open the config file | `Fn+,` | `⌃⌥,` | — |
| Focus the display left / right / above / below | `Fn+⌥A` / `Fn+⌥D` / `Fn+⌥W` / `Fn+⌥S` | unbound ‡ | — |
| Move window to the display left / right / above / below | `Fn+⇧←` / `Fn+⇧→` / `Fn+⇧↑` / `Fn+⇧↓` | unbound ‡ | — |
| Move the whole workspace to the display left / right / above / below | `Fn+⌥⇧←` / `Fn+⌥⇧→` / `Fn+⌥⇧↑` / `Fn+⌥⇧↓` | unbound ‡ | — |
| Focus previous / next screen (aliases) | `Fn+[` / `Fn+]` | `⌃⌥[` / `⌃⌥]` | — |
| Move window to previous / next screen (aliases) | `Fn+⇧[` / `Fn+⇧]` | `⌃⌥⇧[` / `⌃⌥⇧]` | — |
| Toggle float on the focused window | `Fn+G` | `⌃⌥G` | — |
| Resize the focused tile: narrower / wider | `Fn+⌃A` / `Fn+⌃D` | `⌃⌥⌘A` / `⌃⌥⌘D` | — |
| Resize the focused tile: shorter / taller | `Fn+⌃W` / `Fn+⌃S` | `⌃⌥⌘W` / `⌃⌥⌘S` | — |
| Balance: the workspace's layouts back to their designed sizes | `Fn+⌃=` | `⌃⌥⌘=` | — |
| Arrow aliases: focus / move | `⌃⌥←→↑↓` / `⌃⌥⇧←→↑↓` | same | — |

† "Left/right" walks every *visible* window of the active workspace, floating ones included, and
wraps at the ends; minimized / hidden windows are skipped, and so are placeholder tabs (#128 —
saved windows whose app has not brought them back), and ephemeral "visitor" windows (System
Settings, Calculator by default) are in no row at all. Under the *maximize* layout this behaves
exactly like switching tabs — the newly focused window fills the screen and the previous one is
parked. Under *split* (#114) a view of N consecutive windows is shown (2 by default); moving
focus inside it moves nothing, and moving past either edge slides it along by one window.

‡ The grammar is Fn = navigate, +⇧ = move, +⌃ = resize, +⌥ = monitor, and on the move chord +⌥
means "the whole app". The `ctrl-alt` prefix already holds ⌥, so there the chord would be `⌃⌥⇧W/S`
(move window up/down); bind `move-app-up` / `move-app-down` yourself if you want them. The same
goes for the display chords (`⌃⌥A` is already focus-window-left, and `⌃⌥` + arrows are the row/tab
aliases) and for the tab digits (`⌃⌥1` is workspace 1): bind `focus-screen-left`…,
`move-window-to-screen-left`…, `move-workspace-to-screen-left`… and `focus-tab-1`… by name. Digits have no display meaning, which is
why `Fn+⌥+digit` is free for tabs on the `fn` preset.

Semantics worth knowing:

- Focus workspace **down** from the last (empty) workspace does nothing; move window **down**
  from it creates a new workspace below (there is always one empty, unpinned workspace at the
  bottom of every screen — that is where new things go). With `workspace-wrap = true`, `Fn+W` on
  the first workspace goes to the last non-empty one and `Fn+S` on the last non-empty one goes to
  the first; the empty one at the bottom is then reached by the rail's "+" or by `Fn+⇧S`.
- "The display that way" is judged on the displays' real arrangement (System Settings → Displays),
  not their order: the nearest display whose centre lies in that direction — within 45° of it if
  any display does, else anywhere on that side. With nothing that way the chord does nothing (no
  wrap). The `[`/`]` aliases still step through the displays in left-to-right order, wrapping.
- `Fn+⌥N` focuses the Nth tab of the active workspace as the tab bar draws it, minimized tabs
  included (landing on one brings it back, like clicking it). N past the last tab focuses the last;
  `Fn+⌥0` focuses the first. On an empty workspace it does nothing. On a placeholder tab (#128) it
  does what a click does: opens the app, whose window then takes that tab's place.
- **Placeholder tabs** (#128): after a relaunch every window you had comes back as a tab in its
  place — dimmed, with a dashed outline, the app's icon and the window's last title — until its
  app opens a window again, which takes that exact slot (same row, same position, floating if it
  was). Clicking one (or choosing Open from its right-click menu) opens the app; closing one
  (middle-click, or Close in the menu) forgets the slot. Placeholders take no tile and are never
  focused, so they never hide a live window; they drag between tabs and onto rail rows like any
  tab. Matching goes by the app's bundle id, then the same title, then the tab you clicked, then
  the order the tabs were in.
- **Pinned tabs** (#129, material-shell's persistent tab): right-click a tab → **Pin** (or bind
  `toggle-pin`). A pinned tab shows `pin.circle.fill`; when its window closes — or its app quits —
  the tab stays where it was as a placeholder, and the app's next window takes it back, still
  pinned. A pinned placeholder cannot be closed (Close is disabled, middle-click does nothing)
  until you **Unpin** it. Pins survive relaunch.
- **Dragging placeholders** (#129): a placeholder tab drags like any tab — along its bar, onto
  another display's bar, onto a rail row (with ⇧ or ⌥ held, every window of that app goes too). It has no window to grab
  by a title bar, so the tab is the handle; the drag-swap verb (`dropWindow`) accepts it on either
  side, swapping within a row or taking a slot in another. Focus never follows a placeholder.
- Move window left/right at the end of the row (or as the only tab) carries the window to the
  neighbouring screen in that direction, landing at the near end of its active row (moving right
  lands leftmost, moving left lands rightmost), keeping its floating flag; focus follows. On the
  outermost screen in that direction it is a no-op (no wrap for moves).
- Move window left/right under **maximize** — or any layout that shows fewer than two windows,
  such as a one-zone drawn layout — promotes the workspace to **split**. Maximize paints only the
  focused window and the focus travels with it, so the move would reorder the row without changing
  a pixel; the verb means "put this beside that", and split is the narrowest layout that can show
  the pair. Layouts that already show more than one window are left as you set them. Only
  an in-row swap promotes: a move to another screen leaves both layouts alone, and a refused move
  (outermost screen) changes nothing at all, layout included.
- Move to another screen appends the window to that screen's active workspace and focus follows.
- `Fn+⌥⇧+arrow` moves the active workspace itself to the display that way — its windows, layout,
  resized portions and category go with it — and focus follows. It lands where `category-order`
  puts its category (taking that category from any row already there), else just above the
  display's empty bottom row; each display still ends in exactly one empty row. The display it
  left activates the row above it (below, if it was the first). It does nothing with no display
  that way, on the empty bottom row, or on a display's only workspace.
- `Fn+N` on the workspace you are already on goes back to the one you were on before, so one chord
  flips between two workspaces. Each screen remembers its own previous workspace; if that
  workspace has gone away (emptied and removed), the re-press does nothing.
- `Fn+⇧N` moves the focused window to workspace N of its screen and focus follows. N past the last
  workspace lands in the trailing empty one, and a new empty one appears below it.
- `Fn+⌥⇧W/S` moves every window of the focused window's app (tiled and floating; popups and
  ignored windows stay put), in order, to the workspace above / below the focused one, and focus
  follows. From the top row it opens a new workspace above, like `Fn+⇧W`. Holding **⌥ while
  dropping a tab** (on a rail tile or a tab bar) does the same for that tab's app, into that
  workspace, without switching to it. Either way the app's new windows land there too, and this
  wins over category routing for that app from then on.
- **Resize** (`Fn+⌃A/D/W/S`, #113) moves one edge of the focused tile by 5 % of the tiling area: its
  right (or bottom) edge, or its left (or top) edge when it is the last column (row), so `D`/`S`
  always make it bigger. A step that would cross 25, 50 or 75 % stops on it. The neighbour across
  that edge gives or takes the space; no tile goes below 10 % of the area, and the tiles never go
  below the 120 × 80 pt floor on the real screen. Sizes are remembered per workspace, per layout,
  per number of tiles shown (three columns and four keep their own), and survive relaunch;
  `Fn+⌃=` (`balance`) puts every layout of the workspace back as designed. Maximize has no edge
  to move, so the keys do nothing there; nor does a tile whose edge on that axis is the screen's.
- **Split columns** (#114): *split* shows N windows side by side, N per workspace from 2 to 6
  (default 2). Change it with the − / + on the Split row of the tab bar's layout popover (the cog),
  or bind `split-columns-more` / `split-columns-fewer`. N is remembered per workspace and survives
  relaunch; resized sizes apply within the N shown, and each N keeps its own. A screen too narrow
  for N columns of 120 pt shows as many as fit.
- **Mouse resize** (#113): hover the gap between two tiles and it lights up; drag it and both
  tiles follow live, snapping to 25/50/75 % when you pass within 2 % of them. Grabbing a tile's own
  edge next to a neighbour does the same. Every edge in line with it moves too: dragging the line
  between the master and the stack in *half* resizes every window of the stack.
- **Resize to maximize** (#178): in *split*, letting go of a border (or lifting a four-finger
  drag) with one tile within 2 % of the largest a tile can get — every other tile at or near its
  10 % floor, so 88 % with two columns and 78 % with three — switches the workspace to *maximize* on that tile, focused, and forgets the split's sizes, so
  going back to split starts even (50/50 with two columns). Only at the release, and only after a
  real resize: mid-drag nothing switches, and neither does a click or a nudge (under 2 %) on a
  border the keys already left that far. Other layouts keep whatever size you leave them at.
- Close presses the window's close button; the app stays running (macOS convention). Focus goes to
  the window you used before it in that workspace (#137), else the left neighbour, else the right.
- **Focus history** (#137): each workspace remembers the last five windows focused in it, however
  focus got there (keys, clicks, ⌘Tab). It is what a close falls back to, and what `Fn+P`
  (`focus-previous-window`; it was ``Fn+` `` until #188) walks: it focuses the window before this
  one, and pressed again comes back, so one chord flips between two windows — the window-level
  twin of `Fn+N` on the active workspace. A minimized window there is brought back, as a tab click does. Placeholder tabs
  (#128) are never in the history. It is not saved: a relaunch starts every workspace afresh.
- **App window switcher** (#188): Linux's Super+`` ` ``. ``Fn+` `` (``⌃⌥` `` on `ctrl-alt`) or ``⌘` ``
  (on every preset — macOS's own ⌘` only cycles the current Space, where the shell has parked the
  other workspaces' windows, so the shell takes the chord) opens a panel of every window of the
  focused window's app, on every workspace and display: a preview of each (its app's icon until a
  capture lands, or without Screen Recording), its title and its workspace. The focused window is
  first, then the rest most recently used first, and the selection starts on the second, so a tap
  and release goes to the app's previous window, like ⌘Tab. Keep the modifier (Fn, ⌃⌥ or ⌘) down
  and tap `` ` `` to step, ``⇧` `` to step back (both wrap); let go to switch there, workspace and
  display included, as a tab click does. `Esc` cancels; clicking a preview switches to it. With a
  single window it does not open. Placeholder tabs are not listed; popups are.
- Autorepeat of a bound chord is swallowed, not re-fired: holding `Fn+D` moves once and types
  nothing into the front app.
- **Spatial view** (#132): the focused display's workspaces zoomed out, one mini-desktop per row,
  top to bottom, with the active row in the middle. Each window is a chip (icon and title) where
  its row's layout puts it; windows the layout does not show right now (past split's view, a
  floating or minimized one) wait beside the mini-desktop. Drawn from the model, not captured, so it
  needs no Screen Recording grant. `Fn+Z` opens it until `Fn+Z` again; while it is open `Fn+W/S`,
  `Fn+A/D` and the rest work as always and the camera slides to follow. **Holding** `Fn+W` or
  `Fn+S` (or `Fn+⇧W/S`) past the key-repeat delay opens it the ⌘Tab way instead: keep `Fn` down,
  tap `W`/`S` to ride between rows, and let go of `Fn` to land. Click a mini-desktop to go to that
  workspace, a chip to go to that window, or the backdrop to close it. With Reduce Motion the camera
  cuts instead of sliding.

## Rebinding

Add a `[keybindings]` table. A chord you name **replaces** the built-in binding for that chord;
a chord the preset doesn't use is **added**. (M1 has no way to *unbind* a built-in chord — only to
point it at another command.)

```toml
[keybindings]
"fn-shift-g" = "toggle-float"      # add a second chord for float
"ctrl-alt-t" = "cycle-layout"      # extra binding on top of the preset
"fn-q"       = "toggle-shell-ui"   # repoint Fn+Q away from close (e.g. if you keep Quick Note)
```

**Chord notation:** modifiers joined by `-`, then one key name. Modifiers: `fn`, `ctrl`/`control`,
`alt`/`option`, `shift`, `cmd`/`command`. Key names are US-layout virtual-key positions
(`kVK_ANSI_*`): `a`…`z`, `0`…`9`, `space`, `tab`, `enter`, `esc`, `backspace`, `minus`, `equal`,
`leftSquareBracket`, `rightSquareBracket`, `semicolon`, `quote`, `comma`, `period`, `slash`,
`backslash`, `backtick`, `left`, `right`, `up`, `down`, `home`, `end`, `pageUp`, `pageDown`
(`fn-` + an arrow means the navigation key Fn turns it into: `fn-shift-left` is `fn-shift-home`).
`set-layout-<id>` binds a specific layout: `"fn-alt-shift-g" = "set-layout-grid"`. The full generated list and every command
name are in [`docs/config.md`](config.md#keybindings--overrides-and-additions).

Config is watched: save the file and bindings reload live (invalid TOML keeps the previous config
and logs the error).

### Recipes

- **Hyper key on Caps Lock** (Karabiner-Elements users): map Caps Lock → `⌃⌥⇧⌘`, then bind
  `"ctrl-alt-shift-cmd-w" = "focus-workspace-up"` and so on. Every chord in the table above works
  with `ctrl-alt-shift-cmd-` as the prefix.
- **Non-Apple keyboard, but you want the Fn feel:** in Karabiner-Elements map a spare key to `fn`
  (Karabiner's virtual keyboard presents Apple ids, so the remapped Fn arrives as real Fn) and keep
  `keybinding-preset = "fn"`. Or just use `ctrl-alt`.
- **Colemak / Dvorak:** key names are physical positions, so `w`/`a`/`s`/`d` stay where they are
  on the board regardless of layout — usually what you want for a spatial-navigation cluster.

## Trackpad swipes

Swiping with three fingers does what `Fn+W/A/S/D` do, one step per swipe:

| Swipe | Runs | Same as |
|---|---|---|
| left | `focus-window-right` | `Fn+D` |
| right | `focus-window-left` | `Fn+A` |
| up | `focus-workspace-up` | `Fn+W` |
| down | `focus-workspace-down` | `Fn+S` |

This follows macOS's own swipes. Horizontally the content follows the fingers, like switching
full-screen apps: the swipe pushes the current window away and pulls in its neighbour. Vertically
the swipe points, like Mission Control's swipe up: up goes to the workspace above, as on the rail.
`gesture-invert = true` flips both. A swipe fires once it has travelled about an eighth of the trackpad along one
axis, clearly more along that axis than the other; a diagonal does nothing. Lift your fingers to
swipe again. `gesture-fingers` picks 3, 4 or 5 fingers, and `gestures = false` turns swipes off
(see [config](config.md)). Both toggles are also in the settings window's General pane.

**Four** fingers change the layout (`gesture-layout`, on by default; *Layout swipes* in the General
pane):

| Four fingers | Does | Same as |
|---|---|---|
| swipe up | `cycle-layout`, one step per swipe | `Fn+Space` |
| swipe down | `cycle-layout-reverse`, one step per swipe | `Fn+⇧Space` |
| drag right / left | the focused tile grows / shrinks, live, by how far the fingers go | dragging the border between tiles with the mouse |

Left and right are not steps but a drag. As soon as four fingers have moved a little (about 3 % of
the trackpad) more sideways than up or down, they take hold of the focused tile's side edge (the
edge `Fn+⌃A/D` move: its right edge, or its left one for the last column) until you lift. The
edge follows your fingers, whichever side of the tile it is on: right moves it right. The change is
proportional and gentle: the full width of the trackpad moves the edge half the width of the row. It behaves exactly like dragging that border with the mouse: no tile gets
narrower than a tenth of the row, the edge catches on the 25/50/75 % marks as it passes them, and
where you lift is where it stays, except that in `split` lifting with either tile within 2 % of the
largest a tile can get switches to `maximize` on it (see *Resize to maximize* above). Fingers lifting unevenly don't move
it. In `maximize` there is no edge, so a sideways drag does nothing. A swipe that starts up or down stays a layout swipe, however
it goes on.

`gesture-invert` doesn't apply to four fingers. Three and four fingers are told apart per gesture:
fingers usually land one at a time, so a gesture counts as the most fingers it had down, and
lifting a four-finger gesture through three never fires a three-finger swipe. With
`gesture-fingers = 4`, four fingers navigate and the layout gestures are off.

**Turn off macOS's own gestures on the fingers SpacialShell uses.** SpacialShell can watch trackpad
gestures but, through public API, not take them away from macOS, so a swipe that macOS also uses
switches Space or opens Mission Control as well. In System Settings → Trackpad → More Gestures,
turn **Mission Control**, **App Exposé** and **Swipe between full-screen applications** off, or
set them to four fingers if you turn `gesture-layout` off (moving them to four fingers while layout
swipes are on only moves the clash); if "Swipe between pages" uses three fingers, change that too.
Three-finger drag (Accessibility → Pointer Control → Trackpad Options) turns three-finger movement
into a drag and also conflicts. While a conflicting setting is on, a warning under the rail cog says
which to change; it clears the next time you leave System Settings with it fixed.

## Secure input and Karabiner-Elements

While an app has a password field focused, macOS turns on **Secure Event Input**: key-downs are
hidden from every event tap, SpacialShell's included, so the hotkeys do nothing until you leave the
field (#193). A password prompt can also hold it while hidden behind other windows.

[Karabiner-Elements](https://karabiner-elements.pqrs.org) seizes the keyboard below the
WindowServer, through its own virtual HID driver, so its rules still fire in password fields.
SpacialShell can hand its hotkeys to Karabiner as a rules file (#196):

1. **Settings → General → Karabiner-Elements → Write rules file.** The section is there only when
   `/Applications/Karabiner-Elements.app` is installed, and nothing is written until you click.
   With Karabiner installed and no rules file, the rail cog lists the offer once; **Dismiss** puts
   it away for good (Settings → General → Silenced warnings → **Warn again** brings it back).
2. **Enable it in Karabiner-Elements → Settings → Complex Modifications → Add predefined rule →
   SpacialShell.** **Open Karabiner-Elements** in the same section gets you there.

The file is `~/.config/karabiner/assets/complex_modifications/spacialshell.json`, Karabiner's
import folder. SpacialShell never edits `karabiner.json`. The file holds one rule with one entry per
bound chord, Fn as Karabiner's `fn` modifier. Each runs `spacialctl run <command>`, with the full
path of the `spacialctl` inside the app. For dotfiles, `spacialctl karabiner-rules` prints the same
JSON, and `spacialctl karabiner-rules --write` writes the file.

**Keeping it current.** Once the file exists, SpacialShell rewrites it whenever your bindings or the
preset change, and at each launch (the app may have moved). Karabiner copies a rule into its own
config when you enable it, so to pick up a change remove the SpacialShell rule in Karabiner and add
it again. Delete the file to opt out; SpacialShell then stops writing it.

**What is different through Karabiner:**

- Karabiner consumes the chord, so SpacialShell's own tap never also sees it: nothing fires twice.
- Each chord spawns `spacialctl`, which costs about 5–20 ms more than the tap. If you press a second
  chord while the first `spacialctl` is still running, Karabiner kills the first one, so very fast
  repeats can drop a step.
- A chord fires once per press. Holding it does not repeat, and holding `Fn+W`/`Fn+S` does not open
  the spatial view (#132).
- The app window switcher (`` ⌘` ``, `` Fn+` ``, #188) is left out: it opens on the press and picks on the
  release, which a one-shot command cannot follow. The rule's description in Karabiner lists these.
- The rules run everywhere, not just in password fields. Karabiner's rule wins over the tap, so the
  hotkeys work as before, plus the spawn cost above.

## Conflicts and edge cases

- `Fn+F` is intentionally unbound (Apple full screen). `Fn+F1…F20` are never bindable (media keys /
  `fnKeyMode`).
- Tapping `Fn` **alone** still triggers whatever "Press 🌐 key to" is set to in System Settings
  (emoji picker, dictation…); SpacialShell only matches Fn *held* with another key.
- While a **password field has focus** (Secure Input), macOS stops delivering keystrokes to every
  event tap; hotkeys are deaf until you leave the field. This is by design of macOS, and nothing
  can opt out of it. SpacialShell notices within about 2 s and lists it under the rail cog, naming
  the app and window asking for a password and its workspace, with **Show window** to bring it up.
  The usual culprit is a prompt you can't see: a password window left on another workspace, or an
  app that reopened after a reboot with its password field focused (#193). So such a window is
  never left parked: while it holds a focused password field it is shown centred on the focused
  display, in front, without taking focus, and goes back to its own row once it lets go (#195).
  Terminal's and iTerm's
  **Secure Keyboard Entry** do the same without a password field; they are listed as "An app has
  secure keyboard entry on". `log stream --predicate 'subsystem == "sh.emu.SpacialShell" AND
  category == "hotkeys"'` shows each change with the app's pid and window.
  With Karabiner-Elements they keep working anyway: see [Secure input and Karabiner-Elements](#secure-input-and-karabiner-elements).
- Another window manager or hotkey daemon that also consumes these chords (skhd, Hammerspoon,
  BetterTouchTool, Raycast's Fn hotkeys) wins or loses depending on which tap was installed first —
  run one at a time.
- Sleep/lock/re-sign can disable an event tap; SpacialShell re-enables its own on wake and unlock
  and polls its health every second. If hotkeys ever go dead, `killall SpacialShell` and relaunch.

See also: [`docs/config.md`](config.md) (full reference), [`docs/platform-notes.md`](platform-notes.md)
(what is verified on real hardware and what is still pending), and the spec's §6 for the design
rationale.
