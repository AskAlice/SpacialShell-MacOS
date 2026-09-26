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
`Fn+⇧+arrow` moves the window to the display that way. (macOS turns `Fn+arrows` into
Home/End/PgUp/PgDn below the keyboard driver, so that is what those chords are bound to.)

| Command | `fn` preset | `ctrl-alt` preset | material-shell |
|---|---|---|---|
| Focus workspace up / down | `Fn+W` / `Fn+S` | `⌃⌥W` / `⌃⌥S` | Super+W / S |
| Focus window left / right † | `Fn+A` / `Fn+D` | `⌃⌥A` / `⌃⌥D` | Super+A / D |
| Focus workspace 1…10 (again on the active one: back to the previous) | `Fn+1` … `Fn+9`, `Fn+0` | `⌃⌥1` … `⌃⌥0` | Super+1 … 0 |
| Focus tab 1…9 of the active workspace (past the last: the last; `0`: the first) | `Fn+⌥1` … `Fn+⌥9`, `Fn+⌥0` | unbound ‡ | — |
| Move window to workspace 1…10 | `Fn+⇧1` … `Fn+⇧0` | `⌃⌥⇧1` … `⌃⌥⇧0` | Super+Shift+1 … 0 |
| Move the whole app to the workspace above / below | `Fn+⌥⇧W` / `Fn+⌥⇧S` | unbound ‡ | — |
| Close focused window (app keeps running) | `Fn+Q` | `⌃⌥Q` | Super+Q |
| Move window left / right | `Fn+⇧A` / `Fn+⇧D` | `⌃⌥⇧A` / `⌃⌥⇧D` | Super+Shift+A / D |
| Move window to workspace above / below | `Fn+⇧W` / `Fn+⇧S` | `⌃⌥⇧W` / `⌃⌥⇧S` | Super+Shift+W / S |
| Cycle layout round the layout bar (default: maximize → split → column → half → grid) | `Fn+Space` | `⌃⌥Space` | Super+Space |
| Cycle layout backwards | `Fn+⇧Space` | `⌃⌥⇧Space` | — |
| Set a specific layout (`set-layout-grid`, `set-layout-<saved id>`) | unbound | unbound | — |
| Toggle shell panels (Zen mode) | `Fn+Esc` | `⌃⌥Esc` | Super+Esc |
| Open overview / launcher | `Fn+Tab` | `⌃⌥Tab` | Super (overview) |
| Open the config file | `Fn+,` | `⌃⌥,` | — |
| Focus the display left / right / above / below | `Fn+⌥A` / `Fn+⌥D` / `Fn+⌥W` / `Fn+⌥S` | unbound ‡ | — |
| Move window to the display left / right / above / below | `Fn+⇧←` / `Fn+⇧→` / `Fn+⇧↑` / `Fn+⇧↓` | unbound ‡ | — |
| Focus previous / next screen (aliases) | `Fn+[` / `Fn+]` | `⌃⌥[` / `⌃⌥]` | — |
| Move window to previous / next screen (aliases) | `Fn+⇧[` / `Fn+⇧]` | `⌃⌥⇧[` / `⌃⌥⇧]` | — |
| Toggle float on the focused window | `Fn+G` | `⌃⌥G` | — |
| Arrow aliases: focus / move | `⌃⌥←→↑↓` / `⌃⌥⇧←→↑↓` | same | — |

† "Left/right" walks every *visible* window of the active workspace, floating ones included, and
wraps at the ends; minimized / hidden windows are skipped and ephemeral "visitor" windows (System
Settings, Calculator by default) are in no row at all. Under the *maximize* layout this behaves
exactly like switching tabs — the newly focused window fills the screen and the previous one is
parked. Under *split* the focused window and its right neighbour are shown.

‡ The grammar is Fn = navigate, +⇧ = move, +⌃ = resize, +⌥ = monitor, and on the move chord +⌥
means "the whole app". The `ctrl-alt` prefix already holds ⌥, so there the chord would be `⌃⌥⇧W/S`
(move window up/down); bind `move-app-up` / `move-app-down` yourself if you want them. The same
goes for the display chords (`⌃⌥A` is already focus-window-left, and `⌃⌥` + arrows are the row/tab
aliases) and for the tab digits (`⌃⌥1` is workspace 1): bind `focus-screen-left`…,
`move-window-to-screen-left`… and `focus-tab-1`… by name. Digits have no display meaning, which is
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
  `Fn+⌥0` focuses the first. On an empty workspace it does nothing.
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
- Close presses the window's close button; the app stays running (macOS convention). Focus goes to
  the left neighbour, else the right.
- Autorepeat of a bound chord is swallowed, not re-fired: holding `Fn+D` moves once and types
  nothing into the front app.

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

## Conflicts and edge cases

- `Fn+F` is intentionally unbound (Apple full screen). `Fn+F1…F20` are never bindable (media keys /
  `fnKeyMode`).
- Tapping `Fn` **alone** still triggers whatever "Press 🌐 key to" is set to in System Settings
  (emoji picker, dictation…); SpacialShell only matches Fn *held* with another key.
- While a **password field has focus** (Secure Input), macOS stops delivering keystrokes to every
  event tap; hotkeys are deaf until you leave the field. This is by design of macOS.
- Another window manager or hotkey daemon that also consumes these chords (skhd, Hammerspoon,
  BetterTouchTool, Raycast's Fn hotkeys) wins or loses depending on which tap was installed first —
  run one at a time.
- Sleep/lock/re-sign can disable an event tap; SpacialShell re-enables its own on wake and unlock
  and polls its health every second. If hotkeys ever go dead, `killall SpacialShell` and relaunch.

See also: [`docs/config.md`](config.md) (full reference), [`docs/platform-notes.md`](platform-notes.md)
(what is verified on real hardware and what is still pending), and the spec's §6 for the design
rationale.
