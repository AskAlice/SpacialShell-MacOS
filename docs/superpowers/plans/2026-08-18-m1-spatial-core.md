# SpacialShell M1 Spatial Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A headless macOS agent that keeps every window in a per-screen stack of workspaces, tiles the active workspace with one of five layouts, parks everything else in a screen corner, and is driven entirely by Fn-based hotkeys — the material-shell spatial paradigm without any UI yet.

**Architecture:** A pure-Swift `SpacialShellKit` (model, layout, commands, reconciler, config, state) sits above a `WindowBackend` protocol; `SpacialShellPlatform` implements it with the Accessibility API using AeroSpace's MIT-licensed threading/parking/classification code lifted with attribution; a thin `SpacialShell` executable wires config → backend → `WorldStore` actor → hotkey tap. Everything above the seam is unit-tested without permissions; the platform layer is exercised by an opt-in integration suite against TextEdit.

**Tech Stack:** Swift 6 (tools 6.0, strict concurrency), SwiftPM, Swift Testing (`import Testing`), AppKit + ApplicationServices (AX) + CoreGraphics event taps, `dduan/TOMLDecoder` for config, one private symbol `_AXUIElementGetWindow` via a header-only C target.

**Spec:** `docs/superpowers/specs/2026-08-18-m1-spatial-core-design.md` — every task cites the section it implements. Read the spec first.

## Global Constraints

- Swift tools version `6.0`; `platforms: [.macOS(.v14)]`; strict concurrency (all Kit types `Sendable`).
- Package/target names exactly: `SpacialShellKit`, `SpacialShellPlatform`, `PrivateApi`, `SpacialShell` (executable), tests `SpacialShellKitTests`, `SpacialShellPlatformTests`, `PlatformIntegrationTests`.
- `SpacialShellKit` imports only `Foundation` (and `TOMLDecoder` in `Config`). Never `AppKit`, `ApplicationServices`, `CoreGraphics` directly. `CGRect`/`CGPoint`/`CGSize` come through Foundation.
- All geometry crossing `WindowBackend` is **top-left origin, y-down, global** (AX convention). The NSScreen flip happens once, in `DisplayTopology`.
- Every file lifted from AeroSpace keeps the header comment `// Adapted from AeroSpace (MIT) — <original path> @ c548c7f` as its first line, and `legal/third-party/LICENSE-AeroSpace.txt` ships the full MIT text. AeroSpace clone for copying: `/private/tmp/claude-501/-Users-alice-mac-material-shell/aa7fe75f-1297-4120-92ea-463238dbfe97/scratchpad/AeroSpace` (re-clone `https://github.com/nikitabobko/AeroSpace` at `c548c7f` if missing).
- Paths: config `~/.config/spacial-shell/config.toml`; state `~/Library/Application Support/SpacialShell/state.json`. Bundle id `me.askalice.SpacialShell`.
- Licence GPL-3.0. No code from material-shell or Veshell (GPL-3).
- Test runner: `swift test --filter <TestSuiteName>` for Kit/Platform tests; integration tests only run when `SPACIAL_INTEGRATION=1`.
- Commit after every task with the message given in the task; run `swift build` before every commit.

## File Structure

```
Package.swift
LICENSE                                   GPL-3.0, copyright 2026 Alice
NOTICE                                    lists lifted files
legal/third-party/LICENSE-AeroSpace.txt
README.md
Sources/PrivateApi/include/{private.h,private.m,module.modulemap}   lifted verbatim
Sources/SpacialShellKit/
  Model/Model.swift                       WindowRef, Layout, Workspace, Screen, Focus, World, WindowKind
  Model/World+Invariants.swift            invariantViolations()
  Model/World+Mutations.swift             empty(), adopt, remove, setHidden, setFloating, setScreens, normalize, queries
  Layout/LayoutEngine.swift               frames(_:count:focused:in:gap:)
  Commands/Command.swift                  Command, Effect, Vertical/Horizontal/Neighbor
  Commands/CommandRunner.swift            apply(_:to:)
  Backend/WindowBackend.swift             protocol + DisplayInfo, WindowSnapshot, AppInfo, Snapshot, BackendEvent, BackendError
  Reconcile/Parking.swift                 corner(for:among:), origin(windowSize:visibleFrame:corner:sliver:)
  Reconcile/Reconciler.swift              Placement, Write, LayoutConfig, desired(...), plan(...)
  Reconcile/IntentSet.swift               feedback suppression
  Store/WorldStore.swift                  actor: events + commands → World → writes
  Config/Config.swift                     Config, AppRule, WorkspaceSeed, load(from:)
  Config/KeyBindings.swift                Chord, KeyCodes, parse, presets, table(for:)
  State/PersistedState.swift              save/load/restore
Sources/SpacialShellPlatform/
  Lifted/Common/{commonUtil,AeroAny,ConvenienceMutable,OptionalEx,TaskEx,MainActorEx}.swift
  Lifted/{Json,accessibility,AxSubscription,AxUiElementMock,ThreadGuardedValue,AxAppThreadToken,runLoop,
          CompletableFuture,AwaitableOneTimeBroadcastLatch,dumpAxRecursive,axTrustedCheckOptionPrompt,
          NSRunningApplicationEx,NsApplicationEx,Rect,KnownBundleId,AxUiElementWindowType,windowLevelCache,
          ConfigFileWatcher,startAtLogin}.swift
  AX/AXApp.swift                          per-pid facade (thread, observers, frame writes, parking write, raise, close)
  AX/WindowClassifier.swift               AxUiElementWindowType → WindowKind
  AX/Permissions.swift                    waitForAccessibility()
  Display/DisplayTopology.swift           NSScreen → [DisplayInfo] with UUIDs and flipped coordinates
  Backend/RefreshSession.swift            builds Snapshot from running apps
  Backend/AXWindowBackend.swift           WindowBackend impl + global observers + event stream + termination restore
  Hotkeys/HotkeyTap.swift                 CGEventTap → Command
Sources/SpacialShell/
  main.swift                              entry; accessory policy; run loop
  AppRuntime.swift                        wiring: paths, config watch, store, tap, state save, signals
Tests/SpacialShellKitTests/
  Support/{TestRNG,FakeBackend,Fixtures}.swift
  {Model,Invariant,Layout,Command,Property,Parking,Reconciler,IntentSet,WorldStore,Config,KeyBindings,PersistedState}Tests.swift
Tests/SpacialShellPlatformTests/ClassifierCorpusTests.swift
Tests/PlatformIntegrationTests/TextEditTests.swift
axDumps/                                  119 fixtures lifted verbatim
Scripts/{dev.sh,bundle.sh}
docs/testing.md, docs/platform-notes.md
```

---

### Task 1: Package scaffold, licence, attribution skeleton

**Files:**
- Create: `Package.swift`, `LICENSE`, `NOTICE`, `legal/third-party/LICENSE-AeroSpace.txt`, `README.md`
- Create: `Sources/PrivateApi/include/{private.h,private.m,module.modulemap}` (lifted verbatim)
- Create: placeholder `Sources/SpacialShellKit/Model/Model.swift` (real content in Task 2), `Sources/SpacialShellPlatform/Platform.swift` (`import SpacialShellKit` only), `Sources/SpacialShell/main.swift` (`print("SpacialShell")`)
- Create: `Tests/SpacialShellKitTests/SmokeTests.swift`

**Interfaces:**
- Produces: the build graph every later task compiles into.

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpacialShell",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpacialShellKit", targets: ["SpacialShellKit"]),
        .executable(name: "SpacialShell", targets: ["SpacialShell"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.0"),
    ],
    targets: [
        .target(name: "PrivateApi", path: "Sources/PrivateApi"),
        .target(
            name: "SpacialShellKit",
            dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")]
        ),
        .target(name: "SpacialShellPlatform", dependencies: ["SpacialShellKit", "PrivateApi"]),
        .executableTarget(name: "SpacialShell", dependencies: ["SpacialShellKit", "SpacialShellPlatform"]),
        .testTarget(name: "SpacialShellKitTests", dependencies: ["SpacialShellKit"]),
        .testTarget(name: "SpacialShellPlatformTests", dependencies: ["SpacialShellPlatform"]),
        .testTarget(name: "PlatformIntegrationTests", dependencies: ["SpacialShellPlatform", "SpacialShellKit"]),
    ]
)
```

- [ ] **Step 2: Lift PrivateApi verbatim**

```bash
AERO=/private/tmp/claude-501/-Users-alice-mac-material-shell/aa7fe75f-1297-4120-92ea-463238dbfe97/scratchpad/AeroSpace
mkdir -p Sources/PrivateApi/include
cp "$AERO"/Sources/PrivateApi/include/private.h "$AERO"/Sources/PrivateApi/include/private.m "$AERO"/Sources/PrivateApi/include/module.modulemap Sources/PrivateApi/include/
```
Then prepend `// Adapted from AeroSpace (MIT) — Sources/PrivateApi/include/<file> @ c548c7f` to `private.h` and `private.m`. Copy `"$AERO"/LICENSE.txt` to `legal/third-party/LICENSE-AeroSpace.txt`.

- [ ] **Step 3: Write LICENSE, NOTICE, README stub**

`LICENSE`: the verbatim GPL-3.0 text from https://www.gnu.org/licenses/gpl-3.0.txt.

`NOTICE`:
```
SpacialShell includes code adapted from AeroSpace (https://github.com/nikitabobko/AeroSpace),
Copyright (c) 2023 Nikita Bobko, MIT License — see legal/third-party/LICENSE-AeroSpace.txt.
Adapted files carry an "Adapted from AeroSpace" header comment. Current list:
  Sources/PrivateApi/include/private.h
  Sources/PrivateApi/include/private.m
```
(Later tasks append to this list.)

`README.md`:
```markdown
# SpacialShell

A spatial window manager for macOS: workspaces stacked vertically, windows arranged horizontally,
every window has one address. A continuation of the GNOME material-shell / Veshell paradigm.

Status: M1 (spatial core, headless) in progress. See docs/superpowers/specs/.
```

- [ ] **Step 4: Placeholders so the graph builds**

`Sources/SpacialShellKit/Model/Model.swift`:
```swift
import Foundation
public enum SpacialShellKit { public static let version = "0.1.0" }
```
`Sources/SpacialShellPlatform/Platform.swift`:
```swift
import SpacialShellKit
public enum SpacialShellPlatform { public static let kitVersion = SpacialShellKit.version }
```
`Sources/SpacialShell/main.swift`:
```swift
import SpacialShellKit
print("SpacialShell \(SpacialShellKit.version)")
```
`Tests/SpacialShellKitTests/SmokeTests.swift`:
```swift
import Testing
@testable import SpacialShellKit
@Suite struct SmokeTests {
    @Test func versionIsSet() { #expect(SpacialShellKit.version == "0.1.0") }
}
```
Empty test targets need one file each: `Tests/SpacialShellPlatformTests/PlatformSmokeTests.swift` and `Tests/PlatformIntegrationTests/IntegrationSmokeTests.swift` with a trivially passing `@Test`.

- [ ] **Step 5: Build and test**

Run: `swift build && swift test --filter SmokeTests`
Expected: build succeeds; 1 test passes.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: package scaffold, GPL-3.0 licence, AeroSpace attribution, PrivateApi target"
```

---

### Task 2: Model types and invariant checker

**Files:**
- Modify: `Sources/SpacialShellKit/Model/Model.swift` (replace placeholder)
- Create: `Sources/SpacialShellKit/Model/World+Invariants.swift`
- Test: `Tests/SpacialShellKitTests/InvariantTests.swift`

**Interfaces:**
- Produces: `WindowRef`, `Layout` (+`next`), `Workspace`, `Screen`, `Focus`, `World`, `WindowKind`, `World.invariantViolations() -> [String]`. Spec §4.1, §4.2.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct InvariantTests {
    static let a = WindowRef(id: 1, pid: 100)
    static let b = WindowRef(id: 2, pid: 100)

    func world(_ wss: [[WindowRef]], active: Int = 0) -> World {
        let ws = wss.map { Workspace(name: "W", layout: .maximize, windows: $0) }
        return World(
            screens: ["D1": Screen(display: "D1", rect: nil, workspaces: ws, activeIndex: active)],
            screenOrder: ["D1"], focus: Focus(screen: "D1", window: nil),
            ephemeral: [], ignored: [], hidden: [], parents: [:], defaultLayout: .maximize)
    }

    @Test func validWorldHasNoViolations() {
        #expect(world([[Self.a], []]).invariantViolations().isEmpty)
    }
    @Test func lastWorkspaceMustBeEmpty() {
        #expect(!world([[Self.a]]).invariantViolations().isEmpty)
    }
    @Test func windowInTwoWorkspacesIsViolation() {
        #expect(world([[Self.a], [Self.a], []]).invariantViolations().contains { $0.contains("and") })
    }
    @Test func emptyNonTrailingNonActiveIsViolation() {
        #expect(!world([[Self.a], [], []], active: 0).invariantViolations().isEmpty)
    }
    @Test func emptyActiveIsAllowed() {
        #expect(world([[], [Self.a], []], active: 0).invariantViolations().isEmpty)
    }
    @Test func pinnedEmptyIsAllowed() {
        var w = world([[Self.a], [], []], active: 0)
        w.screens["D1"]!.workspaces[1].pinned = true
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func focusMustBeInActiveWorkspaceOrEphemeral() {
        var w = world([[Self.a], [Self.b], []], active: 0)
        w.focus.window = Self.b
        #expect(!w.invariantViolations().isEmpty)
        w.focus.window = Self.a
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func layoutNextCycles() {
        #expect(Layout.maximize.next == .split)
        #expect(Layout.grid.next == .maximize)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter InvariantTests`
Expected: FAIL — compile errors, `WindowRef` etc. undefined.

- [ ] **Step 3: Write Model.swift**

```swift
import Foundation

public typealias DisplayID = String   // CGDisplayCreateUUIDFromDisplayID string
public typealias WindowID = UInt32    // CGWindowID

public struct WindowRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public let id: WindowID
    public let pid: Int32
    public init(id: WindowID, pid: Int32) { self.id = id; self.pid = pid }
    public var description: String { "w\(id)@\(pid)" }
}

public enum Layout: String, Codable, CaseIterable, Sendable {
    case maximize, split, column, half, grid
    public var next: Layout {
        let all = Layout.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public enum WindowKind: String, Codable, Sendable { case tile, float, ephemeral, ignore }

public struct Workspace: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var layout: Layout
    public var windows: [WindowRef]      // ordered left→right; tiled + floating
    public var floating: Set<WindowRef>
    public var anchor: WindowRef?         // last focused window here; maximize/split anchor
    public var pinned: Bool               // never reaped when empty (config seed / user-named)
    public init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2", layout: Layout,
                windows: [WindowRef] = [], floating: Set<WindowRef> = [], anchor: WindowRef? = nil, pinned: Bool = false) {
        self.id = id; self.name = name; self.symbol = symbol; self.layout = layout
        self.windows = windows; self.floating = floating; self.anchor = anchor; self.pinned = pinned
    }
    public var isEmpty: Bool { windows.isEmpty }
}

public struct Screen: Codable, Equatable, Sendable {
    public let display: DisplayID
    public var rect: CGRect?             // nil = whole display visibleFrame
    public var workspaces: [Workspace]   // top→bottom
    public var activeIndex: Int
    public init(display: DisplayID, rect: CGRect? = nil, workspaces: [Workspace], activeIndex: Int) {
        self.display = display; self.rect = rect; self.workspaces = workspaces; self.activeIndex = activeIndex
    }
    public var active: Workspace {
        get { workspaces[activeIndex] }
        set { workspaces[activeIndex] = newValue }
    }
}

public struct Focus: Codable, Equatable, Sendable {
    public var screen: DisplayID
    public var window: WindowRef?
    public init(screen: DisplayID, window: WindowRef?) { self.screen = screen; self.window = window }
}

public struct World: Codable, Equatable, Sendable {
    public var screens: [DisplayID: Screen]
    public var screenOrder: [DisplayID]        // left→right, top→bottom
    public var focus: Focus
    public var ephemeral: Set<WindowRef>       // visitors: no workspace, never parked
    public var ignored: Set<WindowRef>         // popups / fullscreen / unmanageable
    public var hidden: Set<WindowRef>          // minimized or app-hidden; keep slot, skip layout+nav
    public var parents: [WindowRef: WindowRef] // dialog → owner
    public var defaultLayout: Layout
    public init(screens: [DisplayID: Screen], screenOrder: [DisplayID], focus: Focus,
                ephemeral: Set<WindowRef>, ignored: Set<WindowRef>, hidden: Set<WindowRef>,
                parents: [WindowRef: WindowRef], defaultLayout: Layout) {
        self.screens = screens; self.screenOrder = screenOrder; self.focus = focus
        self.ephemeral = ephemeral; self.ignored = ignored; self.hidden = hidden
        self.parents = parents; self.defaultLayout = defaultLayout
    }
}
```

- [ ] **Step 4: Write World+Invariants.swift**

