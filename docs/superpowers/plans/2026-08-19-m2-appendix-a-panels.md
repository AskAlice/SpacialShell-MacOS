# M2 appendix A — Shell panels (planner output, verbatim)

I have read the spec and all cited sources. Here is the plan.

---

# SpacialShell M2 — Shell UI Panels: Implementation Plan

**Goal.** Per display: a vibrancy rail (`ScreenPanel`), a vibrancy top bar (`WorkspacePanel`), a focus highlight overlay, Zen, and drag — driven entirely by a value the store publishes, built with Apple materials, with the spatial model untouched below.

**Spec anchors.** §1.1 (M2 row: rail + tab bar + layout switcher), §4 (model), §5 ("M2's panels will add insets here; the Layout layer takes insets as data and does not know what draws them" — this plan honours that literally), §6.1 (`toggleShellUI` reserved), §15 (panels are the M1 non-goal being lifted).

---

## 0. Decisions (each "decide" from the brief, with the reason)

| Question | Decision | One-line reason |
|---|---|---|
| New verbs: extend `Command` or a second enum? | **Second enum `Request`**, with `case command(Command)` wrapping the existing set. | `Command` is `Hashable` and is the *value type of the keybinding table* (`[Chord: Command]`) and of `KeyBindings.commandNames`; payload verbs are unbindable and unnamable, and Swift **forbids two enum cases with the same base name**, so `focusWorkspace(Vertical)` + `focusWorkspace(id:)` would not even compile. `Request` is also the natural future IPC surface (§15). |
| Insets: reuse `Screen.rect` or add an inset map? | **Neither in the model — a `desired(insets:)` parameter.** `Screen.rect` stays reserved for the ultrawide split it was designed for. | `Screen.rect` means "the portion of the display this Screen owns"; two Screens on one ultrawide would each have to re-derive the same rail dodge. And writing it on Zen toggle would mutate `World` (Equatable, persisted, invariant-tested) for a pure-UI state change, churning `state.json` on every Fn+Esc. |
| Who computes the insets? | **Kit, purely, from `Config`** (`ShellInsets(config:railSide:hidden:)`); the UI reads the *same* function to place panels. | Panels are fixed-size by design (48/34). Measure-then-report would create a layout→measure→relayout feedback loop and a one-frame flicker for zero benefit. One source of truth. |
| Zen state: `state.json` or config? | **`state.json` — `"shellHidden": bool`.** | Config is a hand-edited dotfile under a live `DispatchSource` watcher; writing a runtime toggle into it would fight the user's editor and round-trip through `reloadConfig()`. `state.json` is machine-owned and already debounce-saved. |
| How does the UI receive data? | **Widen the single callback**: `onChange: @Sendable (World, ShellSnapshot) -> Void`. | Both are derived from the same instant inside `reconcile()`; two callbacks invite one going stale relative to the other. Cost is 6 mechanical call sites (5 tests + `AppRuntime.swift:66`). |
| `SpacialShellUI` deps | **Kit only.** | Its three platform needs are `NSRunningApplication.icon`, `NSWorkspace.open`, and NSWindow placement — all AppKit, no AX. The only thing it wanted from Platform was the coordinate flip, which this plan promotes into Kit (below). |
| The coordinate flip | **Promote `DisplayTopology.flip` into Kit as `Geometry.flip(_:mainHeight:)`;** `DisplayTopology.flip` forwards to it; the UI calls it for NSWindow frames. | It is pure arithmetic and it is an *involution* — the same function converts both ways given the same `mainHeight`. One helper, called from two places, as the brief asks. |
| Native-fullscreen detection | **Store publishes `isCoveredByFullscreen` per screen**, derived from the `isFullscreen` windows it already tracks. | Per-display correctness: fullscreen on display 2 must not hide display 1's panels. `visibleFrame == frame` heuristics also fire on auto-hidden Dock + menu bar. |
| Panel lifecycle on hot-plug | **Panels are a pure function of `ShellSnapshot.screens`** — created, moved and destroyed on each snapshot; the UI never observes `NSScreen` itself. | The backend already debounces transient topologies (`settleMs = 500`, `emptyTopologyRetries`); re-deriving from `NSScreen` in the UI would reintroduce every hot-plug bug M1 already paid for. |

---

## 1. Visual token system

Everything comes from the OS. **One hex literal in the whole target**, and it is a fallback.

### Colour
| Token | Value |
|---|---|
| `Surface.rail` | `NSVisualEffectView` `.sidebar`, `blendingMode = .behindWindow`, **`state = .active`** |
| `Surface.topBar` | `NSVisualEffectView` `.headerView`, same blending/state |
| `Tint.active` | `Color.accentColor` / `NSColor.controlAccentColor` |
| `Tint.activeFill` | `Color.accentColor.opacity(0.18)` (rounded-square behind the active workspace glyph) |
| `Glyph.on` / `Glyph.off` | `NSColor.labelColor` / `.secondaryLabelColor` |
| `Hairline` | `NSColor.separatorColor`, 1 px (`1 / backingScaleFactor`) |
| `Highlight.stroke` | `NSColor.controlAccentColor`; **fallback `#0A84FF`** if it resolves with < 1.5:1 contrast against the accent-free "graphite" setting — the only hex in the target, defined once in `Tokens.swift` |

