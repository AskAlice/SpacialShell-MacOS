# DE gap analysis — what a functional, intuitive shell still needs

Date: 2026-08-25. Scope: window manager + shell (macOS owns the rest). Method: full read of the
specs/plans/research inventory plus a code sweep for unwired paths, dead keys, and ignored window
states. Every finding carries a file reference; findings already on the roadmap cite their task
(T-numbers from `2026-08-19-m2-shell-ui-design.md`) or milestone and are not re-litigated here.

Severity order: **A** breaks trust in the core promise ("there is never any doubt where a window
went"), **B** makes daily use frustrating, **C** is dishonest surface (things that parse or render
but do nothing), **D** is polish.

## A. Broken at head (fixed on this branch, kept for the record)

- **IPC socket dead** — `IPCServer.acceptOne()` lost its `readers[fd]` registration to an
  automated fix (`4ff82ae`); every `spacialctl` call and all Raycast commands hung forever.
  Fixed; `IPCServerTests.roundTrip` now fails loudly (5 s recv timeout) instead of hanging.
- **Launcher fallback dead** — the rail search glyph's `.toggleOverview` went to the store (a
  deliberate no-op) instead of the overview controller. Fixed by the shared `route()` dispatcher
  in `AppRuntime`; `open-settings` (`Fn+,`) got its first real behaviour at the same time.

## A. The "no invisible windows" family (violations of the promise; → M3a)

The paradigm's core claim is that a window is never ambiguous. Parking-as-hiding makes several
paths where a window is effectively *gone* — off-screen as a 1 pt sliver, or unmanaged — with no
route back. Alice's stated invariant: **a window is never moved off screen unless it is minimized
or on a different workspace; switching to an app must always show a window.**

1. **Stranded retirees.** Three failed AX writes retire a window to `ignored` permanently
   (`WorldStore.note(_:for:)`, `Store/WorldStore.swift:222-235`) — if it was parked at the time it
   stays a corner sliver for the whole session; only the termination restore ever rescues it. No
   retry, no notification. (M1 spec §13.3 already floats a "rescue" command — never built.)
2. **Fullscreen erases windows.** Native fullscreen ⇒ `world.ignored`
   (`Store/WorldStore.swift:118-120`): the window leaves the rail count, the tab bar, and
   `Fn+A`/`Fn+D`. The shell has no way back to it; the model forgets it exists.
3. **Minimized windows are one-way.** They keep a (dimmed) tab, but clicking it is a silent no-op
   (`CommandRunner` refuses hidden refs) and the backend has no deminiaturize verb at all
   (`Backend/WindowBackend.swift:59-66`) — recovery is Dock-only, outside the shell.
4. **Zero/negative frames.** `LayoutEngine.columns/rows` (`Layout/LayoutEngine.swift:32-38`) do no
   minimum-size clamping; `.column` with ~10 windows or a large `gap` writes degenerate frames
   straight to AX.
5. **Other-Space phantoms.** Nothing models "on another native Space"
   (`AX/AXApp.swift:341-343`); a window the user drags to another Space keeps its tab and slot,
   and the reconciler keeps writing frames at it forever.
6. **Activation latency.** ⌘Tab/Dock activation reaches the model via a debounced full refresh,
   not a direct focus event (`Backend/AXWindowBackend.swift:94,115`); refreshes are also
   suppressed while the mouse button is down (`:221`) and can lag up to `refresh-interval-ms`.
   Between activation and refresh the activated window may sit in its corner sliver.

## B. Daily-use friction (unacknowledged unless noted)

- **Auto-created workspaces are anonymous and mortal.** Every auto row is named "Workspace" with
  the default symbol (`Model/World+Mutations.swift:29`), there is no rename anywhere (T21), and
  `PersistedState.restore` keeps only pinned shells — **user-created workspaces, their layouts and
  order are discarded on every relaunch** (`State/PersistedState.swift`, `.filter(\.pinned)`).
- **Display replug loses arrangement.** Unplug merges into main (I-documented), but replug
  restores nothing (`Model/World+Mutations.swift:100-117` + pinned-only persistence).
- **No quit affordance.** Accessory app, no Dock icon, no menu item, no `quit` IPC verb, no ⌘Q —
  `kill` only (README documents it; nothing in-app discovers it). T21's app menu is the fix.
- **Onboarding can hang invisibly.** Deny the Accessibility grant and boot waits forever with no
  UI (`AX/Permissions.swift:30-36`); worse, 20 s after first launch the app silently runs
  `tccutil reset Accessibility` (`:31-34`), which can revoke a grant the user just gave.
