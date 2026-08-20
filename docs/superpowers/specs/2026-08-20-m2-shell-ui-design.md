# M2 — Shell UI: design

Date: 2026-08-20. Builds on the M1 spatial core (`2026-08-18-m1-spatial-core-design.md`); the
lineage map there (§1.1) names the two panels this milestone starts delivering. Reference
material: material-shell's interface showcase — left system panel with the workspace list, top
workspace panel with app tabs and the layout switcher, launcher overview in the middle.

## 1. Scope

**In this slice**: `ScreenPanel` (workspace rail), `WorkspacePanel` (window tab bar + layout
switcher), Zen mode on `toggle-shell-ui`, panel insets in the layout, `[ui]` config.

**Deferred within M2**: the ephemeral-window overview/launcher, `Fn+Drag` reordering, window
titles in tabs (needs an AX title feed through the store; tabs show app name + icon until then),
workspace renaming from the rail.

## 2. Shape

The panels follow M1's layering exactly — every piece that can be pure is pure and lives in Kit:

```
Kit    ShellUI.state(for:in:)  World → ScreenShellState   (rail items, tab items, layout)
Kit    Command                 four new UI verbs; CommandRunner stays (World, Command) → (World, [Effect])
Kit    PanelInsets             LayoutConfig grows insets; Reconciler subtracts them from the screen rect
App    ShellController         one rail + one bar per display; renders ScreenShellState, forwards clicks
App    PanelWindow             borderless non-activating NSPanel, .floating, all-Spaces, never key
App    ScreenPanelView /       SwiftUI, Apple-native materials; resolves app name + icon by pid
       WorkspacePanelView      (NSRunningApplication), cached
```

Data flows one way and commands flow the other, both through existing doors: the store's
`onChange` already publishes every world change (the panels are just a second listener next to
state save), and a panel click calls `store.run(command)` exactly as the hotkey tap does. The
panels never mutate the model and hold no state of their own beyond the last world rendered.

## 3. The panels

**ScreenPanel** (left edge, `rail-width` pt, full height): one button per workspace, top→bottom in
stack order — symbol (the workspace's SF Symbol, seeded from config) over the window count. The
active workspace is filled with the accent color. The trailing empty workspace renders as `+`:
activating it *is* creating a workspace, which is invariant 4 (there's always a way down) doing
the work — there is deliberately no separate "add" button. A pinned empty workspace keeps its own
symbol; it is a named category, not the way down. Clicking a rail item on an unfocused screen
moves focus to that screen first, like the keyboard path.

**WorkspacePanel** (top edge, right of the rail, `bar-height` pt): one tab per window in the
active workspace's row, left→right in row order — the same order `Fn+A`/`Fn+D` walk, floating
windows included at their index (they show a pin), minimized/hidden ones dimmed (a click on them
is a no-op: raising would not deminiaturize, and focus must stay somewhere real). The focused tab
carries the close button. On the right, five buttons — one per layout, current one highlighted;
a click sets that layout outright (the keyboard's `cycle-layout` is unchanged).

**Zen mode** (`toggle-shell-ui`, `Fn+Esc`): a `shellUIVisible` flag on `World`, flipped by
`CommandRunner`. It lives in the model because the layout rect depends on it — the reconciler
reads it to pick the insets, so the toggle is an ordinary command → relayout round trip and the
panels hide/show in the same `onChange` that re-tiles the windows. Not persisted meaningfully:
a fresh world starts visible.

## 4. Insets

Spec §5 reserved this: the Layout layer takes insets as data and does not know what draws them.
`LayoutConfig` gains `PanelInsets { top, leading }` (top-left y-down, like everything in that
layer). `Reconciler.desired` subtracts them from the screen rect before the gap inset and the 1 pt
height guard. The store computes them: `[ui] enabled && world.shellUIVisible` → config values,
otherwise `.zero`. Parking corners still use the raw `visibleFrame` — a parked sliver under the
rail is fine, the rail floats above it.

## 5. New commands

Keyboard verbs are relative to the focused screen; a panel click names its target outright — the
rail on a second screen must work without moving focus there first.

| Command | From | Does |
|---|---|---|
| `activateWorkspace(DisplayID, Int)` | rail click | focus that screen, activate that index (0-based), focus falls to the workspace's anchor |
| `selectWindow(WindowRef)` | tab click | focus that window wherever it is (activates its workspace and screen); no-op on hidden windows; plain focus for ephemeral ones |
| `setLayout(DisplayID, Layout)` | layout switcher | set that screen's active workspace's layout; does not move focus |
| `closeWindow(WindowRef)` | tab close | emit `.close` — the app closes it, the vanish comes back through the snapshot path like any other close |

## 6. Windows, materials, focus

Panels are `NSPanel`s: borderless, `.nonactivatingPanel`, `.floating` level, join all Spaces,
`canBecomeKey == false`. A click must change focus through the model, never through AppKit — the
panel taking key status would *unfocus* the window the user is working in, which is the one thing
the shell must never do. Content is SwiftUI (`NSHostingView`) on `.thinMaterial`; the OS owns
appearance, per the M1 spec's theming row. Frames are set in `NSScreen` coordinates directly
(bottom-left y-up — no flip, the panels never touch AX geometry); `NSScreen` is matched to the
world's `DisplayID` by `DisplayTopology.uuid(for:)`, now public. Hot-plugs re-anchor on
`didChangeScreenParameters` immediately and reconcile fully when the backend's snapshot lands.

## 7. Testing

Pure parts under `SpacialShellKitTests` (`ShellUITests.swift`): state derivation (rail order,
active/pinned/trailing flags, tab flags, focus), the four commands (cross-screen focus moves,
hidden no-op, ephemeral focus, invariants after every run), insets arithmetic against M1's rect,
`[ui]` config parsing and defaults. `WorldStoreTests` pins `ui.enabled = false` — its frame maths
predates the panels and what it tests is inset-agnostic. The AppKit layer stays untested like the
rest of the platform layer's drawing-adjacent code; the TextEdit integration test's containment
checks hold under insets.