```swift
import Foundation

extension World {
    /// Spec §4.2. Empty array == all invariants hold.
    public func invariantViolations() -> [String] {
        var v: [String] = []
        if Set(screenOrder) != Set(screens.keys) { v.append("screenOrder \(screenOrder) != screens \(screens.keys.sorted())") }
        var seen: [WindowRef: String] = [:]
        for (id, s) in screens {
            guard !s.workspaces.isEmpty else { v.append("\(id): no workspaces"); continue }
            guard (0..<s.workspaces.count).contains(s.activeIndex) else { v.append("\(id): activeIndex \(s.activeIndex) out of range"); continue }
            if !s.workspaces.last!.isEmpty { v.append("\(id): last workspace not empty") }
            for (i, ws) in s.workspaces.enumerated() {
                let last = i == s.workspaces.count - 1
                if ws.isEmpty && !last && i != s.activeIndex && !ws.pinned { v.append("\(id)[\(i)]: empty, unpinned, non-trailing, non-active") }
                if Set(ws.windows).count != ws.windows.count { v.append("\(id)[\(i)]: duplicate windows") }
                for w in ws.windows {
                    if let prev = seen[w] { v.append("\(w) in \(prev) and \(id)[\(i)]") }
                    seen[w] = "\(id)[\(i)]"
                    if ephemeral.contains(w) { v.append("\(w) both placed and ephemeral") }
                    if ignored.contains(w) { v.append("\(w) both placed and ignored") }
                }
                for f in ws.floating where !ws.windows.contains(f) { v.append("\(id)[\(i)]: floating \(f) not in windows") }
                if let a = ws.anchor, !ws.windows.contains(a) { v.append("\(id)[\(i)]: anchor \(a) not in windows") }
            }
        }
        for w in ephemeral where ignored.contains(w) { v.append("\(w) both ephemeral and ignored") }
        for w in hidden where seen[w] == nil { v.append("\(w) hidden but not placed") }
        guard let fs = screens[focus.screen] else { v.append("focus.screen \(focus.screen) unknown"); return v }
        if let w = focus.window {
            if !fs.active.windows.contains(w) && !ephemeral.contains(w) { v.append("focus \(w) not in active workspace of \(focus.screen) nor ephemeral") }
            if hidden.contains(w) { v.append("focus \(w) is hidden") }
        }
        return v
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter InvariantTests`
Expected: all 8 pass.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(kit): model types and invariant checker"
```

---

### Task 3: World mutations — adopt, remove, normalize, screens

**Files:**
- Create: `Sources/SpacialShellKit/Model/World+Mutations.swift`
- Test: `Tests/SpacialShellKitTests/ModelTests.swift`

**Interfaces:**
- Produces: `World.empty(screens:defaultLayout:)`, `World.location(of:) -> (screen: DisplayID, index: Int)?`, `World.workspace(containing:)`, `World.tiled(in:) -> [WindowRef]`, `World.visible(in:) -> [WindowRef]` (tiled+floating minus hidden), `World.screenContaining(_ w) -> DisplayID?`, `mutating adopt(_:kind:on:parent:)`, `mutating remove(_:)`, `mutating setHidden(_:_:)`, `mutating setFloating(_:_:)`, `mutating setScreens(_:main:)`, `mutating activate(index:on:)`, `mutating normalize()`, `mutating newWorkspace() -> Workspace`. Spec §4.2 invariants 2–5, §7.8 unplug/replug.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ModelTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 2)

    @Test func emptyWorldHasOneEmptyWorkspacePerScreen() {
        let w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        #expect(w.screens.count == 2)
        #expect(w.screens["D1"]!.workspaces.count == 1)
        #expect(w.focus == Focus(screen: "D1", window: nil))
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func adoptAppendsToActiveAndCreatesTrailingEmpty() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        w.adopt(b, kind: .tile, on: "D1")
        #expect(w.screens["D1"]!.workspaces.count == 2)
        #expect(w.screens["D1"]!.workspaces[0].windows == [a, b])
        #expect(w.focus.window == a)              // first adoption takes focus
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func adoptDialogGoesAfterParent() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        w.adopt(c, kind: .float, on: "D1", parent: a)
        #expect(w.screens["D1"]!.workspaces[0].windows == [a, c, b])
        #expect(w.screens["D1"]!.workspaces[0].floating == [c])
        #expect(w.parents[c] == a)
    }
    @Test func adoptEphemeralAndIgnoreDontEnterWorkspaces() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .ephemeral, on: "D1"); w.adopt(b, kind: .ignore, on: "D1")
        #expect(w.ephemeral == [a] && w.ignored == [b])
        #expect(w.screens["D1"]!.workspaces[0].windows.isEmpty)
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func adoptTwiceIsNoop() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(a, kind: .tile, on: "D1")
        #expect(w.screens["D1"]!.workspaces[0].windows == [a])
    }
    @Test func removeMovesFocusToLeftNeighbourThenRight() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1"); w.adopt(c, kind: .tile, on: "D1")
        w.focus.window = b
        w.remove(b); #expect(w.focus.window == a)
        w.remove(a); #expect(w.focus.window == c)
        w.remove(c); #expect(w.focus.window == nil)
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func emptiedNonActiveWorkspaceIsReaped() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        w.activate(index: 1, on: "D1")           // trailing empty becomes active → new trailing appended
        w.adopt(b, kind: .tile, on: "D1")
        #expect(w.screens["D1"]!.workspaces.count == 3)
        w.activate(index: 0, on: "D1")
        w.remove(b)                              // workspace 1 now empty, not active, not last → reaped
        #expect(w.screens["D1"]!.workspaces.count == 2)
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func pinnedWorkspaceSurvivesEmpty() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.screens["D1"]!.workspaces.insert(Workspace(name: "Code", layout: .half, pinned: true), at: 0)
        w.normalize()
        #expect(w.screens["D1"]!.workspaces.count == 2)
        #expect(w.screens["D1"]!.workspaces[0].name == "Code")
    }
    @Test func hiddenWindowsAreExcludedFromVisible() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        w.setHidden(a, true)
        #expect(w.visible(in: w.screens["D1"]!.active) == [b])
        #expect(w.focus.window == b)             // focus left the hidden window
        w.setHidden(a, false)
        #expect(w.visible(in: w.screens["D1"]!.active) == [a, b])
    }
    @Test func removingScreenMergesWorkspacesIntoMain() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D2"); w.focus = Focus(screen: "D2", window: a)
        w.setScreens(["D1"], main: "D1")
        #expect(w.screens["D2"] == nil)
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[], [a], []])
        #expect(w.focus.screen == "D1")
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func addingScreenCreatesEmptyStack() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.setScreens(["D1", "D2"], main: "D1")
        #expect(w.screens["D2"]!.workspaces.count == 1)
        #expect(w.screenOrder == ["D1", "D2"])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ModelTests` — Expected: compile failure (`empty`, `adopt` undefined).

- [ ] **Step 3: Implement World+Mutations.swift**

```swift
import Foundation

extension World {
    public static func empty(screens ids: [DisplayID], defaultLayout: Layout) -> World {
        var screens: [DisplayID: Screen] = [:]
        for id in ids {
            screens[id] = Screen(display: id, workspaces: [Workspace(name: "Workspace 1", layout: defaultLayout)], activeIndex: 0)
        }
        return World(screens: screens, screenOrder: ids, focus: Focus(screen: ids.first ?? "", window: nil),
                     ephemeral: [], ignored: [], hidden: [], parents: [:], defaultLayout: defaultLayout)
    }

    // MARK: queries

    public func location(of w: WindowRef) -> (screen: DisplayID, index: Int)? {
        for id in screenOrder {
            if let i = screens[id]!.workspaces.firstIndex(where: { $0.windows.contains(w) }) { return (id, i) }
        }
        return nil
    }
    public func workspace(containing w: WindowRef) -> Workspace? {
        location(of: w).map { screens[$0.screen]!.workspaces[$0.index] }
    }
    public func screenContaining(_ w: WindowRef) -> DisplayID? { location(of: w)?.screen }
    /// Windows the layout engine positions: not floating, not hidden.
    public func tiled(in ws: Workspace) -> [WindowRef] { ws.windows.filter { !ws.floating.contains($0) && !hidden.contains($0) } }
    /// Windows reachable by left/right navigation: not hidden.
    public func visible(in ws: Workspace) -> [WindowRef] { ws.windows.filter { !hidden.contains($0) } }
    public func newWorkspace() -> Workspace { Workspace(name: "Workspace", layout: defaultLayout) }

    // MARK: mutations

    public mutating func adopt(_ w: WindowRef, kind: WindowKind, on screen: DisplayID, parent: WindowRef? = nil) {
        guard location(of: w) == nil, !ephemeral.contains(w), !ignored.contains(w) else { return }
        switch kind {
        case .ignore: ignored.insert(w); return
        case .ephemeral: ephemeral.insert(w); return
        case .tile, .float: break
        }
        var target = screens[screen] != nil ? screen : focus.screen
        var index: Int? = nil
        if let p = parent, let loc = location(of: p) {
            target = loc.screen; index = loc.index; parents[w] = p
        }
        let wsIndex = index ?? screens[target]!.activeIndex
        var ws = screens[target]!.workspaces[wsIndex]
        if let p = parent, let pi = ws.windows.firstIndex(of: p) { ws.windows.insert(w, at: pi + 1) } else { ws.windows.append(w) }
        if kind == .float { ws.floating.insert(w) }
        screens[target]!.workspaces[wsIndex] = ws
        if focus.window == nil, target == focus.screen, wsIndex == screens[target]!.activeIndex { focus.window = w }
        normalize()
    }

    public mutating func remove(_ w: WindowRef) {
        ephemeral.remove(w); ignored.remove(w); hidden.remove(w); parents[w] = nil
        parents = parents.filter { $0.value != w }
        if let loc = location(of: w) {
            var ws = screens[loc.screen]!.workspaces[loc.index]
            let vis = visible(in: ws)
            if focus.window == w {
                let i = vis.firstIndex(of: w)!
                focus.window = i > 0 ? vis[i - 1] : (vis.count > 1 ? vis[i + 1] : nil)
            }
            ws.windows.removeAll { $0 == w }; ws.floating.remove(w)
            if ws.anchor == w { ws.anchor = focus.window.flatMap { ws.windows.contains($0) ? $0 : nil } ?? ws.windows.first }
            screens[loc.screen]!.workspaces[loc.index] = ws
        } else if focus.window == w { focus.window = nil }
        normalize()
    }

    public mutating func setHidden(_ w: WindowRef, _ isHidden: Bool) {
        guard location(of: w) != nil else { return }
        if isHidden { hidden.insert(w) } else { hidden.remove(w) }
        normalize()
    }

    public mutating func setFloating(_ w: WindowRef, _ floating: Bool) {
        guard let loc = location(of: w) else { return }
        if floating { screens[loc.screen]!.workspaces[loc.index].floating.insert(w) }
        else { screens[loc.screen]!.workspaces[loc.index].floating.remove(w) }
    }

    public mutating func activate(index: Int, on screen: DisplayID) {
        guard var s = screens[screen], (0..<s.workspaces.count).contains(index) else { return }
        s.activeIndex = index
        screens[screen] = s
        if focus.screen == screen {
            let vis = visible(in: s.active)
            focus.window = s.active.anchor.flatMap { vis.contains($0) ? $0 : nil } ?? vis.first
        }
        normalize()
    }

    /// Spec §7.8: unplug merges into main; replug creates an empty stack (state restore may refill it).
    public mutating func setScreens(_ order: [DisplayID], main: DisplayID) {
        for id in order where screens[id] == nil {
            screens[id] = Screen(display: id, workspaces: [newWorkspace()], activeIndex: 0)
        }
        for id in screens.keys where !order.contains(id) {
            let gone = screens.removeValue(forKey: id)!
            let mainId = screens[main] != nil ? main : (order.first ?? "")
            guard var m = screens[mainId] else { continue }
            let insertAt = m.workspaces.count - 1
            m.workspaces.insert(contentsOf: gone.workspaces.filter { !$0.isEmpty || $0.pinned }, at: insertAt)
            screens[mainId] = m
            if focus.screen == id { focus.screen = mainId }
        }
        screenOrder = order.filter { screens[$0] != nil }
        if screens[focus.screen] == nil { focus.screen = screenOrder.first ?? "" }
        normalize()
    }

    /// Restores invariants 4 and 5 after any mutation. Idempotent.
    public mutating func normalize() {
        for id in screens.keys {
            var s = screens[id]!
            let activeId = s.workspaces.indices.contains(s.activeIndex) ? s.workspaces[s.activeIndex].id : nil
            var kept: [Workspace] = []
            for (i, ws) in s.workspaces.enumerated() {
                let last = i == s.workspaces.count - 1
                if ws.isEmpty && !last && ws.id != activeId && !ws.pinned { continue }
                kept.append(ws)
            }
            if kept.isEmpty || !kept.last!.isEmpty { kept.append(newWorkspace()) }
            s.workspaces = kept
            s.activeIndex = kept.firstIndex { $0.id == activeId } ?? min(s.activeIndex, kept.count - 1)
            for i in kept.indices {
                if let a = kept[i].anchor, !kept[i].windows.contains(a) { s.workspaces[i].anchor = nil }
                if s.workspaces[i].anchor == nil { s.workspaces[i].anchor = tiled(in: s.workspaces[i]).first }
            }
            screens[id] = s
        }
        if screens[focus.screen] == nil { focus.screen = screenOrder.first ?? "" }
        guard let fs = screens[focus.screen] else { return }
        let vis = visible(in: fs.active)
        if let w = focus.window, !(vis.contains(w) || ephemeral.contains(w)) { focus.window = nil }
        if focus.window == nil { focus.window = fs.active.anchor.flatMap { vis.contains($0) ? $0 : nil } ?? vis.first }
        if let w = focus.window, vis.contains(w) { screens[focus.screen]!.workspaces[fs.activeIndex].anchor = w }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter "ModelTests|InvariantTests"` — Expected: all pass. If `removingScreenMergesWorkspacesIntoMain` fails on the exact array shape, check that the gone screen's trailing empty was filtered (it should be — `!isEmpty || pinned`).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(kit): world mutations, normalization, screen merge"
```

---

### Task 4: Layout engine

**Files:**
- Create: `Sources/SpacialShellKit/Layout/LayoutEngine.swift`
- Test: `Tests/SpacialShellKitTests/LayoutTests.swift`

**Interfaces:**
- Produces: `LayoutEngine.frames(_ layout: Layout, count: Int, focused: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?]` (nil = parked by layout). Spec §5.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct LayoutTests {
    let r = CGRect(x: 0, y: 0, width: 1000, height: 600)
    func eq(_ a: CGRect?, _ b: CGRect, _ tol: CGFloat = 0.01) -> Bool {
        guard let a else { return false }
        return abs(a.minX-b.minX) < tol && abs(a.minY-b.minY) < tol && abs(a.width-b.width) < tol && abs(a.height-b.height) < tol
    }
    func overlaps(_ fs: [CGRect?]) -> Bool {
        let rects = fs.compactMap { $0 }
        for i in rects.indices { for j in rects.indices where j > i {
            if rects[i].intersects(rects[j]) && rects[i].intersection(rects[j]).width > 0.01 && rects[i].intersection(rects[j]).height > 0.01 { return true }
        } }
        return false
    }

    @Test func zeroWindowsIsEmpty() { #expect(LayoutEngine.frames(.grid, count: 0, focused: 0, in: r, gap: 0).isEmpty) }
    @Test func maximizeShowsOnlyFocused() {
        let f = LayoutEngine.frames(.maximize, count: 3, focused: 1, in: r, gap: 8)
        #expect(f[0] == nil && f[2] == nil && eq(f[1], r))
    }
    @Test func splitShowsFocusedAndRightNeighbour() {
        let f = LayoutEngine.frames(.split, count: 4, focused: 1, in: r, gap: 0)
        #expect(f[0] == nil && f[3] == nil)
        #expect(eq(f[1], CGRect(x: 0, y: 0, width: 500, height: 600)))
        #expect(eq(f[2], CGRect(x: 500, y: 0, width: 500, height: 600)))
    }
    @Test func splitAtLastUsesLeftNeighbour() {
        let f = LayoutEngine.frames(.split, count: 3, focused: 2, in: r, gap: 0)
        #expect(f[0] == nil && f[1] != nil && f[2] != nil)
        #expect(f[1]!.minX < f[2]!.minX)
    }
    @Test func splitWithOneFillsRect() { #expect(eq(LayoutEngine.frames(.split, count: 1, focused: 0, in: r, gap: 8)[0], r)) }
    @Test func columnDividesWithGaps() {
        let f = LayoutEngine.frames(.column, count: 4, focused: 0, in: r, gap: 10)
        #expect(f.allSatisfy { $0 != nil })
        #expect(eq(f[0], CGRect(x: 0, y: 0, width: 242.5, height: 600)))
        #expect(eq(f[3], CGRect(x: 757.5, y: 0, width: 242.5, height: 600)))
    }
    @Test func halfStacksRest() {
        let f = LayoutEngine.frames(.half, count: 4, focused: 0, in: r, gap: 0)
        #expect(eq(f[0], CGRect(x: 0, y: 0, width: 500, height: 600)))
        #expect(eq(f[1], CGRect(x: 500, y: 0, width: 500, height: 200)))
        #expect(eq(f[3], CGRect(x: 500, y: 400, width: 500, height: 200)))
    }
    @Test func gridFiveIsThreeByTwoWithWideLastRow() {
        let f = LayoutEngine.frames(.grid, count: 5, focused: 0, in: r, gap: 0)
        #expect(f.compactMap { $0 }.count == 5)
        #expect(eq(f[0], CGRect(x: 0, y: 0, width: 1000/3, height: 300)))
        #expect(eq(f[3], CGRect(x: 0, y: 300, width: 500, height: 300)))
        #expect(eq(f[4], CGRect(x: 500, y: 300, width: 500, height: 300)))
    }
    @Test func neverOverlapsAcrossLayouts() {
        for l in Layout.allCases { for n in 1...9 { for f in 0..<n {
            #expect(!overlaps(LayoutEngine.frames(l, count: n, focused: f, in: r, gap: 6)), "\(l) n=\(n) f=\(f)")
        } } }
    }
    @Test func focusedOutOfRangeIsClamped() {
        #expect(LayoutEngine.frames(.maximize, count: 2, focused: 9, in: r, gap: 0)[1] != nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test --filter LayoutTests` → compile error.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum LayoutEngine {
    /// One entry per tiled window index; nil means this layout parks that window. Spec §5.
    public static func frames(_ layout: Layout, count: Int, focused: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
        guard count > 0 else { return [] }
        let f = min(max(focused, 0), count - 1)
        switch layout {
        case .maximize:
            var out = [CGRect?](repeating: nil, count: count); out[f] = rect; return out
        case .split:
            if count == 1 { return [rect] }
            let (a, b) = f == count - 1 ? (f - 1, f) : (f, f + 1)
            let cols = columns(2, in: rect, gap: gap)
            var out = [CGRect?](repeating: nil, count: count); out[a] = cols[0]; out[b] = cols[1]; return out
        case .column:
            return columns(count, in: rect, gap: gap)
        case .half:
            if count == 1 { return [rect] }
            let cols = columns(2, in: rect, gap: gap)
            return [cols[0]] + rows(count - 1, in: cols[1], gap: gap)
        case .grid:
            let cols = Int(Double(count).squareRoot().rounded(.up))
            let nRows = Int((Double(count) / Double(cols)).rounded(.up))
            let rowRects = rows(nRows, in: rect, gap: gap)
            var out: [CGRect?] = []
            for r in 0..<nRows { out += columns(min(cols, count - r * cols), in: rowRects[r], gap: gap) }
            return out
        }
    }

    static func columns(_ n: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
        let w = (rect.width - gap * CGFloat(n - 1)) / CGFloat(n)
        return (0..<n).map { CGRect(x: rect.minX + CGFloat($0) * (w + gap), y: rect.minY, width: w, height: rect.height) }
    }
    static func rows(_ n: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
        let h = (rect.height - gap * CGFloat(n - 1)) / CGFloat(n)
        return (0..<n).map { CGRect(x: rect.minX, y: rect.minY + CGFloat($0) * (h + gap), width: rect.width, height: h) }
    }
}
```

- [ ] **Step 4: Run** — `swift test --filter LayoutTests` → all pass.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(kit): layout engine for maximize/split/column/half/grid"`

---

### Task 5: Commands

**Files:**
- Create: `Sources/SpacialShellKit/Commands/Command.swift`, `Sources/SpacialShellKit/Commands/CommandRunner.swift`
- Test: `Tests/SpacialShellKitTests/CommandTests.swift`

