# M2 appendix B — IPC socket, spacialctl, model verbs (planner output, verbatim)

I have everything I need. Here is the plan.

---

# SpacialShell M2 — IPC socket, `spacialctl`, and the model verbs behind them

Read alongside `docs/superpowers/specs/2026-08-18-m1-spatial-core-design.md` (§4 model, §6.1 verbs, §9 state, §15 which deferred exactly this).

---

## 0. Decisions ("decide" items, one line each)

| # | Question | Decision | Why |
|---|---|---|---|
| D1 | Extend `Command` vs. add a `Request` enum | **Extend `Command`** with new cases carrying `UUID`/`WindowRef`/`String`/`Layout`/`Bool` payloads | All payload types are already `Hashable + Sendable`, so `Command` stays `Hashable`; one dispatch path, one `CommandRunner`, one property-test generator, `WorldStore.run(_:)` unchanged, and `KeyBindings.commandNames` simply doesn't list the payload verbs (a keybinding to "focus workspace `<uuid>`" is meaningless anyway). |
| D2 | Case naming | **Distinct base names** (`focusWorkspaceID`, `focusWindowRef`, `moveWindowToWorkspaceID`, `moveWindowToIndex`, `setWorkspaceLayout`) — never `focusWorkspace(Vertical)` + `focusWorkspace(id: UUID)` | **Verified on the 6.3.3 toolchain**: overloaded enum case names *declare* fine but **break pattern matching** — `case .setLayout(let l)` silently binds the 2-value overload as a deprecated tuple, and `case .moveWindow(let r, toWorkspace: let u)` errors with `tuple pattern element label 'toWorkspace' must be 'toIndex'`. Distinct names typecheck clean. |
| D3 | `onChange` shape | **`onChange: @Sendable (World, ShellSnapshot) -> Void`** | One publish point, no skew between the state-saver and the IPC broadcast, no fan-out machinery inside the actor; the snapshot build is O(rows) after a reconcile that just made N async AX calls. 5 test call sites change (`{ _ in }` → `{ _, _ in }`). |
| D4 | Where the wire types live | **New leaf target `SpacialShellProtocol`**; move `WindowRef`, `WindowID`, `DisplayID`, `Layout` into it and leave `public typealias` shims in Kit | `spacialctl` then links neither TOMLDecoder, the reconciler, nor `CommandRunner` — it *cannot* reach into the model. The move is ~20 lines (`Model.swift:4-22`) and every other Kit file and test compiles unchanged. Cheaper fallback if this proves annoying: put `ShellSnapshot` in Kit and let the CLI depend on Kit. |
| D5 | Geometry on the wire | **`RectDTO { x, y, width, height }`**, never bare `CGRect` | **Measured**: `JSONEncoder` encodes `CGRect` as `[[1,2],[3,4]]`. Raycast/TS consumers should not have to know that. |
| D6 | `removeWorkspace` on the active workspace | **Allowed**; its windows merge into the workspace above (below if it is first) and that workspace becomes active, so focus follows its windows | "Down always means something" (I4) survives; refusing would make the CLI unable to undo an `add-workspace`. |
| D7 | `removeWorkspace` on the trailing empty | **Refused** (`notApplicable`) | `normalize()` would immediately recreate one with a new UUID — a no-op that looks like a success. |
| D8 | `removeWorkspace` on a pinned workspace | **Allowed** | An explicit remove is a stronger signal than a pin. |
| D9 | `renameWorkspace` on an unpinned workspace | **Pins it** | Spec §4.2 I4 verbatim: "Pinned workspaces — seeded from config, **or user-named in M2** — survive empty; that is what makes named categories possible." Without this you name the trailing empty "Code" and it is reaped the moment you leave. |
| D10 | `addWorkspace(pinned: false, name: nil)` | **Creates nothing; returns the screen's existing trailing-empty UUID** | An empty, unpinned, non-active, non-trailing workspace is reaped by `normalize()` the instant it is created — the verb would otherwise be a guaranteed lie. Any `name != nil` implies `pinned: true` (D9). |
| D11 | `moveWindowToWorkspaceID` focus behaviour | **Does not follow** the window (unlike the keyboard `moveWindowToWorkspace(Vertical)`, which keeps following) | These verbs are driven by the CLI, Raycast and M2's `Fn+Drag`; teleporting the user after a drag-onto-the-rail is wrong. A caller who wants to follow sends `focusWorkspaceID` next. |
| D12 | `toggleShellUI` becoming real | **`World.zen: Bool`**, toggled by `.toggleShellUI`, published in `ShellSnapshot.zen`; `zen == true` means "panels hidden" | One bit, one verb, one name on the wire (`toggle-zen`). Not persisted — a view mode, not a layout. |
| D13 | Error channel for the payload verbs | **`CommandRunner.run(_:on:) -> CommandOutcome`** (new workhorse) + `apply(_:to:) -> (World, [Effect])` kept as a shim; `WorldStore.run` becomes `@discardableResult ... -> CommandReport` | The IPC must say "no such workspace" rather than silently succeeding. Keeping `apply` means `CommandTests`, `PropertyTests` and `ReconcilerTests` need **zero** edits. It also closes a real gap: today a command sent while the screen is locked is swallowed with no signal (`WorldStore.swift:61`). |
| D14 | CLI argument parsing | **Hand-rolled**, no swift-argument-parser | Every subcommand is `--key value` / `--key=value` with ≤ 4 flags; the parser is a `[String] -> ParsedInvocation` pure function of ~120 lines that is trivially unit-testable. Adding a package dependency to a binary that ships *inside* the app bundle buys nothing. |
| D15 | AeroSpace attribution | **Write both sides fresh; no lift, no NOTICE change** | Spec §14 already lists `server.swift` and `Cli/**` under "Not lifted", and our framing (newline-delimited) and message shape differ. Add a prior-art *comment* at the `NWParameters.tcp` idiom. **If** the implementer copies `NWConnectionEx.initConnection()` verbatim, the header rule fires: `// Adapted from AeroSpace (MIT) — Sources/Common/util/NWConnectionEx.swift @ c548c7f`, plus a `NOTICE` line and a correction to spec §14. |

---

## 1. Target graph

`Package.swift` gains three libraries, one executable, two test targets.

