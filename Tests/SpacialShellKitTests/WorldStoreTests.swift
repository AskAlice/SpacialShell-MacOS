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
    @Test func exportForTerminationCarriesTheCurrentWorld() async {
        let (store, _) = await make(snap([win(a), win(b)], focused: a))
        let world = await store.world
        let export = await store.exportForTermination()
        #expect(export.world == world && export.displays == [d1] && export.observed[a] != nil)
        // Maximize layout: `a` is the anchor and tiled, `b` is parked in the corner. Only `b` is
        // stranded anywhere the user cannot reach, so only `b` is the restore's business —
        // centring `a` as well would scramble a layout that is perfectly fine (I4).
        #expect(export.parked == [b])
    }
    /// A window retired after three failed writes *while parked* leaves the model entirely, so
    /// nothing would ever unpark it — spec §7.4 says quitting must not strand it in the corner.
    @Test func retiredWhileParkedWindowIsExportedAsStranded() async {
        // Two windows, maximize layout: `a` is the anchor, `b` is parked in the corner.
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        #expect(await store.debugSideTables().parked.contains(b))
        await be.fail(b)
        for y in [100.0, 200.0, 300.0] {
            await store.apply(.windowMoved(b, CGRect(x: y, y: y, width: 300, height: 200)))
        }
        #expect(await store.world.ignored.contains(b))          // retired, unreachable by the reconciler
        let export = await store.exportForTermination()
        #expect(export.stranded[b] != nil && export.stranded[a] == nil)
    }
    /// C1: macOS reports an empty screen list mid-hot-plug, at wake and around the lock screen.
    /// Acting on one used to reseed the world from nothing — every workspace dropped, and the
    /// re-adoption that followed force-unwrapped a screen that no longer existed.
    @Test func emptyDisplaySnapshotIsIgnored() async {
        let (store, _) = await make(snap([win(a)], focused: a))
        let before = await store.world
        await store.apply(.snapshot(Snapshot(displays: [], apps: [], windows: [], focused: nil)))
        let after = await store.world
        #expect(after == before)
        #expect(after.invariantViolations().isEmpty)
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
    @Test func interleavedSnapshotDuringPlanDoesNotResurrectSideTables() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.reset()
        await be.armGate(onWriteNumber: 1)                       // plan is [setFrame(b), setPosition(a)]
        let run = Task { await store.run(.focusWindow(.right)) }
        while await !be.isGateArmed() { try? await Task.sleep(for: .milliseconds(5)) }
        await store.apply(.snapshot(snap([win(b)], focused: b)))  // a vanished while our plan is mid-flight
        await be.releaseGate()
        await run.value
        let w = await store.world
        #expect(w.location(of: a) == nil && !w.ignored.contains(a))
        let tables = await store.debugSideTables()
        #expect(!tables.parked.contains(a) && tables.prePark[a] == nil && tables.observed[a] == nil)
        #expect(await !be.calls.contains(.setPosition(a, CGPoint(x: 999, y: 699))))   // stale write never issued
    }
    @Test func intentEchoDoesNotAbortInFlightPlan() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.reset()
        await be.armGate(onWriteNumber: 1)                       // plan is [setFrame(b), setPosition(a)]
        let run = Task { await store.run(.focusWindow(.right)) }
        while await !be.isGateArmed() { try? await Task.sleep(for: .milliseconds(5)) }
        let planned = CGRect(x: 8, y: 33, width: 984, height: 658)
        await store.apply(.windowMoved(b, planned))              // AX echo of the very write in flight
        await be.releaseGate()
        await run.value
        let calls = await be.calls
        #expect(calls.contains(.setFrame(b, planned)))
        #expect(calls.contains(.setPosition(a, CGPoint(x: 999, y: 699))))   // plan ran to completion
    }
    @Test func threeFailedWritesMoveWindowToIgnored() async {
        let (store, be) = await make(snap([win(a)], focused: a))
        await be.fail(a)
        for y in [100.0, 200.0, 300.0] {
            await store.apply(.windowMoved(a, CGRect(x: y, y: y, width: 984, height: 658)))
        }
        #expect(await store.world.ignored.contains(a))
        #expect(await store.world.location(of: a) == nil)
        await be.reset()
        await store.apply(.snapshot(snap([win(a)], focused: nil)))       // stays ignored, never placed again
        let calls = await be.calls
        #expect(!calls.contains { touches($0, a) })
    }
    @Test func commandsAreIgnoredWhileLocked() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await store.apply(.screenLocked)
        await be.reset()
        await store.run(.focusWindow(.right))
        #expect(await be.calls.isEmpty)
        #expect(await store.world.focus.window == a)
        await store.apply(.screenUnlocked)
        await be.reset()
        await store.run(.focusWindow(.right))
        #expect(await store.world.focus.window == b)
        #expect(await !be.calls.isEmpty)
    }
    /// Spec §7.7 freeze. Setting `locked` only stops the *next* pass from starting — a plan
    /// already mid-flight kept writing frames at a locked screen, where AX reports the lock
    /// screen's geometry rather than the user's. The lock now bumps `generation`, which is the
    /// signal every await in `reconcile()` already checks.
    @Test func lockMidPlanStopsFurtherWrites() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.reset()
        await be.armGate(onWriteNumber: 1)                       // plan is [setFrame(b), setPosition(a)]
        let run = Task { await store.run(.focusWindow(.right)) }
        while await !be.isGateArmed() { try? await Task.sleep(for: .milliseconds(5)) }
        await store.apply(.screenLocked)                         // the screen locks mid-plan
        await be.releaseGate()
        await run.value
        // The write that was already in flight lands; nothing after it is issued.
        #expect(await be.calls == [.setFrame(b, CGRect(x: 8, y: 33, width: 984, height: 658))])
    }
    @Test func onChangeFiresWithWorld() async {
        let be = FakeBackend(snapshot: snap([win(a)], focused: a))
        let box = ChangeBox()
        let store = WorldStore(backend: be, config: Config(), world: nil, zeroSliverBundleIDs: [], onChange: { w in Task { await box.set(w) } })
        await store.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await box.value?.screens["D1"]?.active.windows == [a])
    }

    /// Deferred from Task 13's review: a store-level counterpart to `PropertyTests`, which drives
    /// `World` directly. This drives the actor through `FakeBackend`, so it also exercises
    /// adoption-from-snapshot, vanish-on-refresh, native focus, and the parking side tables —
    /// everything `PropertyTests` cannot see because it never goes through `WorldStore`.
    struct LiveWindow { var ref: WindowRef; var kind: WindowKind; var minimized = false; var fullscreen = false; var parent: WindowRef? }

    func randomSnapshot(_ live: [LiveWindow], focused: WindowRef?) -> Snapshot {
        snap(live.map { win($0.ref, kind: $0.kind, min: $0.minimized, fs: $0.fullscreen, parent: $0.parent) }, focused: focused)
    }

    @Test(arguments: 0..<50)
    func randomSnapshotsPreserveInvariants(seed: Int) async {
        var rng = TestRNG(seed: UInt64(seed) &+ 7_000)
        let be = FakeBackend(snapshot: snap([]))
        let store = WorldStore(backend: be, config: Config(), world: nil, zeroSliverBundleIDs: ["us.zoom.xos"], onChange: { _ in })
        await store.start()

        let cmds: [Command] = [
            .focusWorkspace(.up), .focusWorkspace(.down), .focusWorkspaceIndex(Int.random(in: 1...4, using: &rng)),
            .focusWindow(.left), .focusWindow(.right), .closeFocusedWindow,
            .moveWindow(.left), .moveWindow(.right), .moveWindowToWorkspace(.up), .moveWindowToWorkspace(.down),
            .cycleLayout, .toggleShellUI, .focusScreen(.prev), .focusScreen(.next),
            .moveWindowToScreen(.prev), .moveWindowToScreen(.next), .toggleFloat,
        ]
        var live: [LiveWindow] = []
        var nextID: WindowID = 1

        for step in 0..<30 {
            switch Int.random(in: 0..<10, using: &rng) {
            case 0...3:   // snapshot event: mutate the live-window set, then resend it whole
                switch Int.random(in: 0..<4, using: &rng) {
                case 0 where live.count < 10:
                    let kind: WindowKind = [.tile, .tile, .tile, .float, .ephemeral, .ignore].randomElement(using: &rng)!
                    let parent = Bool.random(using: &rng) ? live.randomElement(using: &rng)?.ref : nil
                    live.append(LiveWindow(ref: WindowRef(id: nextID, pid: 1), kind: kind, parent: parent))
                    nextID += 1
                case 1 where !live.isEmpty:
                    live.remove(at: Int.random(in: 0..<live.count, using: &rng))
                case 2 where !live.isEmpty:
                    live[Int.random(in: 0..<live.count, using: &rng)].minimized.toggle()
                case 3 where !live.isEmpty:
                    live[Int.random(in: 0..<live.count, using: &rng)].fullscreen.toggle()
                default: break   // list too small/large for the picked mutation: resend unchanged
                }
                let focused = live.isEmpty ? nil : (Bool.random(using: &rng) ? live.randomElement(using: &rng)?.ref : nil)
                await store.apply(.snapshot(randomSnapshot(live, focused: focused)))
            case 4...6:   // run a random command
                await store.run(cmds.randomElement(using: &rng)!)
            default:   // external move (AX echo or a real drag)
                if let l = live.randomElement(using: &rng) {
                    let f = CGRect(x: Double.random(in: 0...500, using: &rng), y: Double.random(in: 0...500, using: &rng), width: 300, height: 200)
                    await store.apply(.windowMoved(l.ref, f))
                }
            }
            let w = await store.world   // bind before calling: `#expect((await store.world).invariantViolations()...)` doesn't compile.
            let v = w.invariantViolations()
            #expect(v.isEmpty, "seed \(seed) step \(step): \(v)")
            if !v.isEmpty { return }
        }
    }
}
func touches(_ c: FakeBackend.Call, _ r: WindowRef) -> Bool {
    switch c {
    case .setFrame(let x, _), .setPosition(let x, _), .raise(let x), .close(let x): return x == r
    }
}
actor ChangeBox { var value: World?; func set(_ w: World) { value = w } }