- **Tab ergonomics.** Close renders only on the focused tab (`Shell/WorkspacePanelView.swift`);
  a background window takes two clicks to close; dimmed tabs are tappable dead clicks (see A.3).
- **Sheets are peers.** A save sheet classifies `.dialog → float` and takes a row slot + tab next
  to its owner (`AX/WindowClassifier.swift:10-14`).
- **Keyboard-opened windows tile late.** No `windowCreated` event; adoption rides mouse-up
  snapshots and the 2 s poll (`Backend/AXWindowBackend.swift:161-166,221`).
- **Tap failure is silent.** If the event tap can't install, the app logs and keeps running as a
  window manager with no hotkeys and no visible error (`AppRuntime.swift`). Similarly, a failed
  `ipc.start()` silently kills the whole control surface.
- **Accessory-app windows are never adopted** (`Backend/RefreshSession.swift:21-25` walks
  `.regular` apps only).

## C. Dishonest surface (parses/renders but does nothing)

- `theme`, `font`, `icon-set` config keys: decoded, rendered back by `Config.render()`, read by
  nothing — and a typo in one **rejects the entire config**, disarming live reload
  (`Config/Config.swift`). They also contradict the design's own theming ruling ("the OS material
  is the palette"). → remove (this branch, step 5d).
- `highlight-ms` / `highlight-color`: fully parsed (incl. `HighlightColor.rgba`), documented as
  the focus-flash duration — there is no focus highlight in the source (T20 builds it). → honest
  "not yet wired" doc markers until T20.
- `open-settings` (`Fn+,`): was bound and routed nowhere — now opens the config file (fixed
  above); still needs its docs row.
- `CheatSheet.rows(for:)` + `Hint.after(...)` (`Config/CheatSheet.swift`): complete, display-ready,
  wired to nothing; the `HotkeyTap.onFlags` hook meant to trigger the Fn-hold sheet is never
  passed (`Hotkeys/HotkeyTap.swift:58`, `AppRuntime.swift`). The one discoverability feature the
  code contains is invisible.
- `ShellSnapshot` + `IPCEvent` (Protocol target): codec-tested wire contract that nothing emits
  (T8/T12) — needs "not yet emitted" markers so it doesn't read as shipped.
- `WireState.capabilities = ["run"]` under-advertises the daemon's real surface
  (`Store/WireState.swift:19`).
- `Reconciler.desired(suspended:)` is a live parameter the store never passes (T23's hook).
- `start-at-login`: parsed, honestly documented as inert (M4).

## C. Contract gaps between the daemon and its clients

- Raycast `switch` sends `focus-workspace-${i+1}` — no such name past 10, so workspaces 11+ are
  unreachable (`raycast/src/switch.tsx:33` vs `Config/KeyBindings.swift`); it also lists only the
  focused screen (`:11,15`). The shell verbs (`focusWorkspaceID` …) have no wire names at all, so
  IPC/Raycast cannot address anything by id. `spacialctl run toggle-overview` is accepted and
  silently does nothing (routes to the store, not the app layer).
- The IPC table is `version`/`run`/`state` only; no `toggle-zen`, no `quit`, no by-id verbs, no
  `subscribe` (T9–T12). A second instance silently steals the socket
  (`IPC/IPCServer.swift:28`, unconditional unlink).

## D. Known and tracked (referenced, not re-analyzed)

Fn-vs-macOS hotkey pre-emption and the seven other `pending grant` empirical checks
(`docs/platform-notes.md`); Mission Control/⌘Tab seeing parked slivers; one native Space per
display; Secure Input deafness; drag of tiled windows snapping back (drag semantics are T22/T23);
hover labels, clock, focus glow, menus (T18–T21); window titles (T8); Raycast tasks T29–T34;
manual-only integration checklist (`docs/testing.md` §4, T24 additions pending).

## Verdict

The spatial core is solid and honestly documented; the intuition gaps cluster in three places:
**(1)** the paradigm's own promise is violated at the edges (§A family — highest priority, now
invariant I6 in the M3 roadmap), **(2)** identity and persistence of what the user builds
(workspace names, layouts, arrangements) evaporate across relaunches and replugs, and **(3)** the
project carries more dead surface than a young shell can afford — every dead key or unwired
feature costs trust twice, once when discovered and once when it breaks config reload. The M3
roadmap (`2026-08-25-m3-roadmap.md`) sequences the fixes.
