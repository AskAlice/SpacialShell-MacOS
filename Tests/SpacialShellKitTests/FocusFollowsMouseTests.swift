import Testing
import Foundation
@testable import SpacialShellKit

/// #135 (G28): focus follows the mouse, opt-in, after a dwell. Only a resting pointer over another
/// tiled or floating window focuses it, the topmost one where they overlap; the rail, the tab bar,
/// ephemeral windows and anything they overlap never do, and nothing but pointer movement starts
/// the wait.
@Suite struct FocusFollowsMouseTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 2)
    let tileA = CGRect(x: 0, y: 0, width: 100, height: 100)
    let tileB = CGRect(x: 110, y: 0, width: 100, height: 100)
    var targets: PointerTargets {
        PointerTargets(windows: [.init(window: a, frame: tileA), .init(window: b, frame: tileB)], covers: [], focused: a)
    }
    let inB = CGPoint(x: 150, y: 50)
    /// 150 ms, the default.
    var ffm: FocusFollowsMouse { FocusFollowsMouse() }

    // MARK: the dwell

    @Test func restingOnAnotherTileFocusesItOnceTheDelayPasses() {
        var f = ffm
        f.moved(to: inB, over: b, focused: a, now: 10)
        #expect(f.deadline == 10.15)
        #expect(f.tick(now: 10.1, over: b, focused: a) == nil)
        #expect(f.tick(now: 10.15, over: b, focused: a) == b)
        #expect(f.pending == nil)
        #expect(f.tick(now: 11, over: b, focused: a) == nil)   // once
    }

    /// Mouse jitter within `restRadius` is still resting: the clock keeps running from the stop.
    @Test func jitterKeepsTheClock() {
        var f = ffm
        f.moved(to: inB, over: b, focused: a, now: 10)
        f.moved(to: CGPoint(x: inB.x + 3, y: inB.y - 3), over: b, focused: a, now: 10.1)
        #expect(f.deadline == 10.15)
        #expect(f.tick(now: 10.15, over: b, focused: a) == b)
    }

    /// Sweeping across a window on the way to another one never focuses it: every move further
    /// than `restRadius` starts the wait again.
    @Test func sweepingAcrossAWindowNeverFocusesIt() {
        var f = ffm
        var t = 10.0
        for x in stride(from: 110.0, through: 210.0, by: 10) {
            f.moved(to: CGPoint(x: x, y: 50), over: x < 210 ? b : nil, focused: a, now: t)
            #expect(f.tick(now: t, over: b, focused: a) == nil)
            t += 0.05   // 20 moves a second, 100 pt a second: slow, and still a sweep
        }
        #expect(f.pending == nil)   // it left the window
    }

    @Test func movingOntoTheFocusedWindowOrNothingCancels() {
        var f = ffm
        f.moved(to: inB, over: b, focused: a, now: 10)
        f.moved(to: CGPoint(x: 50, y: 50), over: a, focused: a, now: 10.05)
        #expect(f.pending == nil)
        f.moved(to: inB, over: b, focused: a, now: 10.1)
        f.moved(to: CGPoint(x: 105, y: 50), over: nil, focused: a, now: 10.12)   // the gap
        #expect(f.pending == nil)
        #expect(f.tick(now: 11, over: b, focused: a) == nil)
    }

    @Test func anotherWindowStartsTheWaitAgain() {
        var f = ffm
        f.moved(to: inB, over: b, focused: a, now: 10)
        f.moved(to: CGPoint(x: 250, y: 50), over: c, focused: a, now: 10.1)
        #expect(f.pending?.target == c && f.deadline == 10.25)
        #expect(f.tick(now: 10.25, over: c, focused: a) == c)
    }

    /// A key, a click or a command moved focus while the pointer waited: the user already chose.
    @Test func focusMovingByAnotherRouteAbandonsTheDwell() {
        var f = ffm
        f.moved(to: inB, over: b, focused: a, now: 10)
        #expect(f.tick(now: 10.2, over: b, focused: c) == nil)
        #expect(f.pending == nil)
    }

    /// #107: a command focuses a window on another display and warps the pointer to its centre.
    /// The warp posts no move, and a later move there is over the focused window: no second change.
    @Test func aPointerWarpNeverCausesASecondFocusChange() {
        var f = ffm
        f.moved(to: inB, over: b, focused: a, now: 10)   // pending on b when the key lands
        #expect(f.tick(now: 10.2, over: c, focused: c) == nil)
        f.moved(to: CGPoint(x: 1150, y: 150), over: c, focused: c, now: 10.3)
        #expect(f.pending == nil)
    }

    /// The layout moved under a resting pointer (a switch, a resize): what is under it now decides.
    @Test func aTargetNoLongerUnderThePointerIsNotFocused() {
        var f = ffm
        f.moved(to: inB, over: b, focused: a, now: 10)
        #expect(f.tick(now: 10.2, over: nil, focused: a) == nil)
    }

    /// Only movement arms a dwell: focus moving under a still pointer is never undone.
    @Test func nothingHappensWithoutAMove() {
        var f = ffm
        #expect(f.deadline == nil)
        #expect(f.tick(now: 100, over: b, focused: a) == nil)
    }

    @Test func aKeyOrAButtonCancels() {
        var f = ffm
        f.moved(to: inB, over: b, focused: a, now: 10)
        f.cancel()
        #expect(f.deadline == nil)
        #expect(f.tick(now: 11, over: b, focused: a) == nil)
    }

    @Test func delayIsClamped() {
        #expect(FocusFollowsMouse(delayMs: 0).delay == 0.05)
        #expect(FocusFollowsMouse(delayMs: 400).delay == 0.4)
        #expect(FocusFollowsMouse(delayMs: 60_000).delay == 2)
    }

    /// The window server's own stacking has the last word.
    @Test func onlyAnOrdinaryWindowOfTheTargetsAppInFrontIsAccepted() {
        #expect(FocusFollowsMouse.accepts(b, frontmost: (pid: 1, layer: 0)))
        #expect(!FocusFollowsMouse.accepts(b, frontmost: (pid: 9, layer: 0)))    // another app's window
        #expect(!FocusFollowsMouse.accepts(b, frontmost: (pid: 1, layer: 101)))  // its own menu
        #expect(!FocusFollowsMouse.accepts(b, frontmost: nil))
    }

    // MARK: hit-testing

    @Test func hitTestFindsTilesAndNotGapsOrCovers() {
        var t = targets
        #expect(t.window(at: inB) == b)
        #expect(t.window(at: CGPoint(x: 105, y: 50)) == nil)   // the gap
        #expect(t.window(at: CGPoint(x: 500, y: 500)) == nil)
        t.covers = [CGRect(x: 140, y: 40, width: 20, height: 20)]
        #expect(t.window(at: inB) == nil)
        #expect(t.window(at: CGPoint(x: 120, y: 90)) == b)
    }

    /// 2026-09-26 (#135): floating windows are targets, and the topmost window under the pointer
    /// wins. A float over a tile takes the overlap; the tile keeps the rest of itself.
    @Test func theTopmostWindowUnderThePointerWins() {
        let float = CGRect(x: 140, y: 40, width: 100, height: 40)   // over b's right edge and past it
        var t = targets
        t.windows.insert(.init(window: c, frame: float), at: 0)
        #expect(t.window(at: inB) == c)
        #expect(t.window(at: CGPoint(x: 230, y: 60)) == c)   // beside b, still on the float
        #expect(t.window(at: CGPoint(x: 120, y: 90)) == b)   // b, clear of the float
        // b raised over the float: the overlap is b's, the part sticking out is still the float's.
        t.windows = [t.windows[2], t.windows[0], t.windows[1]]
        #expect(t.window(at: inB) == b)
        #expect(t.window(at: CGPoint(x: 230, y: 60)) == c)
    }

    /// A window that cannot take focus still hides whatever is stacked under it.
    @Test func anUnfocusableWindowStillHidesWhatIsUnderIt() {
        var t = targets
        t.windows[1].focusable = false
        t.windows.append(.init(window: c, frame: CGRect(x: 100, y: 0, width: 200, height: 100)))
        #expect(t.window(at: inB) == nil)                         // b's, and b takes nothing
        #expect(t.window(at: CGPoint(x: 105, y: 50)) == c)        // the gap shows c
        #expect(t.window(at: CGPoint(x: 250, y: 50)) == c)
    }

    /// The store's stacking: focus goes to the front, the rest keep their order, and windows the
    /// world no longer holds drop out.
    @Test func restackPutsFocusOnTopAndForgetsTheGone() {
        var w = World.seeded(screens: [d1.id], config: Config())
        let sid = w.screenOrder[0]
        w.screens[sid]!.workspaces[0].windows = [a, b]
        w.ephemeral = [c]
        #expect(PointerTargets.restack([], focused: a, world: w) == [a])
        #expect(PointerTargets.restack([a, c], focused: b, world: w) == [b, a, c])
        #expect(PointerTargets.restack([b, a, c], focused: a, world: w) == [a, b, c])
        #expect(PointerTargets.restack([b, WindowRef(id: 9, pid: 9), a], focused: nil, world: w) == [b, a])
    }

    @Test func panelStripsFollowTheRailSide() {
        var config = Config(); config.panelWidth = 48; config.panelHeight = 34
        let vf = CGRect(x: 0, y: 25, width: 1000, height: 675)
        #expect(PointerTargets.panelStrips(vf, config: config) == [
            CGRect(x: 0, y: 25, width: 48, height: 675), CGRect(x: 0, y: 25, width: 1000, height: 34)])
        config.railSide = .right
        #expect(PointerTargets.panelStrips(vf, config: config)[0] == CGRect(x: 952, y: 25, width: 48, height: 675))
    }

    // MARK: from the store

    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let d2 = DisplayInfo(id: "D2", frame: CGRect(x: 1000, y: 0, width: 800, height: 600), visibleFrame: CGRect(x: 1000, y: 0, width: 800, height: 600), isMain: false)

    func win(_ r: WindowRef, _ f: CGRect, kind: WindowKind = .tile, fullscreen: Bool = false) -> WindowSnapshot {
        WindowSnapshot(ref: r, frame: f, title: "t", bundleID: r.pid == 1 ? "com.x" : "com.y", kind: kind, parent: nil,
                       isMinimized: false, isFullscreen: fullscreen)
    }

    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var got: [PointerTargets] = []
        func add(_ t: PointerTargets) { lock.withLock { got.append(t) } }
        var all: [PointerTargets] { lock.withLock { got } }
    }

    /// `a` and `b` tiled as columns on D1, plus `extra`.
    func make(_ extra: [WindowSnapshot] = [], panels: Bool = false, autohide: Bool = false) async -> (WorldStore, Sink) {
        let ws = [win(a, CGRect(x: 0, y: 30, width: 300, height: 200)), win(b, CGRect(x: 0, y: 30, width: 300, height: 200))] + extra
        let s = Snapshot(displays: [d1, d2], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false),
                                                    AppInfo(pid: 2, bundleID: "com.y", isHidden: false)],
                         windows: ws, focused: a)
        var config = Config(); config.showPanels = panels; config.railAutohide = autohide
        config.categoryOrder = []; config.defaultLayout = .column
        let sink = Sink()
        let store = WorldStore(backend: FakeBackend(snapshot: s), config: config, world: nil, zeroSliverBundleIDs: [],
                               onPointerTargets: { sink.add($0) }, onChange: { _, _ in })
        await store.start()
        return (store, sink)
    }
    func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    @Test func theStorePublishesTheActiveRowsTiles() async throws {
        let (store, sink) = await make()
        let t = await store.pointerTargets()
        #expect(Set(t.windows.map(\.window)) == [a, b])
        #expect(t.focused == a)
        #expect(t.window(at: centre(try #require(t.frame(of: b)))) == b)
        #expect(sink.all.last == t)
    }

    @Test func focusMovingRepublishes() async {
        let (store, sink) = await make()
        await store.run(.focusWindowRef(b))
        #expect(await store.pointerTargets().focused == b)
        #expect(sink.all.last?.focused == b)
    }

    /// A floating window is a target, stacked by where focus last landed: over a tile until that
    /// tile is focused (and so raised), and back on top once it is focused itself. The tile under
    /// it stays a target wherever it shows.
    @Test func aFloatingWindowIsATargetAndTheTopmostWindowWins() async throws {
        let (store, _) = await make([win(c, CGRect(x: 700, y: 300, width: 200, height: 150), kind: .float)])
        await store.run(.focusWindowRef(a))
        let onFloat = CGPoint(x: 800, y: 375)
        var t = await store.pointerTargets()
        #expect(t.frame(of: a) != nil && t.frame(of: b) != nil && t.frame(of: c) != nil)
        #expect(try #require(t.frame(of: b)).contains(onFloat))
        #expect(t.window(at: onFloat) == c)                        // never focused, over the tiles
        #expect(t.window(at: CGPoint(x: 600, y: 100)) == b)        // on b, clear of it
        await store.run(.focusWindowRef(b))
        t = await store.pointerTargets()
        #expect(t.window(at: onFloat) == b)                        // b raised over the float
        await store.run(.focusWindowRef(c))
        t = await store.pointerTargets()
        #expect(t.window(at: onFloat) == c)
        #expect(t.window(at: CGPoint(x: 600, y: 100)) == b)
    }

    /// Ephemeral windows come and go: never a target, and a window one overlaps takes nothing,
    /// since raising it would bury the visitor. It still hides what is stacked under it.
    @Test func anEphemeralWindowIsACoverAndDisqualifiesWhatItOverlaps() throws {
        var noPanels = Config(); noPanels.showPanels = false
        var w = World.seeded(screens: [d1.id], config: noPanels)
        let sid = w.screenOrder[0]
        w.screens[sid]!.workspaces[0].windows = [a, b]
        w.focus = Focus(screen: sid, window: a)
        w.ephemeral = [c]
        let ws = w.screens[sid]!.workspaces[0]
        let shown = [sid: ShownRow(workspace: ws.id, index: 0, order: [ws.id], row: [a, b], focused: a,
                                   frames: [a: tileA, b: tileB])]
        let t = PointerTargets(world: w, shown: shown, observed: [c: CGRect(x: 20, y: 60, width: 40, height: 30)],
                               displays: [d1], config: noPanels, stacking: [a])
        #expect(t.window(at: CGPoint(x: 30, y: 70)) == nil)     // on the visitor
        #expect(t.window(at: CGPoint(x: 80, y: 20)) == nil)     // a, clear of it
        #expect(t.window(at: inB) == b)                          // b, which it does not touch
        #expect(t.windows.first { $0.window == a }?.focusable == false)
    }

    /// An auto-hiding rail takes no tiling width, so tiles run under its column; that column is
    /// still the rail, where the pointer goes to reveal it.
    @Test func theRailAndTabBarNeverFocus() async throws {
        let (store, _) = await make(panels: true, autohide: true)
        let t = await store.pointerTargets()
        let fa = try #require(t.frame(of: a))
        #expect(fa.minX < 48)
        #expect(t.window(at: CGPoint(x: fa.minX + 2, y: fa.midY)) == nil)   // under the rail
        #expect(t.window(at: CGPoint(x: fa.midX, y: 40)) == nil)            // the tab bar
        #expect(t.window(at: CGPoint(x: 60, y: fa.midY)) == a)
    }

    @Test func aDisplayShowingAFullscreenSpaceOffersNothing() async {
        let e = WindowRef(id: 4, pid: 2)
        let tileOnD2 = win(e, CGRect(x: 1100, y: 100, width: 300, height: 200))
        let (plain, _) = await make([tileOnD2])
        #expect(await plain.pointerTargets().frame(of: e) != nil)
        let (store, _) = await make([tileOnD2, win(c, d2.frame, fullscreen: true)])
        let t = await store.pointerTargets()
        #expect(t.frame(of: e) == nil && t.frame(of: c) == nil)
        #expect(t.frame(of: a) != nil)   // D1 is unaffected
    }

    // MARK: config

    @Test func keysDefaultOffAndParse() throws {
        let d = Config()
        #expect(!d.focusFollowsMouse && d.focusFollowsMouseDelayMs == 150)
        let c = try Config.parse(toml: "focus-follows-mouse = true\nfocus-follows-mouse-delay-ms = 300\n")
        #expect(c.focusFollowsMouse && c.focusFollowsMouseDelayMs == 300)
        #expect(Config.unknownKeys(toml: "focus-follows-mouse = true\nfocus-follows-mouse-delay-ms = 300\n").isEmpty)
        #expect(try Config.parse(toml: "focus-follows-mouse-delay-ms = 5").focusFollowsMouseDelayMs == 50)
        #expect(try Config.parse(toml: "focus-follows-mouse-delay-ms = 99999").focusFollowsMouseDelayMs == 2000)
    }

    @Test func theSettingsToggleWinsOverTheFile() throws {
        var file = Config(); file.focusFollowsMouse = false; file.focusFollowsMouseDelayMs = 400
        var gui = SettingsOverrides(); gui.focusFollowsMouse = true
        let out = Settings.effective(config: file, overrides: gui)
        #expect(out.focusFollowsMouse && out.focusFollowsMouseDelayMs == 400)
        let json = try JSONEncoder().encode(gui)
        #expect(try JSONDecoder().decode(SettingsOverrides.self, from: json).focusFollowsMouse == true)
    }
}