Light/dark is automatic: never read `NSApp.effectiveAppearance`, never branch on it.

### Type
| Element | Font |
|---|---|
| Tab title | `.system(size: 12, weight: .regular)`, truncating tail |
| Workspace hover label | `.system(size: 12, weight: .medium)` on a `.popover` material |
| Clock (HH over MM) | `.system(size: 11, weight: .medium, design: .monospaced)`, two lines, `lineSpacing(-1)`, `.monospacedDigit()` |
| Layout tooltip | `.system(size: 11)` |
| Badge "+N" | `.system(size: 9, weight: .semibold, design: .rounded)` |

### Spacing — 8 pt grid
- Rail **48 pt** wide (`panel-width`); tile 32×32 centred (8 pt gutters); 8 pt between tiles; **16 pt** between groups (search / workspaces / "+" / clock+menu); corner radius **8**.
- Top bar **34 pt** tall (`panel-height`); tab height 26 (4 pt vertical margins); app icon 16 pt; 6 pt icon→title; 10 pt horizontal padding; 8 pt between tabs; corner radius **6**; tab max width 220, min 88.
- Layout switcher: 24×24 glyph, 12 pt from the trailing edge; badge offset (+7, −7).
- SF Symbols: search `magnifyingglass`, add `plus`, app menu `square.stack.3d.up`, layouts → `rectangle` (maximize), `rectangle.split.2x1` (split), `rectangle.split.3x1` (column), `sidebar.left` (half — reads as "one big + a stack", better than `.slash` variants), `square.grid.2x2` (grid).

### The one signature element — **the focus glow that lands on the tile**
A 3 pt accent rounded stroke drawn at the focused window's **desired** frame (from `Reconciler`, not AX), entering at scale 1.06 / opacity 0 and settling to 1.0 with a 180 ms spring, then fading over `highlight-ms` (600). Because it is the *desired* frame it appears **before** the AX write lands — the glow arrives, the window arrives into it. That is the whole feel of the product in one 600 ms gesture, and it is free: the reconciler already computed the rect.

---

## 2. Module layout

```
Sources/SpacialShellUI/            NEW target — depends on SpacialShellKit only
  Theme/Tokens.swift
  Geometry/ShellGeometry.swift
  Panels/{ShellPanel,PanelHost,HighlightPanel}.swift
  Views/{RailView,WorkspaceTile,TopBarView,WindowTabView,LayoutSwitcher,HighlightView}.swift
  Menus/{WorkspaceMenu,ShellMenu}.swift
  Drag/{ShellDragController,DragHitTest}.swift
  Launcher.swift
  ShellUI.swift                    the one public entry point
Tests/SpacialShellUITests/
```

`Package.swift`: `.target(name: "SpacialShellUI", dependencies: ["SpacialShellKit"])`; executable gains `"SpacialShellUI"`; `.testTarget(name: "SpacialShellUITests", dependencies: ["SpacialShellUI"])`.

**Why our panels are never managed:** `RefreshSession.run()` filters `$0.processIdentifier != mine` and `AXApp.getOrCreate` refuses our own pid (`AXApp.swift:103`). Panels are invisible to the model by construction — no `[[ignore]]` rule needed, and this is the load-bearing reason the whole design is safe.

---

## 3. Tasks

### Task 1 — Config keys, `RailSide`, `ShellInsets`, `Geometry.flip`
**Files:** `Sources/SpacialShellKit/Config/Config.swift`, `Sources/SpacialShellKit/Model/Geometry.swift` *(new)*, `docs/config.md`

```swift
// Config.swift
public enum RailSide: String, Codable, Sendable { case left, right }

public var panelWidth: Double = 48      // "panel-width"
public var panelHeight: Double = 34     // "panel-height"
public var railSide: RailSide = .left   // "rail-side"
public var highlightMs: Int = 600       // "highlight-ms"
public var launcherURL: String = "raycast://"  // "launcher-url"
public var showPanels: Bool = true      // "show-panels"
```
Added to `CodingKeys` and to the hand-written `init(from:)` with `decodeIfPresent ?? default` — matching the existing style exactly.

```swift
// Geometry.swift
public enum Geometry {
    /// NSScreen (bottom-left, y-up) ⇄ AX/World (top-left, y-down). Self-inverse for a given
    /// `mainHeight` (the height of the screen whose frame origin is (0,0)).
    public static func flip(_ r: CGRect, mainHeight: CGFloat) -> CGRect
}

public struct ShellInsets: Sendable, Equatable {
    public var top: CGFloat, left: CGFloat, right: CGFloat, bottom: CGFloat
    public static let zero: ShellInsets
    public init(config: Config, hidden: Bool)   // .zero when hidden or !config.showPanels
    public func apply(to rect: CGRect) -> CGRect
}
```