```swift
products: [
    .library(name: "SpacialShellKit", targets: ["SpacialShellKit"]),
    .executable(name: "SpacialShell", targets: ["SpacialShell"]),
    .executable(name: "spacialctl", targets: ["spacialctl"]),          // NEW
],
targets: [
    .target(name: "PrivateApi", path: "Sources/PrivateApi"),
    .target(name: "SpacialShellProtocol"),                              // NEW — leaf, Foundation only
    .target(name: "SpacialShellKit",
            dependencies: ["SpacialShellProtocol",
                           .product(name: "TOMLDecoder", package: "TOMLDecoder")]),
    .target(name: "SpacialShellPlatform", dependencies: ["SpacialShellKit", "PrivateApi"]),
    .target(name: "SpacialShellIPC", dependencies: ["SpacialShellKit", "SpacialShellProtocol"]),  // NEW
    .target(name: "SpacialCtl", dependencies: ["SpacialShellProtocol"]),                          // NEW
    .executableTarget(name: "SpacialShell",
                      dependencies: ["SpacialShellKit", "SpacialShellPlatform", "SpacialShellIPC"]),
    .executableTarget(name: "spacialctl", dependencies: ["SpacialCtl"]),                          // NEW
    .testTarget(name: "SpacialShellKitTests", dependencies: ["SpacialShellKit"]),
    .testTarget(name: "SpacialShellProtocolTests", dependencies: ["SpacialShellProtocol"]),       // NEW
    .testTarget(name: "SpacialShellIPCTests", dependencies: ["SpacialShellIPC", "SpacialCtl"]),   // NEW
    .testTarget(name: "SpacialShellPlatformTests", dependencies: ["SpacialShellPlatform"]),
    .testTarget(name: "PlatformIntegrationTests", dependencies: ["SpacialShellPlatform", "SpacialShellKit"]),
]
```

Dependencies still point strictly downward (spec §3). `spacialctl` sees the wire vocabulary and nothing else.

---

## Task 1 — `SpacialShellProtocol`: core value types

**Files**
- Create `Sources/SpacialShellProtocol/CoreTypes.swift`
- Modify `Package.swift`
- Modify `Sources/SpacialShellKit/Model/Model.swift` (delete lines 4–22, add typealiases)
- 1-line fix: `Sources/SpacialShell/AppRuntime.swift:4` — `import struct SpacialShellKit.WindowRef` → `import struct SpacialShellProtocol.WindowRef`

**Signatures** — move verbatim out of `Model.swift`, unchanged bodies:

```swift
public typealias DisplayID = String   // CGDisplayCreateUUIDFromDisplayID string
public typealias WindowID = UInt32    // CGWindowID
public struct WindowRef: Hashable, Codable, Sendable, CustomStringConvertible { … }
public enum Layout: String, Codable, CaseIterable, Sendable { case maximize, split, column, half, grid; public var next: Layout { … } }

/// Wire geometry. `CGRect`'s synthesised Codable encodes as `[[x,y],[w,h]]` — hostile to any
/// non-Swift consumer, and Raycast is one.
public struct RectDTO: Hashable, Codable, Sendable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double)
    public init(_ r: CGRect)
    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
```

In `Model.swift`, replace the removed declarations with:

```swift
import SpacialShellProtocol
public typealias DisplayID = SpacialShellProtocol.DisplayID
public typealias WindowID  = SpacialShellProtocol.WindowID
public typealias WindowRef = SpacialShellProtocol.WindowRef
public typealias Layout    = SpacialShellProtocol.Layout
```

(Typealiases rather than `@_exported import`: no underscored attributes, and every re-exported name is greppable.)

**Tests** — none new; the gate is that `swift test` still passes untouched. `@testable import SpacialShellKit` resolves `WindowRef(id:pid:)` and `Layout.allCases` through the typealiases.

**Risks**
- `import struct SpacialShellKit.WindowRef` will not resolve a typealias. Fixed by the one-liner above; grep for other `import <kind> SpacialShellKit.X` forms first (currently exactly one).
- `Model.swift` still needs `import CoreGraphics` for `Screen.rect: CGRect?`.

---

## Task 2 — `ShellSnapshot`

**Files**
- Create `Sources/SpacialShellProtocol/ShellSnapshot.swift`

**Signatures**

```swift
public struct ShellSnapshot: Codable, Sendable, Equatable {

    public struct WorkspaceRow: Codable, Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var symbol: String
        public var layout: Layout
        public var pinned: Bool
        public var isActive: Bool
        public var windowCount: Int
    }

    public struct WindowRow: Codable, Sendable, Equatable {
        public var window: WindowRef        // { id, pid }
        public var pid: Int32               // duplicated flat for scripting convenience
        public var title: String
        public var bundleID: String?
        public var isFocused: Bool
        /// The layout would show it. Hidden → false; floating → true; tiled → the layout gives
        /// slot i a frame. Not "is on screen right now" — a display can be missing mid-hot-plug.
        public var isVisibleUnderLayout: Bool
        public var isFloating: Bool
        public var isHidden: Bool
    }

    public struct ScreenRow: Codable, Sendable, Equatable {
        public var display: DisplayID
        public var frame: RectDTO?          // nil while the display is absent from the topology
        public var visibleFrame: RectDTO?
        public var isMain: Bool
        public var isFocused: Bool
        public var workspaces: [WorkspaceRow]
        public var windows: [WindowRow]     // rows of *this screen's active workspace* only
    }

    public struct FocusRow: Codable, Sendable, Equatable {
        public var screen: DisplayID
        public var window: WindowRef?
    }

    public var v: Int                       // == IPCProtocol.version
    public var generation: UInt64           // monotonic per publish; subscribers drop stale
    public var screens: [ScreenRow]         // in world.screenOrder
    public var focus: FocusRow
    public var zen: Bool

    /// Equality ignoring `generation` — the publisher's dedupe key.
    public func isEquivalent(to other: ShellSnapshot) -> Bool
}
```

**Tests** (`Tests/SpacialShellProtocolTests/ShellSnapshotCodecTests.swift`)
- Round-trip: encode → decode → equal.
- Golden JSON: keys are exactly `v, generation, screens, focus, zen`; `frame` is `{"x":…,"y":…,"width":…,"height":…}`; `layout` is `"half"`; `id` is an uppercase UUID string.
- `isEquivalent` ignores `generation` and nothing else.

**Risks**
- Rows are only for the *active* workspace per screen — deliberate, to bound the subscribe payload. `list-windows --workspace <id>` for an inactive workspace needs the separate store query added in Task 5.

---

## Task 3 — IPC codec and framing

**Files**
- Create `Sources/SpacialShellProtocol/JSONValue.swift`
- Create `Sources/SpacialShellProtocol/IPCMessages.swift`
- Create `Sources/SpacialShellProtocol/IPCFraming.swift`

**Signatures**