**Interfaces:**
- Produces: `Vertical {up,down}`, `Horizontal {left,right}`, `Neighbor {prev,next}`, `Command` (11 cases), `Effect {focus(WindowRef), close(WindowRef), relayout}`, `CommandRunner.apply(_:to:) -> (World, [Effect])`. Spec §6.1.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct CommandTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1)
    func base() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1"); w.adopt(c, kind: .tile, on: "D1")
        return w   // focus a on D1[0]
    }
    func run(_ w: World, _ c: Command) -> (World, [Effect]) {
        let r = CommandRunner.apply(c, to: w)
        #expect(r.0.invariantViolations().isEmpty, "after \(c): \(r.0.invariantViolations())")
        return r
    }

    @Test func focusRightWrapsAndAnchors() {
        var w = base()
        (w, _) = run(w, .focusWindow(.right)); #expect(w.focus.window == b)
        (w, _) = run(w, .focusWindow(.right)); (w, _) = run(w, .focusWindow(.right))
        #expect(w.focus.window == a)
        #expect(w.screens["D1"]!.active.anchor == a)
    }
    @Test func focusLeftFromFirstWraps() {
        var w = base(); (w, _) = run(w, .focusWindow(.left)); #expect(w.focus.window == c)
    }
    @Test func focusEmitsFocusAndRelayout() {
        let (_, e) = run(base(), .focusWindow(.right)); #expect(e == [.focus(b), .relayout])
    }
    @Test func focusWorkspaceDownGoesToTrailingEmptyAndNoFurther() {
        var w = base()
        (w, _) = run(w, .focusWorkspace(.down)); #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == nil)
        (w, _) = run(w, .focusWorkspace(.down)); #expect(w.screens["D1"]!.activeIndex == 1)
        (w, _) = run(w, .focusWorkspace(.up)); #expect(w.focus.window == a)
    }
    @Test func focusWorkspaceIndexIsOneBased() {
        var w = base(); (w, _) = run(w, .focusWorkspaceIndex(2)); #expect(w.screens["D1"]!.activeIndex == 1)
        (w, _) = run(w, .focusWorkspaceIndex(9)); #expect(w.screens["D1"]!.activeIndex == 1)   // no-op
    }
    @Test func moveWindowRightSwapsAndStopsAtEnd() {
        var w = base()
        (w, _) = run(w, .moveWindow(.right)); #expect(w.screens["D1"]!.active.windows == [b, a, c])
        (w, _) = run(w, .moveWindow(.right)); (w, _) = run(w, .moveWindow(.right))
        #expect(w.screens["D1"]!.active.windows == [b, c, a] && w.focus.window == a)
    }
    @Test func moveWindowDownCreatesWorkspaceAndFollows() {
        var w = base()
        (w, _) = run(w, .moveWindowToWorkspace(.down))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[b, c], [a], []])
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == a)
        (w, _) = run(w, .moveWindowToWorkspace(.up))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[b, c, a], []])
    }
    @Test func moveWindowUpFromTopIsNoop() {
        let w = base(); let (w2, e) = run(w, .moveWindowToWorkspace(.up)); #expect(w2 == w && e.isEmpty)
    }
    @Test func cycleLayout() {
        var w = base(); (w, _) = run(w, .cycleLayout); #expect(w.screens["D1"]!.active.layout == .split)
    }
    @Test func closeEmitsCloseWithoutMutating() {
        let w = base(); let (w2, e) = run(w, .closeFocusedWindow); #expect(w2 == w && e == [.close(a)])
    }
    @Test func focusScreenNextWraps() {
        var w = base()
        (w, _) = run(w, .focusScreen(.next)); #expect(w.focus.screen == "D2" && w.focus.window == nil)
        (w, _) = run(w, .focusScreen(.next)); #expect(w.focus.screen == "D1" && w.focus.window == a)
    }
    @Test func moveWindowToScreen() {
        var w = base()
        (w, _) = run(w, .moveWindowToScreen(.next))
        #expect(w.screens["D2"]!.active.windows == [a] && w.focus == Focus(screen: "D2", window: a))
        #expect(w.screens["D1"]!.active.windows == [b, c])
    }
    @Test func toggleFloat() {
        var w = base()
        (w, _) = run(w, .toggleFloat); #expect(w.screens["D1"]!.active.floating == [a])
        (w, _) = run(w, .toggleFloat); #expect(w.screens["D1"]!.active.floating.isEmpty)
    }
    @Test func toggleShellUIIsNoop() { let w = base(); #expect(run(w, .toggleShellUI).0 == w) }
    @Test func commandsOnEmptyWorldDontCrash() {
        let w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        for c: Command in [.focusWindow(.left), .moveWindow(.right), .moveWindowToWorkspace(.down), .closeFocusedWindow, .toggleFloat, .moveWindowToScreen(.next), .focusScreen(.prev)] {
            _ = run(w, c)
        }
    }
}
```

- [ ] **Step 2: Run** — `swift test --filter CommandTests` → compile error.

- [ ] **Step 3: Implement Command.swift**

```swift
import Foundation

public enum Vertical: Sendable, Hashable { case up, down }
public enum Horizontal: Sendable, Hashable { case left, right }
public enum Neighbor: Sendable, Hashable { case prev, next }

public enum Command: Sendable, Hashable {
    case focusWorkspace(Vertical)
    case focusWorkspaceIndex(Int)          // 1-based; Fn+0 → 10
    case focusWindow(Horizontal)
    case closeFocusedWindow
    case moveWindow(Horizontal)
    case moveWindowToWorkspace(Vertical)
    case cycleLayout
    case toggleShellUI                     // reserved; no-op in M1
    case focusScreen(Neighbor)
    case moveWindowToScreen(Neighbor)
    case toggleFloat
}

public enum Effect: Sendable, Equatable {
    case focus(WindowRef)
    case close(WindowRef)
    case relayout
}
```

- [ ] **Step 4: Implement CommandRunner.swift**

```swift
import Foundation

public enum CommandRunner {
    public static func apply(_ command: Command, to input: World) -> (World, [Effect]) {
        var w = input
        var effects: [Effect] = []
        let sid = w.focus.screen
        guard let screen = w.screens[sid] else { return (w, []) }

        func setFocus(_ ref: WindowRef?) {
            w.focus.window = ref
            if let ref { w.screens[w.focus.screen]!.workspaces[w.screens[w.focus.screen]!.activeIndex].anchor = ref; effects.append(.focus(ref)) }
        }

        switch command {
        case .focusWindow(let dir):
            let vis = w.visible(in: screen.active)
            guard !vis.isEmpty else { return (w, []) }
            let i = w.focus.window.flatMap { vis.firstIndex(of: $0) } ?? 0
            let j = dir == .right ? (i + 1) % vis.count : (i - 1 + vis.count) % vis.count
            setFocus(vis[j]); effects.append(.relayout)

        case .focusWorkspace(let dir):
            let target = screen.activeIndex + (dir == .down ? 1 : -1)
            guard (0..<screen.workspaces.count).contains(target) else { return (w, []) }
            w.activate(index: target, on: sid)
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .focusWorkspaceIndex(let n):
            let target = n - 1
            guard (0..<screen.workspaces.count).contains(target), target != screen.activeIndex else { return (w, []) }
            w.activate(index: target, on: sid)
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .closeFocusedWindow:
            if let f = w.focus.window { effects.append(.close(f)) }

        case .moveWindow(let dir):
            guard let f = w.focus.window, var ws = Optional(screen.active), let i = ws.windows.firstIndex(of: f) else { return (w, []) }
            let j = dir == .right ? i + 1 : i - 1
            guard (0..<ws.windows.count).contains(j) else { return (w, []) }
            ws.windows.swapAt(i, j)
            w.screens[sid]!.workspaces[screen.activeIndex] = ws
            effects.append(.relayout)

        case .moveWindowToWorkspace(let dir):
            guard let f = w.focus.window, screen.active.windows.contains(f) else { return (w, []) }
            let target = screen.activeIndex + (dir == .down ? 1 : -1)
            guard (0..<screen.workspaces.count).contains(target) else { return (w, []) }
            let wasFloating = screen.active.floating.contains(f)
            w.screens[sid]!.workspaces[screen.activeIndex].windows.removeAll { $0 == f }
            w.screens[sid]!.workspaces[screen.activeIndex].floating.remove(f)
            w.screens[sid]!.workspaces[target].windows.append(f)
            if wasFloating { w.screens[sid]!.workspaces[target].floating.insert(f) }
            w.screens[sid]!.workspaces[target].anchor = f
            w.screens[sid]!.activeIndex = target
            w.focus.window = f
            w.normalize()
            effects.append(.focus(f)); effects.append(.relayout)

        case .cycleLayout:
            w.screens[sid]!.workspaces[screen.activeIndex].layout = screen.active.layout.next
            effects.append(.relayout)

        case .toggleShellUI:
            break

        case .focusScreen(let n):
            guard w.screenOrder.count > 1, let i = w.screenOrder.firstIndex(of: sid) else { return (w, []) }
            let j = n == .next ? (i + 1) % w.screenOrder.count : (i - 1 + w.screenOrder.count) % w.screenOrder.count
            w.focus = Focus(screen: w.screenOrder[j], window: nil)
            w.normalize()
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .moveWindowToScreen(let n):
            guard let f = w.focus.window, screen.active.windows.contains(f), w.screenOrder.count > 1,
                  let i = w.screenOrder.firstIndex(of: sid) else { return (w, []) }
            let j = n == .next ? (i + 1) % w.screenOrder.count : (i - 1 + w.screenOrder.count) % w.screenOrder.count
            let target = w.screenOrder[j]
            let wasFloating = screen.active.floating.contains(f)
            w.screens[sid]!.workspaces[screen.activeIndex].windows.removeAll { $0 == f }
            w.screens[sid]!.workspaces[screen.activeIndex].floating.remove(f)
            let ti = w.screens[target]!.activeIndex
            w.screens[target]!.workspaces[ti].windows.append(f)
            if wasFloating { w.screens[target]!.workspaces[ti].floating.insert(f) }
            w.screens[target]!.workspaces[ti].anchor = f
            w.focus = Focus(screen: target, window: f)
            w.normalize()
            effects.append(.focus(f)); effects.append(.relayout)

        case .toggleFloat:
            guard let f = w.focus.window, screen.active.windows.contains(f) else { return (w, []) }
            w.setFloating(f, !screen.active.floating.contains(f))
            w.normalize()
            effects.append(.relayout)
        }
        return (w, effects)
    }
}
```

- [ ] **Step 5: Run** — `swift test --filter CommandTests` → all pass. `focusEmitsFocusAndRelayout` expects exactly `[.focus(b), .relayout]`; keep that order.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(kit): command runner for the material-shell verb set"`

---

### Task 6: Property tests for invariants

**Files:**
- Create: `Tests/SpacialShellKitTests/Support/TestRNG.swift`, `Tests/SpacialShellKitTests/PropertyTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–5.

- [ ] **Step 1: Write TestRNG**

```swift
import Foundation

/// Deterministic SplitMix64 so failures reproduce from a seed.
struct TestRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
```

- [ ] **Step 2: Write the property tests**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct PropertyTests {
    enum Op { case adopt(WindowKind, DisplayID), remove, hide, unhide, cmd(Command), screens([DisplayID]) }

    func randomOp(_ rng: inout TestRNG, screens: [DisplayID]) -> Op {
        let cmds: [Command] = [.focusWindow(.left), .focusWindow(.right), .focusWorkspace(.up), .focusWorkspace(.down),
            .focusWorkspaceIndex(Int.random(in: 1...4, using: &rng)), .moveWindow(.left), .moveWindow(.right),
            .moveWindowToWorkspace(.up), .moveWindowToWorkspace(.down), .cycleLayout, .focusScreen(.next),
            .focusScreen(.prev), .moveWindowToScreen(.next), .moveWindowToScreen(.prev), .toggleFloat]
        switch Int.random(in: 0..<10, using: &rng) {
        case 0...2: return .adopt([.tile, .tile, .tile, .float, .ephemeral, .ignore].randomElement(using: &rng)!, screens.randomElement(using: &rng)!)
        case 3: return .remove
        case 4: return .hide
        case 5: return .unhide
        case 6: return .screens(Bool.random(using: &rng) ? ["D1"] : ["D1", "D2", "D3"])
        default: return .cmd(cmds.randomElement(using: &rng)!)
        }
    }

    @Test(arguments: 0..<200)
    func randomSequencesPreserveInvariants(seed: Int) {
        var rng = TestRNG(seed: UInt64(seed))
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        var next: WindowID = 1
        var live: [WindowRef] = []
        for step in 0..<60 {
            let op = randomOp(&rng, screens: w.screenOrder)
            switch op {
            case .adopt(let k, let s):
                let r = WindowRef(id: next, pid: 1); next += 1; live.append(r)
                w.adopt(r, kind: k, on: s, parent: Bool.random(using: &rng) ? live.randomElement(using: &rng) : nil)
            case .remove:
                if let r = live.randomElement(using: &rng) { w.remove(r); live.removeAll { $0 == r } }
            case .hide: if let r = live.randomElement(using: &rng) { w.setHidden(r, true) }
            case .unhide: if let r = live.randomElement(using: &rng) { w.setHidden(r, false) }
            case .cmd(let c): w = CommandRunner.apply(c, to: w).0
            case .screens(let s): w.setScreens(s, main: "D1")
            }
            let v = w.invariantViolations()
            #expect(v.isEmpty, "seed \(seed) step \(step) op \(op): \(v)")
            if !v.isEmpty { return }
        }
    }

    @Test(arguments: 0..<50)
    func layoutsNeverOverlap(seed: Int) {
        var rng = TestRNG(seed: UInt64(seed) &+ 99)
        let rect = CGRect(x: 0, y: 0, width: Double.random(in: 300...4000, using: &rng), height: Double.random(in: 200...3000, using: &rng))
        for l in Layout.allCases {
            let n = Int.random(in: 1...12, using: &rng)
            let fs = LayoutEngine.frames(l, count: n, focused: Int.random(in: 0..<n, using: &rng), in: rect, gap: Double.random(in: 0...20, using: &rng)).compactMap { $0 }
            for i in fs.indices { for j in fs.indices where j > i {
                let x = fs[i].intersection(fs[j])
                #expect(x.isNull || x.width < 0.01 || x.height < 0.01, "\(l) n=\(n) overlap \(fs[i]) \(fs[j])")
            } }
        }
    }
}
```

- [ ] **Step 3: Run** — `swift test --filter PropertyTests`. Expected: all 250 cases pass. If any seed fails, fix the model/command code (not the test), then re-run.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "test(kit): property tests for invariants and non-overlap"`

---

### Task 7: Parking geometry

**Files:**
- Create: `Sources/SpacialShellKit/Backend/WindowBackend.swift` (DTOs only in this task; protocol added in Task 8), `Sources/SpacialShellKit/Reconcile/Parking.swift`
- Test: `Tests/SpacialShellKitTests/ParkingTests.swift`

**Interfaces:**
- Produces: `DisplayInfo {id, frame, visibleFrame, isMain}`, `ParkingCorner {bottomRight, bottomLeft}`, `Parking.corner(for:among:) -> ParkingCorner`, `Parking.origin(windowSize:visibleFrame:corner:sliver:) -> CGPoint`. Spec §7.4.

- [ ] **Step 1: Write DisplayInfo (in WindowBackend.swift)**

```swift
import Foundation

public struct DisplayInfo: Equatable, Sendable, Hashable {
    public let id: DisplayID
    public let frame: CGRect          // top-left origin, y-down, global
    public let visibleFrame: CGRect   // minus menu bar and Dock
    public let isMain: Bool
    public init(id: DisplayID, frame: CGRect, visibleFrame: CGRect, isMain: Bool) {
        self.id = id; self.frame = frame; self.visibleFrame = visibleFrame; self.isMain = isMain
    }
}
```

- [ ] **Step 2: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ParkingTests {
    let main = DisplayInfo(id: "M", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055), isMain: true)
    let right = DisplayInfo(id: "R", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 1920, y: 25, width: 1920, height: 1055), isMain: false)
    let below = DisplayInfo(id: "B", frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 1080, width: 1920, height: 1080), isMain: false)

    @Test func singleDisplayParksBottomRight() { #expect(Parking.corner(for: main, among: [main]) == .bottomRight) }
    @Test func displayToTheRightPushesParkingToBottomLeft() { #expect(Parking.corner(for: main, among: [main, right]) == .bottomLeft) }
    @Test func rightDisplayItselfParksBottomRight() { #expect(Parking.corner(for: right, among: [main, right]) == .bottomRight) }
    @Test func bottomRightOriginLeavesOnePixelSliver() {
        let o = Parking.origin(windowSize: CGSize(width: 800, height: 600), visibleFrame: main.visibleFrame, corner: .bottomRight, sliver: 1)
        #expect(o == CGPoint(x: 1919, y: 1079))
    }
    @Test func bottomLeftOriginLeavesOnePixelColumn() {
        let o = Parking.origin(windowSize: CGSize(width: 800, height: 600), visibleFrame: main.visibleFrame, corner: .bottomLeft, sliver: 1)
        #expect(o == CGPoint(x: -799, y: 1079))
    }
    @Test func zeroSliverForZoom() {
        let o = Parking.origin(windowSize: CGSize(width: 800, height: 600), visibleFrame: main.visibleFrame, corner: .bottomRight, sliver: 0)
        #expect(o == CGPoint(x: 1920, y: 1080))
    }
}
```

- [ ] **Step 3: Run** — compile error expected.

- [ ] **Step 4: Implement Parking.swift**

```swift
import Foundation

public enum ParkingCorner: Sendable, Equatable { case bottomRight, bottomLeft }

/// Spec §7.4 — AeroSpace's corner-sliver parking (MacWindow.hideInCorner, refresh.swift OptimalHideCorner).
public enum Parking {
    /// Pick the corner whose probe points fall on the fewest neighbouring displays. Default bottom-right.
    public static func corner(for display: DisplayInfo, among all: [DisplayInfo]) -> ParkingCorner {
        let v = display.visibleFrame
        let others = all.filter { $0.id != display.id }
        func hits(_ probes: [(CGPoint, Int)]) -> Int {
            probes.reduce(0) { acc, p in acc + (others.contains { $0.frame.contains(p.0) } ? p.1 : 0) }
        }
        let dx = v.width * 0.1, dy = v.height * 0.1
        let br = hits([(CGPoint(x: v.maxX + 2, y: v.maxY + 2), 10), (CGPoint(x: v.maxX + dx, y: v.maxY - dy), 1), (CGPoint(x: v.maxX - dx, y: v.maxY + dy), 1)])
        let bl = hits([(CGPoint(x: v.minX - 2, y: v.maxY + 2), 10), (CGPoint(x: v.minX - dx, y: v.maxY - dy), 1), (CGPoint(x: v.minX + dx, y: v.maxY + dy), 1)])
        return bl < br ? .bottomLeft : .bottomRight
    }

    /// Top-left origin that leaves a `sliver`×`sliver` pt corner of the window on screen. sliver 0 for Zoom.
    public static func origin(windowSize: CGSize, visibleFrame v: CGRect, corner: ParkingCorner, sliver: CGFloat) -> CGPoint {
        switch corner {
        case .bottomRight: return CGPoint(x: v.maxX - sliver, y: v.maxY - sliver)
        case .bottomLeft:  return CGPoint(x: v.minX + sliver - windowSize.width, y: v.maxY - sliver)
        }
    }
}
```

- [ ] **Step 5: Run** — `swift test --filter ParkingTests` → pass.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(kit): parking corner selection and sliver origin"`

---

### Task 8: WindowBackend protocol, DTOs, FakeBackend

**Files:**
- Modify: `Sources/SpacialShellKit/Backend/WindowBackend.swift`
- Create: `Tests/SpacialShellKitTests/Support/FakeBackend.swift`
- Test: `Tests/SpacialShellKitTests/FakeBackendTests.swift`

**Interfaces:**
- Produces: `WindowSnapshot`, `AppInfo`, `Snapshot`, `BackendEvent`, `BackendError`, `protocol WindowBackend`, `FakeBackend` (test support). Spec §3.2.

- [ ] **Step 1: Append to WindowBackend.swift**