**Tests** (`GeometryTests`, `ConfigTests`): `flip(flip(r)) == r`; a rect on a secondary display above/below the primary; `ShellInsets(config:hidden:false)` with `.left` and `.right`; `hidden: true` → `.zero`; `showPanels = false` → `.zero`; TOML round-trip of all six keys; unknown `rail-side` value rejects the whole config (existing "keep previous" behaviour).

**macOS 26 risk:** none — pure.

---

### Task 2 — Insets in the reconciler; `DisplayTopology` forwards to `Geometry.flip`
**Files:** `Sources/SpacialShellKit/Reconcile/Reconciler.swift`, `Sources/SpacialShellPlatform/Display/DisplayTopology.swift`

```swift
public static func desired(world: World, displays: [DisplayInfo], config: LayoutConfig,
                           observed: [WindowRef: CGRect], prePark: [WindowRef: CGRect],
                           parkedNow: Set<WindowRef>, zeroSliver: Set<WindowRef>,
                           insets: [DisplayID: ShellInsets] = [:],
                           suspended: Set<WindowRef> = []) -> [WindowRef: Placement]
```

Exact change at `Reconciler.swift:35` — **insets before the gap, gap before the height−1**:
```swift
var rect = insets[sid, default: .zero].apply(to: screen.rect ?? visible)
rect = rect.insetBy(dx: config.gap, dy: config.gap)
rect.size.height -= 1
```
`suspended` (used by Task 14) short-circuits to `.untouched` at the top of the per-window loop; defaulted so it is inert until then. Both parameters defaulted so the 6 existing `ReconcilerTests` call sites compile untouched.

`DisplayTopology.flip` becomes a one-line forward to `Geometry.flip` — its 3 existing tests keep passing.

**Tests:** rail-left inset shifts every layout's x by 48 and narrows by 48; rail-right narrows only; top inset shifts y by 34; `.zero` reproduces the exact frames the M1 tests already assert (regression guard); insets apply per display, not globally.

**What could go wrong:** applying the inset *after* the gap would double-count the 8 pt at the rail edge — a 8 pt seam between rail and first window. The test with an explicit expected rect pins the order.

---

### Task 3 — `Request`, `Effect.toggleShell`, runner
**Files:** `Sources/SpacialShellKit/Commands/Request.swift` *(new)*, `Sources/SpacialShellKit/Commands/CommandRunner.swift`, `Sources/SpacialShellKit/Commands/Command.swift`

```swift
public enum Request: Sendable, Equatable {
    case command(Command)                                  // everything the keyboard can do
    case focusWorkspace(id: UUID)
    case focusWindow(WindowRef)
    case moveWindowToWorkspace(WindowRef, UUID)            // NOT `moveWindow(_:toWorkspace:)`
    case reorderWindow(WindowRef, toIndex: Int)            // NOT `moveWindow(_:toIndex:)`
    case renameWorkspace(UUID, String)
    case setWorkspaceSymbol(UUID, String)
    case setActiveLayout(Layout)                           // NOT `setLayout(Layout)`
    case setLayout(workspace: UUID, Layout)
    case addWorkspace(on: DisplayID, name: String?, pinned: Bool)
    case removeWorkspace(UUID)
    case pinWorkspace(UUID, Bool)
    case toggleShell
}

extension CommandRunner {
    public static func apply(_ request: Request, to input: World) -> (World, [Effect])
}
```

> **Naming is forced, not stylistic.** Swift enum case names must be unique within the enum regardless of associated-value labels, so the brief's `moveWindow(ref, toWorkspace:)` / `moveWindow(ref, toIndex:)` pair and `setLayout(Layout)` / `setLayout(UUID, Layout)` pair cannot coexist. The renames above are the minimum change.

`Effect` gains `case toggleShell`. `CommandRunner.apply(.toggleShellUI)` stops being a `break` and emits `.toggleShell` — `World` is still not mutated, so Zen stays out of the model.

Semantics to implement, each restoring invariants via the existing `normalize()`:
- `focusWorkspace(id:)` → find `(screen, index)`, `world.activate(index:on:)`, set `focus.screen`.
- `focusWindow(ref)` → if located and not hidden, activate its workspace, set focus + anchor, emit `.focus`.
- `moveWindowToWorkspace` → mirror of `Command.moveWindowToWorkspace` but by UUID and across screens; carries `floating` membership, sets the target anchor, moves focus with the window.
- `reorderWindow(_:toIndex:)` → clamp to `0..<windows.count`, `remove` + `insert` (**not** `swapAt` — a drag to position 4 from position 0 must slide, not swap).
- `removeWorkspace(id)` → refuse when it is the trailing empty (invariant 4); windows move to the workspace **above**, or below when it is index 0; then `normalize()` (which reaps and re-appends the trailing empty).
- `addWorkspace(on:name:pinned:)` → insert **before** the trailing empty (invariant 3 + 4).
- `pinWorkspace(id, false)` on an empty non-trailing workspace makes it reapable — call `normalize()` and let it go.

