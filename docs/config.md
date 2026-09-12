# Config reference

SpacialShell reads `~/.config/spacial-shell/config.toml`. The file is watched for changes and
reloaded live; an invalid config is rejected (the previous one keeps running) and the rejection is
logged. Every key is optional — an empty or missing file gives you `Config()`'s defaults, shown
below.

> **Sandboxed builds read the same path inside the app's container**, i.e.
> `~/Library/Containers/sh.emu.SpacialShell/Data/.config/spacial-shell/config.toml`. See
> [Where the file lives](#where-the-file-lives) — it changes where you hand-edit, and the
> settings window's **Open config.toml…** button is the route you should use rather than typing
> that path.

## Full example

```toml
keybinding-preset = "fn"          # or "ctrl-alt"
gap = 8                           # pt between windows and to the screen edge
default-layout = "maximize"       # maximize | split | column | half | grid
ax-timeout-ms = 1000
refresh-interval-ms = 2000
start-at-login = false
panel-width = 48
panel-height = 34
rail-side = "left"                # or "right"
tab-sizing = "fit"                # or "equal"
highlight-ms = 600
launcher-url = "raycast://"
show-panels = true

[[workspace]]                     # pinned, named workspaces seeded on every screen
name = "Code"                     # (material-shell "categories")
symbol = "terminal"               # SF Symbol name
layout = "half"

[[ephemeral]]
bundle-id = "com.apple.systempreferences"

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
| `gap` | number (pt) | `8` | Space left between tiled windows and between a window and the screen edge, in every layout. |
| `default-layout` | layout name | `"maximize"` | The layout a newly created workspace starts with (see below for the five names). |
| `ax-timeout-ms` | integer | `1000` | Per-app Accessibility messaging timeout (`AXUIElementSetMessagingTimeout`). A slow or hung app can only delay operations on itself by this long, never other apps. **Needs a relaunch**: it is read when the backend is built. |
| `refresh-interval-ms` | integer | `2000` | Interval for the periodic backstop reconcile — the safety net that catches window changes AX notifications missed. **Needs a relaunch**: it is read when the backend is built. |
| `start-at-login` | boolean | `false` | **Parsed but not implemented in M1** — the key is accepted and validated, and nothing acts on it. Registering a login item needs a real app bundle to point at, so it arrives with the notarized bundle in M4. |
| `panel-width` | number (pt) | `48` | Width of the workspace rail. Windows are inset by this on the rail side. |
| `panel-height` | number (pt) | `34` | Height of the top bar. Windows are inset by this from the top. |
| `tab-sizing` | `"fit"` \| `"equal"` | `"fit"` | How the tab bar spends its width. `fit`: each tab is as wide as its content and they pack left, so a single tab sits at the left edge. `equal`: every tab takes 1/n of the bar and centres its content. |
| `rail-side` | `"left"` \| `"right"` | `"left"` | Which screen edge the rail sits on. An unknown value rejects the whole config (the previous one keeps running). |
| `highlight-ms` | integer | `600` | Duration of the focus-highlight flash, in milliseconds. `0` skips the animation. **Parsed but not yet wired** — the focus glow lands with M3b (T20); until then the key is accepted and nothing reads it (same for `highlight-color`). |
| `app-categories` | table of bundle-id → category | `{}` | Overrides the rail's category label per app. Values: `web`, `coding`, `terminal`, `communication`, `media`, `design`, `productivity`, `utilities`. See below — this exists because macOS cannot answer the question. |
| `keybinding-overrides` | table of command \u2192 chord | `{}` | Rebinds a command, *replacing* its default chord. This is what the settings window writes. Distinct from `keybindings` below, which is chord \u2192 command and only ever *adds* a chord \u2014 useful in a hand-edited file, useless for rebinding, since the old chord keeps working. |
| `launcher-url` | string | `"raycast://"` | URL opened by the rail search glyph. If nothing handles it, the built-in overview opens instead. |
| `show-panels` | boolean | `true` | When `false`, panels are not drawn and windows are not inset for them. |

Layout names: `maximize` (one window fills the screen), `split` (focused window + one neighbour,
two columns), `column` (all windows as equal columns), `half` (one window fills the left half, the
rest stack in the right half), `grid` (a roughly-square grid, row-major, last row widened to fill).

## `[[workspace]]` — pinned workspace seeds

Each `[[workspace]]` table seeds one **pinned, named** workspace on every screen at launch — the
material-shell "category" concept (e.g. a permanent "Code" or "Web" row). Pinned workspaces never
get reaped for being empty, unlike ordinary auto-created ones (spec §4.2 invariant 4); that's what
makes a named category usable before window-to-workspace persistence exists (that's M3).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | *(required)* | Display name — "Workspace N" if you don't seed one. |
| `symbol` | string | `"square.grid.2x2"` | SF Symbol name, for the M2 shell UI. |
| `layout` | layout name | `"maximize"` | This workspace's starting layout, independent of `default-layout`. |

Windows themselves are **not** persisted or re-associated with pinned workspaces in M1 (`CGWindowID`
doesn't survive an app restart, and the matching algorithm is M3 work) — only the empty, named,
pinned workspace shell is restored from `state.json` on launch.

## `[[ephemeral]]`, `[[float]]`, `[[ignore]]` — app rules

Each entry matches windows by bundle id and, optionally, a regex against the window title:

| Key | Type | Meaning |
|---|---|---|
| `bundle-id` | string, required | Exact match against the owning app's bundle identifier. |
| `title-regex` | string, optional | If present, the window title must also match this regex (`NSString.range(of:options:.regularExpression)`). Omit it to match every window of that app. |

Config rules always win over SpacialShell's own heuristic window classifier (spec §7.3 rule 0),
checked in this order: `ephemeral`, then `float`, then `ignore`.

- **`ephemeral`** — Veshell's "visitor" windows: they belong to no workspace, are centred on the
  focused screen when they appear, are never parked, and `Fn+A`/`Fn+D` skip over them entirely.
  **Default** (used whenever `[[ephemeral]]` is absent from your config entirely):
  `com.apple.systempreferences`, `com.apple.calculator`. Note this is a full **replacement**, not
  a merge — if you add your own `[[ephemeral]]` entries, System Settings and Calculator stop being
  ephemeral unless you list them yourself.
- **`float`** — windows that belong to a workspace and are shown/parked with it, but are excluded
  from tiling and keep their own frame (also toggleable per-window at runtime with `Fn+G`). No
  default entries.
- **`ignore`** — windows SpacialShell never touches at all: no placement, no parking, no tiling.
  No default entries.

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
| `cycle-layout` | Cycle the active workspace's layout: maximize → split → column → half → grid → maximize |
| `toggle-shell-ui` | Zen mode: hide/show the shell panels; their edges go back to the layout while hidden |
| `toggle-overview` | Open/close the overview/launcher (search over open windows and installed apps) |
| `open-settings` | Open `~/.config/spacial-shell/config.toml` in its default editor (created empty — all defaults — if missing) |
| `focus-screen-prev` | Focus the previous screen |
| `focus-screen-next` | Focus the next screen |
| `move-window-to-screen-prev` | Move the focused window to the previous screen and follow it |
| `move-window-to-screen-next` | Move the focused window to the next screen and follow it |
| `toggle-float` | Float a tiled window at its current frame, or re-tile a floating one |
| `focus-workspace-1` … `focus-workspace-10` | Jump directly to workspace 1…10 on the focused screen (`focus-workspace-10` is bound to the `0` key by default) |

### Key names

Generated from `KeyCodes.byName` (macOS `kVK_ANSI_*` virtual key codes, US layout positions):

`a`, `s`, `d`, `f`, `h`, `g`, `z`, `x`, `c`, `v`, `b`, `q`, `w`, `e`, `r`, `y`, `t`, `1`, `2`, `3`,
`4`, `6`, `5`, `equal` (`=`), `9`, `7`, `minus` (`-`), `8`, `0`, `rightSquareBracket` (`]`), `o`,
`u`, `leftSquareBracket` (`[`), `i`, `p`, `enter`, `l`, `j`, `quote` (`'`), `k`, `semicolon` (`;`),
`backslash` (`\`), `comma` (`,`), `slash` (`/`), `n`, `m`, `period` (`.`), `tab`, `space`,
`backtick` (`` ` ``), `backspace`, `esc`, `left`, `right`, `down`, `up`.

Note `Fn+arrows` are not usable no matter how you spell them: the HID layer remaps them to
Home/End/Page Up/Page Down before the hotkey tap ever sees a `left`/`right`/`up`/`down` keycode —
see `docs/platform-notes.md` check #2. The arrow keys only work meaningfully under the `ctrl-alt`
(or another non-`fn`) modifier combination, which is why they ship pre-bound to `⌃⌥` in both
presets rather than left for you to configure.

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
workspace shells (name, symbol, layout, id) per screen, written debounced on every model change.
It is machine-owned — not meant for hand editing — and is not covered by this reference.


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
