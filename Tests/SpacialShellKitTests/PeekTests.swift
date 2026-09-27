import Testing
import Foundation
@testable import SpacialShellKit

/// #179: hovering a rail hover-card preview peeks the real window — a transient `World.peek`, set
/// by `.peek` and placed by the reconciler — without moving focus or the active rows.
@Suite struct PeekTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1)
    let cfg = LayoutConfig(gap: 10, layouts: .builtins)
    /// `ReconcilerTests`' maximize frame: the visible frame less the gap, 1 pt short.
    let rect = CGRect(x: 10, y: 35, width: 980, height: 654)

    /// `a` focused in the active row (ws1), `b` alone in the row above it, parked.
    func world() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        w = CommandRunner.apply(.moveWindowToWorkspace(.down), to: w, in: .test()).0
        return w
    }
    func run(_ command: Command, _ w: World) -> CommandOutcome { CommandRunner.run(command, on: w, in: .test()) }
    func desired(_ w: World, refused: [WindowRef: Refusal] = [:], peekHome: [WindowRef: CGRect] = [:]) -> [WindowRef: Placement] {
        Reconciler.desired(world: w, displays: [d1], config: cfg, observed: [:], prePark: [:], parkedNow: [],
                           zeroSliver: [], refused: refused, peekHome: peekHome)
    }

    // MARK: the command

    @Test func peekSetsAndClearsTheStateAndMovesNothingElse() {
        let w = world()
        #expect(w.focus.window == a && w.screens["D1"]!.activeIndex == 1)
        let peeked = run(.peek(b), w)
        #expect(peeked.world.peek == b)
        #expect(peeked.report == .done && peeked.effects == [.relayout])
        var same = peeked.world; same.peek = nil
        #expect(same == w, "a peek changes nothing in the model but the peek")

        let ended = run(.peek(nil), peeked.world)
        #expect(ended.world.peek == nil && ended.world == w)
    }

    @Test func aPeekLeavesFocusAlone() {
        let w = run(.peek(b), world()).world
        #expect(w.focus.window == a)
        #expect(w.screens["D1"]!.activeIndex == 1)
        #expect(w.screens["D1"]!.workspaces[0].anchor == b && w.screens["D1"]!.workspaces[1].anchor == a)
    }

    @Test func movingToAnotherPreviewSwapsThePeek() {
        var w = world()
        w.adopt(c, kind: .tile, on: "D1")   // into the active row, next to `a`
        let first = run(.peek(b), w).world
        #expect(run(.peek(c), first).world.peek == c)
    }

    @Test func aMinimizedWindowOrAnUnknownOneIsNotPeeked() {
        var w = world(); w.setHidden(b, true)
        let hidden = run(.peek(b), w)
        #expect(hidden.world.peek == nil)
        if case .noop = hidden.report {} else { Issue.record("expected a no-op, got \(hidden.report)") }
        let unknown = run(.peek(WindowRef(id: 99, pid: 9)), world())
        #expect(unknown.report == .failed(.unknownWindow(WindowRef(id: 99, pid: 9))))
    }

    /// The pointer moved on from a peeked preview to one that cannot be shown: the first window's
    /// peek ends rather than staying on screen under the new preview's highlight.
    @Test func aPreviewThatCannotBeShownEndsThePeekBeforeIt() {
        var w = world()
        w.adopt(c, kind: .tile, on: "D1"); w.setHidden(c, true)
        let moved = run(.peek(c), run(.peek(b), w).world)
        #expect(moved.world.peek == nil && moved.effects == [.relayout])
    }

    @Test func aSheetPeeksItsOwner() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        w.adopt(c, kind: .float, on: "D1", parent: b)
        #expect(run(.peek(c), w).world.peek == b)
    }

    // MARK: what ends it

    @Test func anyOtherCommandEndsThePeek() {
        let w = run(.peek(b), world()).world
        #expect(run(.focusWindow(.right), w).world.peek == nil, "a hotkey ends the peek")
        #expect(run(.focusWorkspace(.up), w).world.peek == nil, "a workspace switch ends the peek")
        let clicked = run(.focusWindowRef(b), w).world
        #expect(clicked.peek == nil && clicked.focus.window == b, "a click on the preview focuses it, as #51 does")
    }

    @Test func aWorkspaceSwitchFromOutsideACommandEndsThePeek() {
        var w = run(.peek(b), world()).world
        w.activate(index: 0, on: "D1")   // e.g. the user ⌘Tabbed to a window in another row
        #expect(w.peek == nil)
    }

    @Test func aVanishedPeekedWindowClearsThePeek() {
        var w = run(.peek(b), world()).world
        w.remove(b)
        #expect(w.peek == nil)
        var hidden = run(.peek(b), world()).world
        hidden.setHidden(b, true)
        #expect(hidden.peek == nil, "minimized while peeked: nothing left to show")
    }

    // MARK: never persisted

    @Test func aPeekNeverReachesStateJSON() throws {
        let w = run(.peek(b), world()).world
        #expect(w.peek == b)
        let state = String(decoding: try JSONEncoder().encode(PersistedState(world: w)), as: UTF8.self)
        #expect(!state.contains("peek"))
        #expect(try JSONDecoder().decode(PersistedState.self, from: Data(state.utf8)) == PersistedState(world: w))
        let encoded = try JSONEncoder().encode(w)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("peek"))
        #expect(try JSONDecoder().decode(World.self, from: encoded).peek == nil)
    }

    /// `World.CodingKeys` exists only to leave `peek` out; every other stored property must be in
    /// it, or it silently stops being encoded.
    @Test func worldCodesEveryPropertyButThePeek() {
        let stored = Set(Mirror(reflecting: world()).children.compactMap(\.label))
        let coded = Set(World.CodingKeys.allCases.map(\.stringValue))
        #expect(stored.subtracting(coded) == ["peek"])
        #expect(coded.isSubset(of: stored))
    }

    // MARK: the reconciler

    @Test func thePeekedWindowIsCentredAt80By85PercentAndParkedAgainAfter() {
        let before = desired(world())
        #expect(before[b] == .parked(CGPoint(x: 999, y: 699)))

        let peeked = run(.peek(b), world()).world
        let d = desired(peeked)
        // 980 × 0.8 = 784, 654 × 0.85 = 555.9 → 556; centred in `rect`.
        #expect(d[b] == .frame(CGRect(x: 108, y: 84, width: 784, height: 556)))
        #expect(Reconciler.peekFrame(in: rect) == CGRect(x: 108, y: 84, width: 784, height: 556))
        #expect(d[a] == .frame(rect), "the rest of the display is left exactly as it was")

        let after = desired(run(.peek(nil), peeked).world)
        #expect(after[b] == .parked(CGPoint(x: 999, y: 699)))
        #expect(after == before)
    }

    @Test func aPeekedWindowInTheActiveRowComesBackToItsTile() {
        var w = World.empty(screens: ["D1"], defaultLayout: .column)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        let tiles = desired(w)
        let d = desired(run(.peek(b), w).world)
        #expect(d[b] == .frame(Reconciler.peekFrame(in: rect)))
        #expect(d[a] == tiles[a])
        #expect(desired(run(.peek(nil), run(.peek(b), w).world).world) == tiles)
    }

    @Test func aWindowThatRefusesThePeekSizeIsCentredAtItsOwn() {
        let peeked = run(.peek(b), world()).world
        let asked = Reconciler.peekFrame(in: rect)
        let d = desired(peeked, refused: [b: Refusal(asked: asked, size: CGSize(width: 500, height: 400))])
        #expect(d[b] == .frame(CGRect(x: 250, y: 162, width: 500, height: 400)))
    }

    @Test func aFloatingWindowGoesBackToWhereItWasBeforeThePeek() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .float, on: "D1")
        let home = CGRect(x: 200, y: 200, width: 300, height: 200)
        #expect(desired(w)[b] == .untouched)
        let peeked = run(.peek(b), w).world
        #expect(desired(peeked, peekHome: [b: home])[b] == .frame(Reconciler.peekFrame(in: rect)))
        #expect(desired(run(.peek(nil), peeked).world, peekHome: [b: home])[b] == .frame(home))
    }
}