**Tests** (`RequestTests`): one test per verb on a hand-built world, each asserting `invariantViolations().isEmpty` afterwards; `removeWorkspace` on the trailing empty is a no-op; `reorderWindow` slides rather than swaps; `removeWorkspace(activeId)` leaves a valid `activeIndex`. Extend `PropertyTests` to draw from `Request` as well as `Command` — this is the highest-value test in the milestone, because the UI is now a second, unaudited mutation path into the model.

---

### Task 4 — `ShellSnapshot` and its pure builder
**Files:** `Sources/SpacialShellKit/Shell/ShellSnapshot.swift` *(new)*, `Sources/SpacialShellKit/Shell/ShellSnapshotBuilder.swift` *(new)*

```swift
public enum WorkspaceGlyph: Sendable, Equatable {
    case symbol(String)                              // SF Symbol
    case appIcon(bundleID: String, pid: Int32)       // material-shell's category-from-content
}

public struct ShellChrome: Sendable, Equatable {     // config, flattened for the views
    public let panelWidth, panelHeight: CGFloat
    public let railSide: RailSide
    public let highlightMs: Int
    public let launcherURL: String
    public let showPanels: Bool
}

public struct ShellSnapshot: Sendable, Equatable {
    public struct WorkspaceItem: Sendable, Equatable, Identifiable {
        public let id: UUID, name: String, glyph: WorkspaceGlyph, layout: Layout
        public let pinned: Bool, isActive: Bool, windowCount: Int, isTrailingEmpty: Bool
    }
    public struct TabItem: Sendable, Equatable, Identifiable {
        public let id: WindowRef, title: String, bundleID: String?
        public let isFocused, isVisibleUnderLayout, isFloating: Bool
    }
    public struct ScreenView: Sendable, Equatable, Identifiable {
        public let id: DisplayID, display: DisplayInfo
        public let workspaces: [WorkspaceItem], tabs: [TabItem]
        public let activeLayout: Layout, hiddenByLayoutCount: Int
        public let isFocused, isCoveredByFullscreen: Bool
        public let insets: ShellInsets
    }
    public let screens: [ScreenView]        // in world.screenOrder
    public let focus: Focus
    public let focusedFrame: CGRect?        // desired frame, top-left/y-down — the glow's target
    public let shellHidden, locked: Bool
    public let chrome: ShellChrome
    public let generation: UInt64
}

extension ShellSnapshot {
    public static func build(world: World, displays: [DisplayInfo],
                             titles: [WindowRef: String], bundleIDs: [WindowRef: String],
                             desired: [WindowRef: Placement], fullscreenDisplays: Set<DisplayID>,
                             config: Config, shellHidden: Bool, locked: Bool,
                             generation: UInt64) -> ShellSnapshot
}
```

Builder rules, all pure and all tested:
- Glyph: `.appIcon` when `windowCount > 0 && symbol == Workspace.defaultSymbol` and the first window has a bundle id; else `.symbol(ws.symbol)`. (Introduce `Workspace.defaultSymbol = "square.grid.2x2"` and use it in `Workspace.init` and `WorkspaceSeed.init` instead of the two current literals.)
- `tabs` = the active workspace's `visible(in:)` order — **hidden windows excluded, parked-by-layout windows included** (that is the point under maximize: tabs are the switcher).
- `isVisibleUnderLayout` = `desired[ref]` is `.frame`; `.parked` → false; floating `.untouched` → true.
- `hiddenByLayoutCount` = `tabs.count { !isVisibleUnderLayout && !isFloating }` — the "+N" badge.
- `focusedFrame` = `desired[world.focus.window]`, only when `.frame`.
- Title fallback when `titles` has no entry yet: app name is unavailable in Kit, so fall back to `""` and let the view render the app icon alone. Do **not** invent a placeholder string in Kit.

**Tests** (`ShellSnapshotTests`): glyph falls back to app icon only under both conditions; maximize with 4 windows → 4 tabs, `hiddenByLayoutCount == 3`; floating window is a tab, `isFloating`, never counted in the badge; trailing empty flagged on exactly one workspace per screen; screens in `screenOrder`; `Equatable` means an unchanged world yields an equal snapshot (this is what stops the UI redrawing on every 2 s backstop refresh).

---

### Task 5 — Store integration
**Files:** `Sources/SpacialShellKit/Store/WorldStore.swift`, `Sources/SpacialShellKit/State/PersistedState.swift`

```swift
public init(backend:config:world:zeroSliverBundleIDs:shellHidden: Bool = false,
            onChange: @escaping @Sendable (World, ShellSnapshot) -> Void)
public func run(_ request: Request) async          // same `guard !locked` as run(_:Command)
```
New private state: `titles: [WindowRef: String]`, `fullscreenDisplays: Set<DisplayID>`, `shellHidden: Bool`, `shellGeneration: UInt64`.

