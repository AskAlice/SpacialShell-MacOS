# SpacialShell

**material-shell's spatial desktop, on the Mac.** A tiling window manager where every window has
one address, you move by direction, and the shell remembers where you put things.

![The shell at a glance: rail, tab bar and tiled windows](media/live-overview.webp)

*Live capture: the rail on the left, the tab bar on top, tiled windows below. `Fn+Space` cycles
layouts, `Fn+A`/`Fn+D` move along the row, `Fn+W`/`Fn+S` move between rows.*

[Install](#get-started){ .md-button .md-button--primary }
[Keybindings](keybindings.md){ .md-button }
[Config reference](config.md){ .md-button }

---

## Why space works

Your brain is already a very good window manager, if you give it a *place* to work with. Two
everyday mental mechanisms do the heavy lifting:

- **Spatial memory**: remembering where things are in a space you know. You don't search your
  kitchen for the mugs; your hand goes to the cupboard.
- **Mental mapping**: holding a picture of that space in your head and planning a route through it.

A pile of overlapping windows gives neither anything to hold on to. A stable grid gives both
everything they need. So SpacialShell:

1. **Lays your apps out in two dimensions**, grouped by use case, category or project: browsers on
   one row, editor and terminal on the next, Spotify and VLC below.
2. **Remembers that layout on the fly.** No config to write; you build the arrangement by using it,
   and it survives a reboot.
3. **Moves by direction**, like a game world: up, down, left, right. No hunting through lists.
4. **Shows the whole map at a glance**, so the mouse is as good a way around as the keyboard.

Finding a window stops being a search and becomes *wayfinding*.

## Built for macOS, not Linux

[material-shell](https://github.com/material-shell/material-shell) extended GNOME Shell, and its
successor [Veshell](https://github.com/free-explorers/veshell) is its own Wayland environment. Both
*own the compositor*. On a Mac nobody does, and that shapes everything here:

- **The Accessibility API instead of a compositor.** Windows are moved and sized through the same
  public AX interface screen readers use. It asks for Accessibility and nothing more.
- **Screenshot-proxy animations.** macOS has no hooks for animating another app's window, so a
  switch captures the windows, slides the *pictures*, and moves the real windows once at the end.
- **Living beside Spaces, fullscreen and the menu bar**, rather than replacing them. A fullscreen
  window keeps its tab, and an app can't pull you out of a fullscreen Space by grabbing focus.
- **No private APIs, SIP stays on.** No scripting addition to reinstall after every macOS update.
- **Notarised, outside the App Store**, because the App Store sandbox forbids the Accessibility
  control a tiler needs.

## The spatial model

- A **workspace is a row**; an app window is a **cell** in it. New windows go to the end of the
  row, new workspaces below.
- **Up/down** changes workspace, **left/right** changes window. The screen is a viewport onto a
  larger grid that stays sorted.
- **One address:** every managed window lives in exactly one workspace on exactly one display.
- **Down always leads somewhere:** every display's stack ends in one empty workspace.
- **Per-display rails:** every display has its own stack, and a whole workspace can move between
  displays (`Fn+⌥⇧+arrows`).
- **Categories are identity:** the rail shows what each row *is* (web, terminal, coding, media)
  instead of asking you to name it.

![Workspaces as rows, windows as cells](media/spatialisation.webp)

*Live capture.*

## Placement memory

- **Windows go back to their workspace and display** across restarts; displays are matched by
  UUID, not arrangement order.
- **Category routing:** with `category-order`, each category gets its own row at the top of every
  display, so a new browser window lands with the other browsers.
- **The launch-crowd rule:** an app that restores a pile of windows at login gets its own row
  instead of flooding yours.
- **No invisible windows:** every window the shell lists can be reached with one click or
  command, and parked windows are recovered after a crash.

![The rail with real apps, each in the row its category sends it to](media/live-rail-apps.webp)

*Live capture.*

## The tiling engine

Windows are always tiled and never overlap. `Fn+Space` cycles **maximize**, **split** (an
N-column sliding view, N per workspace), **column**, **half** and **grid**.

![Cycling the layouts](media/tiling-showcase.webp)

*Live capture.*

- **Layouts are data:** draw your own in the layout editor, or write `[[layout]]` blocks in
  `config.toml`.
- **Resize, one model for every layout:** drag a border, or `Fn+⌃A/D/W/S` in 5% steps that stop on
  25/50/75%; `Fn+⌃=` balances. Sizes are kept per workspace and per layout.
- **A minimum-size floor with paging:** no window gets less than 120 × 80 pt; overflow pages, and
  the parked windows keep their tabs.
- **The reconciler owns geometry:** one pure function decides where every window goes, and every
  click re-enters the same command pipeline as a hotkey.

## Design

No colour palette of its own: native vibrancy materials, your system accent colour, light and dark
from System Settings. Two panels, one job — showing you *where you are*:

- **The rail** (left): one row per workspace with its apps and category, hover previews, a tray for
  hidden and minimized windows, right-click menus, scroll to switch, and Dock-style auto-hide.
- **The tab bar** (top): one tab per window, drag to reorder or onto a rail row to move it,
  right-click for Close / Float / Move to workspace, middle-click to close.

![A tab dragged along the bar, then onto a workspace in the rail](media/live-tab-drag.webp)

*Live capture.*

Hold `Fn` for a cheat sheet of *your* bindings, `Fn+Tab` for the overview, `Fn+Esc` for Zen mode.
Reduce Motion is respected.

## A keyboard grammar

The **Fn / Globe** key takes the place of Super; a `⌃⌥` preset covers keyboards that never send Fn.

| Modifier | Meaning | Examples |
|---|---|---|
| **Fn** | navigate | `Fn+W/S` rows, `Fn+A/D` windows, `Fn+1…0` workspace N |
| **+ ⇧** | move the window | `Fn+⇧A/D` along the row, `Fn+⇧W/S` between rows, `Fn+⇧+arrows` to a display |
| **+ ⌃** | resize | `Fn+⌃A/D` narrower/wider, `Fn+⌃W/S` shorter/taller, `Fn+⌃=` balance |
| **+ ⌥** | display / whole app | `Fn+⌥W/A/S/D` focus a display, `Fn+⌥1…9` tab N, `Fn+⌥⇧+arrows` move the workspace |

Every chord can be rebound — see [Keybindings](keybindings.md). Scripts drive the shell through
`spacialctl` ([control socket](ipc.md)).

## Get started

```sh
brew install --cask askalice/tools/spacialshell
```

Or download the notarised DMG from
[Releases](https://github.com/AskAlice/SpacialShell-MacOS/releases), move it to `/Applications`,
launch it and grant **Accessibility**. Grant **Screen Recording** too for hover previews and
sliding switches; without it switches are instant and everything else works.

Then press `Fn+S`.

## Credits

SpacialShell exists because of [material-shell](https://github.com/material-shell/material-shell)
([material-shell.com](https://material-shell.com)) and
[Veshell](https://github.com/free-explorers/veshell), by PapyElGringo and the
[Free Explorers](https://free-explorers.com) collective. It borrows their *design* — the model, the
vocabulary, the "not-desktop" — and no code; like both, SpacialShell is GPL-3.0. The macOS
platform layer adapts MIT-licensed code from [AeroSpace](https://github.com/nikitabobko/AeroSpace).