```swift
public enum JSONValue: Codable, Sendable, Equatable, Hashable {
    case null, bool(Bool), int(Int), double(Double), string(String)
    case array([JSONValue]), object([String: JSONValue])

    public init<T: Encodable>(encoding value: T) throws
    public func decode<T: Decodable>(_ type: T.Type) throws -> T
    // typed accessors used by the dispatcher
    public subscript(key: String) -> JSONValue? { get }
    public var stringValue: String? { get }
    public var intValue: Int? { get }
    public var boolValue: Bool? { get }
    public var uuidValue: UUID? { get }
}

public enum IPCProtocol {
    public static let version = 1
    public static let maxRequestBytes = 64 * 1024
    public static let socketFileName = "spacialshell.sock"
    /// `~/Library/Application Support/SpacialShell/spacialshell.sock`, or
    /// `/tmp/spacialshell-<uid>.sock` when that would exceed `sun_path`'s 104 bytes.
    public static func defaultSocketPath() -> String
}

public struct IPCRequest: Codable, Sendable, Equatable {
    public var id: Int
    public var cmd: String
    public var args: [String: JSONValue]
}

public struct IPCResponse: Codable, Sendable, Equatable {
    public var id: Int
    public var v: Int
    public var ok: Bool
    public var data: JSONValue?
    public var error: String?
    public static func ok(id: Int, data: JSONValue? = nil) -> IPCResponse
    public static func failure(id: Int, _ message: String) -> IPCResponse
}

public struct IPCEvent: Codable, Sendable, Equatable {
    public var v: Int
    public var event: String            // "shell"
    public var data: JSONValue
}

/// Newline-delimited JSON. `JSONEncoder` with `[.sortedKeys]` (never `.prettyPrinted`) cannot
/// emit a bare newline — string contents escape it as the two characters `\n`.
public struct LineFramer: Sendable {
    public init(maxLineBytes: Int = IPCProtocol.maxRequestBytes)
    public enum Outcome: Sendable, Equatable { case lines([Data]), overflow }
    /// Appends `chunk` and returns whatever complete lines that produced. `.overflow` once the
    /// buffer passes `maxLineBytes` with no newline — unrecoverable, the caller must close.
    public mutating func push(_ chunk: Data) -> Outcome
}

public enum IPCCodec {
    public static let encoder: JSONEncoder      // outputFormatting = [.sortedKeys]
    public static let decoder: JSONDecoder
    public static func line<T: Encodable>(_ value: T) throws -> Data   // JSON + 0x0A
}
```

**Tests** (`Tests/SpacialShellProtocolTests/CodecTests.swift`)
- `JSONValue` round-trips every case including nested objects and `null`.
- `IPCRequest`/`IPCResponse`/`IPCEvent` round-trip; `error` absent when `ok`.
- `IPCCodec.line` never contains an interior `0x0A`, including a payload whose *string value* contains a real newline.
- `LineFramer`: one line delivered in 3 chunks; two lines in one chunk; a trailing partial line held back; `\r\n` tolerated (strip trailing `\r`); `.overflow` at exactly `maxLineBytes + 1`.
- `defaultSocketPath()` length < 104.

---

## Task 4 — the model verbs

**Files**
- Modify `Sources/SpacialShellKit/Commands/Command.swift`
- Modify `Sources/SpacialShellKit/Commands/CommandRunner.swift`
- Modify `Sources/SpacialShellKit/Model/Model.swift` (`World.zen`)

**Signatures**

```swift
public enum Command: Sendable, Hashable {
    // … the 11 M1 cases, unchanged …

    case focusWorkspaceID(UUID)
    case focusWindowRef(WindowRef)
    case moveWindowToWorkspaceID(WindowRef, UUID)
    case moveWindowToIndex(WindowRef, Int)
    case renameWorkspace(UUID, String)
    case setWorkspaceSymbol(UUID, String)
    case setLayout(Layout)                                   // active workspace of the focused screen
    case setWorkspaceLayout(UUID, Layout)
    case addWorkspace(display: DisplayID, name: String?, pinned: Bool)
    case removeWorkspace(UUID)
    case pinWorkspace(UUID, Bool)
}

public enum CommandError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownWorkspace(UUID)
    case unknownWindow(WindowRef)
    case unknownScreen(DisplayID)
    case notApplicable(String)
    case locked                                              // spec §7.7 freeze
    public var description: String { … }                     // the string the CLI prints
}

public struct CommandOutcome: Sendable, Equatable {
    public var world: World
    public var effects: [Effect]
    public var error: CommandError?
    public var workspaceID: UUID?                            // addWorkspace: what the caller should target
}

public enum CommandRunner {
    public static func run(_ command: Command, on input: World) -> CommandOutcome
    /// M1 shim — every existing call site and test keeps compiling.
    public static func apply(_ command: Command, to input: World) -> (World, [Effect]) {
        let o = run(command, on: input); return (o.world, o.effects)
    }
}
```

`World` gains one stored property, appended so the memberwise init stays source-compatible:

```swift
public var zen: Bool          // §6.1 toggleShellUI / Fn+Esc; true == panels hidden
public init(…, defaultLayout: Layout, zen: Bool = false)
```

**Per-verb semantics** (each is a bullet in the implementation and a test):

- `focusWorkspaceID(id)` — locate `(screen, index)`; `w.focus = Focus(screen: screen, window: nil)` **then** `w.activate(index:on:)` (`activate` only re-derives `focus.window` when `focus.screen == screen`, so the order is load-bearing). Unknown id → `.unknownWorkspace`.
- `focusWindowRef(ref)` — ephemeral → `focus.window = ref`, screen unchanged. Placed → set `focus.screen`, `activate(index:on:)`, `focus.window = ref`, anchor = ref. Hidden → `.notApplicable("window is minimised or hidden")` (I5 forbids focusing a hidden window). Unknown → `.unknownWindow`.
- `moveWindowToWorkspaceID(ref, id)` — remove from source (carrying `floating` membership), append to target, target `anchor = ref`. **Does not activate the target and does not move focus** (D11); if `ref` was the focused window, focus falls to its neighbour exactly as `World.remove` does. `normalize()` reaps the source if it is now empty/unpinned/non-active, and appends a fresh trailing empty if the target *was* the trailing one (I4). No-op-with-success when source == target.
- `moveWindowToIndex(ref, i)` — **insertion**, not swap: remove at the old index, insert at `min(max(i,0), count-1)` within the same workspace. Out of range clamps rather than errors (friendlier for a CLI; adjacent moves therefore agree with `moveWindow(.left/.right)`).
- `renameWorkspace(id, name)` — empty/whitespace name → `.notApplicable`. **Sets `pinned = true`** (D9).
- `setWorkspaceSymbol(id, symbol)` — empty → `.notApplicable`; no SF Symbol validation in Kit (no AppKit).
- `setLayout(l)` / `setWorkspaceLayout(id, l)` — assignment; `.relayout`.
- `addWorkspace(display:name:pinned:)` — unknown display → `.unknownScreen`. If `name == nil && !pinned` → create nothing, `workspaceID = <trailing empty's id>` (D10). Otherwise insert `Workspace(name: name ?? "Workspace", symbol: default, layout: world.defaultLayout, pinned: true)` at `workspaces.count - 1`, `workspaceID = <new id>`.
- `removeWorkspace(id)` — trailing → `.notApplicable` (D7). Else target `= index > 0 ? index - 1 : index + 1`; append windows in order, carry `floating`; drop the workspace; if it was that screen's active one, `activeIndex = index > 0 ? index - 1 : 0`; `normalize()`.
- `pinWorkspace(id, false)` on an empty non-active non-trailing workspace **deletes it** via `normalize()` — documented, not a bug.
- `toggleShellUI` — `w.zen.toggle()`, effects `[.relayout]`.