Precise edits:
1. `applySnapshot` — beside `bundleIDs[w.ref] = w.bundleID` add `titles[w.ref] = w.title`; recompute `fullscreenDisplays` from the `w.isFullscreen` branch via the existing `screenFor(w.frame)`; in the gone-sweep add `titles[gone] = nil` **next to `bundleIDs[gone] = nil`** — those are the two tables with identical lifetime and they must be cleared together or titles leak for the process's life.
2. `reconcile()` — compute `let insets = shellHidden || !config.showPanels ? [:] : Dictionary(...)` from `displays` and pass it to `Reconciler.desired`; replace `onChange(world)` with `publish(desired: desired)`.
3. New `private func publish(desired:)` → bumps `shellGeneration`, builds the `ShellSnapshot`, calls `onChange(world, snapshot)`.
4. `.screenLocked` currently sets the flag and `return`s **before any reconcile**, so today the UI would never learn the screen locked. Add a `publish(desired: [:])` immediately before that `return`, and one on `.screenUnlocked`.
5. `run(_ command:)` effect loop gains `case .toggleShell: shellHidden.toggle()` before the `reconcile()` — the insets recompute on the same pass, so panels fade and windows expand in one frame.

`PersistedState` gains `public var shellHidden: Bool = false`, a `init(world:shellHidden: Bool = false)`, and an explicit `init(from:)` using `decodeIfPresent ?? false` so existing `state.json` files load unchanged (version stays 1 — the change is additive).

**Tests:** `onChange` delivers a snapshot whose tabs match the world; toggling shell zeroes the insets *and* the next `setFrame` covers the full `visibleFrame`; `.screenLocked` publishes with `locked == true` and issues no writes; `titles` cleared when a window closes; `Request` under lock is a no-op; `PersistedState` round-trips `shellHidden`; a v1 file without the key decodes to `false`.

**What could go wrong:** `reconcile()` early-returns on `gen != generation` *before* `publish` — a burst of commands publishes only once, at the end. That is correct and desirable (no intermediate flicker), but it means a test that awaits "one snapshot per command" will be flaky; assert on final state instead.

---

### Task 6 — UI target scaffold: tokens + geometry
**Files:** `Package.swift`, `Sources/SpacialShellUI/Theme/Tokens.swift`, `Sources/SpacialShellUI/Geometry/ShellGeometry.swift`

```swift
public enum ShellGeometry {
    /// Height of the NSScreen at origin (0,0) — the same rule DisplayTopology uses.
    @MainActor static func mainHeight() -> CGFloat
    /// World rect (top-left, y-down) → NSWindow frame (bottom-left, y-up).
    @MainActor public static func windowFrame(_ worldRect: CGRect) -> CGRect
    /// The two panel rects for a display, in world coordinates.
    public static func railRect(display: DisplayInfo, chrome: ShellChrome) -> CGRect
    public static func topBarRect(display: DisplayInfo, chrome: ShellChrome) -> CGRect
}
```
Rail spans the full `visibleFrame` height on the configured side; the top bar spans `visibleFrame.width − panelWidth`, offset by the rail — matching `ShellInsets` exactly. **Both derived from `ShellInsets`**, not re-typed, so drift is impossible.

**Tests:** `railRect` + `topBarRect` + `ShellInsets.apply` tile the `visibleFrame` with no overlap and no gap, for both rail sides, on a secondary display with negative y.

**What could go wrong:** `mainHeight()` returns 0 when no screen sits at (0,0) (real, mid-reconfiguration — `DisplayTopology` already logs it). Then every panel lands at y = −height, off-screen. Mitigation: fall back to `NSScreen.screens.first?.frame.height`, and after `setFrame` verify `panel.screen != nil`, logging `os_log` category `shell` when it is not.

---

### Task 7 — `ShellPanel` + `PanelHost`
**Files:** `Sources/SpacialShellUI/Panels/ShellPanel.swift`, `Sources/SpacialShellUI/Panels/PanelHost.swift`

```swift
final class ShellPanel: NSPanel {
    init(material: NSVisualEffectView.Material, content: some View)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func update(rootView: some View)
    func place(worldRect: CGRect)
}

@MainActor final class PanelHost {
    init(kind: Kind, send: @escaping @Sendable (Request) -> Void)
    func apply(_ snapshot: ShellSnapshot)   // create / move / destroy, keyed by DisplayID
}
```
Panel configuration, exactly:
```swift
styleMask = [.borderless, .nonactivatingPanel]
isFloatingPanel = true
level = .floating
collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
hidesOnDeactivate = false; isOpaque = false; backgroundColor = .clear; hasShadow = false
acceptsMouseMovedEvents = true; isMovableByWindowBackground = false
becomesKeyOnlyIfNeeded = true
```
Content: `NSVisualEffectView(material:, blendingMode: .behindWindow, state: .active)` as `contentView`, with an `NSHostingView` pinned inside it.

**Tests** (`PanelSmokeTests`, `@Suite(.enabled(if: !NSScreen.screens.isEmpty))`): a panel constructs, its frame round-trips through `windowFrame`, `canBecomeKey == false`, `collectionBehavior` contains `.canJoinAllSpaces`, and `PanelHost.apply` with a two-screen snapshot creates two panels and destroys one when the snapshot drops to one screen.