/// #179 in the store: the peek is placed and raised without activating anything, and neither the
/// raise nor its late echoes are read as the user focusing the peeked window.
@Suite struct PeekStoreTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 2)
    /// `WorldStoreTests`' M1 geometry: no panels, gap 8.
    let rect = CGRect(x: 8, y: 33, width: 984, height: 658)

    func win(_ r: WindowRef, bundle: String, kind: WindowKind = .tile) -> WindowSnapshot {
        WindowSnapshot(ref: r, frame: CGRect(x: 0, y: 0, width: 300, height: 200), title: "t", bundleID: bundle, kind: kind,
                       parent: nil, isMinimized: false, isFullscreen: false)
    }
    final class Clock: @unchecked Sendable { var t = ContinuousClock.now }

    /// `a` focused in the active row, `b` (another app) parked in another row.
    func make(bKind: WindowKind = .tile, clock: Clock = Clock()) async -> (WorldStore, FakeBackend) {
        var c = Config(); c.showPanels = false; c.categoryOrder = []
        let s = Snapshot(displays: [d1], apps: [AppInfo(pid: 1, bundleID: "com.a", isHidden: false), AppInfo(pid: 2, bundleID: "com.b", isHidden: false)],
                         windows: [win(a, bundle: "com.a"), win(b, bundle: "com.b", kind: bKind)], focused: a)
        let be = FakeBackend(snapshot: s)
        let store = WorldStore(backend: be, config: c, world: nil, zeroSliverBundleIDs: [], now: { clock.t },
                               onChange: { _, _ in })
        await store.start()
        await store.run(.moveWindowToWorkspace(.down))   // `a` → a row of its own, focused; `b` stays, parked
        await be.reset()
        return (store, be)
    }

    @Test func thePeekRaiseIsNotReadAsAFocusChange() async {
        let (store, be) = await make()
        let settled = await store.world
        #expect(settled.focus.window == a)
        let row = settled.screens["D1"]!.activeIndex
        #expect(settled.location(of: b)!.index != row)

        await store.run(.peek(b))
        let calls = await be.calls
        #expect(calls.contains(.setFrame(b, Reconciler.peekFrame(in: rect))))
        #expect(calls.contains(.raiseWithoutActivating(b)))
        #expect(!calls.contains(.raise(b)), "a peek never focuses the window")

        // The raise made `b` its app's focused window, and macOS says so — twice, and its app too.
        await store.apply(.focusChanged(b))
        await store.apply(.focusChanged(b))
        await store.apply(.appActivated(pid: b.pid))
        var w = await store.world
        #expect(w.focus.window == a && w.screens["D1"]!.activeIndex == row && w.peek == b)

        await be.reset()
        await store.run(.peek(nil))
        let back = await be.calls
        #expect(back.contains { if case .setPosition(b, _) = $0 { true } else { false } }, "the peeked window is parked again")
        #expect(back.contains(.raise(a)), "the model's focus goes back in front")

        await store.apply(.focusChanged(b))
        w = await store.world
        #expect(w.focus.window == a && w.screens["D1"]!.activeIndex == row && w.peek == nil)
    }

    /// A long hover: past the raise's echo window, macOS reporting the peeked window is still the
    /// peek, not the user — for as long as the peek lasts.
    @Test func aReportOfThePeekedWindowDuringALongPeekIsNotAFocusChange() async {
        let clock = Clock()
        let (store, _) = await make(clock: clock)
        let row = await store.world.screens["D1"]!.activeIndex
        await store.run(.peek(b))
        clock.t = clock.t.advanced(by: .seconds(3))
        await store.apply(.focusChanged(b))
        let w = await store.world
        #expect(w.focus.window == a && w.screens["D1"]!.activeIndex == row && w.peek == b)
    }

    /// The raise's report can land after the hover has already ended the peek: still our own echo,
    /// not the user choosing the window that has just been parked again.
    @Test func aLateEchoOfThePeekRaiseAfterThePeekIsNotAFocusChange() async {
        let (store, _) = await make()
        let row = await store.world.screens["D1"]!.activeIndex
        await store.run(.peek(b))
        await store.run(.peek(nil))
        await store.apply(.focusChanged(b))   // the peek raise's late echo, in raise order…
        #expect(await store.world.screens["D1"]!.activeIndex == row, "a late peek echo switched the workspace")
        await store.apply(.focusChanged(a))   // …then the focus's re-raise
        let w = await store.world
        #expect(w.focus.window == a && w.screens["D1"]!.activeIndex == row, "a late peek echo switched the workspace")
    }

    /// ⌘Tab (or a Dock click) to the peeked window's app while the peek lasts is the user's
    /// choice: the model follows it, and the switch ends the peek.
    @Test func theUserSwitchingToThePeekedWindowIsAFocusChange() async {
        let clock = Clock()
        let (store, _) = await make(clock: clock)
        await store.run(.peek(b))
        clock.t = clock.t.advanced(by: .seconds(3))
        await store.apply(.humanInput)
        await store.apply(.focusChanged(b))
        let w = await store.world
        #expect(w.focus.window == b && w.peek == nil)
        #expect(w.screens["D1"]!.activeIndex == w.location(of: b)!.index)
    }

    /// Every command ends a peek, even one that changes nothing or fails.
    @Test func aCommandThatDoesNothingStillEndsThePeek() async {
        let (store, be) = await make()
        await store.run(.peek(b))
        await be.reset()
        let report = await store.run(.resizeWindow(.width, grow: true))   // maximize: nothing to resize
        if case .noop = report {} else { Issue.record("expected a no-op, got \(report)") }
        #expect(await store.world.peek == nil)
        #expect(await be.calls.contains { if case .setPosition(b, _) = $0 { true } else { false } }, "and the window is put back")
        await store.run(.peek(b))
        await store.run(.focusWindowRef(WindowRef(id: 99, pid: 9)))   // fails: no such window
        #expect(await store.world.peek == nil)
    }

    /// #164: a window that refused its tile keeps that refusal through a peek, whose own frame it
    /// refuses too: back in its tile it is centred at once, rather than asked for the whole tile
    /// and learning the refusal all over again.
    @Test func aPeekDoesNotCostTheWindowItsTileRefusal() async {
        let (store, be) = await make()
        await store.run(.focusWindowRef(b))                    // `b` framed in its own row
        let tile = CGRect(x: 8, y: 33, width: 984, height: 658)
        let small = CGRect(x: 8, y: 33, width: 600, height: 400)
        await store.apply(.windowResized(b, small))            // refused…
        await store.apply(.windowResized(b, small))            // …twice: confirmed, centred
        #expect(await store.debugRefusal(b)?.asked == tile)

        await store.run(.focusWindowRef(a))                    // `b` parked again
        await store.run(.peek(b))
        let peekAsked = Reconciler.peekFrame(in: tile)
        let peekGot = CGRect(origin: peekAsked.origin, size: small.size)
        await store.apply(.windowResized(b, peekGot))          // the peek frame refused as well
        await store.apply(.windowResized(b, peekGot))
        #expect(await store.debugRefusal(b)?.asked == peekAsked)
        await be.reset()
        await store.run(.focusWindowRef(b))                    // the click: back to its tile
        #expect(await store.debugRefusal(b)?.asked == tile, "the tile's refusal is back")
        #expect(!(await be.calls.contains(.setFrame(b, tile))), "not the whole tile, to be refused again")
    }

    @Test func aPeekRaisesOnceAndSwapsWithoutRestoringInBetween() async {
        let (store, be) = await make()
        await store.run(.peek(b))
        await store.run(.peek(b))
        #expect(await be.calls.filter { $0 == .raiseWithoutActivating(b) }.count == 1)
        await be.reset()
        await store.run(.peek(a))   // the focused window's own preview
        let calls = await be.calls
        #expect(calls.contains(.raiseWithoutActivating(a)))
        #expect(!calls.contains(.raise(a)), "a swap is not the end of the peek")
    }

    @Test func aFloatingWindowParkedAfterItsPeekRemembersWhereItWas() async {
        let (store, be) = await make(bKind: .float)
        let home = await store.debugRecord(b).prePark
        #expect(home != nil)
        await store.run(.peek(b))
        await store.run(.peek(nil))
        #expect(await store.debugRecord(b).prePark == home, "not the peek's frame")
        await be.reset()
        await store.run(.focusWindowRef(b))
        #expect(await be.calls.contains(.setFrame(b, home!)))
    }
}