**Tests** (`Tests/SpacialShellKitTests/CommandTests.swift`, +~18 tests)
- One happy-path test per verb, plus one error test per verb (`unknownWorkspace`, `unknownWindow`, `unknownScreen`, hidden-window focus, trailing-workspace removal).
- `removeWorkspaceMergesUpAndKeepsFocus`, `removeFirstWorkspaceMergesDown`, `removeActiveWorkspaceMovesFocusUp`.
- `renamePinsTheWorkspace`, `unpinningAnEmptyWorkspaceReapsIt`, `addWorkspaceUnpinnedReturnsTheTrailingEmpty`, `addWorkspaceInsertsBeforeTheTrailingEmpty`.
- `moveWindowToWorkspaceIDDoesNotFollow` vs. the existing `moveWindowDownCreatesWorkspaceAndFollows` — the contrast is the point.
- **Existing test must change**: `CommandTests.swift:80 toggleShellUIIsNoop` asserts `run(w, .toggleShellUI).0 == w`; `World` is `Equatable` and now carries `zen`, so it becomes `toggleShellUIFlipsZen`.
- Every assertion goes through the existing `run(_:_:)` helper, which already asserts `invariantViolations().isEmpty` after each command.
- Remember the swift-testing quirk: `#expect(w.mutatingCall())` on a struct does not compile — bind to a `let` first.

**`PropertyTests.randomOp` extension** — the generator must draw **live** ids so it actually exercises the code, plus a slice of garbage to exercise the error paths:

```swift
enum Op { case adopt(WindowKind, DisplayID), remove, hide, unhide, cmd(Command), screens([DisplayID]),
          payload(PayloadKind) }
enum PayloadKind { case focusWorkspaceID, focusWindowRef, moveToWorkspaceID, moveToIndex,
                   rename, symbol, setLayout, setWorkspaceLayout, addWorkspace, removeWorkspace, pin }
```
Build the concrete `Command` inside the loop from the *current* `w`: ~85 % of ids drawn from `w.screens.values.flatMap(\.workspaces).map(\.id)` / `live`, ~15 % fresh `UUID()` / synthetic `WindowRef`. Keep the existing `#expect(v.isEmpty, "seed … step … op …")` shape and the early `return` on first violation. Bump the argument range only if runtime allows (currently `0..<200 × 60` steps).

**Risks**
- `World.zen` changes the synthesised `Codable`. `World` is never archived (`PersistedState` is a separate shape; grep confirms no `decode(World`), so no migration — but say so in a comment so nobody later persists `World` naively.
- `normalize()` runs after every mutation and is the only thing standing between these verbs and I4/I5. Every new verb ends in `w.normalize()`; the property test is what proves it.

---

## Task 5 — `WorldStore`: titles, snapshot, reports

**Files**
- Modify `Sources/SpacialShellKit/Store/WorldStore.swift`
- Create `Sources/SpacialShellKit/Store/ShellSnapshotBuilder.swift`

**Signatures**

```swift
public actor WorldStore {
    private let onChange: @Sendable (World, ShellSnapshot) -> Void          // was (World) -> Void
    private var titles: [WindowRef: String] = [:]                            // NEW side table
    private var snapshotSeq: UInt64 = 0
    private var lastPublished: ShellSnapshot?

    public init(backend: any WindowBackend, config: Config, world: World?,
                zeroSliverBundleIDs: Set<String>,
                onChange: @escaping @Sendable (World, ShellSnapshot) -> Void)

    /// Pull API. Does not bump `generation`.
    public func shellSnapshot() -> ShellSnapshot

    /// Rows for a workspace that is *not* the active one — `ShellSnapshot` deliberately carries
    /// only active-workspace rows. nil when the id is unknown.
    public func windowRows(workspace id: UUID) -> [ShellSnapshot.WindowRow]?

    /// nil-error report. `@discardableResult` keeps `Task { await store.run(cmd) }` compiling.
    @discardableResult
    public func run(_ command: Command) async -> CommandReport
}

public struct CommandReport: Sendable, Equatable {
    public var error: CommandError?
    public var workspaceID: UUID?
    public static let ok = CommandReport()
}
```

**Changes inside the actor**
1. `applySnapshot` (`WorldStore.swift:116`) — next to `bundleIDs[w.ref] = w.bundleID`, add `titles[w.ref] = w.title`.
2. The gone-loop (`:134`) — add `titles[gone] = nil` alongside `bundleIDs[gone] = nil`.
3. `run(_:)` (`:60-66`) — `guard !locked else { return CommandReport(error: .locked) }`; use `CommandRunner.run(command, on: world)`; return `CommandReport(error: o.error, workspaceID: o.workspaceID)`. **Do not reconcile when `o.error != nil`** (the world is unchanged; skip the write pass).
4. `reconcile()` tail (`:212`) — replace `onChange(world)` with:
   ```swift
   snapshotSeq &+= 1
   let shell = buildShellSnapshot(generation: snapshotSeq)
   if lastPublished?.isEquivalent(to: shell) != true {   // dedupe the 2 s backstop's no-op reconciles
       lastPublished = shell
       onChange(world, shell)
   }
   ```
   > This dedupe matters: the periodic 2 s refresh (spec §7.6) drives a reconcile → publish, so without it every subscriber wakes twice a second forever.
   >
   > It also changes the state-saver's cadence. `AppRuntime.scheduleSave` already debounces 500 ms and `PersistedState` only carries name/symbol/layout/pinned — none of which can change without changing the snapshot. Verify against `TerminationGate.note(world:)`, which wants the *latest* world: a deduped publish means the world it holds is identical in every field the fallback restore reads.

**Builder** (`ShellSnapshotBuilder.swift`, `extension WorldStore`)

```swift
func buildShellSnapshot(generation: UInt64) -> ShellSnapshot
```
- Screens in `world.screenOrder`; `frame`/`visibleFrame` from `displays.first { $0.id == sid }` mapped through `RectDTO`, `nil` when absent.
- `WorkspaceRow.windowCount = ws.windows.count`, `isActive = (i == screen.activeIndex)`.
- `WindowRow` for the active workspace only: title from `titles[ref] ?? ""`, bundle from `bundleIDs[ref]`, `isFocused = (world.focus.window == ref)`, `isFloating = ws.floating.contains(ref)`, `isHidden = world.hidden.contains(ref)`.
- `isVisibleUnderLayout` — hidden → `false`; floating → `true`; tiled → recompute nil-ness from `LayoutEngine.frames(ws.layout, count: tiled.count, focused: anchorIndex, in: <unit rect>, gap: 0)[i] != nil`. **This is a pure function of `(layout, count, focused)`** — no display needed, so it is correct even mid-hot-plug when the screen has no `DisplayInfo`.