```swift
public struct AppInfo: Equatable, Sendable, Hashable {
    public let pid: Int32
    public let bundleID: String?
    public let isHidden: Bool
    public init(pid: Int32, bundleID: String?, isHidden: Bool) { self.pid = pid; self.bundleID = bundleID; self.isHidden = isHidden }
}

public struct WindowSnapshot: Equatable, Sendable {
    public let ref: WindowRef
    public let frame: CGRect
    public let title: String
    public let bundleID: String?
    public let kind: WindowKind          // platform heuristic; Kit applies config overrides on top
    public let parent: WindowRef?
    public let isMinimized: Bool
    public let isFullscreen: Bool
    public init(ref: WindowRef, frame: CGRect, title: String, bundleID: String?, kind: WindowKind, parent: WindowRef?, isMinimized: Bool, isFullscreen: Bool) {
        self.ref = ref; self.frame = frame; self.title = title; self.bundleID = bundleID; self.kind = kind
        self.parent = parent; self.isMinimized = isMinimized; self.isFullscreen = isFullscreen
    }
}

/// Full observation of reality. The store diffs it against the model. Spec §7.6.
public struct Snapshot: Equatable, Sendable {
    public var displays: [DisplayInfo]
    public var apps: [AppInfo]
    public var windows: [WindowSnapshot]
    public var focused: WindowRef?
    public var loginwindowFrontmost: Bool
    public init(displays: [DisplayInfo], apps: [AppInfo], windows: [WindowSnapshot], focused: WindowRef?, loginwindowFrontmost: Bool = false) {
        self.displays = displays; self.apps = apps; self.windows = windows; self.focused = focused; self.loginwindowFrontmost = loginwindowFrontmost
    }
}

public enum BackendEvent: Sendable, Equatable {
    case snapshot(Snapshot)
    case windowMoved(WindowRef, CGRect)
    case windowResized(WindowRef, CGRect)
    case focusChanged(WindowRef?)
    case screenLocked
    case screenUnlocked
}

public enum BackendError: Error, Equatable, Sendable { case notFound, timeout, ax(Int32) }

public protocol WindowBackend: Sendable {
    func currentSnapshot() async -> Snapshot
    func setFrame(_ ref: WindowRef, _ frame: CGRect) async -> Result<Void, BackendError>
    func setPosition(_ ref: WindowRef, _ origin: CGPoint) async -> Result<Void, BackendError>
    func raise(_ ref: WindowRef) async -> Result<Void, BackendError>
    func close(_ ref: WindowRef) async -> Result<Void, BackendError>
    var events: AsyncStream<BackendEvent> { get }
}
```

- [ ] **Step 2: Write FakeBackend (test support)**

```swift
import Foundation
@testable import SpacialShellKit

/// In-memory backend: records writes, lets tests push events, applies writes to its own frames.
actor FakeBackend: WindowBackend {
    enum Call: Equatable { case setFrame(WindowRef, CGRect), setPosition(WindowRef, CGPoint), raise(WindowRef), close(WindowRef) }
    var calls: [Call] = []
    var frames: [WindowRef: CGRect] = [:]
    var snapshot: Snapshot
    nonisolated let events: AsyncStream<BackendEvent>
    private let continuation: AsyncStream<BackendEvent>.Continuation

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
        for w in snapshot.windows { frames[w.ref] = w.frame }
        (events, continuation) = AsyncStream.makeStream()
    }
    func currentSnapshot() -> Snapshot { snapshot }
    func setFrame(_ ref: WindowRef, _ frame: CGRect) -> Result<Void, BackendError> { calls.append(.setFrame(ref, frame)); frames[ref] = frame; return .success(()) }
    func setPosition(_ ref: WindowRef, _ o: CGPoint) -> Result<Void, BackendError> {
        calls.append(.setPosition(ref, o)); if let f = frames[ref] { frames[ref] = CGRect(origin: o, size: f.size) }; return .success(())
    }
    func raise(_ ref: WindowRef) -> Result<Void, BackendError> { calls.append(.raise(ref)); return .success(()) }
    func close(_ ref: WindowRef) -> Result<Void, BackendError> { calls.append(.close(ref)); return .success(()) }

    func push(_ e: BackendEvent) { if case .snapshot(let s) = e { snapshot = s; for w in s.windows where frames[w.ref] == nil { frames[w.ref] = w.frame } }; continuation.yield(e) }
    func reset() { calls = [] }
    func finish() { continuation.finish() }
}
```

- [ ] **Step 3: Smoke test**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct FakeBackendTests {
    @Test func recordsWritesAndUpdatesFrames() async {
        let r = WindowRef(id: 1, pid: 1)
        let b = FakeBackend(snapshot: Snapshot(displays: [], apps: [], windows: [WindowSnapshot(ref: r, frame: CGRect(x: 0, y: 0, width: 10, height: 10), title: "", bundleID: nil, kind: .tile, parent: nil, isMinimized: false, isFullscreen: false)], focused: nil))
        _ = await b.setPosition(r, CGPoint(x: 5, y: 5))
        #expect(await b.frames[r] == CGRect(x: 5, y: 5, width: 10, height: 10))
        #expect(await b.calls == [.setPosition(r, CGPoint(x: 5, y: 5))])
    }
}
```

- [ ] **Step 4: Run** — `swift test --filter FakeBackendTests` → pass. `swift build` must still succeed for all targets.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(kit): WindowBackend seam, snapshot DTOs, fake backend"`

---

### Task 9: Reconciler — desired placements and write plan

**Files:**
- Create: `Sources/SpacialShellKit/Reconcile/Reconciler.swift`
- Test: `Tests/SpacialShellKitTests/ReconcilerTests.swift`

**Interfaces:**
- Produces: `LayoutConfig {gap}`, `Placement {frame(CGRect), parked(CGPoint), untouched}`, `Write {setFrame, setPosition}`, `Reconciler.desired(world:displays:config:observed:prePark:parkedNow:zeroSliver:) -> [WindowRef: Placement]`, `Reconciler.plan(desired:observed:parkedNow:) -> [Write]`. Spec §5 (rect derivation), §7.4 (order), §8.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ReconcilerTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1)
    let cfg = LayoutConfig(gap: 10)

    func world() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        return w
    }
    let obs: [WindowRef: CGRect] = [WindowRef(id: 1, pid: 1): CGRect(x: 0, y: 0, width: 300, height: 200), WindowRef(id: 2, pid: 1): CGRect(x: 0, y: 0, width: 400, height: 300)]

    @Test func maximizeFramesFocusedAndParksTheOther() {
        let d = Reconciler.desired(world: world(), displays: [d1], config: cfg, observed: obs, prePark: [:], parkedNow: [], zeroSliver: [])
        // rect = visibleFrame inset by gap, height −1
        #expect(d[a] == .frame(CGRect(x: 10, y: 35, width: 980, height: 654)))
        #expect(d[b] == .parked(CGPoint(x: 999, y: 699)))     // bottom-right sliver of visibleFrame (maxX 1000, maxY 700)
    }
    @Test func inactiveWorkspaceWindowsAreParked() {
        var w = world(); w = CommandRunner.apply(.moveWindowToWorkspace(.down), to: w).0   // a → ws1 (active), b stays ws0
        let d = Reconciler.desired(world: w, displays: [d1], config: cfg, observed: obs, prePark: [:], parkedNow: [], zeroSliver: [])
        #expect(d[b] == .parked(CGPoint(x: 999, y: 699)))
        if case .frame = d[a]! {} else { Issue.record("a should be framed") }
    }
    @Test func floatingVisibleIsUntouchedAndParkedRestoresPrePark() {
        var w = world(); w.setFloating(b, true)
        let d = Reconciler.desired(world: w, displays: [d1], config: cfg, observed: obs, prePark: [:], parkedNow: [], zeroSliver: [])
        #expect(d[b] == .untouched)
        let d2 = Reconciler.desired(world: w, displays: [d1], config: cfg, observed: obs, prePark: [b: CGRect(x: 50, y: 60, width: 400, height: 300)], parkedNow: [b], zeroSliver: [])
        #expect(d2[b] == .frame(CGRect(x: 50, y: 60, width: 400, height: 300)))
    }
    @Test func hiddenAndEphemeralAreUntouchedIgnoredAbsent() {
        var w = world(); w.setHidden(b, true); w.adopt(c, kind: .ephemeral, on: "D1")
        let d = Reconciler.desired(world: w, displays: [d1], config: cfg, observed: obs, prePark: [:], parkedNow: [], zeroSliver: [])
        #expect(d[b] == .untouched && d[c] == .untouched)
    }
    @Test func zeroSliverAppliesToZoom() {
        let d = Reconciler.desired(world: world(), displays: [d1], config: cfg, observed: obs, prePark: [:], parkedNow: [], zeroSliver: [b])
        #expect(d[b] == .parked(CGPoint(x: 1000, y: 700)))
    }
    @Test func planWritesOnlyDeltasUnparkBeforePark() {
        let desired: [WindowRef: Placement] = [a: .frame(CGRect(x: 10, y: 35, width: 980, height: 654)), b: .parked(CGPoint(x: 999, y: 699)), c: .untouched]
        let observed: [WindowRef: CGRect] = [a: CGRect(x: 0, y: 0, width: 300, height: 200), b: CGRect(x: 0, y: 0, width: 400, height: 300), c: .zero]
        let plan = Reconciler.plan(desired: desired, observed: observed, parkedNow: [])
        #expect(plan == [.setFrame(a, CGRect(x: 10, y: 35, width: 980, height: 654)), .setPosition(b, CGPoint(x: 999, y: 699))])
        let again = Reconciler.plan(desired: desired, observed: [a: CGRect(x: 10, y: 35, width: 980, height: 654), b: CGRect(x: 999, y: 699, width: 400, height: 300)], parkedNow: [b])
        #expect(again.isEmpty)
    }
    @Test func planToleratesHalfPointDrift() {
        let plan = Reconciler.plan(desired: [a: .frame(CGRect(x: 10, y: 35, width: 980, height: 654))], observed: [a: CGRect(x: 10.4, y: 35, width: 979.6, height: 654)], parkedNow: [])
        #expect(plan.isEmpty)
    }
}
```

- [ ] **Step 2: Run** — compile error expected.

- [ ] **Step 3: Implement Reconciler.swift**

```swift
import Foundation

public struct LayoutConfig: Sendable, Equatable {
    public var gap: CGFloat
    public init(gap: CGFloat) { self.gap = gap }
}

public enum Placement: Sendable, Equatable { case frame(CGRect), parked(CGPoint), untouched }
public enum Write: Sendable, Equatable { case setFrame(WindowRef, CGRect), setPosition(WindowRef, CGPoint) }

public enum Reconciler {
    static let fallbackSize = CGSize(width: 800, height: 600)

    /// Spec §5, §7.4, §8. Ignored windows are absent from the result.
    public static func desired(world: World, displays: [DisplayInfo], config: LayoutConfig,
                               observed: [WindowRef: CGRect], prePark: [WindowRef: CGRect],
                               parkedNow: Set<WindowRef>, zeroSliver: Set<WindowRef>) -> [WindowRef: Placement] {
        var out: [WindowRef: Placement] = [:]
        let byId = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        for (sid, screen) in world.screens {
            guard let display = byId[sid] else { continue }
            let corner = Parking.corner(for: display, among: displays)
            let visible = display.visibleFrame
            func park(_ w: WindowRef) -> Placement {
                let size = observed[w]?.size ?? fallbackSize
                return .parked(Parking.origin(windowSize: size, visibleFrame: visible, corner: corner, sliver: zeroSliver.contains(w) ? 0 : 1))
            }
            var rect = (screen.rect ?? visible).insetBy(dx: config.gap, dy: config.gap)
            rect.size.height -= 1   // macOS may refuse full-height frames on stacked displays
            for (i, ws) in screen.workspaces.enumerated() {
                let active = i == screen.activeIndex
                let tiled = world.tiled(in: ws)
                let focusedIndex = ws.anchor.flatMap { tiled.firstIndex(of: $0) } ?? 0
                let frames = active ? LayoutEngine.frames(ws.layout, count: tiled.count, focused: focusedIndex, in: rect, gap: config.gap) : []
                for w in ws.windows {
                    if world.hidden.contains(w) { out[w] = .untouched; continue }
                    if !active { out[w] = park(w); continue }
                    if ws.floating.contains(w) {
                        if parkedNow.contains(w) {
                            let restored = prePark[w] ?? centered(size: observed[w]?.size ?? fallbackSize, in: rect)
                            out[w] = .frame(restored)
                        } else { out[w] = .untouched }
                        continue
                    }
                    let ti = tiled.firstIndex(of: w)!
                    out[w] = frames[ti].map { .frame($0) } ?? park(w)
                }
            }
        }
        for w in world.ephemeral { out[w] = .untouched }
        return out
    }

    /// Writes needed to move reality to `desired`. Unparks/frames first, then parks. Stable order by window id.
    public static func plan(desired: [WindowRef: Placement], observed: [WindowRef: CGRect], parkedNow: Set<WindowRef>) -> [Write] {
        var frames: [Write] = [], parks: [Write] = []
        for (w, p) in desired.sorted(by: { $0.key.id < $1.key.id }) {
            switch p {
            case .untouched: continue
            case .frame(let f):
                if let o = observed[w], approx(o, f), !parkedNow.contains(w) { continue }
                frames.append(.setFrame(w, f))
            case .parked(let origin):
                if parkedNow.contains(w), let o = observed[w], approx(o.origin, origin) { continue }
                parks.append(.setPosition(w, origin))
            }
        }
        return frames + parks
    }

