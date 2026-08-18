# SpacialShell for macOS — M1 Spatial Core

Design spec, milestone 1 of 4. Status: approved in design review 2026-08-18. Platform facts verified against AeroSpace source (commit `c548c7f`, 2026-08-10); Veshell's planned specifications (`docs/specifications/**`, commit `7c28384`) used for vocabulary and forward-compatibility; open items in §13.

## 1. Purpose

Reimplement the GNOME material-shell spatial paradigm on macOS as a shippable open-source project. material-shell itself is discontinued; its authors moved on to **Veshell**, a Wayland compositor whose specifications carry the same thesis further. This project is the continuation of that lineage on macOS, not a port of a living project.

The paradigm, from material-shell.com: *"every workspace can be visualized as a row with several apps. When you open a new app, it is automatically placed at the end of the current workspace. When you add a new workspace, it is automatically added underneath. There's never any doubt as to where it has gone."* Up/down moves between workspaces, left/right between windows. Windows are tiled and never overlap. Layout and organization persist.

Veshell's framing sharpens the intent: a **"not-desktop"** — a place you inhabit rather than a desktop you tidy. Applications are either *furniture* (persistent tileables that keep their slot even when closed) or *visitors* (ephemeral windows that appear over the current workspace and never earn a slot). Navigation is game-like directional movement. The environment remembers itself without being asked. Panels exist to give an at-a-glance map of the place.

### 1.1 Lineage map