**Tests**
- `Tests/SpacialShellKitTests/ShellSnapshotTests.swift` (new):
  - titles flow from `WindowSnapshot.title` into rows; a vanished window's title is dropped from the table (assert via a second snapshot, not via `debugSideTables` unless you extend it).
  - rows exist only for the active workspace; `windowCount` covers all of them.
  - `isVisibleUnderLayout` under `maximize` (only the anchor), `split` (two), `column`/`grid` (all), hidden (`false`), floating (`true`).
  - `generation` strictly increases across distinct publishes and does **not** advance across identical ones.
  - `zen` follows `.toggleShellUI`.
  - `windowRows(workspace:)` returns rows for an inactive workspace and `nil` for a stranger UUID.
- `WorldStoreTests.swift` edits: 5 `onChange:` closures `{ _ in }` → `{ _, _ in }` (lines 16, 108, 205, 225 and `TextEditTests.swift:56`); `onChangeFiresWithWorld` becomes `onChangeFiresWithWorldAndSnapshot`. Three `Task { await store.run(…) }` + `await run.value` sites (`:135/:150/:194`) need `_ = await run.value` once `run` returns a value.
- New: `commandWhileLockedReportsLocked`, `unknownWorkspaceIsReportedNotSwallowed`.
- `randomSnapshotsPreserveInvariants` (`:228`): the `cmds` array is built once with fixed payloads before the loop — build the payload commands *inside* the loop from `await store.world` (and remember the binding quirk: bind `let w = await store.world` before calling methods on it).

**Risks**
- `titles` cleanup is skipped while `loginwindowFrontmost` (same as `bundleIDs` today, deliberately). It self-heals on the next non-login snapshot.
- `note(_:for:)` (three-strikes retirement) clears `observed`/`prePark` but not `bundleIDs`; keep `titles` consistent with `bundleIDs` — retired windows go to `world.ignored` and never appear in rows anyway.
- Building the snapshot on every reconcile allocates; it is O(windows) refcount traffic after N awaited AX round-trips. Not worth conditionalising on "is anyone subscribed".

---

## Task 6 — IPC server transport

**Files**
- Create `Sources/SpacialShellIPC/IPCServer.swift`
- Create `Sources/SpacialShellIPC/IPCConnection.swift`
- Create `Sources/SpacialShellIPC/SnapshotHub.swift`

**Signatures**

```swift
public final class IPCServer: Sendable {
    public struct Options: Sendable {
        public var socketPath: String = IPCProtocol.defaultSocketPath()
        public var maxConnections: Int = 16
        public var idleTimeout: Duration = .seconds(30)      // connected, never sent, not subscribed
        public var sendTimeout: Duration = .seconds(10)      // a wedged subscriber
    }
    public enum StartError: Error, Sendable, Equatable {
        case alreadyRunning(path: String)                    // a live server answered on that path
        case pathTooLong(path: String)                       // sun_path is 104 bytes
        case listenerFailed(String)
    }

    public init(store: WorldStore,
                options: Options = .init(),
                reloadConfig: @escaping @Sendable () async -> Void)

    /// Async because a stale/occupied socket only surfaces via the listener's state handler.
    public func start() async throws
    /// Synchronous: TerminationGate calls it on a signal queue, and it must not need another
    /// semaphore hop. Cancels the listener, cancels every connection, unlinks the socket file.
    public func stop()
    /// Called straight from `WorldStore.onChange`, on the actor's executor. Lock + hand-off only.
    public nonisolated func publish(_ snapshot: ShellSnapshot)
}
```

**Listener setup** — the one non-obvious part:

```swift
// Network.framework has no AF_UNIX parameter preset: `.tcp` options plus a unix
// `requiredLocalEndpoint` is the only way to get a stream listener on a socket file.
// AeroSpace (MIT) reaches for the same idiom in Sources/AppBundle/server.swift @ c548c7f;
// written independently here, nothing copied.
let params = NWParameters.tcp
params.requiredLocalEndpoint = .unix(path: options.socketPath)
params.allowLocalEndpointReuse = true          // harmless; does NOT cure EADDRINUSE on AF_UNIX
let listener = try NWListener(using: params)
```