    static func centered(size: CGSize, in rect: CGRect) -> CGRect {
        CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
    static func approx(_ a: CGRect, _ b: CGRect, tol: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol && abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
    }
    static func approx(_ a: CGPoint, _ b: CGPoint, tol: CGFloat = 1) -> Bool { abs(a.x - b.x) < tol && abs(a.y - b.y) < tol }
}
```

- [ ] **Step 4: Run** — `swift test --filter ReconcilerTests` → pass. In `maximizeFramesFocusedAndParksTheOther`, `visibleFrame` is `(0,25,1000,675)` → inset 10 → `(10,35,980,655)` → height −1 → 654. ✓
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(kit): reconciler desired placements and write plan"`

---

### Task 10: IntentSet (feedback suppression)

**Files:**
- Create: `Sources/SpacialShellKit/Reconcile/IntentSet.swift`
- Test: `Tests/SpacialShellKitTests/IntentSetTests.swift`

**Interfaces:**
- Produces: `struct IntentSet { mutating func record(_: Write); mutating func matches(_ ref: WindowRef, frame: CGRect) -> Bool; mutating func forget(_ ref: WindowRef) }`. Spec §8.

- [ ] **Step 1: Tests**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct IntentSetTests {
    let a = WindowRef(id: 1, pid: 1)
    @Test func matchingFrameEventIsAbsorbedOnce() {
        var s = IntentSet()
        s.record(.setFrame(a, CGRect(x: 10, y: 10, width: 100, height: 100)))
        #expect(s.matches(a, frame: CGRect(x: 10.5, y: 10, width: 100, height: 99.5)))
        #expect(!s.matches(a, frame: CGRect(x: 10, y: 10, width: 100, height: 100)))   // consumed
    }
    @Test func positionIntentMatchesOriginOnly() {
        var s = IntentSet()
        s.record(.setPosition(a, CGPoint(x: 999, y: 699)))
        #expect(s.matches(a, frame: CGRect(x: 999, y: 699, width: 400, height: 300)))
    }
    @Test func unrelatedFrameDoesNotMatchAndKeepsIntent() {
        var s = IntentSet()
        s.record(.setFrame(a, CGRect(x: 10, y: 10, width: 100, height: 100)))
        #expect(!s.matches(a, frame: CGRect(x: 500, y: 10, width: 100, height: 100)))
        #expect(s.matches(a, frame: CGRect(x: 10, y: 10, width: 100, height: 100)))
    }
    @Test func newerIntentReplacesOlder() {
        var s = IntentSet()
        s.record(.setFrame(a, CGRect(x: 1, y: 1, width: 1, height: 1)))
        s.record(.setFrame(a, CGRect(x: 2, y: 2, width: 2, height: 2)))
        #expect(!s.matches(a, frame: CGRect(x: 1, y: 1, width: 1, height: 1)))
        #expect(s.matches(a, frame: CGRect(x: 2, y: 2, width: 2, height: 2)))
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

/// Remembers frames we asked for so the resulting AX moved/resized notifications are not mistaken for user actions.
public struct IntentSet: Sendable {
    private enum Intent { case frame(CGRect), origin(CGPoint) }
    private var intents: [WindowRef: Intent] = [:]
    public init() {}
    public mutating func record(_ w: Write) {
        switch w {
        case .setFrame(let r, let f): intents[r] = .frame(f)
        case .setPosition(let r, let o): intents[r] = .origin(o)
        }
    }
    /// True if `frame` is what we asked for (±1 pt); the intent is consumed.
    public mutating func matches(_ ref: WindowRef, frame: CGRect, tolerance: CGFloat = 1) -> Bool {
        guard let i = intents[ref] else { return false }
        let hit: Bool
        switch i {
        case .frame(let f): hit = Reconciler.approx(frame, f, tol: tolerance)
        case .origin(let o): hit = Reconciler.approx(frame.origin, o, tol: tolerance)
        }
        if hit { intents[ref] = nil }
        return hit
    }
    public mutating func forget(_ ref: WindowRef) { intents[ref] = nil }
}
```

- [ ] **Step 3: Run** — `swift test --filter IntentSetTests` → pass.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(kit): intent set for AX feedback suppression"`

---

### Task 11: Config and keybindings

**Files:**
- Create: `Sources/SpacialShellKit/Config/Config.swift`, `Sources/SpacialShellKit/Config/KeyBindings.swift`
- Test: `Tests/SpacialShellKitTests/ConfigTests.swift`, `Tests/SpacialShellKitTests/KeyBindingsTests.swift`

**Interfaces:**
- Produces: `AppRule {bundleId, titleRegex}`, `WorkspaceSeed {name, symbol, layout}`, `KeybindingPreset {fn, ctrlAlt}`, `Config` (all fields with defaults; `Config.parse(toml:)`, `Config.load(from:)`, `kindOverride(bundleID:title:) -> WindowKind?`), `Chord {keyCode, fn, control, option, shift, command}`, `KeyCodes.byName`, `KeyBindings.parse(_:) -> Chord?`, `KeyBindings.commandNames: [String: Command]`, `KeyBindings.table(for:) -> [Chord: Command]`. Spec §6.1, §7.3 rule 0, §9.

- [ ] **Step 1: Config tests**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ConfigTests {
    @Test func emptyTomlGivesDefaults() throws {
        let c = try Config.parse(toml: "")
        #expect(c.keybindingPreset == .fn && c.gap == 8 && c.defaultLayout == .maximize && c.axTimeoutMs == 1000 && c.refreshIntervalMs == 2000)
        #expect(c.ephemeral.map(\.bundleId) == ["com.apple.systempreferences", "com.apple.calculator"])
        #expect(c.workspaces.isEmpty)
    }
    @Test func parsesEverything() throws {
        let c = try Config.parse(toml: """
        keybinding-preset = "ctrl-alt"
        gap = 4
        default-layout = "half"
        ax-timeout-ms = 500
        refresh-interval-ms = 1000
        start-at-login = true
        [[workspace]]
        name = "Code"
        symbol = "terminal"
        layout = "half"
        [[float]]
        bundle-id = "com.apple.iphonesimulator"
        [[ignore]]
        bundle-id = "com.example.x"
        title-regex = "^Picture in Picture$"
        [keybindings]
        "fn-shift-g" = "toggle-float"
        """)
        #expect(c.keybindingPreset == .ctrlAlt && c.gap == 4 && c.defaultLayout == .half && c.startAtLogin)
        #expect(c.workspaces == [WorkspaceSeed(name: "Code", symbol: "terminal", layout: .half)])
        #expect(c.float == [AppRule(bundleId: "com.apple.iphonesimulator", titleRegex: nil)])
        #expect(c.ignore.first?.titleRegex == "^Picture in Picture$")
        #expect(c.keybindings == ["fn-shift-g": "toggle-float"])
    }
    @Test func kindOverrideChecksRulesInOrder() throws {
        let c = try Config.parse(toml: """
        [[float]]
        bundle-id = "com.x"
        [[ignore]]
        bundle-id = "com.x"
        title-regex = "PiP"
        """)
        #expect(c.kindOverride(bundleID: "com.x", title: "Main") == .float)
        #expect(c.kindOverride(bundleID: "com.x", title: "PiP") == .float)   // float listed first wins... no: rule order is ephemeral, float, ignore → float wins
        #expect(c.kindOverride(bundleID: "com.apple.calculator", title: "") == .ephemeral)
        #expect(c.kindOverride(bundleID: "com.other", title: "") == nil)
    }
    @Test func invalidTomlThrows() {
        #expect(throws: (any Error).self) { try Config.parse(toml: "gap = ") }
    }
}
```

- [ ] **Step 2: KeyBindings tests**

```swift
import Testing
@testable import SpacialShellKit

@Suite struct KeyBindingsTests {
    @Test func parsesChords() {
        #expect(KeyBindings.parse("fn-w") == Chord(keyCode: 13, fn: true, control: false, option: false, shift: false, command: false))
        #expect(KeyBindings.parse("ctrl-alt-shift-left") == Chord(keyCode: 123, fn: false, control: true, option: true, shift: true, command: false))
        #expect(KeyBindings.parse("fn-space")?.keyCode == 49)
        #expect(KeyBindings.parse("bogus-w") == nil)
        #expect(KeyBindings.parse("fn-nokey") == nil)
    }
    @Test func fnPresetHasMaterialShellDefaults() throws {
        let t = KeyBindings.table(for: try Config.parse(toml: ""))
        #expect(t[KeyBindings.parse("fn-w")!] == .focusWorkspace(.up))
        #expect(t[KeyBindings.parse("fn-shift-d")!] == .moveWindow(.right))
        #expect(t[KeyBindings.parse("fn-0")!] == .focusWorkspaceIndex(10))
        #expect(t[KeyBindings.parse("fn-q")!] == .closeFocusedWindow)
        #expect(t[KeyBindings.parse("fn-space")!] == .cycleLayout)
        #expect(t[KeyBindings.parse("fn-esc")!] == .toggleShellUI)
        #expect(t[KeyBindings.parse("fn-g")!] == .toggleFloat)
        #expect(t[KeyBindings.parse("fn-rightSquareBracket")!] == .focusScreen(.next))
        #expect(t[KeyBindings.parse("ctrl-alt-up")!] == .focusWorkspace(.up))          // arrows always on ctrl-alt
        #expect(t[KeyBindings.parse("ctrl-alt-shift-right")!] == .moveWindow(.right))
        #expect(t[KeyBindings.parse("fn-f")] == nil)                                     // Globe+F is Apple's
    }
    @Test func ctrlAltPresetAndOverrides() throws {
        let t = KeyBindings.table(for: try Config.parse(toml: "keybinding-preset = \"ctrl-alt\"\n[keybindings]\n\"ctrl-alt-x\" = \"toggle-float\"\n"))
        #expect(t[KeyBindings.parse("ctrl-alt-w")!] == .focusWorkspace(.up))
        #expect(t[KeyBindings.parse("fn-w")!] == nil)
        #expect(t[KeyBindings.parse("ctrl-alt-x")!] == .toggleFloat)
    }
}
```

- [ ] **Step 3: Implement Config.swift**

```swift
import Foundation
import TOMLDecoder

public struct AppRule: Codable, Equatable, Sendable {
    public var bundleId: String
    public var titleRegex: String?
    public init(bundleId: String, titleRegex: String? = nil) { self.bundleId = bundleId; self.titleRegex = titleRegex }
    enum CodingKeys: String, CodingKey { case bundleId = "bundle-id", titleRegex = "title-regex" }
    func matches(bundleID: String?, title: String) -> Bool {
        guard bundleID == bundleId else { return false }
        guard let re = titleRegex else { return true }
        return title.range(of: re, options: .regularExpression) != nil
    }
}

public struct WorkspaceSeed: Codable, Equatable, Sendable {
    public var name: String
    public var symbol: String
    public var layout: Layout
    public init(name: String, symbol: String = "square.grid.2x2", layout: Layout = .maximize) { self.name = name; self.symbol = symbol; self.layout = layout }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        layout = try c.decodeIfPresent(Layout.self, forKey: .layout) ?? .maximize
    }
}

public enum KeybindingPreset: String, Codable, Sendable { case fn, ctrlAlt = "ctrl-alt" }

public struct Config: Codable, Equatable, Sendable {
    public var keybindingPreset: KeybindingPreset = .fn
    public var gap: Double = 8
    public var defaultLayout: Layout = .maximize
    public var axTimeoutMs: Int = 1000
    public var refreshIntervalMs: Int = 2000
    public var startAtLogin: Bool = false
    public var workspaces: [WorkspaceSeed] = []
    public var ephemeral: [AppRule] = Config.defaultEphemeral
    public var float: [AppRule] = []
    public var ignore: [AppRule] = []
    public var keybindings: [String: String] = [:]

    public static let defaultEphemeral = [AppRule(bundleId: "com.apple.systempreferences"), AppRule(bundleId: "com.apple.calculator")]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case keybindingPreset = "keybinding-preset", gap, defaultLayout = "default-layout", axTimeoutMs = "ax-timeout-ms",
             refreshIntervalMs = "refresh-interval-ms", startAtLogin = "start-at-login", workspaces = "workspace",
             ephemeral, float, ignore, keybindings
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        keybindingPreset = try c.decodeIfPresent(KeybindingPreset.self, forKey: .keybindingPreset) ?? .fn
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 8
        defaultLayout = try c.decodeIfPresent(Layout.self, forKey: .defaultLayout) ?? .maximize
        axTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .axTimeoutMs) ?? 1000
        refreshIntervalMs = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMs) ?? 2000
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        workspaces = try c.decodeIfPresent([WorkspaceSeed].self, forKey: .workspaces) ?? []
        ephemeral = try c.decodeIfPresent([AppRule].self, forKey: .ephemeral) ?? Config.defaultEphemeral
        float = try c.decodeIfPresent([AppRule].self, forKey: .float) ?? []
        ignore = try c.decodeIfPresent([AppRule].self, forKey: .ignore) ?? []
        keybindings = try c.decodeIfPresent([String: String].self, forKey: .keybindings) ?? [:]
    }

    public static func parse(toml: String) throws -> Config { try TOMLDecoder().decode(Config.self, from: toml) }
    public static func load(from url: URL) throws -> Config { try parse(toml: String(contentsOf: url, encoding: .utf8)) }

    /// Spec §7.3 rule 0: config wins over heuristics. Order: ephemeral, float, ignore.
    public func kindOverride(bundleID: String?, title: String) -> WindowKind? {
        if ephemeral.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .ephemeral }
        if float.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .float }
        if ignore.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .ignore }
        return nil
    }
}
```
Note: `TOMLDecoder().decode(_:from: String)` — check the package's API on first compile; 0.4.x exposes `decode<T>(_: T.Type, from: String)`. If it only accepts `Data`, pass `Data(toml.utf8)`.

- [ ] **Step 4: Implement KeyBindings.swift**

```swift
import Foundation

public struct Chord: Hashable, Sendable {
    public var keyCode: UInt16
    public var fn: Bool, control: Bool, option: Bool, shift: Bool, command: Bool
    public init(keyCode: UInt16, fn: Bool, control: Bool, option: Bool, shift: Bool, command: Bool) {
        self.keyCode = keyCode; self.fn = fn; self.control = control; self.option = option; self.shift = shift; self.command = command
    }
}

public enum KeyCodes {
    /// kVK_ANSI_* virtual key codes (US layout positions).
    public static let byName: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24, "9": 25, "7": 26, "minus": 27, "8": 28,
        "0": 29, "rightSquareBracket": 30, "o": 31, "u": 32, "leftSquareBracket": 33, "i": 34, "p": 35, "enter": 36, "l": 37,
        "j": 38, "quote": 39, "k": 40, "semicolon": 41, "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47,
        "tab": 48, "space": 49, "backtick": 50, "backspace": 51, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}

public enum KeyBindings {
    public static let commandNames: [String: Command] = [
        "focus-workspace-up": .focusWorkspace(.up), "focus-workspace-down": .focusWorkspace(.down),
        "focus-window-left": .focusWindow(.left), "focus-window-right": .focusWindow(.right),
        "close-window": .closeFocusedWindow,
        "move-window-left": .moveWindow(.left), "move-window-right": .moveWindow(.right),
        "move-window-up": .moveWindowToWorkspace(.up), "move-window-down": .moveWindowToWorkspace(.down),
        "cycle-layout": .cycleLayout, "toggle-shell-ui": .toggleShellUI,
        "focus-screen-prev": .focusScreen(.prev), "focus-screen-next": .focusScreen(.next),
        "move-window-to-screen-prev": .moveWindowToScreen(.prev), "move-window-to-screen-next": .moveWindowToScreen(.next),
        "toggle-float": .toggleFloat,
        "focus-workspace-1": .focusWorkspaceIndex(1), "focus-workspace-2": .focusWorkspaceIndex(2), "focus-workspace-3": .focusWorkspaceIndex(3),
        "focus-workspace-4": .focusWorkspaceIndex(4), "focus-workspace-5": .focusWorkspaceIndex(5), "focus-workspace-6": .focusWorkspaceIndex(6),
        "focus-workspace-7": .focusWorkspaceIndex(7), "focus-workspace-8": .focusWorkspaceIndex(8), "focus-workspace-9": .focusWorkspaceIndex(9),
        "focus-workspace-10": .focusWorkspaceIndex(10),
    ]

    /// "fn-shift-g" → Chord. Modifiers: fn, ctrl, alt, shift, cmd. Last token is a KeyCodes name.
    public static func parse(_ s: String) -> Chord? {
        var parts = s.lowercased().split(separator: "-").map(String.init)
        guard let keyName = parts.popLast() else { return nil }
        let keyLookup = KeyCodes.byName.first { $0.key.lowercased() == keyName }?.value
        guard let keyCode = keyLookup else { return nil }
        var c = Chord(keyCode: keyCode, fn: false, control: false, option: false, shift: false, command: false)
        for m in parts {
            switch m {
            case "fn": c.fn = true
            case "ctrl", "control": c.control = true
            case "alt", "option": c.option = true
            case "shift": c.shift = true
            case "cmd", "command": c.command = true
            default: return nil
            }
        }
        return c
    }

    static let core: [(String, String)] = [   // (key suffix, command name)
        ("w", "focus-workspace-up"), ("s", "focus-workspace-down"), ("a", "focus-window-left"), ("d", "focus-window-right"),
        ("q", "close-window"), ("shift-a", "move-window-left"), ("shift-d", "move-window-right"),
        ("shift-w", "move-window-up"), ("shift-s", "move-window-down"), ("space", "cycle-layout"), ("esc", "toggle-shell-ui"),
        ("leftSquareBracket", "focus-screen-prev"), ("rightSquareBracket", "focus-screen-next"),
        ("shift-leftSquareBracket", "move-window-to-screen-prev"), ("shift-rightSquareBracket", "move-window-to-screen-next"),
        ("g", "toggle-float"),
        ("1", "focus-workspace-1"), ("2", "focus-workspace-2"), ("3", "focus-workspace-3"), ("4", "focus-workspace-4"), ("5", "focus-workspace-5"),
        ("6", "focus-workspace-6"), ("7", "focus-workspace-7"), ("8", "focus-workspace-8"), ("9", "focus-workspace-9"), ("0", "focus-workspace-10"),
    ]
    static let arrows: [(String, String)] = [
        ("ctrl-alt-up", "focus-workspace-up"), ("ctrl-alt-down", "focus-workspace-down"), ("ctrl-alt-left", "focus-window-left"), ("ctrl-alt-right", "focus-window-right"),
        ("ctrl-alt-shift-up", "move-window-up"), ("ctrl-alt-shift-down", "move-window-down"), ("ctrl-alt-shift-left", "move-window-left"), ("ctrl-alt-shift-right", "move-window-right"),
    ]

    public static func table(for config: Config) -> [Chord: Command] {
        var t: [Chord: Command] = [:]
        let prefix = config.keybindingPreset == .fn ? "fn-" : "ctrl-alt-"
        for (k, name) in core { if let ch = parse(prefix + k), let cmd = commandNames[name] { t[ch] = cmd } }
        for (k, name) in arrows { if let ch = parse(k), let cmd = commandNames[name] { t[ch] = cmd } }
        for (k, name) in config.keybindings { if let ch = parse(k), let cmd = commandNames[name] { t[ch] = cmd } }
        return t
    }
}
```

- [ ] **Step 5: Run** — `swift test --filter "ConfigTests|KeyBindingsTests"` → pass. First build fetches TOMLDecoder; if offline, `swift package resolve` first.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(kit): TOML config, app rules, workspace seeds, keybinding presets"`

---

### Task 12: Persisted state

**Files:**
- Create: `Sources/SpacialShellKit/State/PersistedState.swift`
- Test: `Tests/SpacialShellKitTests/PersistedStateTests.swift`

**Interfaces:**
- Produces: `PersistedState {version, screens: [DisplayID: ScreenState]}`, `PersistedState(world:)`, `restore(into world: World) -> World` (re-adds pinned/named workspaces per screen; keeps existing), `load(from:) throws -> PersistedState?`, `save(to:) throws`. Also `World.seeded(screens:config:)` helper: empty world with config workspaces (pinned) on every screen. Spec §9.

- [ ] **Step 1: Tests**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct PersistedStateTests {
    @Test func roundTripsThroughJSON() throws {
        var w = World.seeded(screens: ["D1"], config: { var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code", symbol: "terminal", layout: .half)]; return c }())
        w.screens["D1"]!.activeIndex = 0
        let s = PersistedState(world: w)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("spacial-\(UUID()).json")
        try s.save(to: url)
        let back = try PersistedState.load(from: url)
        #expect(back == s)
        #expect(back?.screens["D1"]?.workspaces.first?.name == "Code")
    }
    @Test func loadMissingFileIsNil() throws {
        #expect(try PersistedState.load(from: URL(fileURLWithPath: "/nonexistent/x.json")) == nil)
    }
    @Test func restoreRebuildsPinnedWorkspacesAndActiveIndex() throws {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code", layout: .half), WorkspaceSeed(name: "Web", layout: .split)]
        var w = World.seeded(screens: ["D1"], config: c)
        w.activate(index: 1, on: "D1")
        let s = PersistedState(world: w)
        let fresh = s.restore(into: World.empty(screens: ["D1", "D2"], defaultLayout: .maximize))
        #expect(fresh.screens["D1"]!.workspaces.map(\.name) == ["Code", "Web", "Workspace"])
        #expect(fresh.screens["D1"]!.workspaces[1].layout == .split)
        #expect(fresh.screens["D1"]!.activeIndex == 1)
        #expect(fresh.screens["D2"]!.workspaces.count == 1)     // unknown screen untouched
        #expect(fresh.invariantViolations().isEmpty)
    }
    @Test func seededWorldPinsConfigWorkspaces() {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code")]
        let w = World.seeded(screens: ["D1"], config: c)
        #expect(w.screens["D1"]!.workspaces.map(\.pinned) == [true, false])
        #expect(w.invariantViolations().isEmpty)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public struct PersistedState: Codable, Equatable, Sendable {
    public struct WorkspaceState: Codable, Equatable, Sendable {
        public var id: UUID; public var name: String; public var symbol: String; public var layout: Layout; public var pinned: Bool
    }
    public struct ScreenState: Codable, Equatable, Sendable {
        public var workspaces: [WorkspaceState]; public var activeIndex: Int
    }
    public var version: Int = 1
    public var screens: [DisplayID: ScreenState]

    public init(world: World) {
        screens = world.screens.mapValues { s in
            ScreenState(workspaces: s.workspaces.map { WorkspaceState(id: $0.id, name: $0.name, symbol: $0.symbol, layout: $0.layout, pinned: $0.pinned) },
                        activeIndex: s.activeIndex)
        }
    }

    /// Re-creates pinned workspaces (empty) on screens the state knows; unpinned ones are dropped
    /// (their windows are gone anyway); trailing empty and invariants restored by normalize().
    public func restore(into world: World) -> World {
        var w = world
        for (id, ss) in screens {
            guard var screen = w.screens[id] else { continue }
            let restored = ss.workspaces.filter(\.pinned).map { Workspace(id: $0.id, name: $0.name, symbol: $0.symbol, layout: $0.layout, pinned: true) }
            let existing = screen.workspaces.filter { !$0.isEmpty || $0.pinned }
            let ids = Set(restored.map(\.id))
            screen.workspaces = restored + existing.filter { !ids.contains($0.id) }
            screen.activeIndex = min(max(ss.activeIndex, 0), max(screen.workspaces.count - 1, 0))
            w.screens[id] = screen
        }
        w.normalize()
        return w
    }

    public static func load(from url: URL) throws -> PersistedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: url))
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}

extension World {
    /// Empty world where every screen starts with the config's pinned workspaces, then a trailing empty.
    public static func seeded(screens ids: [DisplayID], config: Config) -> World {
        var w = World.empty(screens: ids, defaultLayout: config.defaultLayout)
        for id in ids {
            let seeds = config.workspaces.map { Workspace(name: $0.name, symbol: $0.symbol, layout: $0.layout, pinned: true) }
            w.screens[id]!.workspaces = seeds + w.screens[id]!.workspaces
            w.screens[id]!.activeIndex = 0
        }
        w.normalize()
        return w
    }
}
```

- [ ] **Step 3: Run** — `swift test --filter PersistedStateTests` → pass.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(kit): persisted state and seeded worlds"`

---

### Task 13: WorldStore actor

**Files:**
- Create: `Sources/SpacialShellKit/Store/WorldStore.swift`
- Test: `Tests/SpacialShellKitTests/WorldStoreTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `actor WorldStore { init(backend:config:world:zeroSliverBundleIDs:onChange:); func start() async; func run(_: Command) async; func apply(_: BackendEvent) async; var world: World; func stop() }`. Spec §7.6 (refresh semantics), §7.7 (lock defence), §8, §4.3 (fullscreen/minimized/hidden), focus-follows-native-focus.

- [ ] **Step 1: Tests**

```swift
import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct WorldStoreTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1)
    func win(_ r: WindowRef, _ f: CGRect = CGRect(x: 0, y: 0, width: 300, height: 200), kind: WindowKind = .tile, bundle: String? = "com.x", min: Bool = false, fs: Bool = false, parent: WindowRef? = nil) -> WindowSnapshot {
        WindowSnapshot(ref: r, frame: f, title: "t", bundleID: bundle, kind: kind, parent: parent, isMinimized: min, isFullscreen: fs)
    }
    func snap(_ ws: [WindowSnapshot], focused: WindowRef? = nil, login: Bool = false) -> Snapshot {
        Snapshot(displays: [d1], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false)], windows: ws, focused: focused, loginwindowFrontmost: login)
    }
    func make(_ s: Snapshot) async -> (WorldStore, FakeBackend) {
        let be = FakeBackend(snapshot: s)
        let store = WorldStore(backend: be, config: Config(), world: nil, zeroSliverBundleIDs: ["us.zoom.xos"], onChange: { _ in })
        await store.start()
        return (store, be)
    }

    @Test func startAdoptsAndTiles() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        let w = await store.world
        #expect(w.screens["D1"]!.active.windows == [a, b] && w.focus.window == a)
        let calls = await be.calls
        #expect(calls.contains(.setFrame(a, CGRect(x: 8, y: 33, width: 984, height: 658))))
        #expect(calls.contains(.setPosition(b, CGPoint(x: 999, y: 699))))
        #expect(calls.contains(.raise(a)))
    }
    @Test func newWindowInSnapshotIsAdoptedAtEnd() async {
        let (store, be) = await make(snap([win(a)], focused: a))
        await store.apply(.snapshot(snap([win(a), win(b)], focused: b)))
        let w = await store.world
        #expect(w.screens["D1"]!.active.windows == [a, b] && w.focus.window == b)
        #expect(await be.calls.contains(.setPosition(a, CGPoint(x: 999, y: 699))))   // maximize now anchored on b
    }
    @Test func vanishedWindowIsRemovedUnlessLoginwindow() async {
        let (store, _) = await make(snap([win(a), win(b)], focused: a))
        await store.apply(.snapshot(snap([win(a)], focused: a, login: true)))
        #expect(await store.world.screens["D1"]!.active.windows == [a, b])
        await store.apply(.snapshot(snap([win(a)], focused: a)))
        #expect(await store.world.screens["D1"]!.active.windows == [a])
    }
    @Test func lockFreezesUntilUnlock() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.reset()
        await store.apply(.screenLocked)
        await store.apply(.snapshot(snap([], focused: nil)))
        #expect(await store.world.screens["D1"]!.active.windows == [a, b])
        #expect(await be.calls.isEmpty)
        await be.push(.snapshot(snap([win(a), win(b)], focused: a)))
        await store.apply(.screenUnlocked)
        #expect(await store.world.screens["D1"]!.active.windows == [a, b])
    }
    @Test func ourOwnMovesAreIgnoredExternalMovesSnapBack() async {
        let (store, be) = await make(snap([win(a)], focused: a))
        await be.reset()
        await store.apply(.windowMoved(a, CGRect(x: 8, y: 33, width: 984, height: 658)))   // echo of our write
        #expect(await be.calls.isEmpty)
        await store.apply(.windowMoved(a, CGRect(x: 100, y: 100, width: 984, height: 658)))
        #expect(await be.calls == [.setFrame(a, CGRect(x: 8, y: 33, width: 984, height: 658))])
    }
    @Test func focusOnParkedWindowActivatesItsWorkspace() async {
        let (store, _) = await make(snap([win(a), win(b)], focused: a))
        await store.run(.moveWindowToWorkspace(.down))          // a → ws1 active
        await store.apply(.focusChanged(b))                     // user cmd-tabbed to b (parked in ws0)
        let w = await store.world
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus.window == b)
    }
    @Test func configOverridesHeuristicKind() async {
        var c = Config(); c.float = [AppRule(bundleId: "com.x")]
        let be = FakeBackend(snapshot: snap([win(a)], focused: a))
        let store = WorldStore(backend: be, config: c, world: nil, zeroSliverBundleIDs: [], onChange: { _ in })
        await store.start()
        #expect(await store.world.screens["D1"]!.active.floating == [a])
    }
    @Test func fullscreenIsIgnoredThenReadopted() async {
        let (store, _) = await make(snap([win(a), win(b, fs: true)], focused: a))
        #expect(await store.world.ignored == [b])
        await store.apply(.snapshot(snap([win(a), win(b)], focused: a)))
        #expect(await store.world.screens["D1"]!.active.windows == [a, b])
    }
    @Test func minimizedIsHidden() async {
        let (store, _) = await make(snap([win(a), win(b, min: true)], focused: a))
        #expect(await store.world.hidden == [b])
    }
    @Test func ephemeralIsCenteredOnAdoption() async {
        let (_, be) = await make(snap([win(a, CGRect(x: 0, y: 0, width: 400, height: 300), bundle: "com.apple.calculator")], focused: nil))
        #expect(await be.calls.contains(.setFrame(a, CGRect(x: 300, y: 212.5, width: 400, height: 300))))
    }
    @Test func commandCloseCallsBackend() async {
        let (store, be) = await make(snap([win(a)], focused: a))
        await store.run(.closeFocusedWindow)
        #expect(await be.calls.contains(.close(a)))
    }
    @Test func onChangeFiresWithWorld() async {
        let be = FakeBackend(snapshot: snap([win(a)], focused: a))
        let box = ChangeBox()
        let store = WorldStore(backend: be, config: Config(), world: nil, zeroSliverBundleIDs: [], onChange: { w in Task { await box.set(w) } })
        await store.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await box.value?.screens["D1"]?.active.windows == [a])
    }
}
actor ChangeBox { var value: World?; func set(_ w: World) { value = w } }
```

- [ ] **Step 2: Implement WorldStore.swift**

```swift
import Foundation