**macOS 26 pitfalls — this is the task where they live:**
- `NSVisualEffectView.state` defaults to `.followsWindowActiveState`. A panel that is *never key* is permanently "inactive" → the material renders as flat grey. **`state = .active` is mandatory**, not cosmetic.
- On macOS 26 the Liquid Glass materials need `isOpaque = false` **and** `backgroundColor = .clear`; miss either and the panel is a black rectangle.
- `NSHostingView` can draw an opaque background over the effect view. Set `hostingView.layer?.backgroundColor = NSColor.clear.cgColor` after `wantsLayer = true`, and never put a `.background(Material)` in the SwiftUI root — the vibrancy is AppKit's job here.
- `.canJoinAllSpaces` panels can bleed into a fullscreen Space on 26 and float over the fullscreen app; `isCoveredByFullscreen` → explicit `orderOut(nil)` is the only reliable cure.
- `.stationary` + `.canJoinAllSpaces` can leave ghosts after a Mission Control gesture: observe `NSWorkspace.activeSpaceDidChangeNotification` and `orderFront(nil)` the visible panels.
- On `locked == true`, `orderOut` every panel — a floating panel over the lock screen is a security bug, not a cosmetic one.

---

### Task 8 — Wiring: `ShellUI` + `AppRuntime`
**Files:** `Sources/SpacialShellUI/ShellUI.swift`, `Sources/SpacialShell/AppRuntime.swift`

```swift
@MainActor public final class ShellUI {
    public init(send: @escaping @Sendable (Request) -> Void)
    public func apply(_ snapshot: ShellSnapshot)     // the only input
    public func teardown()
}
```
`AppRuntime.boot()` — a new stage between the current 6 and 7 (store started, tap not yet):
```swift
log.info("stage 7/9: shell UI")
let ui = ShellUI(send: { req in Task { await store.run(req) } })
self.shellUI = ui
```
and the store's closure becomes `{ [weak self] world, shell in gate.note(world: world); Task { @MainActor in self?.scheduleSave(world, shellHidden: shell.shellHidden); self?.shellUI?.apply(shell) } }`. Restore `shellHidden` from `PersistedState` at stage 4 and pass it to the store's init. `applicationWillTerminate` / `TerminationGate` call `ui.teardown()` — panels must be gone before the window restore starts, or the restore centres windows behind chrome that is about to vanish.

**Tests:** none beyond build — this is wiring. Manual: launch, see two empty vibrant bars per display, `Fn+Esc` fades them and windows expand into the space.

**What could go wrong:** `NSApp.setActivationPolicy(.accessory)` (already set) means our windows never activate — correct for panels. But an accessory app's panels don't appear at all until `NSApp` has finished launching; `boot()` runs inside `applicationDidFinishLaunching`'s `Task`, so this is satisfied. Do not move the UI stage earlier than the store, or the first `apply` arrives before the panels exist.

---

### Task 9 — `ScreenPanel` (the rail)
**Files:** `Sources/SpacialShellUI/Views/RailView.swift`, `Sources/SpacialShellUI/Views/WorkspaceTile.swift`

Top→bottom: `magnifyingglass` (launcher), spacer 16, the workspace tiles, `plus` tile, `Spacer()`, clock, app-menu glyph. Active tile: `RoundedRectangle(8).fill(Tint.activeFill)` + accent-tinted symbol. Hover: a `.popover`-material label to the trailing side, 6 pt out, driven by `.onHover` with a 250 ms delay.

"+" focuses the trailing empty workspace (`Request.focusWorkspace(id:)` with the trailing-empty id) — it **is** the new one; no `addWorkspace` call from "+".

Clock: a `TimelineView(.periodic(from: .now, by: 60))` — never a `Timer` per panel.

**Tests:** `RailModelTests` — tile order, which tile is active, the "+" target id, glyph selection; no view rendering asserted.

**What could go wrong:** `.onHover` in a never-key window needs `acceptsMouseMovedEvents = true` (Task 7) and still misses the *exit* event when the pointer leaves across a screen edge — the hover label sticks. Mitigation: an `NSTrackingArea` (`.mouseEnteredAndExited, .activeAlways, .inVisibleRect`) on the hosting view that clears the hover state on exit, plus clearing it whenever a new snapshot arrives.

---

### Task 10 — `WorkspacePanel` (the top bar)
**Files:** `Sources/SpacialShellUI/Views/TopBarView.swift`, `Sources/SpacialShellUI/Views/WindowTabView.swift`, `Sources/SpacialShellUI/Views/LayoutSwitcher.swift`

