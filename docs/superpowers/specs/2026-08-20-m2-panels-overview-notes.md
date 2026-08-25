# M2 panels + overview — implementation notes

Date: 2026-08-20, reconciled 2026-08-25 against the accepted M2 design
(`2026-08-19-m2-shell-ui-design.md`) after that design's Kit/IPC substrate merged to `main`.
These notes describe the first working cut of the design's UI tasks (T15–T21, partially) that
landed on this branch, plus one deliberate extension (the built-in overview). Where the two
documents disagree, the 2026-08-19 design wins; this file records what is actually built.

## What is built, in the design's terms

- **Panels (T16/T17 shape, simplified)**: `PanelWindow` matches the design's panel ruling
  (borderless, non-activating, `.floating`, all-Spaces, never key). One rail + one bar per
  display, owned by `ShellController` in the app target — not yet the separate `SpacialShellUI`
  target; moving them is mechanical once the snapshot feed exists.
- **Rail (T18, partial)**: search glyph → `Launcher` behaviour per the design — opens
  `launcher-url` (Raycast by default), falling back to the built-in overview when the URL has no
  handler; workspace tiles from `Workspace.symbol` with window count, active tile accent-filled;
  the trailing empty tile is `plus` (activating it is creating — invariant 4). `rail-side`
  mirrors the rail. Not yet: hover labels, right-click menus, clock, app menu, category-from-content
  icons.
- **Top bar (T19, partial)**: tabs for the active row in `Fn+A`/`Fn+D` order (floating pinned,
  hidden dimmed, close on the focused tab), five-glyph `LayoutSwitcher` with the design's symbols.
  Not yet: window titles (needs the store's title/appName tables from T8), "+N" badge, hover
  states, `+` tab.
- **Zen**: exactly the design's ruling — `World.zen`, flipped by `.toggleShellUI`, read by the
  reconciler through `ShellInsets(config:hidden:)`, persisted as `PersistedState.zen`
  (`decodeIfPresent ?? false`, version stays 1).
- **Verbs**: distinct base names per the ruling — `focusWorkspaceID(UUID)`,
  `focusWindowRef(WindowRef)`, `closeWindowRef(WindowRef)`, `setWorkspaceLayout(UUID, Layout)` —
  pure in `CommandRunner`, no `CommandError`/`CommandOutcome` yet (T6's error channel is still
  open; these return silent no-ops on unknown targets like the M1 verbs do).
- **State feed (pre-T8 stopgap)**: panels render `ShellUI.state(for:in:)`, a pure Kit derivation
  from `World` (`ShellUI/ShellUIState.swift`). It is deliberately shaped like the design's
  `ShellSnapshot` rows (workspace id/name/symbol/pinned/active/trailing-empty; window
  focused/floating/hidden) so the migration to the real snapshot feed is a source swap, not a
  redesign. App names/icons come from `NSRunningApplication` by pid (`AppMetaCache`), cached.

## The extension: built-in overview (`toggle-overview`, `Fn+Tab`)

The design routes "overview" to Raycast. Alice asked for an overview in the shell as well, so the
branch adds one — Spotlight-shaped `OverviewPanel` (the single key-capable shell window; still
non-activating), a search field over **Windows** (every placed window + ephemeral visitors →
`.focusWindowRef`) and **Applications** (top-level `.app` bundles from the standard dirs →
`NSWorkspace.openApplication`; adoption places the new window). `Esc`/`Fn+Tab`/click-away
dismisses (`resignKey` is a dismissal; a plain dismissal re-sends `.focusWindowRef` on the model's
focused window to hand key focus back, and a selection-caused dismissal skips that restore so it
cannot race). `Enter` opens the first match, windows before apps. `toggle-overview` and
`openSettings` are app-layer surfaces: AppRuntime routes them before the store; `CommandRunner`
treats strays as no-ops.

## Testing

`ShellUITests.swift`: state derivation, the four verbs (cross-screen focus, hidden no-op,
ephemeral focus, invariants after every run), the Zen round trip at the reconciler boundary
(pins both rects), Zen persistence (including M1 state files without the key).
`WorldStoreTests` pins `show-panels = false`: its frame maths predates the panels and what it
tests is inset-agnostic — `ReconcilerTests` owns the insets. The AppKit layer stays untested like
the rest of the drawing-adjacent platform code.

## Still open from the design (unchanged)

Error channel (T6), snapshot feed + title/appName tables (T8) and the panels' migration onto it,
focus glow (T20), menus/rename/clock (T21), drag (T22/T23), `SpacialShellUI` target split (T15),
richer IPC command table. The full-screen/lock `orderOut` behaviour and hover polish from the
design's risk list are also still open.