public actor WorldStore {
    public private(set) var world: World
    private let backend: any WindowBackend
    private var config: Config
    private let zeroSliverBundleIDs: Set<String>
    private let onChange: @Sendable (World) -> Void

    private var displays: [DisplayInfo] = []
    private var observed: [WindowRef: CGRect] = [:]
    private var prePark: [WindowRef: CGRect] = [:]
    private var parked: Set<WindowRef> = []
    private var bundleIDs: [WindowRef: String] = [:]
    private var fullscreen: Set<WindowRef> = []
    private var intents = IntentSet()
    private var lastRaised: WindowRef?
    private var locked = false
    private var eventTask: Task<Void, Never>?
    private var started = false

    public init(backend: any WindowBackend, config: Config, world: World?, zeroSliverBundleIDs: Set<String>, onChange: @escaping @Sendable (World) -> Void) {
        self.backend = backend; self.config = config; self.zeroSliverBundleIDs = zeroSliverBundleIDs; self.onChange = onChange
        self.world = world ?? World.seeded(screens: [], config: config)
    }

    public func start() async {
        guard !started else { return }; started = true
        await apply(.snapshot(await backend.currentSnapshot()))
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await e in await self.backend.events { await self.apply(e) }
        }
    }
    public func stop() { eventTask?.cancel() }
    public func update(config: Config) async { self.config = config; await reconcile() }

    public func run(_ command: Command) async {
        let (next, effects) = CommandRunner.apply(command, to: world)
        world = next
        for e in effects { if case .close(let r) = e { _ = await backend.close(r) } }
        await reconcile()
    }

    public func apply(_ event: BackendEvent) async {
        switch event {
        case .snapshot(let s):
            if locked { return }
            applySnapshot(s)
        case .windowMoved(let r, let f), .windowResized(let r, let f):
            if intents.matches(r, frame: f) { observed[r] = f; return }
            observed[r] = f
            if locked { return }
            if let ws = world.workspace(containing: r), !ws.floating.contains(r) { /* tiled: snap back */ } else { return }
        case .focusChanged(let r):
            if locked { return }
            applyNativeFocus(r)
        case .screenLocked:
            locked = true; return
        case .screenUnlocked:
            locked = false
            applySnapshot(await backend.currentSnapshot())
        }
        await reconcile()
    }

    // MARK: snapshot → world

    private func applySnapshot(_ s: Snapshot) {
        // displays
        let sorted = s.displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        displays = sorted
        let main = sorted.first(where: \.isMain)?.id ?? sorted.first?.id ?? ""
        if world.screens.isEmpty && !sorted.isEmpty {
            world = World.seeded(screens: sorted.map(\.id), config: config)
        } else {
            world.setScreens(sorted.map(\.id), main: main)
        }
        let hiddenApps = Set(s.apps.filter(\.isHidden).map(\.pid))
        var present: Set<WindowRef> = []
        for w in s.windows {
            present.insert(w.ref)
            observed[w.ref] = w.frame
            bundleIDs[w.ref] = w.bundleID
            let known = world.location(of: w.ref) != nil || world.ephemeral.contains(w.ref) || world.ignored.contains(w.ref)
            if w.isFullscreen {
                if !fullscreen.contains(w.ref) { fullscreen.insert(w.ref); world.remove(w.ref); world.ignored.insert(w.ref) }
                continue
            } else if fullscreen.contains(w.ref) {
                fullscreen.remove(w.ref); world.ignored.remove(w.ref)
            }
            if !known || (!fullscreen.contains(w.ref) && world.location(of: w.ref) == nil && !world.ephemeral.contains(w.ref) && !world.ignored.contains(w.ref)) {
                let kind = config.kindOverride(bundleID: w.bundleID, title: w.title) ?? w.kind
                world.adopt(w.ref, kind: kind, on: screenFor(w.frame), parent: w.parent)
                if kind == .ephemeral { centerEphemeral(w.ref, size: w.frame.size) }
            }
            world.setHidden(w.ref, w.isMinimized || hiddenApps.contains(w.ref.pid))
        }
        if !s.loginwindowFrontmost {
            let all = Set(world.screens.values.flatMap { $0.workspaces.flatMap(\.windows) }).union(world.ephemeral).union(world.ignored)
            for gone in all.subtracting(present) {
                world.remove(gone); observed[gone] = nil; prePark[gone] = nil; parked.remove(gone); bundleIDs[gone] = nil; fullscreen.remove(gone); intents.forget(gone)
            }
        }
        applyNativeFocus(s.focused)
    }

    private func applyNativeFocus(_ r: WindowRef?) {
        guard let r else { return }
        if world.ephemeral.contains(r) { world.focus.window = r; return }
        guard let loc = world.location(of: r), !world.hidden.contains(r) else { return }
        if world.screens[loc.screen]!.activeIndex != loc.index { world.activate(index: loc.index, on: loc.screen) }
        world.focus = Focus(screen: loc.screen, window: r)
        world.screens[loc.screen]!.workspaces[loc.index].anchor = r
        world.normalize()
    }

    private func screenFor(_ frame: CGRect) -> DisplayID {
        var best: (DisplayID, CGFloat)? = nil
        for d in displays {
            let a = d.frame.intersection(frame); let area = a.isNull ? 0 : a.width * a.height
            if best == nil || area > best!.1 { best = (d.id, area) }
        }
        return best?.0 ?? world.focus.screen
    }

    private var pendingCenter: [(WindowRef, CGSize)] = []
    private func centerEphemeral(_ r: WindowRef, size: CGSize) { pendingCenter.append((r, size)) }

    // MARK: reconcile

    private func reconcile() async {
        let zero = Set(bundleIDs.filter { zeroSliverBundleIDs.contains($0.value) }.map(\.key))
        let desired = Reconciler.desired(world: world, displays: displays, config: LayoutConfig(gap: config.gap),
                                         observed: observed, prePark: prePark, parkedNow: parked, zeroSliver: zero)
        for (r, size) in pendingCenter {
            let d = displays.first { $0.id == world.focus.screen } ?? displays.first
            guard let d else { continue }
            let f = Reconciler.centered(size: size, in: d.visibleFrame)
            intents.record(.setFrame(r, f)); _ = await backend.setFrame(r, f); observed[r] = f
        }
        pendingCenter = []
        for w in Reconciler.plan(desired: desired, observed: observed, parkedNow: parked) {
            intents.record(w)
            switch w {
            case .setFrame(let r, let f):
                _ = await backend.setFrame(r, f); observed[r] = f; parked.remove(r); prePark[r] = nil
            case .setPosition(let r, let o):
                if !parked.contains(r), let cur = observed[r] { prePark[r] = cur }
                _ = await backend.setPosition(r, o)
                if let cur = observed[r] { observed[r] = CGRect(origin: o, size: cur.size) }
                parked.insert(r)
            }
        }
        if let f = world.focus.window, f != lastRaised { lastRaised = f; _ = await backend.raise(f) }
        onChange(world)
    }
}
```
Note on `apply(.windowMoved)`: the code falls through to `reconcile()` for tiled windows (snap back) and returns early for floating/unknown; keep that shape.

- [ ] **Step 3: Run** — `swift test --filter WorldStoreTests`. Expected all pass. `startAdoptsAndTiles` frame: gap 8 → visible (0,25,1000,675) inset 8 → (8,33,984,659) → height −1 → 658 ✓. Ephemeral centre in visibleFrame (0,25,1000,675): x = 500−200 = 300, y = 362.5−150 = 212.5 ✓.
- [ ] **Step 4: Run whole Kit suite** — `swift test --filter SpacialShellKitTests` → all green.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(kit): WorldStore actor — snapshots, native focus, lock defence, reconcile loop"`

---

### Task 14: Lift AeroSpace common helpers, Json, and AX core

**Files:**
- Create under `Sources/SpacialShellPlatform/Lifted/`: `Common/commonUtil.swift`, `Common/AeroAny.swift`, `Common/ConvenienceMutable.swift`, `Common/OptionalEx.swift`, `Common/TaskEx.swift`, `Common/MainActorEx.swift`, `Json.swift`, `accessibility.swift`, `AxSubscription.swift`, `AxUiElementMock.swift`, `ThreadGuardedValue.swift`, `AxAppThreadToken.swift`, `runLoop.swift`, `CompletableFuture.swift`, `AwaitableOneTimeBroadcastLatch.swift`, `dumpAxRecursive.swift`, `axTrustedCheckOptionPrompt.swift`, `NSRunningApplicationEx.swift`, `NsApplicationEx.swift`, `Rect.swift`
- Delete: `Sources/SpacialShellPlatform/Platform.swift` placeholder
- Modify: `NOTICE`

**Interfaces:**
- Produces (used by Tasks 15–18): `enum Ax` attribute descriptors + `AXUIElement.get/set/containingWindowId()`, `AXObserver.new(_:_:)`, `AxSubscription.bulkSubscribe`, `Thread.runInLoop`, `ThreadGuardedValue`, `Rect` (top-left y-down), `check/die/dieT/orDie`.

- [ ] **Step 1: Copy files with headers**

```bash
AERO=/private/tmp/claude-501/-Users-alice-mac-material-shell/aa7fe75f-1297-4120-92ea-463238dbfe97/scratchpad/AeroSpace
L=Sources/SpacialShellPlatform/Lifted; mkdir -p $L/Common
lift() { src="$1"; dst="$2"; { echo "// Adapted from AeroSpace (MIT) — $src @ c548c7f"; cat "$AERO/$src"; } > "$dst"; echo "  $dst" >> NOTICE; }
lift Sources/Common/util/commonUtil.swift        $L/Common/commonUtil.swift
lift Sources/Common/util/AeroAny.swift           $L/Common/AeroAny.swift
lift Sources/Common/util/ConvenienceMutable.swift $L/Common/ConvenienceMutable.swift
lift Sources/Common/util/OptionalEx.swift        $L/Common/OptionalEx.swift
lift Sources/Common/util/TaskEx.swift            $L/Common/TaskEx.swift
lift Sources/Common/util/MainActorEx.swift       $L/Common/MainActorEx.swift
lift Sources/AppBundle/model/Json.swift          $L/Json.swift
lift Sources/AppBundle/util/accessibility.swift  $L/accessibility.swift
lift Sources/AppBundle/util/AxSubscription.swift $L/AxSubscription.swift
lift Sources/AppBundle/util/AxUiElementMock.swift $L/AxUiElementMock.swift
lift Sources/AppBundle/util/ThreadGuardedValue.swift $L/ThreadGuardedValue.swift
lift Sources/Common/model/AxAppThreadToken.swift $L/AxAppThreadToken.swift
lift Sources/AppBundle/runLoop.swift             $L/runLoop.swift
lift Sources/AppBundle/util/CompletableFuture.swift $L/CompletableFuture.swift
lift Sources/AppBundle/util/AwaitableOneTimeBroadcastLatch.swift $L/AwaitableOneTimeBroadcastLatch.swift
lift Sources/AppBundle/util/dumpAxRecursive.swift $L/dumpAxRecursive.swift
lift Sources/AppBundle/util/axTrustedCheckOptionPrompt.swift $L/axTrustedCheckOptionPrompt.swift
lift Sources/AppBundle/util/NSRunningApplicationEx.swift $L/NSRunningApplicationEx.swift
lift Sources/AppBundle/util/NsApplicationEx.swift $L/NsApplicationEx.swift
lift Sources/AppBundle/model/Rect.swift          $L/Rect.swift
git rm -q Sources/SpacialShellPlatform/Platform.swift
```

- [ ] **Step 2: Surgery (make it compile as one module, no `Common` module)**

Apply these edits, then iterate on `swift build` until clean:
1. In every lifted file remove `import Common` and `import PrivateApi` where the symbol isn't used; `accessibility.swift` keeps `import PrivateApi`.
2. `commonUtil.swift`: delete lines defining `socketPath`, `unixUserName`, `mainModeId`, `refreshSessionEvent`, `RefreshSessionEvent`, `exit`, `exitT`, `eprint`, and the `bugPrompt` body's references to `aeroSpaceAppVersion`/`gitHash` — replace `bugPrompt` with:
   ```swift
   public func bugPrompt(_ msg: String, file: String = #fileID, line: Int = #line) -> String {
       "SpacialShell internal error at \(file):\(line): \(msg)\nPlease report at https://github.com/AskAlice/spacial-shell/issues"
   }
   ```
   Keep `check`, `die`, `dieT`, `isUnitTest`, `id`, `throwT`, and the small extensions.
3. `accessibility.swift`: delete `waitForAccessibilityPermission_nonCancellable` and `resetAccessibility` (Task 16 rewrites them without `TrayMenuModel`); delete the `isUnitTest` mock branch inside `AXUIElement.get` (the `if isUnitTest { ... }` block around lines 312–329) and the `serverArgs.isReadOnly` guard in `set` (always perform the set); replace `signposter` calls with nothing (delete the `let state = signposter.beginInterval(...)`/`endInterval` lines) or define `private let signposter = OSSignposter(subsystem: "me.askalice.SpacialShell", category: "ax")` with `import os`.
4. `Json.swift`: keep as is (only depends on `check`/`die`); it needs `import AppKit` for `NSNumber` — already there.
5. `runLoop.swift`: delete the `refreshSessionEvent` propagation (lines ~46–57 that read/write the global); keep `RunLoopJob`, `CancellationMode`, `Thread.runInLoop`, `runInLoopAsync`.
6. `TaskEx.swift`: `Task.startUnstructured` uses `@_inheritActorContext` — keep; it compiles on Swift 6.
7. `Rect.swift`: delete `getDimension(_ orientation:)` (depends on `Orientation`).
8. `dumpAxRecursive.swift`: it defines `kAXAeroSynthetic` and helpers used by mocks; delete anything referencing `TreeNode`/`Window` types if present (grep); keep the AX walk.
9. `NsApplicationEx.swift` / `NSRunningApplicationEx.swift`: keep.
10. Add `import SpacialShellKit` where files need `WindowRef` (none of the lifted files do; only Tasks 16–18 code will).
11. Mark internal (`public` not required) — the module is only consumed by the app target and tests via `@testable`.