| material-shell.com (#interface) | Veshell spec | SpacialShell |
|---|---|---|
| Workspace (row of apps) | `Workspace` with `Layout` + `tileableList` | `Workspace` |
| — (per-monitor implied) | `Screen` — a portion of a `Monitor` owning a workspace stack; ultrawides may hold several | `Screen` (M1: one per display) |
| System panel, left: workspace list/switcher + system tray | `ScreenPanel` | M2 — workspace rail (tray omitted: macOS has a menu bar) |
| Workspace panel, top: app switcher tabs + layout switcher | `WorkspacePanel` | M2 — window tab bar + layout switcher |
| Persistence: placeholder to reopen an app in place | `PersistentWindow` (`placeholder \| opened`), `PersistentApplicationLauncher`, matching algorithm | M3 |
| — | `Overview` with `EphemeralApplicationLauncher` / `EphemeralWindow` | M1: `ephemeral` classification hook; M2: overview |
| `Super+Esc` Zen mode | — | `Fn+Esc` (reserved in M1) |
| Themes dark/light/primary, optional blur | Material Design | Apple-native materials; OS owns appearance |

### 1.2 Milestones

| Milestone | Contents | Spec |
|---|---|---|
| **M1 — spatial core** | Window engine, screen/workspace model, tiling engine, hotkeys, minimal state persistence. Headless: no visible UI. Keyboard-drivable daily. | this document |
| M2 — shell UI | `ScreenPanel` (left rail), `WorkspacePanel` (top tabs + layout switcher), overview/ephemeral launcher, `Fn+Drag` reordering, Zen toggle. Apple-native materials. | later |
| M3 — persistence | Persistent tileables: window ↔ placeholder matching across restart (Veshell `matching_algorithm.md` is the reference), persistent launchers. | later |
| M4 — packaging | Notarized bundle, login item, docs, release pipeline. | later |

Each milestone gets its own spec → plan → build cycle. M1 exists because all technical risk lives in it: if the Accessibility layer cannot park and restore windows reliably across multiple displays, nothing above it matters.

### 1.3 M1 scope

In: everything in §3–§12. Out: any drawn UI, `Fn+Drag`, window re-association after restart, ephemeral launcher/overview UI, notarization, App Store, config GUI. `Fn+Esc` is reserved and is a no-op in M1.

## 2. Product decisions (settled)

| Decision | Choice | Why |
|---|---|---|
| Workspaces | **Emulated**, not macOS Spaces. Inactive windows are parked in a screen corner. | Public API only; SIP stays on; no scripting addition to reinstall on every OS update. Proven by AeroSpace. |
| Displays | **Per-screen workspace stacks.** Up/down cycles the focused screen only. M1: one `Screen` per display. | Lets a second monitor hold reference material while context switches on the first. Veshell's `Screen` lets an ultrawide split later without a remodel. |
| Visual language | **Apple-native**, not Material Design. | Vibrancy, light/dark, accent colour and SF Symbols come from the OS. material-shell's three-theme system drops out of scope entirely. (Only consequence for M1: no theming in config.) |
| Modifier | **Fn/Globe** as Super. `⌃⌥` preset for keyboards without a Globe key. | Globe is macOS's system-shortcut modifier and sits where Super sits. `⌘` is not available (⌘W/⌘S/⌘A/⌘D/⌘Q are load-bearing in every app). |
| Build strategy | **Harvest AeroSpace's MIT platform layer; build the model fresh.** | The macOS quirk landscape (AX threading, parking, frame-write order, window classification, lock screen) is solved there and paradigm-neutral. The i3 tree model is not our model and is not lifted. |
| Language / tooling | Swift 6, SwiftPM package + thin Xcode app wrapper. Minimum deployment macOS 14. | Matches the harvested code (Swift tools 6.2, strict concurrency). |
| Config | TOML at `~/.config/spacial-shell/config.toml`. State JSON at `~/Library/Application Support/SpacialShell/`. | Dotfiles-friendly, which the tiling-WM audience expects; state is machine-owned. |
| Name | **SpacialShell**; repo `macos-spacial-shell`; bundle id `me.askalice.SpacialShell` (changeable before M4). | Chosen by the author. "Material" no longer describes the design system. |
| Licence | MIT. | Matches the harvested code; maximally permissive for an open-source WM. Paradigm lineage (GPL-3 material-shell / Veshell) is design inspiration only — no code from either. |

## 3. Architecture

Six layers. Dependencies point strictly downward. Nothing above the `WindowBackend` seam imports Accessibility, AppKit window APIs, or CoreGraphics event APIs.

```
App          lifecycle, permission onboarding, config + state loading, wiring
Commands     material-shell verb set → pure World mutations
Reconciler   World → desired frames; diff vs observed → minimal backend writes
Layout       pure geometry: (layout, count, rect, gap) → [rect?]
Model        pure values: World → Screen → Workspace → WindowRef
Platform     WindowBackend impl: AX wrappers, parking, displays, hotkey tap    ← harvested
```

### 3.1 Packages

```
Package.swift
Sources/SpacialShellKit/         Model, Layout, Commands, Reconciler, WindowBackend protocol, Config/State codecs
Sources/SpacialShellPlatform/    AXWindowBackend, per-app AX threads, ParkingLot, DisplayTopology, HotkeyTap, WindowClassifier
Sources/PrivateApi/              header-only C target exposing _AXUIElementGetWindow (lifted verbatim, MIT)
Sources/SpacialShell/            app target (LSUIElement): main.swift, Onboarding, wiring
Tests/SpacialShellKitTests/      pure unit + property tests; run on every change
Tests/PlatformIntegrationTests/  drives real apps (TextEdit, Finder); requires AX grant; run on demand
axDumps/                         AX fixture corpus lifted from AeroSpace for classifier regression tests
legal/                           LICENSE (MIT), third-party/LICENSE-AeroSpace.txt, NOTICE
```

`SpacialShellKit` has zero platform dependencies beyond Foundation and is fully testable without the Accessibility grant.

### 3.2 The `WindowBackend` seam

```swift
protocol WindowBackend: Sendable {
    // topology
    func displays() async -> [DisplayInfo]                 // id (UUID), frame, visibleFrame, isMain
    // enumeration
    func windows(of pid: pid_t) async -> [WindowSnapshot]   // id, pid, frame, title, classification, parent
    func runningApps() async -> [AppInfo]                   // regular activation policy + adopted accessories
    // mutation
    func setFrame(_ id: WindowRef, _ frame: CGRect) async -> Result<Void, BackendError>
    func setPosition(_ id: WindowRef, _ origin: CGPoint) async -> Result<Void, BackendError>
    func raise(_ id: WindowRef) async -> Result<Void, BackendError>      // AXMain + AXRaise + activate app
    func close(_ id: WindowRef) async -> Result<Void, BackendError>      // press AXCloseButton
    // events
    var events: AsyncStream<BackendEvent> { get }           // windowCreated/Destroyed/Moved/Resized/FocusChanged,
                                                            // appLaunched/Terminated/Hidden/Unhidden,
                                                            // displaysChanged, screenLocked/Unlocked
}
```

`AXWindowBackend` (Platform) is the real implementation. `FakeBackend` (tests) is an in-memory implementation that records writes and lets tests inject events. All coordinates crossing this seam are **top-left origin, y-down, global** (AX convention). The NSScreen bottom-left flip happens once, inside `DisplayTopology`, and is never seen above.

## 4. Spatial model

### 4.1 Types

```swift
struct WindowRef: Hashable, Codable { let id: CGWindowID; let pid: pid_t }

enum Layout: String, Codable, CaseIterable { case maximize, split, column, half, grid }

struct Workspace: Codable {
    var id: UUID
    var name: String            // "Code", "Web"… user-editable in M2; defaults "Workspace N"
    var symbol: String          // SF Symbol name; default "square.grid.2x2"
    var layout: Layout          // default from config, initially .maximize
    var windows: [WindowRef]    // ordered left→right; tiled + floating; not persisted in M1 (§9)
    var floating: Set<WindowRef>
    var anchor: WindowRef?      // last-focused window here; maximize/split anchor when this screen isn't focused
    var pinned: Bool            // seeded from config or user-named (M2); never reaped when empty
}

struct Screen: Codable {
    let display: DisplayID      // stable UUID from CGDisplayCreateUUIDFromDisplayID
    var rect: CGRect?           // nil = whole display visibleFrame (M1 always nil; ultrawide split later)
    var workspaces: [Workspace] // ordered top→bottom
    var activeIndex: Int
}

struct Focus: Equatable { var screen: DisplayID; var window: WindowRef? }

struct World: Codable {
    var screens: [DisplayID: Screen]
    var focus: Focus
    var ephemeral: Set<WindowRef>   // visitors: shown floating over whatever is active, belong to no workspace
    var ignored: Set<WindowRef>     // popups/PiP/fullscreen/etc. we never touch
    var hidden: Set<WindowRef>      // minimized or Cmd+H-hidden: keep their slot, skip layout and navigation
    var parents: [WindowRef: WindowRef]  // dialog → owner window
}
```

### 4.2 Invariants

Every command and every event handler preserves these. Property tests (§12) generate random worlds and command sequences and assert them.

1. **Single address.** Every managed window is in exactly one workspace of exactly one screen. `ephemeral`, `ignored`, and the workspaces' window lists are pairwise disjoint.
2. **New windows append.** A newly detected tileable window is appended to the end of the *active* workspace of the screen whose rect contains the largest area of the window (fallback: focused screen). A newly detected floating window with a **parent** (dialog/sheet of an existing window) joins its parent's workspace, immediately after the parent.
3. **New workspaces append.** A new workspace is appended to the bottom of the stack it is created in.
4. **Trailing empty.** Each screen's stack ends with an empty, **unpinned** (auto-created) workspace — a pinned workspace never doubles as the scratch one. When a window enters the trailing empty workspace, a fresh empty one is appended below. When a non-trailing, **unpinned** workspace becomes empty and is not the active one, it is reaped. (The active workspace is never reaped out from under the user; it is reaped when focus leaves it. Pinned workspaces — seeded from config, or user-named in M2 — survive empty; that is what makes named categories possible before window persistence exists.)
5. **Valid focus.** `focus.screen` names an existing screen; `focus.window`, if non-nil, is in that screen's active workspace and not hidden, or is ephemeral.

Invariant 4 is what makes "down" always meaningful without letting empty workspaces accumulate.

### 4.3 Semantics worth stating

- **Focus screen** is the screen containing the focused window, or, with no focused window, the last focused screen. Mouse position does not move focus in M1 (no focus-follows-mouse).
- **Floating** windows (auto or `Fn+G`) belong to a workspace and are shown/parked with it, but are excluded from layout and keep their own frame. They sit at their index for `Fn+A/D` navigation but take no tiling slot.
- **Ephemeral** windows (config list, e.g. System Settings, Calculator) belong to no workspace: they are centred on the focused screen when they appear, are never parked, and are not in any row. `Fn+A/D` never reaches them; `Fn+Q` closes them when focused. This is Veshell's "visitor" — the launcher UI for it is M2.
- **Native fullscreen** windows are moved to `ignored` while fullscreen and re-adopted (appended to the active workspace) when they leave fullscreen. macOS owns fullscreen; we do not fight it.
- **Minimized** windows stay in their workspace at their index but are excluded from layout until deminiaturized. `Fn+A/D` skips them.
- **Cmd+H hidden apps**: their windows stay in place in the model and are excluded from layout until the app unhides.

## 5. Layouts

`Layout.frames(count: Int, focused: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?]` is a pure total function. Index i of the result is the frame for the i-th tiled (non-floating, non-minimized) window of the workspace; `nil` means "parked — this layout does not show slot i".

| Layout | Visible slots | Arrangement |
|---|---|---|
| maximize | 1 | The focused window fills the rect. |
| split | 2 | The focused window and its right neighbour (left neighbour if focused is last) as two equal columns. With 1 window, it fills the rect. |
| column | all | n equal columns. |
| half | all | Slot 0 is the left half; slots 1…n−1 stack vertically in the right half. With 1 window, it fills the rect. |
| grid | all | `cols = ceil(sqrt(n))`, `rows = ceil(n / cols)`; row-major; last row's cells widen to fill. |

Anchoring maximize/split on the workspace's `anchor` (its last-focused window) is what makes `Fn+A/D` under maximize behave like tab switching — the same as material-shell — and keeps a non-focused screen showing what it showed when you left it.

`rect` is the screen rect (display `visibleFrame` — menu bar and Dock excluded — or the configured sub-rect) minus outer gap, with **height reduced by 1 pt** (macOS can refuse full-height frames on vertically stacked displays; AeroSpace `layoutRecursive.swift:5-12`). M2's panels will add insets here; the Layout layer takes insets as data and does not know what draws them.

**Parking is the single hiding mechanism.** Windows on inactive workspaces, windows on other screens' inactive workspaces, and windows in slots the current layout does not show are all handled identically: moved to the parking corner. There is no minimize, no app-hide, no second path.

## 6. Commands and hotkeys

### 6.1 Verb set

Commands are pure functions `(World, Command) -> (World, [Effect])`; effects are `focus(WindowRef)`, `close(WindowRef)`, and `relayout(DisplayID)`. The Reconciler turns effects into backend calls.

| Command | Default (`fn` preset) | `ctrl-alt` preset | material-shell |
|---|---|---|---|
| focusWorkspace(.up / .down) | `Fn+W` / `Fn+S` | `⌃⌥W` / `⌃⌥S` | Super+W/S |
| focusWindow(.left / .right) | `Fn+A` / `Fn+D` | `⌃⌥A` / `⌃⌥D` | Super+A/D |
| focusWorkspace(index: 1…10) | `Fn+1`…`Fn+0` | `⌃⌥1`…`⌃⌥0` | Super+1…0 |
| closeFocusedWindow | `Fn+Q` | `⌃⌥Q` | Super+Q |
| moveWindow(.left / .right) | `Fn+⇧A` / `Fn+⇧D` | `⌃⌥⇧A` / `⌃⌥⇧D` | Super+Shift+A/D |
| moveWindowToWorkspace(.up / .down) | `Fn+⇧W` / `Fn+⇧S` | `⌃⌥⇧W` / `⌃⌥⇧S` | Super+Shift+W/S |
| cycleLayout | `Fn+Space` | `⌃⌥Space` | Super+Space |
| toggleShellUI *(no-op in M1)* | `Fn+Esc` | `⌃⌥Esc` | Super+Esc |
| focusScreen(.prev / .next) | `Fn+[` / `Fn+]` | `⌃⌥[` / `⌃⌥]` | — |
| moveWindowToScreen(.prev / .next) | `Fn+⇧[` / `Fn+⇧]` | `⌃⌥⇧[` / `⌃⌥⇧]` | — |
| toggleFloat | `Fn+G` | `⌃⌥G` | — |

Arrow aliases: `⌃⌥←→↑↓` and `⌃⌥⇧←→↑↓` are bound in **both** presets to the four navigation and four move commands. They are deliberately not on bare `Fn`, because `Fn+arrows` are Home/End/PageUp/PageDown system-wide.

Semantics:
- `focusWindow(.right)` at the last window wraps to the first (material-shell behaviour). `focusWorkspace(.down)` at the trailing empty workspace stays.
- `moveWindow(.right)` at the end of the row is a no-op; `moveWindowToWorkspace(.down)` from the trailing empty workspace creates a new one below (invariant 4).
- `moveWindowToScreen` appends to the active workspace of the target screen and moves focus with the window. Screens order left→right, top→bottom by rect origin.
- `closeFocusedWindow` presses the window's close button. The app stays running (macOS convention). Focus moves to the left neighbour, or right if none, or nil.
- `toggleFloat` on a tiled window floats it at its current frame; on a floating window re-tiles it at its index.
- `Fn+F` is not used: Globe+F is Apple's fullscreen shortcut.

`Fn+Drag` (reorder by dragging) is **deferred to M2** because its main value is dropping onto the `ScreenPanel`, which does not exist yet, and because it requires a drag state machine that suspends reconciliation. The `moveWindow` verbs it will call exist now.

### 6.2 Hotkey capture

A `CGEventTap` at the session level (`kCGSessionEventTap`, `kCGHeadInsertEventTap`, active/`defaultTap`) filtering `keyDown`. Bound chords are consumed (return `nil`); everything else passes through untouched. Fn is `kCGEventFlagMaskSecondaryFn`. The tap re-enables itself on `kCGEventTapDisabledByTimeout` / `ByUserInput`. AeroSpace's Carbon `RegisterEventHotKey` approach is not used because Carbon hotkeys cannot express Fn as a modifier; only its key-name table (`keysMap.swift`) is lifted for config parsing.

Open verification items for the tap are in §13.

## 7. Platform layer

Everything in this section is either lifted from AeroSpace (paths cited) or a small adaptation of it. File-level lift list is in §14.

### 7.1 Threading and AX access

- One `Thread` per running application running a `CFRunLoop` (`AxAppThread <pid>`); `AXUIElementCreateApplication` and every AX read/write/observer for that app happen only on that thread. A hung app blocks only its own thread. (`tree/MacApp.swift:65-99`, `runLoop.swift`, `util/ThreadGuardedValue.swift`, `Common/model/AxAppThreadToken.swift`.)
- Additionally, `AXUIElementSetMessagingTimeout` is set per app element (AeroSpace does not; we add it so a hung app's thread also recovers instead of blocking forever). Timeout value from config, default 1 s.
- Model state lives in a single `actor WorldStore` (Kit). Platform threads never touch it; they emit `BackendEvent`s.
- Never send AX requests to our own pid; ignore `com.apple.loginwindow`.

### 7.2 Window identity and enumeration

- `WindowRef.id` comes from `_AXUIElementGetWindow` — the single private symbol, header-only C target (`Sources/PrivateApi/**`). Windows for which it returns nil are dropped (Finder desktop etc.).
- Enumerate via `kAXWindowsAttribute` per app. **Known limitation:** it only returns windows on the *current native macOS Space* of that display. M1 documents this and recommends one native Space per display; windows on other native Spaces are simply unseen until they come to the current Space, at which point they are adopted normally.
- Alive/dead partition each refresh by whether `containingWindowId()` still resolves — **skipped when the frontmost app is loginwindow** (see §7.7).
- **Parent detection** for dialogs/sheets: `AXParent` where present, else same-pid heuristics (the app's focused window at creation time). Feeds invariant 2.

### 7.3 Window classification (tile / float / ephemeral / ignore)

Lifted: `model/AxUiElementWindowType.swift`, `model/KnownBundleId.swift`, `windowLevelCache.swift`, and the 119-fixture `axDumps/` corpus with its regression test. Rules, in order:

0. User config: `[[ephemeral]]` → **ephemeral**; `[[float]]` → **float**; `[[ignore]]` → **ignore**. Match on `bundle-id` and optional `title-regex`.
1. Window level ≠ normal (0) via `CGWindowListCopyWindowInfo` → popup, **ignore**.
2. `AXSubrole ≠ AXStandardWindow` → dialog, **float** (with parent).
3. No fullscreen button, or disabled → dialog, **float** (with the per-app exceptions in `KnownBundleId`: terminals/editors that hide title-bar buttons still tile; Activity Monitor tiles; iOS Simulator and Photo Booth always float; Firefox PiP floats; Xcode `open_quickly` and Ghostty quick terminal are ignored).
4. Accessory apps without a close button → **ignore**.
5. `AXSize` not settable → **float**.
6. Otherwise → **tile**.

`toggleFloat` overrides everything for that window until it closes. Default `[[ephemeral]]` list ships with System Settings, Calculator, and Finder's Quick Look.

### 7.4 Frame writes and parking

- Every frame write is `size → position → size` (order matters, AeroSpace #143 #335) wrapped in a temporary `AXEnhancedUserInterface = false` on the app element to suppress animation, restored afterwards. Per-window pending writes are deduplicated: a newer write cancels an older one still queued. (`tree/MacApp.swift:411-436`.)
- **Parking** = position-only write to a display corner such that a **1 pt-wide sliver stays on screen** (macOS also keeps the top ~32 pt of the frame on-screen, so the real footprint is 1×32 — see §13.1; the reconciler tolerates that y clamp); size is preserved so unparking is a single position write (or a normal relayout for tiled windows). Bottom-right: origin = `visibleRect.bottomRight − (1,1)`. Bottom-left: origin = `(visibleRect.minX + 1 − width, visibleRect.maxY − 1)`. **Zoom (`us.zoom.xos`) gets zero offset** — it jumps off-screen otherwise (AeroSpace #527). (`tree/MacWindow.swift:121-155`.)
- **Corner choice per display**: probe points just outside the bottom-left and bottom-right corners (2 pt past, and 10 % of width/height, diagonal weighted ×10), count how many fall inside another display's frame, pick the corner with fewer hits so parked windows don't spill onto a neighbour; default bottom-right. (`layout/refresh.swift:164-188`.)
- **Order on every relayout**: first unpark + lay out the visible workspace of every screen, then park everything else — reduces flicker. (`layout/refresh.swift:190-201`.)
- Before parking, remember the window's origin as a proportion of its screen rect; floating windows unpark to that proportional position, clamped inside the screen. (`tree/MacWindow.swift:125-138`.)
- **On termination** (SIGTERM/SIGINT/`applicationWillTerminate`), every parked window is unparked and centred on its screen with its last size, using blocking non-cancellable AX calls, so quitting SpacialShell never strands windows in a corner. (`util/appBundleUtil.swift:11-53`.)

### 7.5 Focus, close, native state

- Focus: set `AXMain = true`, perform `AXRaise`, then `NSRunningApplication.activate(.activateIgnoringOtherApps)`. (`tree/MacApp.swift:130-148`.)
- Close: `AXPress` on `kAXCloseButtonAttribute`.
- Each refresh reads `AXFullScreen`, `AXMinimized`, and `NSRunningApplication.isHidden` per window/app and applies §4.3. Detection logic lifted from `normalizeLayoutReason.swift`; the container binding there is tree-specific and is not.

### 7.6 Events

Per-app AX observers (`util/AxSubscription.swift`), one observer per app on that app's thread: app-level `kAXWindowCreated`, `kAXFocusedWindowChanged`; window-level `kAXUIElementDestroyed`, `kAXWindowMiniaturized`/`Deminiaturized`, `kAXMoved`, `kAXResized`. Global: `NSWorkspace` `didLaunch/didTerminate/didActivate/didHide/didUnhide/activeSpaceDidChange`, `NSApplication.didChangeScreenParameters`, `DistributedNotificationCenter` `com.apple.screenIsLocked/Unlocked`, and a global `leftMouseUp` monitor — because `kAXUIElementDestroyed` is unreliable (close-button clicks on unfocused windows), a mouse-up triggers a refresh, and new-window registration is deferred while the mouse button is down (tab drag-out, AeroSpace #1001).

Every event coalesces into a **refresh session**: cancel any in-flight session, then re-enumerate apps and windows, gc dead ones, adopt new ones, read native state, and hand the delta to `WorldStore`. Commands run in a light session that syncs focus afterwards. Startup runs one non-cancellable heavy session. A **periodic refresh every 2 s** (config) backstops missed notifications.

### 7.7 Lock screen defence

When the screen locks, every AX attribute reads empty and every window id resolves to nil — it looks like every window closed. Three defences, all lifted in logic: (1) on any window death, snapshot the World; if a cached id re-resolves later, restore from the snapshot; (2) skip alive/dead partition while loginwindow is frontmost; (3) ignore NSWorkspace notifications from loginwindow. Additionally we subscribe to `screenIsLocked/Unlocked` and freeze the reconciler between them. (`tree/frozen/closedWindowsCache.swift`.)

### 7.8 Displays and screens

- Identity: `CGDisplayCreateUUIDFromDisplayID` (stable across reconnect), not `CGDirectDisplayID` and not top-left point (AeroSpace uses the point; UUID lets a screen's stack follow its display across unplug/replug).
- Topology: rebuilt from `NSScreen.screens` on every access; main = the screen with `frame.origin == (0,0)`, never `NSScreen.main` (unreliable in activation callbacks; AeroSpace note). Frames converted to top-left/y-down once, here.
- **Unplug**: that screen's workspaces are appended, in order, to the bottom of the main screen's stack (before its trailing empty). The stack is remembered in state keyed by display UUID. **Replug**: remembered workspaces move back to their screen, appended after whatever the screen accumulated meanwhile.
- **Adoption at startup**: every existing tileable window is appended to the active workspace of the screen holding most of its area, in z-order (front to back), so a first launch tiles what you see and parks nothing you can't get back with `Fn+A/D`.

## 8. Reconciler

```
BackendEvent ─┐
Command ──────┼─▶ WorldStore.apply ─▶ World' ─▶ Layout.frames per active workspace ─▶ desired: [WindowRef: Frame|Parked]
displays ─────┘                                                                                │
                                        observed: [WindowRef: Frame]  ◀── backend ────────────┤ diff
                                                                                               ▼
                                                                                    setFrame / setPosition / raise / close
```

- Diff desired vs. last-observed; write only deltas; unpark-then-park ordering (§7.4).
- **Feedback suppression**: every write records an *intent* `(WindowRef, frame, generation)`. Incoming `moved`/`resized` events whose frame matches a live intent (±1 pt) are dropped and the intent retired. Events that don't match are external (user drag, app self-resize) and cause a relayout, which snaps the window back — tiled windows cannot be freely moved in M1 (drag semantics arrive in M2).
- Writes are per-app-thread and cancellable; a burst of commands collapses into the final desired state.
- The reconciler is a pure function of `(World, observed)` plus a stateful intent set, so it is unit-tested against `FakeBackend`.

## 9. Config and state

**Config** `~/.config/spacial-shell/config.toml`, watched for changes (`config/ConfigFileWatcher.swift` lifted), reloaded live, invalid config keeps the previous one and logs.

```toml
keybinding-preset = "fn"          # or "ctrl-alt"
gap = 8                           # pt between windows and to screen edge
default-layout = "maximize"
ax-timeout-ms = 1000
refresh-interval-ms = 2000
start-at-login = false

[[workspace]]                     # pinned, named workspaces seeded on every screen (material-shell "categories")
name = "Code"
symbol = "terminal"               # SF Symbol
layout = "half"

[[ephemeral]]
bundle-id = "com.apple.systempreferences"

[[float]]
bundle-id = "com.apple.iphonesimulator"

[keybindings]                     # optional overrides, same notation as AeroSpace keysMap
"fn-shift-g" = "toggle-float"
```

**State** `~/Library/Application Support/SpacialShell/state.json`, written debounced on every model change:

```json
{ "version": 1,
  "screens": { "<display-uuid>": { "workspaces": [ { "id": "…", "name": "Code", "symbol": "terminal", "layout": "half", "pinned": true } ], "activeIndex": 0 } } }
```

Windows are **not** persisted in M1 (window ids don't survive app restart; matching is M3). On launch, pinned workspaces are restored empty (unpinned ones would be reaped immediately, so they are not restored) and existing windows are adopted per §7.8 into each screen's active workspace.

## 10. Permissions and onboarding

- First launch: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`. If not trusted, open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`, poll every second, and start managing only after the grant. On retry after a re-sign, run `tccutil reset Accessibility <bundle-id>` (macOS does not reset TCC when the signature changes; AeroSpace `accessibility.swift:5-26`).
- The event tap requires the same Accessibility trust; no separate Input Monitoring prompt is expected for an active tap from a trusted process (verify — §13).
- Secure Input (`IsSecureEventInputEnabled`) makes the tap deaf while a password field is focused; log it, do nothing else in M1 (M2 shows a HUD).

## 11. Error handling

- No AX failure ever crashes the agent. Every backend call returns `Result`; a failing window is marked unmanageable for that refresh; three consecutive failures move it to `ignored` until it changes.
- An app whose thread times out is marked unresponsive; its windows keep their last frames and are skipped by the reconciler until an event from it succeeds.
- `os_log` categories: `model`, `reconcile`, `ax`, `hotkeys`, `displays`. A watchdog logs any refresh session over 500 ms with per-app timings.
- Termination path always restores parked windows (§7.4).

## 12. Testing

1. **Kit unit tests** (`SpacialShellKitTests`) — Layout: exact frames for each layout at n = 0…7 including focus anchoring, gap math and the height−1 rule; Model/Commands: every verb on hand-built worlds; **property tests**: random worlds × random command/event sequences → invariants 1–5 hold and `Layout.frames` never returns overlapping frames; Reconciler: given desired+observed, exact write set, intent suppression, unpark-before-park order. Runs in < 5 s, no permissions.
2. **Classifier regression** — `axDumps/*.json5` corpus → expected tile/float/ignore; lifted test.
3. **Platform integration** (`PlatformIntegrationTests`, opt-in via env var, needs AX grant) — launches TextEdit windows, asserts frames after commands, asserts parking sliver geometry per display, asserts termination restore.
4. **Manual checklist** (in `docs/testing.md`) — display unplug/replug with 3 displays, lock/unlock, hung app (`kill -STOP`), native fullscreen round-trip, Zoom parking, Secure Input.

## 13. Research findings, risks, and empirical checks

Findings from a 9-agent research + adversarial-verification pass (2026-08-18; AeroSpace source, Apple SDK headers, IOHIDFamily source, live measurements on this Mac under macOS 26.5). Settled unless marked *verify*.

### 13.1 Parking (settled, live-measured)
- A titled window whose requested frame has **zero horizontal overlap** with every screen is relocated to a 40 pt overlap; with **≥ 1 pt overlap** the x request is honoured exactly. The **top 32 pt of the frame is always forced inside some screen's visibleFrame**. So the bottom-right request `(visibleFrame.maxX − 1, maxY − 1)` lands at `(maxX − 1, maxY − 32)`: the parked footprint is **1 pt wide × ~32 pt tall**, not 1×1. Consequence for the reconciler: compare parked *x* with 1 pt tolerance and *y* with 40 pt tolerance, both in `Reconciler.plan` and `IntentSet`, or every refresh re-parks. Borderless windows are unconstrained (they can be placed fully off-screen).
- The whole 2026 ecosystem converged on the same technique (AeroSpace, Rift `REVEAL_PX = 1`, OmniWM `SideHiding` 1 pt reveal, Paneru slivers, PaperWM.spoon edge margin). ScrollWM's "40 px sliver" conclusion came from zero-overlap requests; its edge-scrim workaround is unnecessary.
- *Verify:* stacked (vertical) display arrangements — the 32-pt title-bar rule can push a parked window onto the display below (Paneru #17 "flying over"); the corner probes may need vertical-neighbour awareness. *Verify:* Chrome/Electron, Java, Qt and Zoom behave like AppKit under cross-process writes.

### 13.2 Hotkeys (settled unless marked)
- `Fn` reaches a session-level active `CGEventTap` as the letter keycode + `kCGEventFlagMaskSecondaryFn`; returning NULL swallows. Shipping precedent: skhd, Hammerspoon, Loop, BTT, Raycast. Carbon `RegisterEventHotKey` cannot express Fn (why AeroSpace can't offer it).
- **Fn+arrows never arrive as arrows**: the HID layer (IOHIDKeyboardFilter) remaps Fn+←/→/↑/↓ to Home/End/PgUp/PgDn keycodes (115/119/116/121) with the Fn flag set, on Apple-VID keyboards. Binding them would steal Home/End/PgUp/PgDn system-wide — hence arrows stay on `⌃⌥`.
- **macOS 26.5 reserves Fn+letter symbolic hotkeys**: `Fn+Q` Quick Note, `Fn+H` Show Desktop, `Fn+F` Full Screen, `Fn+S` Type-to-Siri, `Fn+A` Dock, `Fn+C` Control Center, `Fn+N` Notification Center, `Fn+M`, `Fn+⇧A` Apps, plus Fn+Ctrl(+…)+arrows for native tiling. Only Fn+Q and the window-tiling group are changeable in System Settings; the rest have no UI (only "Press 🌐 key to" and "Function (fn) key → No Action/…", which kills Fn as a modifier). Session-level taps are evaluated **before** symbolic hotkeys for ⌘Space/⌘Tab (skhd #337, Hammerspoon #766) — *verify* that this holds for Fn+A/S/Q/H/F on 26.5 (T1). If a session tap does not pre-empt them, try `kCGHIDEventTap` (works for non-root with Accessibility trust); if neither, **the default preset becomes `ctrl-alt`** and `fn` stays a documented option.
- Non-Apple keyboards handle Fn in firmware and never deliver it; Karabiner-Elements re-emits through a virtual keyboard with Apple VID/PID, so "map key → fn" works. Document: non-Apple keyboard → Karabiner or the `ctrl-alt` preset.
- Tap hygiene (from AltTab/Loop/skhd/Ghostty): run the tap on a **dedicated thread with its own CFRunLoop** (a busy main actor triggers `kCGEventTapDisabledByTimeout`); callback must be O(µs) — table lookup, return NULL, dispatch async; re-enable on both disable events; also re-enable on `NSWorkspace.didWake` (+3 s), `com.apple.screenIsUnlocked`, session-active; 5 s health poll on `CGEvent.tapIsEnabled` with recreate + circuit breaker (≤5 per 2 s). Never post synthetic Fn events (ignored). Never bind Fn+F1…F20 (media/fnKeyMode-dependent). A Fn *tap* alone fires the Globe action (keycode 0xB3 may arrive) — we only match letters, so pass it through.
- Secure Input drops keyDown to all taps but flagsChanged still arrives (*verify*).
- *Verify* also: IME breakage with an always-on active tap (EVKey on 15.7 — not reproducible on 26.5); numeric tap timeout; behaviour after sleep/lock/re-sign (TCC re-evaluation after re-signing silently makes taps inert → the `tccutil reset` step matters).

### 13.3 AX events, threading, identity (settled)
- `kAXWindowCreated`/`kAXUIElementDestroyed` are unreliable (AeroSpace #445, yabai #174/#2431; Sequoia stops sending destroys for some apps). Treat every notification as a hint and run a cancellable full reconcile on any AX/NSWorkspace/mouse-up event; defer registration while the mouse is down; optional public fallback: periodic `CGWindowListCopyWindowInfo` diff for destroys.
- `AXObserverAddNotification` transiently returns `kAXErrorCannotComplete` right after launch → retry with real exponential backoff (≤ 6 tries; Amethyst's `count ^ 2 * 100` is XOR, a bug).
- Default AX messaging timeout ≈ 6 s (undocumented). Per-app 1 s via `AXUIElementSetMessagingTimeout` (public); timeouts surface as `kAXErrorCannotComplete`. AX to other processes may run on any thread (thread-per-app since AeroSpace 0.18.0); AX to **our own pid must never happen** (SIGTRAP off-main). One slow app must not delay detection for all (AeroSpace #1615) — report per app, don't await all.
- `CGDisplayCreateUUIDFromDisplayID` lives in ColorSync on 26.5 and round-trips; register `CGDisplayRegisterReconfigurationCallback` + `didChangeScreenParameters` and **debounce transient topologies on wake/lock** (Rift lost workspaces to transient Space snapshots).
- Lock screen: `_AXUIElementGetWindow` returns nil for everything while locked; Finder always has an AXWindow id 0 (desktop); windows hidden at login may report wid 0. `kAXWindows` omits inactive-Space windows.
- No public stable cross-restart window id exists (CGWindowID is per-session; kAXIdentifier rare) — M3 must match by (bundle id, title, pid-we-launched), exactly Veshell's algorithm.
- Cmd+Tab only targets an app's *last-used* window (OmniWM #184); AltTab/Raycast likewise. Floating windows can get stranded off-screen (OmniWM #224/#178) — the termination restore and a future "rescue" command matter. Another resident WM (AeroSpace, yabai, Rectangle, Loop, Paneru, Rift, OmniWM…) fights us — detect and warn at startup (M2/M4).

### 13.4 Prior art (settled)
- No macOS project implements the material-shell paradigm. Closest: **lthms/spatial-shell** (OCaml, i3/sway, MPL-2.0, "spatial model inspired by Material Shell", last push 2024-05) — note the name; our `spacial` spelling distinguishes. **Paneru** (Rust, 2k★) has experimental "virtual workspaces = stacked rows"; **OmniWM/Hiro** (Swift 6.4, GPL-2, 2.5k★, macOS 26+), **Rift** (Rust, Apache-2.0), **ScrollWM** (Swift, MIT), **PaperWM.spoon** are niri/PaperWM-style scrollers — all park by 1 pt sliver, several use one read-only private CGS call to identify the native Space (public API gives no Space id).
- Since 2026-05 a private SkyLight op (`SLSBridgedMoveWindowsToManagedSpaceOperation`, yabai 7.1.25, Loop) moves windows between **native Spaces with SIP enabled**. Private, may break per OS release — but it is a credible future backend for real Spaces without the SIP tax. Not for M1; noted in §15.
- Name collision (informational): carloscuesta/materialshell is a terminal theme; irrelevant now that we are SpacialShell.

### 13.5 Empirical checks owned by the first implementation
Recorded in `docs/platform-notes.md` when done: T1 Fn+letter pre-emption at session level (decides the default preset); Fn+arrow keycodes (expect 115/119/116/121); Input Monitoring prompt or not; Fn+Q/A/D/S/W/G/[/]/Space/Esc/1 reaching us; cross-process parking sliver geometry; stacked-display parking; observer-subscribe retries observed; tap survival across sleep/lock.

## 14. Attribution and lift list

MIT requires shipping AeroSpace's copyright line and permission notice with any lifted code. `legal/third-party/LICENSE-AeroSpace.txt` carries the full text; every lifted file keeps a header `// Adapted from AeroSpace (MIT) — <original path> @ c548c7f`. `NOTICE` lists them.

Lift verbatim or near-verbatim (paradigm-neutral): `Sources/PrivateApi/**`; `util/accessibility.swift` (drop unit-test mock branch and tray refs); `util/AxSubscription.swift`; `util/AxUiElementMock.swift`; `util/ThreadGuardedValue.swift`; `Common/model/AxAppThreadToken.swift`; `runLoop.swift`; `util/CompletableFuture.swift`; `util/AwaitableOneTimeBroadcastLatch.swift`; `util/dumpAxRecursive.swift`; `util/axTrustedCheckOptionPrompt.swift`; `util/NSRunningApplicationEx.swift`; `util/NsApplicationEx.swift`; `model/Rect.swift`; `model/MonitorInfo.swift` (drop test stubs); `model/KnownBundleId.swift`; `model/AxUiElementWindowType.swift`; `windowLevelCache.swift`; `appBundleUtil.swift` §§ CGPoint ops / monitorApproximation / withYAxisFlipped / termination restore; `config/ConfigFileWatcher.swift`; `config/startAtLogin.swift`; `config/keysMap.swift`; `Common/util/{TaskEx,MainActorEx,commonUtil}.swift`; `axDumps/**` + `AxUiElementWindowTypeTest.swift`.

Lift with surgery (logic yes, tree bindings no): `tree/MacApp.swift` (per-app facade ~80 %), `tree/MacWindow.swift:121-187` (parking), `layout/refresh.swift:143-201` (corner choice, ordering), `GlobalObserver.swift` (notification list), `normalizeLayoutReason.swift` (native-state detection), `tree/frozen/closedWindowsCache.swift` (lock-screen snapshot logic).

Not lifted (i3/tree model, commands, CLI, UI, config schema): everything under `tree/` except the above, `layout/layoutRecursive.swift`, `command/**`, `config/**` (except the three files above), `shell/**`, `ui/**`, `Cli/**`, `server.swift`, `subscriptions.swift`.

Dependencies that come along: none required. We pick our own TOML decoder — `TOMLDecoder` (MIT) is the obvious choice.

## 15. Non-goals for M1

Panels and any drawn UI; `Fn+Drag`; focus-follows-mouse; window re-association across restart; multiple native Spaces per display; ultrawide screen splitting (model supports it, no config yet); per-workspace app pinning; CLI/IPC socket (useful for scripting later, but tests drive `Commands` in-process); App Store distribution; a real-Spaces backend via the private SkyLight bridged-move op (§13.4) — possible later behind the `WindowBackend` seam, never a requirement.
