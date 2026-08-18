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
    @Test func onChangeFiresWithWorld() async {
        let be = FakeBackend(snapshot: snap([win(a)], focused: a))
        let box = ChangeBox()
        let store = WorldStore(backend: be, config: Config(), world: nil, zeroSliverBundleIDs: [], onChange: { w in Task { await box.set(w) } })
        await store.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await box.value?.screens["D1"]?.active.windows == [a])
    }
}
func touches(_ c: FakeBackend.Call, _ r: WindowRef) -> Bool {
    switch c {
    case .setFrame(let x, _), .setPosition(let x, _), .raise(let x), .close(let x): return x == r
    }
}
actor ChangeBox { var value: World?; func set(_ w: World) { value = w } }