- [ ] **Step 3: Build** — `swift build` → clean. Also `swift test --filter SmokeTests` still passes.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "chore(platform): lift AeroSpace AX core, threading, Json and helpers (MIT, attributed)"`

---

### Task 15: Lift the window classifier and its 119-fixture corpus

**Files:**
- Create: `Sources/SpacialShellPlatform/Lifted/{KnownBundleId,AxUiElementWindowType,windowLevelCache}.swift`, `Sources/SpacialShellPlatform/AX/WindowClassifier.swift`, `axDumps/**` (copied), `Tests/SpacialShellPlatformTests/ClassifierCorpusTests.swift`
- Delete: `Tests/SpacialShellPlatformTests/PlatformSmokeTests.swift`
- Modify: `NOTICE`

**Interfaces:**
- Produces: `WindowClassifier.kind(axWindow: AxUiElementMock, axApp: AxUiElementMock, bundleID: String?, activationPolicy: NSApplication.ActivationPolicy, windowLevel: MacOsWindowLevel?) -> WindowKind` mapping `.window→.tile`, `.dialog→.float`, `.popup→.ignore`. Spec §7.3 rules 1–6.

- [ ] **Step 1: Copy**

```bash
AERO=/private/tmp/claude-501/-Users-alice-mac-material-shell/aa7fe75f-1297-4120-92ea-463238dbfe97/scratchpad/AeroSpace
L=Sources/SpacialShellPlatform/Lifted
lift() { src="$1"; dst="$2"; { echo "// Adapted from AeroSpace (MIT) — $src @ c548c7f"; cat "$AERO/$src"; } > "$dst"; echo "  $dst" >> NOTICE; }
lift Sources/AppBundle/model/KnownBundleId.swift $L/KnownBundleId.swift
lift Sources/AppBundle/model/AxUiElementWindowType.swift $L/AxUiElementWindowType.swift
lift Sources/AppBundle/windowLevelCache.swift $L/windowLevelCache.swift
cp -R "$AERO/axDumps" axDumps
echo "  axDumps/** (test fixtures)" >> NOTICE
git rm -q Tests/SpacialShellPlatformTests/PlatformSmokeTests.swift
```

- [ ] **Step 2: Write the corpus test (Swift Testing port of AeroSpace's test)**

```swift
import Testing
import Foundation
import AppKit
@testable import SpacialShellPlatform

@Suite struct ClassifierCorpusTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func allFixturesClassifyAsRecorded() throws {
        var count = 0
        try walk(Self.root.appendingPathComponent("axDumps")) { file in
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file), options: [.json5Allowed]) as! [String: Any]
            let json = Json.newOrDieRecursive(raw).asDictOrDie
            let app = json["Aero.AXApp"]!.asDictOrDie
            let bundle = (raw["Aero.App.appBundleId"] as? String).flatMap { KnownBundleId(rawValue: $0) }
            let level = json["Aero.windowLevel"].map { MacOsWindowLevel.fromJson($0) ?? dieT() }
            let policy = NSApplication.ActivationPolicy.from(string: raw["Aero.App.nsApp.activationPolicy"] as! String)
            let expected = AxUiElementWindowType(rawValue: raw["Aero.AxUiElementWindowType"] as! String)!
            #expect(json.getWindowType(axApp: app, bundle, policy, level) == expected, "\(file.lastPathComponent)")
            #expect(json.isDialogHeuristic(bundle, level) == (raw["Aero.AxUiElementWindowType_isDialogHeuristic"] as! Bool), "\(file.lastPathComponent)")
            count += 1
        }
        #expect(count >= 119)
    }
    func walk(_ dir: URL, _ f: (URL) throws -> Void) throws {
        for u in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) {
            if (try u.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true { try walk(u, f) }
            else if u.pathExtension != "md" { try f(u) }
        }
    }
    @Test func kindMappingIsFixed() {
        #expect(WindowClassifier.kind(for: .window) == .tile)
        #expect(WindowClassifier.kind(for: .dialog) == .float)
        #expect(WindowClassifier.kind(for: .popup) == .ignore)
    }
}
```
Bring the `extension [String: Json]: AxUiElementMock` and `NSApplication.ActivationPolicy.from(string:)` from AeroSpace's `AxUiElementWindowTypeTest.swift` into `Sources/SpacialShellPlatform/Lifted/AxUiElementMock.swift` (they are needed by the mock in production too? No — put them in a new lifted test-support file `Tests/SpacialShellPlatformTests/AxDumpMock.swift` with the attribution header). Replace `assertEquals` with `#expect`.

- [ ] **Step 3: Write WindowClassifier.swift**

```swift
import AppKit
import SpacialShellKit

enum WindowClassifier {
    static func kind(for t: AxUiElementWindowType) -> WindowKind {
        switch t { case .window: .tile; case .dialog: .float; case .popup: .ignore }
    }
    /// Spec §7.3 rules 1–6 (rule 0 — config — is applied by the Kit store).
    static func kind(axWindow: any AxUiElementMock, axApp: any AxUiElementMock, bundleID: String?,
                     activationPolicy: NSApplication.ActivationPolicy, windowLevel: MacOsWindowLevel?) -> WindowKind {
        kind(for: axWindow.getWindowType(axApp: axApp, bundleID.flatMap { KnownBundleId(rawValue: $0) }, activationPolicy, windowLevel))
    }
}
```
If `getWindowType`'s parameter labels differ in the lifted file, match them exactly (read `AxUiElementWindowType.swift`).

- [ ] **Step 4: Run** — `swift test --filter ClassifierCorpusTests` → 2 tests pass, ≥119 fixtures checked.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(platform): window classifier with AeroSpace's AX-dump regression corpus"`

---

### Task 16: AXApp facade — per-app thread, observers, reads, frame writes, parking, focus, close

**Files:**
- Create: `Sources/SpacialShellPlatform/AX/AXApp.swift`, `Sources/SpacialShellPlatform/AX/Permissions.swift`
- Reference for adaptation: AeroSpace `Sources/AppBundle/tree/MacApp.swift:46-100, 102-148, 259-298, 343-436` and `tree/MacWindow.swift:121-187`.

**Interfaces:**
- Produces:
  ```swift
  final class AXApp: @unchecked Sendable {   // one per pid; all AX on its own thread
      let pid: pid_t; let bundleID: String?; let nsApp: NSRunningApplication
      static func getOrCreate(_ app: NSRunningApplication, timeoutMs: Int, onEvent: @escaping @Sendable (AXAppEvent) -> Void) -> AXApp?
      func snapshotWindows() async -> [WindowSnapshot]         // enumerate + classify + frames + parent + minimized/fullscreen
      func focusedWindowRef() async -> WindowRef?
      func setFrame(_ id: WindowID, _ frame: CGRect) async -> Result<Void, BackendError>     // size→pos→size, animations off
      func setPosition(_ id: WindowID, _ origin: CGPoint) async -> Result<Void, BackendError>
      func raise(_ id: WindowID) async -> Result<Void, BackendError>                         // AXMain, AXRaise, activate
      func close(_ id: WindowID) async -> Result<Void, BackendError>                         // press close button
      func setFrameForTermination(_ id: WindowID, _ frame: CGRect)                           // blocking, non-cancellable
      func destroy()
  }
  enum AXAppEvent: Sendable { case windowsChanged, focusChanged, moved(WindowID, CGRect), resized(WindowID, CGRect) }
  enum Permissions { static func waitForAccessibility(bundleID: String) async }
  ```
  Spec §7.1, §7.2, §7.4, §7.5, §7.6.

- [ ] **Step 1: Write AXApp.swift (adapt, do not rewrite)**

Structure to reproduce from `MacApp.swift`, renamed and stripped of tree types:
1. `init` creates `Thread` named `"AxAppThread \(pid)"` running `CFRunLoopRun()` after binding `axTaskLocalAppThreadToken` (lift `getOrRegister` lines 46–100 → `getOrCreate`). Store `AXUIElementCreateApplication(pid)` in a `ThreadGuardedValue`. Call `AXUIElementSetMessagingTimeout(axApp, Float(timeoutMs)/1000)` right after creation (our addition).
2. Observers via `AxSubscription.bulkSubscribe` on the app thread: app-level `kAXWindowCreatedNotification`, `kAXFocusedWindowChangedNotification` → `onEvent(.windowsChanged)`/`.focusChanged`; per-window (subscribe when a window is first seen) `kAXUIElementDestroyedNotification`, `kAXWindowMiniaturizedNotification`, `kAXWindowDeminiaturizedNotification` → `.windowsChanged`; `kAXMovedNotification` → read `Ax.topLeftCornerAttr`+`Ax.sizeAttr` → `.moved(id, rect)`; `kAXResizedNotification` → `.resized(id, rect)`. (MacApp.swift 68–72, 375–383.)
3. `snapshotWindows()`: on app thread, `axApp.get(Ax.windowsAttr)`, for each element `containingWindowId()` (drop nil), read `Ax.topLeftCornerAttr`, `Ax.sizeAttr`, `Ax.titleAttr`, `Ax.minimizedAttr`, `Ax.isFullscreenAttr`, classify with `WindowClassifier.kind(axWindow:axApp:bundleID:activationPolicy:windowLevel:)` using `getWindowLevel(for:)` (MainActor cache → hop with `await MainActor.run`), parent = for `.float` kind read `Ax.parentAttr`? — AeroSpace has no parent attr descriptor; add to `enum Ax` in `accessibility.swift`: `static let parentAttr = ReadableAttrImpl<AXUIElement>(key: kAXParentAttribute, getter: { $0 as! AXUIElement })` and resolve its `containingWindowId()`; if the parent is the app element (not a window) → nil. Build `WindowSnapshot(ref: WindowRef(id:pid:), frame:, title:, bundleID:, kind:, parent:, isMinimized:, isFullscreen:)`.
4. `setFrame`: lift `setAxFrame` + `disableAnimations` (MacApp.swift 411–436): wrap in `AXEnhancedUserInterface=false`, write size, position, size; return `.success` if all sets returned `.success` else `.failure(.ax(code))`. Deduplicate: keep `pendingFrameJob: [WindowID: RunLoopJob]` and cancel the previous one for the same id (MacApp.swift `setFrameJobs`).
5. `setPosition`: same wrapper, position only.
6. `raise`: lift `nativeFocus` (MacApp.swift 130–148): `set(Ax.isMainAttr, true)`, `AXUIElementPerformAction(kAXRaiseAction)`, then on MainActor `nsApp.activate(options: .activateIgnoringOtherApps)`.
7. `close`: get `Ax.closeButtonAttr`, `AXUIElementPerformAction(button, kAXPressAction)`.
8. `setFrameForTermination`: lift `setAxFrameForTermination` (blocking `DispatchSemaphore` variant, MacApp.swift 186–195).
9. `destroy`: stop run loop, destroy `ThreadGuardedValue`s on the app thread (MacApp.swift 343–359).

Window elements: keep `[WindowID: ThreadGuardedValue<AXUIElement>]` so ids resolve to elements for writes; refresh it in `snapshotWindows()`.

- [ ] **Step 2: Write Permissions.swift**

```swift
import AppKit
import ApplicationServices

enum Permissions {
    /// Spec §10. Prompts once, then polls each second; resets TCC on the first retry (signature change).
    static func waitForAccessibility(bundleID: String) async {
        if AXIsProcessTrusted() { return }
        _ = AXIsProcessTrustedWithOptions([axTrustedCheckOptionPrompt: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        var didReset = false
        while !AXIsProcessTrusted() {
            if !didReset { didReset = true; _ = try? Process.run(URL(filePath: "/usr/bin/tccutil"), arguments: ["reset", "Accessibility", bundleID]) }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
```

- [ ] **Step 3: Build** — `swift build` clean. No unit test here (needs AX); it is exercised by Task 21's integration test.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(platform): AXApp per-app facade with parking-safe frame writes"`

---

### Task 17: DisplayTopology

**Files:**
- Create: `Sources/SpacialShellPlatform/Display/DisplayTopology.swift`
- Test: `Tests/SpacialShellPlatformTests/DisplayTopologyTests.swift`

**Interfaces:**
- Produces: `enum DisplayTopology { @MainActor static func current() -> [DisplayInfo]; static func flip(_ r: CGRect, mainHeight: CGFloat) -> CGRect; static func uuid(for screen: NSScreen) -> DisplayID }`. Spec §7.8, §3.2 coordinate rule.

- [ ] **Step 1: Test the pure flip**

```swift
import Testing
import Foundation
@testable import SpacialShellPlatform

@Suite struct DisplayTopologyTests {
    @Test func flipConvertsBottomLeftToTopLeft() {
        // main 1000x700; NSScreen visibleFrame y=0 h=675 (dock 0, menu bar 25) → top-left y = 700-675 = 25
        #expect(DisplayTopology.flip(CGRect(x: 0, y: 0, width: 1000, height: 675), mainHeight: 700) == CGRect(x: 0, y: 25, width: 1000, height: 675))
        // a display above main: NSScreen frame y=700..1400 → top-left y = 700-1400 = -700
        #expect(DisplayTopology.flip(CGRect(x: 0, y: 700, width: 1000, height: 700), mainHeight: 700) == CGRect(x: 0, y: -700, width: 1000, height: 700))
    }
    @Test @MainActor func currentReturnsAtLeastOneDisplayWithUUID() {
        let d = DisplayTopology.current()
        #expect(!d.isEmpty && d.contains(where: \.isMain) && d.allSatisfy { !$0.id.isEmpty })
    }
}
```

- [ ] **Step 2: Implement**

```swift
import AppKit
import SpacialShellKit

enum DisplayTopology {
    /// NSScreen (bottom-left, y-up) → AX (top-left, y-down). mainHeight = height of the screen whose frame origin is (0,0).
    static func flip(_ r: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }
    static func uuid(for screen: NSScreen) -> DisplayID {
        let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        guard let cf = CGDisplayCreateUUIDFromDisplayID(num)?.takeRetainedValue() else { return "display-\(num)" }
        return CFUUIDCreateString(nil, cf) as String
    }
    /// Spec §7.8: main = the screen at origin (0,0), never NSScreen.main.
    @MainActor static func current() -> [DisplayInfo] {
        let screens = NSScreen.screens
        let main = screens.first { $0.frame.origin == .zero } ?? screens.first
        let h = main?.frame.height ?? 0
        return screens.map { s in
            DisplayInfo(id: uuid(for: s), frame: flip(s.frame, mainHeight: h), visibleFrame: flip(s.visibleFrame, mainHeight: h), isMain: s === main)
        }
    }
}
```

- [ ] **Step 3: Run** — `swift test --filter DisplayTopologyTests` → pass.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(platform): display topology with UUID identity and y-flip"`

---

### Task 18: AXWindowBackend — refresh sessions, global observers, event stream, termination restore

**Files:**
- Create: `Sources/SpacialShellPlatform/Backend/RefreshSession.swift`, `Sources/SpacialShellPlatform/Backend/AXWindowBackend.swift`

**Interfaces:**
- Consumes: `AXApp`, `DisplayTopology`, Kit DTOs.
- Produces: `public final class AXWindowBackend: WindowBackend, @unchecked Sendable { public init(config: Config); public func start(); public func restoreAllForTermination(); }`. Spec §7.6, §7.7, §7.4 termination.

- [ ] **Step 1: RefreshSession.swift**

```swift
import AppKit
import SpacialShellKit

/// Builds one Snapshot from every regular app (plus already-registered accessories). Spec §7.6.
struct RefreshSession {
    let apps: AXAppRegistry

    @MainActor func run() async -> Snapshot {
        let displays = DisplayTopology.current()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        var infos: [AppInfo] = []
        var windows: [WindowSnapshot] = []
        for nsApp in running {
            guard let app = apps.getOrCreate(nsApp) else { continue }
            infos.append(AppInfo(pid: app.pid, bundleID: app.bundleID, isHidden: nsApp.isHidden))
            windows += await app.snapshotWindows()
        }
        apps.reapTerminated(alive: Set(running.map(\.processIdentifier)))
        let front = NSWorkspace.shared.frontmostApplication
        let focused = await front.flatMap { apps.get($0.processIdentifier) }?.focusedWindowRef()
        return Snapshot(displays: displays, apps: infos, windows: windows, focused: focused,
                        loginwindowFrontmost: front?.bundleIdentifier == "com.apple.loginwindow")
    }
}

/// pid → AXApp, owned by the backend.
final class AXAppRegistry: @unchecked Sendable {
    private var apps: [pid_t: AXApp] = [:]
    private let lock = NSLock()
    let timeoutMs: Int
    let onEvent: @Sendable (pid_t, AXAppEvent) -> Void
    init(timeoutMs: Int, onEvent: @escaping @Sendable (pid_t, AXAppEvent) -> Void) { self.timeoutMs = timeoutMs; self.onEvent = onEvent }
    func get(_ pid: pid_t) -> AXApp? { lock.withLock { apps[pid] } }
    func getOrCreate(_ nsApp: NSRunningApplication) -> AXApp? {
        lock.withLock {
            if let a = apps[nsApp.processIdentifier] { return a }
            let pid = nsApp.processIdentifier
            guard let a = AXApp.getOrCreate(nsApp, timeoutMs: timeoutMs, onEvent: { [onEvent] e in onEvent(pid, e) }) else { return nil }
            apps[pid] = a; return a
        }
    }
    func reapTerminated(alive: Set<pid_t>) {
        let dead = lock.withLock { apps.filter { !alive.contains($0.key) } }
        for (pid, app) in dead { app.destroy(); lock.withLock { apps[pid] = nil } }
    }
    func all() -> [AXApp] { lock.withLock { Array(apps.values) } }
}
```

- [ ] **Step 2: AXWindowBackend.swift**

```swift
import AppKit
import SpacialShellKit

public final class AXWindowBackend: WindowBackend, @unchecked Sendable {
    public let events: AsyncStream<BackendEvent>
    private let continuation: AsyncStream<BackendEvent>.Continuation
    private let registry: AXAppRegistry
    private let config: Config
    private var observers: [Any] = []
    private var refreshTask: Task<Void, Never>?
    private var periodic: Task<Void, Never>?
    private var mouseDown = false
    private var deferredRefresh = false

    public init(config: Config) {
        self.config = config
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
        var cont: AsyncStream<BackendEvent>.Continuation? = nil
        cont = continuation
        registry = AXAppRegistry(timeoutMs: config.axTimeoutMs) { pid, e in
            switch e {
            case .windowsChanged, .focusChanged: break            // handled by scheduleRefresh below via weak self hop
            case .moved(let id, let r): cont?.yield(.windowMoved(WindowRef(id: id, pid: pid), r))
            case .resized(let id, let r): cont?.yield(.windowResized(WindowRef(id: id, pid: pid), r))
            }
        }
        // second stage: route windowsChanged/focusChanged to a refresh (needs self)
        registry.onEventSelfHook = { [weak self] e in
            switch e { case .windowsChanged: self?.scheduleRefresh(); case .focusChanged: self?.scheduleRefresh(); default: break }
        }
    }
```
Simplify: give `AXAppRegistry` a mutable `var onEventSelfHook: (@Sendable (AXAppEvent) -> Void)?` invoked after `onEvent`; declare it in Task 18's registry (edit `RefreshSession.swift` accordingly).

```swift
    /// Spec §7.6 global observers + periodic backstop. Call once from the main thread.
    @MainActor public func start() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                if (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "com.apple.loginwindow" { return }
                self?.scheduleRefresh()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh() })
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.continuation.yield(.screenLocked) })
        observers.append(dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.continuation.yield(.screenUnlocked) })
        // kAXUIElementDestroyed is unreliable; mouse-up after a close-button click triggers a refresh. New windows are deferred while dragging (tab drag-out).
        observers.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in self?.mouseDown = true } as Any)
        observers.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.mouseDown = false; self?.scheduleRefresh()
        } as Any)
        periodic = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(self?.config.refreshIntervalMs ?? 2000))
                self?.scheduleRefresh()
            }
        }
    }

    /// Cancel any in-flight session and start a new one; the newest snapshot wins.
    private func scheduleRefresh() {
        if mouseDown { deferredRefresh = true; return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snap = await RefreshSession(apps: registry).run()
            if Task.isCancelled { return }
            continuation.yield(.snapshot(snap))
        }
    }

    public func currentSnapshot() async -> Snapshot { await MainActor.run { RefreshSession(apps: registry) }.run() }
    public func setFrame(_ ref: WindowRef, _ frame: CGRect) async -> Result<Void, BackendError> { await registry.get(ref.pid)?.setFrame(ref.id, frame) ?? .failure(.notFound) }
    public func setPosition(_ ref: WindowRef, _ origin: CGPoint) async -> Result<Void, BackendError> { await registry.get(ref.pid)?.setPosition(ref.id, origin) ?? .failure(.notFound) }
    public func raise(_ ref: WindowRef) async -> Result<Void, BackendError> { await registry.get(ref.pid)?.raise(ref.id) ?? .failure(.notFound) }
    public func close(_ ref: WindowRef) async -> Result<Void, BackendError> { await registry.get(ref.pid)?.close(ref.id) ?? .failure(.notFound) }

    /// Spec §7.4: never strand windows in a corner. Blocking; called from the termination path.
    public func restoreAllForTermination(world: World, displays: [DisplayInfo], observed: [WindowRef: CGRect]) {
        for (sid, screen) in world.screens {
            guard let d = displays.first(where: { $0.id == sid }) else { continue }
            for ws in screen.workspaces { for w in ws.windows {
                let size = observed[w]?.size ?? CGSize(width: 800, height: 600)
                let f = CGRect(x: d.visibleFrame.midX - size.width / 2, y: d.visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
                registry.get(w.pid)?.setFrameForTermination(w.id, f)
            } }
        }
    }
}
```
`WorldStore` must expose what termination needs: add `public func exportForTermination() -> (World, [DisplayInfo], [WindowRef: CGRect])` to `WorldStore` (returns `world`, `displays`, `observed`) — add it in this task with a one-line unit test in `WorldStoreTests` asserting the world matches.

- [ ] **Step 3: Build** — `swift build` clean; `swift test --filter SpacialShellKitTests` still green.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(platform): AXWindowBackend with refresh sessions, global observers, termination restore"`

---

### Task 19: HotkeyTap (CGEventTap) + empirical Fn checks

**Files:**
- Create: `Sources/SpacialShellPlatform/Hotkeys/HotkeyTap.swift`, `docs/platform-notes.md`
- Test: `Tests/SpacialShellPlatformTests/HotkeyTapTests.swift` (pure chord-matching only)

**Interfaces:**
- Produces: `public final class HotkeyTap { public init(table: [Chord: Command], onCommand: @escaping @Sendable (Command) -> Void); @MainActor public func start() throws; public func stop(); public func update(table:); static func chord(from flags: CGEventFlags, keyCode: UInt16) -> Chord }`. Spec §6.2, §13.

- [ ] **Step 1: Test the pure flag→Chord mapping**

```swift
import Testing
import CoreGraphics
@testable import SpacialShellPlatform
@testable import SpacialShellKit

@Suite struct HotkeyTapTests {
    @Test func mapsFlagsToChord() {
        let c = HotkeyTap.chord(from: [.maskSecondaryFn, .maskShift], keyCode: 13)
        #expect(c == Chord(keyCode: 13, fn: true, control: false, option: false, shift: true, command: false))
        let d = HotkeyTap.chord(from: [.maskControl, .maskAlternate], keyCode: 126)
        #expect(d == Chord(keyCode: 126, fn: false, control: true, option: true, shift: false, command: false))
    }
    @Test func ignoresIrrelevantFlags() {
        // caps lock / numeric pad / help must not affect matching
        let c = HotkeyTap.chord(from: [.maskSecondaryFn, .maskAlphaShift, .maskNumericPad], keyCode: 0)
        #expect(c == Chord(keyCode: 0, fn: true, control: false, option: false, shift: false, command: false))
    }
}
```

- [ ] **Step 2: Implement HotkeyTap.swift**

```swift
import AppKit
import CoreGraphics
import Carbon.HIToolbox
import SpacialShellKit
import os

public final class HotkeyTap: @unchecked Sendable {
    private var table: [Chord: Command]
    private let onCommand: @Sendable (Command) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let log = Logger(subsystem: "me.askalice.SpacialShell", category: "hotkeys")

    public init(table: [Chord: Command], onCommand: @escaping @Sendable (Command) -> Void) { self.table = table; self.onCommand = onCommand }
    public func update(table: [Chord: Command]) { self.table = table }

    static func chord(from flags: CGEventFlags, keyCode: UInt16) -> Chord {
        Chord(keyCode: keyCode, fn: flags.contains(.maskSecondaryFn), control: flags.contains(.maskControl),
              option: flags.contains(.maskAlternate), shift: flags.contains(.maskShift), command: flags.contains(.maskCommand))
    }

    public enum TapError: Error { case creationFailed }

    /// Session-level active tap; consumes bound chords, passes everything else. Re-enables itself when macOS disables it.
    @MainActor public func start() throws {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.tapDisabledByTimeout.rawValue) | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                          callback: { _, type, event, userInfo in
            let me = Unmanaged<HotkeyTap>.fromOpaque(userInfo!).takeUnretainedValue()
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            case .keyDown:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return Unmanaged.passUnretained(event) }
                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let chord = HotkeyTap.chord(from: event.flags, keyCode: code)
                if let cmd = me.table[chord] {
                    if IsSecureEventInputEnabled() { me.log.warning("secure input active; hotkeys may be unreliable") }
                    me.onCommand(cmd)
                    return nil                                     // consume
                }
                return Unmanaged.passUnretained(event)
            default:
                return Unmanaged.passUnretained(event)
            }
        }, userInfo: selfPtr) else { throw TapError.creationFailed }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    public func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil; tap = nil
    }
}
```

- [ ] **Step 3: Empirical checks (record results in `docs/platform-notes.md`)**

After Task 20 makes the app runnable, run it with a debug env var `SPACIAL_LOG_KEYS=1` that makes the tap log `keyCode` + `flags` for every keyDown, and record:
1. Does `Fn+W` arrive as keyCode 13 with `.maskSecondaryFn`, and is it swallowed (no "w" typed in TextEdit)?
2. Does `Fn+↑` arrive as keyCode 126 with Fn, or as 116 (Page Up)? Note the answer; it decides whether Fn+arrows could ever be bound (spec assumes not).
3. Does the first launch prompt for Input Monitoring in addition to Accessibility?
4. Do `Fn+Q`, `Fn+A`, `Fn+D`, `Fn+S`, `Fn+G`, `Fn+[`, `Fn+]`, `Fn+Space`, `Fn+Esc`, `Fn+1` reach us before macOS acts (any of them showing a system UI = conflict → move that binding and note it)?
Write findings as a table in `docs/platform-notes.md` and, if any default conflicts, change the default in `KeyBindings.core` and its test.

- [ ] **Step 4: Run** — `swift test --filter HotkeyTapTests` → pass; `swift build` clean.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(platform): CGEventTap hotkeys with Fn modifier and self-re-enable"`

---

### Task 20: App target — wiring, onboarding, config watch, state save, signals, dev scripts

**Files:**
- Modify: `Sources/SpacialShell/main.swift`
- Create: `Sources/SpacialShell/AppRuntime.swift`, `Sources/SpacialShell/Paths.swift`, `Scripts/dev.sh`, `Scripts/bundle.sh`, `Resources/Info.plist`

**Interfaces:**
- Consumes: `Config`, `PersistedState`, `WorldStore`, `AXWindowBackend`, `HotkeyTap`, `Permissions`, `KeyBindings`.

- [ ] **Step 1: Paths.swift**

```swift
import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let configDir = home.appendingPathComponent(".config/spacial-shell", isDirectory: true)
    static let configFile = configDir.appendingPathComponent("config.toml")
    static let stateDir = home.appendingPathComponent("Library/Application Support/SpacialShell", isDirectory: true)
    static let stateFile = stateDir.appendingPathComponent("state.json")
    static let bundleID = "me.askalice.SpacialShell"
}
```

- [ ] **Step 2: AppRuntime.swift**

```swift
import AppKit
import SpacialShellKit
import SpacialShellPlatform
import os

@MainActor
final class AppRuntime: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: Paths.bundleID, category: "app")
    private var config = Config()
    private var backend: AXWindowBackend!
    private var store: WorldStore!
    private var tap: HotkeyTap!
    private var saveTask: Task<Void, Never>?
    private var configWatch: DispatchSourceFileSystemObject?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await boot() }
    }

    private func boot() async {
        await Permissions.waitForAccessibility(bundleID: Paths.bundleID)
        loadConfig()
        backend = AXWindowBackend(config: config)
        let restored = try? PersistedState.load(from: Paths.stateFile)
        let seeded = World.seeded(screens: DisplayTopology.current().map(\.id), config: config)
        let initial = restored?.restore(into: seeded) ?? seeded
        store = WorldStore(backend: backend, config: config, world: initial, zeroSliverBundleIDs: ["us.zoom.xos"]) { [weak self] world in
            Task { @MainActor in self?.scheduleSave(world) }
        }
        backend.start()
        await store.start()
        tap = HotkeyTap(table: KeyBindings.table(for: config)) { [weak self] cmd in
            Task { await self?.store.run(cmd) }
        }
        do { try tap.start() } catch { log.error("event tap failed: \(String(describing: error))"); }
        watchConfig()
        installSignalHandlers()
        log.info("SpacialShell running")
    }

    private func loadConfig() {
        do { config = try Config.load(from: Paths.configFile) }
        catch CocoaError.fileReadNoSuchFile { config = Config() }
        catch { log.error("config invalid, keeping previous: \(String(describing: error))") }
    }

    private func watchConfig() {
        try? FileManager.default.createDirectory(at: Paths.configDir, withIntermediateDirectories: true)
        let fd = open(Paths.configDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let old = self.config
            self.loadConfig()
            if self.config != old {
                self.tap.update(table: KeyBindings.table(for: self.config))
                Task { await self.store.update(config: self.config) }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume(); configWatch = src
    }

    private func scheduleSave(_ world: World) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, self != nil else { return }
            do { try PersistedState(world: world).save(to: Paths.stateFile) } catch { self?.log.error("state save failed: \(String(describing: error))") }
        }
    }

    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in self?.terminate() }
            src.resume(); signalSources.append(src)
        }
    }
    private var signalSources: [DispatchSourceSignal] = []

    func applicationWillTerminate(_ n: Notification) { restoreWindows() }
    private func terminate() { restoreWindows(); exit(0) }
    private func restoreWindows() {
        guard let store, let backend else { return }
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            let (world, displays, observed) = await store.exportForTermination()
            backend.restoreAllForTermination(world: world, displays: displays, observed: observed)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 3)
    }
}
```

- [ ] **Step 3: main.swift**

```swift
import AppKit

let app = NSApplication.shared
let runtime = AppRuntime()
app.delegate = runtime
app.run()
```

- [ ] **Step 4: Scripts and Info.plist**

`Scripts/dev.sh`:
```bash
#!/bin/sh
set -e
cd "$(dirname "$0")/.."
swift build
exec .build/debug/SpacialShell
```
`Scripts/bundle.sh` (assembles a minimal .app so TCC identity is stable):
```bash
#!/bin/sh
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=build/SpacialShell.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SpacialShell "$APP/Contents/MacOS/SpacialShell"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier me.askalice.SpacialShell "$APP"
echo "built $APP"
```
`Resources/Info.plist`: `CFBundleIdentifier` `me.askalice.SpacialShell`, `CFBundleName` `SpacialShell`, `CFBundleExecutable` `SpacialShell`, `CFBundleVersion` `0.1.0`, `CFBundleShortVersionString` `0.1.0`, `LSUIElement` `true`, `LSMinimumSystemVersion` `14.0`, `NSPrincipalClass` `NSApplication`, `CFBundlePackageType` `APPL`.
`chmod +x Scripts/*.sh`.

- [ ] **Step 5: Run it** — `Scripts/dev.sh`; grant Accessibility when prompted; open two TextEdit windows; verify `Fn+A/D` switch, `Fn+S/W` move between workspaces, `Fn+Space` cycles layouts, `Fn+⇧S` moves a window down, quitting with Ctrl-C restores windows to the centre. Then do Task 19 Step 3's empirical checks and write `docs/platform-notes.md`.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(app): runtime wiring, onboarding, config watch, state save, termination restore, dev scripts"`

---

### Task 21: Platform integration tests (opt-in)

**Files:**
- Create: `Tests/PlatformIntegrationTests/TextEditTests.swift`; delete `IntegrationSmokeTests.swift`

**Interfaces:**
- Consumes: `AXWindowBackend`, `WorldStore`, `Config`.

- [ ] **Step 1: Write the test**

```swift
import Testing
import AppKit
import Foundation
@testable import SpacialShellKit
@testable import SpacialShellPlatform

/// Runs only with SPACIAL_INTEGRATION=1 and the Accessibility grant for the test host.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SPACIAL_INTEGRATION"] == "1"))
struct TextEditTests {
    static let textEdit = "com.apple.TextEdit"

    @MainActor func openTextEditWindows(_ n: Int) async throws -> NSRunningApplication {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.textEdit)!
        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true; cfg.createsNewApplicationInstance = false
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        for _ in 0..<n {
            let s = NSAppleScript(source: "tell application \"TextEdit\" to make new document")
            s?.executeAndReturnError(nil)
            try await Task.sleep(for: .milliseconds(300))
        }
        return app
    }

    @Test @MainActor func tilesTwoWindowsMaximizeAndParksTheOther() async throws {
        let app = try await openTextEditWindows(2)
        defer { app.terminate() }
        let backend = AXWindowBackend(config: Config())
        let store = WorldStore(backend: backend, config: Config(), world: nil, zeroSliverBundleIDs: [], onChange: { _ in })
        backend.start()
        await store.start()
        try await Task.sleep(for: .seconds(1))
        let w = await store.world
        let te = w.screens.values.flatMap { $0.workspaces.flatMap(\.windows) }.filter { $0.pid == app.processIdentifier }
        #expect(te.count >= 2)
        await store.run(.focusWindow(.right))
        try await Task.sleep(for: .milliseconds(500))
        let snap = await backend.currentSnapshot()
        let frames = Dictionary(uniqueKeysWithValues: snap.windows.filter { $0.ref.pid == app.processIdentifier }.map { ($0.ref, $0.frame) })
        let display = snap.displays.first(where: \.isMain)!
        let visibleOnes = frames.values.filter { display.visibleFrame.insetBy(dx: -2, dy: -2).contains($0) }
        let parkedOnes = frames.values.filter { $0.minX >= display.visibleFrame.maxX - 2 || $0.minX <= display.visibleFrame.minX - $0.width + 2 }
        #expect(visibleOnes.count == 1 && parkedOnes.count >= 1)
        await store.run(.cycleLayout)                        // → split: both visible
        try await Task.sleep(for: .milliseconds(500))
        let snap2 = await backend.currentSnapshot()
        let both = snap2.windows.filter { $0.ref.pid == app.processIdentifier && display.visibleFrame.insetBy(dx: -2, dy: -2).contains($0.frame) }
        #expect(both.count == 2)
    }
}
```

- [ ] **Step 2: Run** — `SPACIAL_INTEGRATION=1 swift test --filter TextEditTests` (grant Accessibility to the `xctest`/`swift-testing` host on first run). Expected: pass. Without the env var the suite is skipped.
- [ ] **Step 3: Commit** — `git add -A && git commit -m "test(platform): opt-in TextEdit integration test for tiling and parking"`

---

### Task 22: Docs — README, testing checklist, config reference

**Files:**
- Modify: `README.md`
- Create: `docs/testing.md`, `docs/config.md`

- [ ] **Step 1: README.md** — sections: what it is (2 paragraphs, lineage: material-shell → Veshell → SpacialShell), status (M1), install (`Scripts/bundle.sh`, move to /Applications, grant Accessibility), the hotkey table from spec §6.1 (both presets, arrows), workspace model in five bullets (§4.2 invariants in plain words), known limitations (one native Space per display; Mission Control/Cmd-Tab see parked windows; no UI yet), licence + attribution to AeroSpace.
- [ ] **Step 2: docs/config.md** — the TOML example from spec §9 with every key explained, `[[workspace]]` seeds, `[[ephemeral]]/[[float]]/[[ignore]]`, `[keybindings]` names (all keys of `KeyBindings.commandNames`) and key-name list (`KeyCodes.byName` keys).
- [ ] **Step 3: docs/testing.md** — the manual checklist from spec §12.4: 3-display unplug/replug, lock/unlock, `kill -STOP <pid>` of a managed app then `kill -CONT`, native fullscreen round-trip, Zoom parking, Secure Input in a password field, quit restores windows.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "docs: README, config reference, manual test checklist"`

---

## Self-review

**Spec coverage** — §2 decisions: Task 1 (names/licence), 11 (config paths, presets), 20 (paths). §3 layering/packages/seam: Tasks 1, 8. §4 model+invariants: Tasks 2, 3, 6; §4.3 semantics: 13 (fullscreen/minimized/hidden/ephemeral centring), 5 (float). §5 layouts + rect rule + parking single mechanism: Tasks 4, 9. §6.1 verbs + presets + arrows: Tasks 5, 11; drag deferred (no task, by design). §6.2 tap: Task 19. §7.1 threading + timeout: 14, 16. §7.2 identity/enumeration/parent: 1 (PrivateApi), 16. §7.3 classifier + config rule 0: 15, 11, 13. §7.4 frame writes/parking/corner/order/termination: 16, 7, 9, 18, 20. §7.5 focus/close/native state: 16, 13. §7.6 events/refresh/periodic/mouse-up: 18. §7.7 lock defence: 13, 18. §7.8 displays/UUID/unplug/adoption: 17, 3, 13. §8 reconciler/intents: 9, 10, 13. §9 config/state + `pinned` seeds: 11, 12, 20. §10 onboarding: 16, 20. §11 error handling: results in 8/16, unresponsive apps via timeouts in 16 (no separate "unresponsive" flag — acceptable simplification; note in platform-notes). §12 testing tiers: 2–13 (unit), 15 (corpus), 21 (integration), 22 (manual). §13 empirical checks: 19. §14 attribution: 1, 14, 15. Gap: spec §11's "three consecutive failures → ignored" is not implemented — add to Task 13 as a follow-up if it proves needed in practice; recorded here so it is not silently dropped.

**Placeholder scan** — Task 14/15 lift steps reference source files by path with explicit deletions; Task 16 is an adaptation guide with the exact AeroSpace line ranges and every method's contract; the rest is code. No "TBD"/"similar to".

**Type consistency** — `WorldStore.init(backend:config:world:zeroSliverBundleIDs:onChange:)` used identically in Tasks 13, 20, 21. `Reconciler.desired(world:displays:config:observed:prePark:parkedNow:zeroSliver:)` matches Tasks 9 and 13. `Parking.origin(windowSize:visibleFrame:corner:sliver:)` in 7 and 9. `KeyBindings.table(for:)`/`parse` in 11, 19, 20. `AXWindowBackend(config:)`, `.start()`, `.restoreAllForTermination(world:displays:observed:)` in 18, 20, 21; `WorldStore.exportForTermination()` added in 18, used in 20. `WindowSnapshot` initializer labels match between 8, 13, 16.

