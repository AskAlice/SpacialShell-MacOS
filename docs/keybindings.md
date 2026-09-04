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
Shift moves the window instead of the focus.** Arrow keys are aliases and are always on `⌃⌥`,
in both presets — `Fn+arrows` are Home/End/PgUp/PgDn at the keyboard-driver level and can never be
bound.

| Command | `fn` preset | `ctrl-alt` preset | material-shell |
|---|---|---|---|
| Focus workspace up / down | `Fn+W` / `Fn+S` | `⌃⌥W` / `⌃⌥S` | Super+W / S |
| Focus window left / right † | `Fn+A` / `Fn+D` | `⌃⌥A` / `⌃⌥D` | Super+A / D |
| Focus workspace 1…10 | `Fn+1` … `Fn+9`, `Fn+0` | `⌃⌥1` … `⌃⌥0` | Super+1 … 0 |
| Close focused window (app keeps running) | `Fn+Q` | `⌃⌥Q` | Super+Q |
| Move window left / right | `Fn+⇧A` / `Fn+⇧D` | `⌃⌥⇧A` / `⌃⌥⇧D` | Super+Shift+A / D |
| Move window to workspace above / below | `Fn+⇧W` / `Fn+⇧S` | `⌃⌥⇧W` / `⌃⌥⇧S` | Super+Shift+W / S |
| Cycle layout (maximize → split → column → half → grid) | `Fn+Space` | `⌃⌥Space` | Super+Space |
| Toggle shell panels (Zen mode) | `Fn+Esc` | `⌃⌥Esc` | Super+Esc |
| Open overview / launcher | `Fn+Tab` | `⌃⌥Tab` | Super (overview) |
| Open the config file | `Fn+,` | `⌃⌥,` | — |
| Focus previous / next screen | `Fn+[` / `Fn+]` | `⌃⌥[` / `⌃⌥]` | — |
| Move window to previous / next screen | `Fn+⇧[` / `Fn+⇧]` | `⌃⌥⇧[` / `⌃⌥⇧]` | — |
| Toggle float on the focused window | `Fn+G` | `⌃⌥G` | — |
| Arrow aliases: focus / move | `⌃⌥←→↑↓` / `⌃⌥⇧←→↑↓` | same | — |

† "Left/right" walks every *visible* window of the active workspace, floating ones included, and
wraps at the ends; minimized / hidden windows are skipped and ephemeral "visitor" windows (System
Settings, Calculator by default) are in no row at all. Under the *maximize* layout this behaves
exactly like switching tabs — the newly focused window fills the screen and the previous one is
parked. Under *split* the focused window and its right neighbour are shown.

Semantics worth knowing:

- Focus workspace **down** from the last (empty) workspace does nothing; move window **down**
  from it creates a new workspace below (there is always one empty, unpinned workspace at the
  bottom of every screen — that is where new things go).
- Move window left/right at the end of the row is a no-op (no wrap for moves).
- Move to another screen appends the window to that screen's active workspace and focus follows.
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
`backslash`, `backtick`, `left`, `right`, `up`, `down`. The full generated list and every command
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
  and polls its health every 5 s. If hotkeys ever go dead, `killall SpacialShell` and relaunch.

See also: [`docs/config.md`](config.md) (full reference), [`docs/platform-notes.md`](platform-notes.md)
(what is verified on real hardware and what is still pending), and the spec's §6 for the design
rationale.