Name the tab view `WindowTabView` — `TabView` collides with SwiftUI's. Tabs: `NSRunningApplication(processIdentifier:)?.icon` at 16 pt (cached by pid in a small `IconCache`; icons are not cheap and this view rebuilds on every snapshot), title, close `×` revealed on hover, active tab gets a 2 pt accent underline plus `Tint.activeFill`. `isVisibleUnderLayout == false` → title at `.secondaryLabelColor` (still a tab, still clickable — that is the maximize-mode switcher). Click → `Request.focusWindow`; `×` → `.command(.closeFocusedWindow)` after focusing, or better a direct `close` path: focus then close in one `Request` is not needed — send `.focusWindow(ref)` then `.command(.closeFocusedWindow)` is racy; instead reuse the existing close effect by adding nothing: `Request.focusWindow(ref)` followed by close is wrong. **Cleanest: `CommandRunner.apply(.command(.closeFocusedWindow))` only closes the focused one, so add `case closeWindow(WindowRef)` to `Request` in Task 3** and emit `.close(ref)`. (Fold this into Task 3's enum; noted here because it is discovered here.)

`+` tab and the trailing layout switcher (glyph per layout, click cycles via `.setActiveLayout(layout.next)`, hover shows the name, `+N` badge from `hiddenByLayoutCount`).

**Tests:** `TopBarModelTests` — tab order equals `visible(in:)` order, badge count, which tab is active, close target.

---

### Task 11 — `FocusHighlight`
**Files:** `Sources/SpacialShellUI/Panels/HighlightPanel.swift`, `Sources/SpacialShellUI/Views/HighlightView.swift`

One borderless panel per display, `ignoresMouseEvents = true`, `level = .floating` (same as panels — above app windows, below system UI), `collectionBehavior` as the panels. Frame = the display's `visibleFrame` (never the focused frame — resizing a window on every focus change is jarring and costs a Core Animation re-layout); the stroke is drawn *inside* at `focusedFrame` converted to panel-local coordinates.

Animation: `scale 1.06 → 1.0`, `opacity 0 → 1` over 180 ms `.spring(response: 0.18, dampingFraction: 0.8)`, then `opacity → 0` over `highlight-ms`. Triggered by a change in `(focus.window, focusedFrame)`, so a relayout that moves the focused window re-lands the glow.

**Tests:** pure `HighlightPlacement.rect(focusedFrame:in:)` conversion; the animation is manual-verify.

**What could go wrong:** `ignoresMouseEvents = true` is essential — a full-screen-sized panel that eats clicks would make the desktop unusable, and it is the single most damaging possible bug in this milestone. Assert it in the smoke test. Also: at `highlightMs = 0` the view must not schedule an animation at all (division/zero-duration edge).

---

### Task 12 — Menus, rename, launcher
**Files:** `Sources/SpacialShellUI/Menus/WorkspaceMenu.swift`, `Sources/SpacialShellUI/Menus/ShellMenu.swift`, `Sources/SpacialShellUI/Launcher.swift`

Workspace context menu: Rename…, Set icon…, Layout ▸ (5), Pin/Unpin, Remove (disabled for the trailing empty). App menu: Toggle Zen (`Fn+Esc`), Reload config, About, Quit. **Quit runs the `TerminationGate`** — expose it as a `@Sendable () -> Void` passed into `ShellUI` from `AppRuntime`, never `NSApp.terminate` directly, or windows stay parked.

Rename and Set icon use `NSAlert` with an accessory `NSTextField`, preceded by `NSApp.activate()`. This *does* momentarily activate our accessory app — accepted deliberately: it is an explicit, user-initiated, ~2 s interaction, and hand-rolling a key-capable panel to avoid it costs a first-responder chain we would otherwise never need.

`Launcher.open(chrome.launcherURL)` → `NSWorkspace.shared.open(URL)`; if the URL has no handler, `open` returns `false` → log and no-op (the documented fallback).

**Documented tray slot:** `RailView` keeps an empty `SystemTraySlot` view between the clock and the app-menu glyph, with a comment citing §1.1 ("tray omitted: macOS has a menu bar") so the silhouette gap is intentional and findable.

---

### Task 13 — Drag (a) tab reorder and (b) tab → workspace
**Files:** `Sources/SpacialShellUI/Drag/ShellDragController.swift`, `Sources/SpacialShellUI/Drag/DragHitTest.swift`

**Do not use SwiftUI drag-and-drop.** It routes through `NSItemProvider`/pasteboard and behaves badly in non-activating, never-key panels; and (b) crosses two separate `NSWindow`s, which SwiftUI drop destinations cannot see. Instead: a `DragGesture(minimumDistance: 4)` starts the drag, and `ShellDragController` takes over using `NSEvent.mouseLocation` (macOS routes the whole drag to the originating window, so the gesture keeps updating), converting to world coordinates with `Geometry.flip` and hit-testing against frames the two panels publish.

```swift
public enum DragHitTest {
    public static func insertionIndex(x: CGFloat, tabFrames: [CGRect]) -> Int
    public static func workspaceRow(at point: CGPoint, rowFrames: [(UUID, CGRect)]) -> UUID?
}
```
Drop → `.reorderWindow(ref, toIndex:)` or `.moveWindowToWorkspace(ref, id)`. Live feedback: a 2 pt accent insertion caret between tabs; the target rail tile pulses `Tint.activeFill`.