**Startup sequence** (order is load-bearing):
1. Guard `socketPath.utf8.count < 104` → `.pathTooLong`.
2. `FileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])` — a `0700` **directory** is the real access control; no other uid can even traverse to the socket.
3. If the file exists, **probe before unlinking**: `NWConnection(to: .unix(path:), using: .tcp)`, 500 ms budget. Reaches `.ready` → another SpacialShell owns it → throw `.alreadyRunning`. Otherwise `unlink(path)`. *(AeroSpace unlinks unconditionally, `server.swift:6` — that silently steals the socket from a live second instance; we don't.)*
4. `listener.stateUpdateHandler` → resume a one-shot continuation on `.ready` or `.failed`, with a 2 s timeout; `listener.start(queue:)`.
5. **On `.ready`, and only then**, `chmod(path, 0o600)` — the socket file is created asynchronously by `start()`, so chmod'ing earlier fails with `ENOENT` and leaves the default mode.
6. `newConnectionHandler`: over `maxConnections` → write one `{"ok":false,"error":"too many connections"}` line and `cancel()`. Otherwise register and start on a **fresh serial queue per connection**.

**Connection** — a pull-driven pump, which is what makes actor re-entrancy a non-issue:

```swift
actor IPCConnection {
    init(_ connection: NWConnection, id: Int, dispatch: IPCDispatch, hub: SnapshotHub, options: IPCServer.Options)
    func run() async                      // read → dispatch → write → read …
    func cancel()
    func deliver(_ snapshot: ShellSnapshot) async   // subscriber path
}
```
`run()` issues the next `receive` only after the previous response has been written, so two requests can never interleave and no `Task` ordering guarantee is needed. `receive` and `send` are bridged with `withCheckedContinuation`. EOF (`data == nil || isComplete`) → deregister from the hub and return. `LineFramer.Outcome.overflow` → one error line, then cancel (you cannot resync a truncated stream).

**Back-pressure** (`SnapshotHub`) — a **single-slot coalescing mailbox per subscriber**:
- Each subscriber holds `pending: ShellSnapshot?`, `inFlight: Bool`, `lastSent: UInt64`.
- `publish` overwrites `pending` rather than queueing — a snapshot is full state, not a delta, so dropping intermediates is *correct*, and memory is bounded at one snapshot per connection.
- When a `send` completes, if `pending != nil` send that next.
- `generation` guards ordering: any snapshot with `generation <= lastSent` is dropped, so it does not matter which `Task` wins a race.
- If a `send` has not completed within `sendTimeout`, cancel the connection — a subscriber that stops reading forever must not pin the hub.
- On `subscribe`, send one snapshot immediately (`shellSnapshot()`), then stream.

**Tests** (`Tests/SpacialShellIPCTests/ServerTransportTests.swift`)
- Start on `/tmp/spacialshell-test-<UUID>.sock` (short path; `/var/folders/...` temp dirs are long and swift-testing runs suites in parallel, so a per-test random name is mandatory) and `unlink` in `defer`.
- Socket file exists after `start()`; mode is `0600`; parent directory is `0700`.
- `start()` twice on the same path → `.alreadyRunning`.
- Stale file with no listener → cleaned up and `start()` succeeds.
- `stop()` unlinks the file (`NWListener.cancel()` does **not**).
- `maxConnections + 1` connections: the last one gets an error line and is closed.
- Oversized line (`64 KiB + 1` bytes, no newline) → error response then close.
- Subscribe back-pressure: a client that reads nothing while 200 snapshots are published → the server does not grow unboundedly and eventually cancels the connection at `sendTimeout`. (Assert on the hub's `pending` depth staying ≤ 1 via a test-only accessor rather than on timing.)

**Risks**
- `NWConnection` to a dead socket enters **`.waiting(.posix(.ECONNREFUSED))`, not `.failed`**, and retries forever by default. Both the probe here and the CLI client in Task 9 must treat `.waiting` as terminal. This is the single most common Network.framework mistake; AeroSpace handles it at `NWConnectionEx.swift:26` (`case .failed(let e), .waiting(let e)`).
- `NWParameters.tcp` over AF_UNIX is undocumented usage. It typechecks on the 6.3.3 toolchain / macOS 26 SDK with a macOS 14 deployment target, and AeroSpace ships it. Contingency if it regresses: a plain `socket(AF_UNIX, SOCK_STREAM, 0)` + `DispatchSource.makeReadSource` server, ~80 lines; the `IPCServer` surface above does not change.
- A raw-POSIX fallback would need `SO_NOSIGPIPE`; Network.framework does not raise SIGPIPE.
- No entitlement is needed for AF_UNIX in the user's own container, hardened runtime included — worth noting for the M4 notarisation task.

---

## Task 7 — request dispatch

**Files**
- Create `Sources/SpacialShellIPC/IPCDispatch.swift`
- Create `Sources/SpacialShellIPC/IPCCommandTable.swift`

**Signatures**

```swift
public struct IPCDispatch: Sendable {
    public init(store: WorldStore, appVersion: String, reloadConfig: @escaping @Sendable () async -> Void)
    /// `.subscribe` tells the connection to switch modes; everything else answers inline.
    public enum Result: Sendable { case response(IPCResponse), subscribe(IPCResponse) }
    public func handle(_ request: IPCRequest) async -> Result
}
```

**Command table**

| `cmd` | args | store call | `data` |
|---|---|---|---|
| `version` | — | none | `{"app":"0.1.0","protocol":1}` |
| `state` | — | `shellSnapshot()` | `ShellSnapshot` |
| `list-screens` | — | `shellSnapshot()` | `[{display, frame, visibleFrame, isMain, isFocused, workspaceCount}]` |
| `list-workspaces` | `screen?` | `shellSnapshot()` | `[WorkspaceRow]` (+ `screen`) |
| `list-windows` | `workspace?` | `shellSnapshot()` / `windowRows(workspace:)` | `[WindowRow]` |
| `focus-workspace` | `id` \| `index`(+`screen?`) \| `name` | resolve → `.focusWorkspaceID` | `null` |
| `focus-window` | `id`, `pid` | `.focusWindowRef` | `null` |
| `move-window` | `window?{id,pid}`, one of `to-workspace` / `to-screen` / `to-index` | `.moveWindowToWorkspaceID` / `.moveWindowToIndex` | `null` |
| `add-workspace` | `screen?`, `name?`, `pinned?` | `.addWorkspace` | `{"id":"<uuid>"}` |
| `rename-workspace` | `id`, `name` | `.renameWorkspace` | `null` |
| `set-symbol` | `id`, `symbol` | `.setWorkspaceSymbol` | `null` |
| `set-layout` | `id?`, `layout` | `.setWorkspaceLayout` / `.setLayout` | `null` |
| `pin-workspace` | `id`, `pinned` | `.pinWorkspace` | `null` |
| `remove-workspace` | `id` | `.removeWorkspace` | `null` |
| `cycle-layout` | — | `.cycleLayout` | `null` |
| `toggle-zen` | — | `.toggleShellUI`, then `shellSnapshot()` | `{"zen":true\|false}` |
| `run` | `command` \| `list:true` | `KeyBindings.commandNames[name]` | `null` / `[names]` |
| `reload-config` | — | the `reloadConfig` closure | `null` |
| `subscribe` | — | — | `.subscribe`, then `{"v":1,"event":"shell","data":…}` per change |

**Resolution rules**
- `focus-workspace {index}` is 1-based, resolved against `screen` if given else `focus.screen`, then converted to a UUID and sent as `.focusWorkspaceID` — so it works on any screen, unlike the keyboard-only `.focusWorkspaceIndex`.
- `focus-workspace {name}` scans screens in `screenOrder`, preferring the focused screen on ties; no match → `"unknown workspace 'X'"`.
- `move-window` with no `window` uses `shellSnapshot().focus.window`.
- `move-window {to-screen}` resolves to that screen's *active* workspace id.
- `run {command}` with an unknown name errors with the sorted list of `KeyBindings.commandNames.keys`; `run {list:true}` returns them.
- Unknown `cmd`, missing/ill-typed args → `ok:false` with a message naming the argument. **Never** a crash; every `args[...]` read goes through the typed `JSONValue` accessors.

**Tests** (`Tests/SpacialShellIPCTests/DispatchTests.swift`) — drive a real `WorldStore` over a ~25-line `StubBackend` local to this target (`FakeBackend` lives in `SpacialShellKitTests` and SwiftPM cannot share a source file between two targets; the IPC tests assert on responses, not on backend writes, so the stub is enough — the alternative, promoting `FakeBackend` to a `SpacialShellTestSupport` library target, is more surgery than it buys).
- One test per row of the table: happy path + one malformed-args path.
- `focus-workspace` by all three selectors resolves to the same workspace.
- `run` with a bad name lists the valid names.
- Errors are `ok:false` with a human message; `id` echoes the request's `id` including for parse failures where `id` is unknown (use `0`).

**Risks**
- **Two-hop resolution race**: name/index/focused-window resolution reads `shellSnapshot()`, then a second `await` runs the command. A keystroke landing in between can move focus. Every verb re-validates its own target inside `CommandRunner`, so the worst case for an *id-carrying* verb is a clean `unknownWorkspace` error, never the wrong target. The one genuinely racy case is `move-window` with no `--window` (the focused window may have changed). Document it in `docs/ipc.md`; do not paper over it with a lock.

---

## Task 8 — CLI parsing and rendering

**Files**
- Create `Sources/SpacialCtl/CLIParser.swift`
- Create `Sources/SpacialCtl/Render.swift`
- Create `Sources/SpacialCtl/Usage.swift`

**Signatures**

```swift
public enum ExitCode: Int32, Sendable { case ok = 0, daemonError = 1, usage = 2, cannotConnect = 3 }

public struct Invocation: Sendable, Equatable {
    public var cmd: String                    // the wire `cmd`
    public var args: [String: JSONValue]
    public var json: Bool                     // --json, or the default for state/list-*
    public var subscribes: Bool
}

public enum ParseResult: Sendable, Equatable {
    case invocation(Invocation)
    case help(String)                         // exit 0
    case usageError(String)                   // exit 2
}

public enum CLIParser {
    public static func parse(_ argv: [String]) -> ParseResult
}

public enum Render {
    public static func screens(_ v: [ShellSnapshot.ScreenRow]) -> String
    public static func workspaces(_ v: [ShellSnapshot.WorkspaceRow]) -> String
    public static func windows(_ v: [ShellSnapshot.WindowRow]) -> String
    public static func state(_ v: ShellSnapshot) -> String
    public static func table(_ rows: [[String]], header: [String]) -> String   // 2-space gutter, left-aligned
}
```

**Parser rules** (deliberately boring, so it fits in one testable function)
- `spacialctl <subcommand> [--flag value | --flag=value | --bool-flag]`; `--` ends flag parsing.
- Bare `--json` / `-h|--help` / `-v|--version` handled first.
- Subcommand names are exactly the wire `cmd` names — the CLI is a thin shell over the protocol, and that is a feature (`spacialctl <tab>` and `docs/ipc.md` never drift).
- `--json` is the **default** for `state`, `list-screens`, `list-workspaces`, `list-windows`; every other subcommand prints a human line unless `--json` is given. `--no-json` forces the table for the list commands.
- `--window 12345:678` and `--id/--pid` are both accepted for `focus-window` / `move-window`.
- Unknown flag, missing required value, unknown subcommand → `.usageError` with the one-line usage for that subcommand.

**Tests** (`Tests/SpacialShellIPCTests/CLIParserTests.swift`)
- Every subcommand: `--flag value` and `--flag=value` produce identical `Invocation`s.
- `--json` defaults per subcommand; `--no-json` overrides.
- `--window 12:34` and `--id 12 --pid 34` agree.
- `-h`, `--help`, bare invocation, unknown subcommand, unknown flag, missing value → correct `ParseResult` case and message.
- `Render.table` column alignment with an empty set, a single row, and a row containing a wide character.

---

## Task 9 — CLI client and executable

**Files**
- Create `Sources/SpacialCtl/IPCClient.swift`
- Create `Sources/SpacialCtl/Run.swift`
- Create `Sources/spacialctl/main.swift`

**Signatures**

```swift
public struct IPCClient: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        case cannotConnect(path: String, detail: String)
        case io(String)
        case malformedResponse(String)
    }
    public init(socketPath: String = IPCProtocol.defaultSocketPath(),
                connectTimeout: Duration = .seconds(2))
    public func connect() async throws
    public func send(_ request: IPCRequest) async throws -> IPCResponse
    public func stream(_ request: IPCRequest, onEvent: @Sendable (IPCEvent) -> Void) async throws -> Never
    public func close()
}

public enum SpacialCtl {
    /// The whole CLI, minus `exit`. Returns the process exit code.
    public static func run(arguments: [String],
                           out: @Sendable (String) -> Void = { print($0) },
                           err: @Sendable (String) -> Void = { FileHandle.standardError.write(…) }) async -> ExitCode
}
```

`Sources/spacialctl/main.swift` is five lines:
```swift
import SpacialCtl
import Darwin
let code = await SpacialCtl.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(code.rawValue)
```
(top-level `await` in `main.swift` is fine; the logic lives in the library so the test target can call `SpacialCtl.run` directly without depending on an executable target).

**Connect semantics**
- `NWConnection(to: .unix(path:), using: .tcp)`, `stateUpdateHandler` resolving a one-shot continuation, treating **`.waiting` exactly like `.failed`** (see Task 6 risks), with a hard 2 s `Task.sleep` race as the outer bound.
- On failure, exit `3` with:
  `SpacialShell isn't running (socket <path>)`
- Daemon `ok:false` → print `error` to stderr, exit `1`.
- `subscribe` prints one JSON object per line and `fflush(stdout)` after each (Network.framework buffers; without the flush a piped consumer sees nothing until the buffer fills — AeroSpace hits the same, `Cli/_main.swift:147`).

**Tests** (`Tests/SpacialShellIPCTests/EndToEndTests.swift`)
- `IPCServer` + `IPCClient` over a per-test `/tmp/spacialshell-test-<UUID>.sock`: `version`, `state`, `list-workspaces`, `add-workspace` → returns a UUID → `rename-workspace` → `list-workspaces` shows the name and `pinned:true`.
- `subscribe`: connect, receive the immediate snapshot, run a command through a *second* connection, receive the change, assert `generation` increased.
- `SpacialCtl.run(arguments:)` against a live server with captured `out`/`err`: exit `0` and a parseable table.
- `SpacialCtl.run(["state"])` against a nonexistent socket path → exit `3`, stderr contains the path.
- Bad subcommand → exit `2`, nothing on stdout.

**Risks**
- `spacialctl subscribe | head -1` gets SIGPIPE on the second `print` and dies with 141. That is idiomatic for a streaming CLI; document it rather than trapping it.
- `run(arguments:)` must not call `exit()` itself — that is what makes it testable; only `main.swift` exits.

---

## Task 10 — AppRuntime and bundle wiring

**Files**
- Modify `Sources/SpacialShell/AppRuntime.swift`
- Modify `Sources/SpacialShell/Paths.swift`
- Modify `Scripts/bundle.sh`

**`Paths.swift`** — one source of truth for the socket, shared with the CLI:
```swift
static let socketFile = URL(fileURLWithPath: IPCProtocol.defaultSocketPath())
```

**`AppRuntime`** — the ordering constraint is that the store needs `onChange` at init but the server needs the store, so a small box breaks the cycle:

```swift
/// Breaks the store↔server construction cycle: `WorldStore` needs `onChange` at init, and
/// `IPCServer` needs the store. Lock-guarded, never blocking — it is called on the actor's executor.
private nonisolated let publisher = SnapshotPublisher()
private var ipc: IPCServer?
```
Boot becomes nine stages:
```swift
// stage 5/9: constructing the store
let publisher = self.publisher
let store = WorldStore(backend: backend, config: config, world: initial,
                       zeroSliverBundleIDs: Self.zeroSliverBundleIDs) { [weak self] world, shell in
    gate.note(world: world)
    publisher.publish(shell)
    Task { @MainActor in self?.scheduleSave(world) }
}
…
// stage 7/9: starting the IPC server  (AFTER await store.start(), per spec)
let server = IPCServer(store: store,
                       options: .init(socketPath: Paths.socketFile.path),
                       reloadConfig: { [weak self] in await MainActor.run { self?.reloadConfig() } })
publisher.attach(server)
do { try await server.start(); self.ipc = server; termination.arm(server: server) }
catch { log.error("IPC server unavailable: \(…); spacialctl will not connect") }
```
The server failing to start must **never** fail boot — a stuck socket file must not cost the user their window manager.

**`TerminationGate`** — `arm(server:)`, and inside `run(onMainThread:)` place `server?.stop()` **immediately after `tap?.stop()`**, before the export:
> Same reason the tap is stopped first — a CLI command landing between the export and the restore would move windows the restore has already decided about. `stop()` is synchronous, so it needs no semaphore hop from the signal queue.

**`Scripts/bundle.sh`** — sign inside-out:
```sh
swift build -c release
…
cp .build/release/SpacialShell "$APP/Contents/MacOS/SpacialShell"
cp .build/release/spacialctl  "$APP/Contents/MacOS/spacialctl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/MacOS/spacialctl"          # nested first…
codesign --force --sign - --identifier me.askalice.SpacialShell "$APP"   # …then the bundle
```
> Signing the bundle alone seals `spacialctl` as a *resource*, leaving the helper binary itself unsigned — which becomes a notarisation failure at M4. Sign nested code first.

**Tests** — no unit test crosses into AppRuntime (unchanged from M1). Manual checklist additions in `docs/testing.md`:
- launch → `spacialctl version` → `spacialctl state --json | jq .screens[0].workspaces`
- `spacialctl subscribe` in one terminal, `Fn+S` on the keyboard, watch an event arrive
- SIGTERM → socket file is gone, `spacialctl state` exits 3 with the right message
- second app instance → refuses the socket, logs `alreadyRunning`, first instance keeps working

**Risks**
- `Task { await store.run(command) }` in the hotkey closure (`AppRuntime.swift:81`) still compiles once `run` is `@discardableResult`; verify with a build, since the `Task`'s result type changes.
- `reloadConfig()` is a `private` main-actor method; the closure needs it at least `fileprivate`/`internal` and must hop via `MainActor.run`.

---

## Task 11 — docs

**Files**
- Create `docs/ipc.md` — the protocol reference: socket path and mode, framing, envelope, the full command table with args and `data` shapes, error strings, exit codes, the `subscribe` contract (one immediate snapshot, coalesced thereafter), the documented races (`move-window` without `--window`), and a worked `jq` example.
- Modify `README.md` — a "Scripting" section: build, `ln -s /Applications/SpacialShell.app/Contents/MacOS/spacialctl /usr/local/bin/spacialctl`, three example invocations, and a pointer to `docs/ipc.md`.
- Modify `docs/config.md:123` — `toggle-shell-ui` is no longer "Reserved; no-op in M1"; it toggles Zen and is published as `zen`.

Leave the approved M1 spec alone (it is a historical record); `docs/ipc.md` is where §15's deferred item is discharged.

---

## Cross-cutting risks

**Network.framework / AF_UNIX on macOS 14–26**
1. `NWParameters.tcp` + `requiredLocalEndpoint = .unix(path:)` is the only route to an AF_UNIX listener and is undocumented. Typechecks on 6.3.3 / macOS 26 SDK; AeroSpace ships it. POSIX fallback designed in Task 6.
2. **`.waiting` is not `.failed`.** A client connecting to a dead socket waits and retries forever unless you treat `.waiting(let e)` as terminal. Affects both the stale-socket probe and the CLI.
3. The socket file is created **asynchronously** during `listener.start()`. `chmod` before `.ready` fails silently with `ENOENT`. Real protection is the `0700` parent directory.
4. `NWListener.cancel()` does **not** unlink the socket file. Explicit `unlink()` in `stop()` and on `.failed`.
5. `EADDRINUSE` surfaces through `stateUpdateHandler`, not as a `throw` from `NWListener(using:)` — hence `start()` is `async throws`.
6. `sun_path` is **104 bytes** (verified in `sys/un.h`). `~/Library/Application Support/SpacialShell/spacialshell.sock` is ~71 for a typical home; guard and fall back to `/tmp/spacialshell-<uid>.sock`. Tests must use short `/tmp` paths, not `NSTemporaryDirectory()`.
7. `NWListener` enforces no connection cap; the registry does.

**Concurrency**
8. `NWConnection` callbacks fire on their queue with no ordering guarantee relative to other `Task`s. Mitigated structurally: a pull-driven read loop per connection (next `receive` only after the previous response is written) and `generation`-guarded publishes.
9. `publish` runs on `WorldStore`'s executor — lock + struct hand-off only, never `await`.
10. Back-pressure: single-slot coalescing mailbox per subscriber + `sendTimeout` cancel. Dropping intermediate snapshots is correct because a snapshot is full state.
11. Publish dedupe (`isEquivalent`) is what stops the 2 s backstop refresh from waking every subscriber twice a second forever.

**Model**
12. Every new verb ends in `normalize()`; the extended property test is the only real proof that I1–I5 survive. Prioritise it over hand-written tests if time is short.
13. `addWorkspace(pinned:false)` and `pinWorkspace(id,false)` both interact with the reaper in ways that surprise callers — D10 and the "unpinning an empty workspace deletes it" test exist to pin the behaviour down.
14. `World.zen` changes `World`'s synthesised `Codable` and `Equatable`; nothing archives `World` today (verified), and `CommandTests.toggleShellUIIsNoop` is the one existing test that must change.

**Toolchain**
15. **Overloaded enum case names break pattern matching** (measured). Distinct base names, no exceptions.
16. `#expect(structValue.mutatingCall())` does not compile under swift-testing — bind to a `let` first. Applies to every new `store.world` assertion.
17. Making `WorldStore.run` return a value turns `await run.value` in three `WorldStoreTests` into "result unused" warnings; prefix with `_ =`.

---

### Critical Files for Implementation
- `/Users/alice/code/spacial-shell/Sources/SpacialShellKit/Store/WorldStore.swift`
- `/Users/alice/code/spacial-shell/Sources/SpacialShellKit/Commands/CommandRunner.swift`
- `/Users/alice/code/spacial-shell/Sources/SpacialShellKit/Model/World+Mutations.swift`
- `/Users/alice/code/spacial-shell/Sources/SpacialShell/AppRuntime.swift`
- `/Users/alice/code/spacial-shell/Package.swift`