**Tests** (`DragHitTestTests`, pure): insertion index at the left half / right half of each tab, before the first, after the last, empty bar; workspace row hit with a point 1 pt inside/outside.

**What could go wrong:** `AXWindowBackend`'s global mouse monitor never sees events delivered to *our* process, so a drag on a tab leaves `mouseDown == false` — good (no refresh gate wedge), but it also means the usual `leftMouseUp → scheduleRefresh` does not fire. The drop's `Request` triggers its own `reconcile()`, so this is covered; do not add a manual refresh.

---

### Task 14 — `Fn+Drag` on a window body *(final; independently deferrable)*
**Files:** `Sources/SpacialShellPlatform/Hotkeys/DragTap.swift` *(new)*, `Sources/SpacialShellKit/Store/WorldStore.swift`

**A separate `CGEventTap` on its own thread — not the hotkey tap.** `HotkeyTap` is the load-bearing keyboard path; adding `leftMouseDragged` to its mask puts a high-frequency event stream inside the callback that must stay O(µs), and one overrun means `kCGEventTapDisabledByTimeout` and dead hotkeys. `DragTap` reuses `HotkeyTap`'s proven shape verbatim (dedicated thread + keep-alive source + health poll + circuit breaker + wake/unlock re-arm) with mask `leftMouseDown | leftMouseDragged | leftMouseUp`, and returns pass-through immediately unless `flags.contains(.maskSecondaryFn)` or a drag is already armed.

```swift
// WorldStore
public func suspend(_ refs: Set<WindowRef>) async     // → Reconciler.desired(suspended:)
```
Flow: Fn+mouseDown → resolve the window under the cursor from the store's last `desired` map (no AX hit-test needed — we already know every tile's rect) → `suspend([ref])` → swallow the drag events → on mouse-up, hit-test the cursor against the other tiles' rects, left/right half → `.reorderWindow(ref, toIndex:)` → `suspend([])` → relayout snaps it home.

**Tests:** pure `DragTap.decision(flags:type:armed:)` state machine; `Reconciler.desired(suspended:)` yields `.untouched`; `DragTapTests` mirroring `HotkeyTapTests`' lifecycle seams (`_testStartWithoutTap` etc.).

**What could go wrong:** a swallowed `leftMouseDown` that is never followed by an `Up` we see (app crash, Space switch mid-drag) leaves the window suspended forever. Guard with a 5 s watchdog that clears `suspended` and a `NSEvent.pressedMouseButtons` check on every tick — the same "the flag is a hint, the hardware is the authority" pattern `AXWindowBackend.isMouseDown` already uses.

---

## 4. Cross-cutting risks on macOS 26

| Risk | Where it bites | Mitigation |
|---|---|---|
| Vibrancy renders flat grey | Never-key panel + default `.followsWindowActiveState` | `state = .active` (Task 7) |
| Black rectangle instead of glass | 26's material path needs both flags | `isOpaque = false` **and** `backgroundColor = .clear` |
| Opaque SwiftUI background over the material | `NSHostingView` | `wantsLayer` + clear layer background; no `.background(Material)` in the root |
| Hover states stick | No mouse-exit across screen edges | `NSTrackingArea` + clear-on-snapshot |
| Panels float over a fullscreen app | `.canJoinAllSpaces` on 26 | per-display `isCoveredByFullscreen` → `orderOut` |
| Panels survive the lock screen | `.screenLocked` currently publishes nothing | Task 5 item 4 adds the publish; UI orders out on `locked` |
| Panels on the wrong display after hot-plug | `mainHeight()` = 0 mid-reconfiguration | fallback + post-`setFrame` `panel.screen` assertion, logged |
| Double gap at the rail edge | inset applied after the gap | `ReconcilerTests` pins the exact rect |
| Refresh gate wedged by a panel drag | global monitor blind to our own process | already handled by `isMouseDown`'s hardware check; do not "fix" it |
| Hotkeys die when Fn+Drag ships | mouse events in the keyboard tap | separate `DragTap` (Task 14) |

## 5. Docs to update (fold into their tasks)
`docs/config.md` (six new keys, Task 1); `docs/keybindings.md` (`Fn+Esc` is live, Task 5); `docs/testing.md` (manual checklist: hot-plug with panels, fullscreen round-trip, lock/unlock, Zen persistence across relaunch, rail-side flip, drag onto a rail tile); `README.md` (M2 line).

---

### Critical Files for Implementation
- /Users/alice/code/spacial-shell/Sources/SpacialShellKit/Store/WorldStore.swift
- /Users/alice/code/spacial-shell/Sources/SpacialShellKit/Reconcile/Reconciler.swift
- /Users/alice/code/spacial-shell/Sources/SpacialShellKit/Commands/CommandRunner.swift
- /Users/alice/code/spacial-shell/Sources/SpacialShellKit/Config/Config.swift
- /Users/alice/code/spacial-shell/Sources/SpacialShell/AppRuntime.swift