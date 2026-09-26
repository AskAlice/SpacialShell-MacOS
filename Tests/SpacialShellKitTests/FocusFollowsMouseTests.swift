import Testing
import Foundation
@testable import SpacialShellKit

/// #135 (G28): focus follows the mouse, opt-in, after a dwell. Only a resting pointer over another
/// tiled window focuses it; the rail, the tab bar, floating and ephemeral windows, and anything
/// they cover never do, and nothing but pointer movement starts the wait.
@Suite struct FocusFollowsMouseTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 2)
    let tileA = CGRect(x: 0, y: 0, width: 100, height: 100)
    let tileB = CGRect(x: 110, y: 0, width: 100, height: 100)
    var targets: PointerTargets { PointerTargets(tiles: [a: tileA, b: tileB], covers: [], focused: a) }
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
        #expect(Set(t.tiles.keys) == [a, b])
        #expect(t.focused == a)
        #expect(t.window(at: centre(try #require(t.tiles[b]))) == b)
        #expect(sink.all.last == t)
    }

    @Test func focusMovingRepublishes() async {
        let (store, sink) = await make()
        await store.run(.focusWindowRef(b))
        #expect(await store.pointerTargets().focused == b)
        #expect(sink.all.last?.focused == b)
    }

    /// A floating window is a cover, and the tile under it is no target at all: raising that tile
    /// would bury the floating window.
    @Test func aFloatingWindowCoversAndDisqualifiesTheTileUnderIt() async throws {
        let (store, _) = await make([win(c, CGRect(x: 700, y: 300, width: 200, height: 150), kind: .float)])
        await store.run(.focusWindowRef(a))
        let t = await store.pointerTargets()
        #expect(t.tiles[a] != nil && t.tiles[b] == nil)
        #expect(t.window(at: CGPoint(x: 800, y: 375)) == nil)   // on the floating window
        #expect(t.window(at: CGPoint(x: 600, y: 100)) == nil)   // on b, clear of it
    }

    @Test func anEphemeralWindowIsACover() async throws {
        let (store, _) = await make([win(c, CGRect(x: 100, y: 100, width: 50, height: 50), kind: .ephemeral)])
        let t = await store.pointerTargets()
        #expect(t.window(at: CGPoint(x: 125, y: 125)) == nil)
    }

    /// An auto-hiding rail takes no tiling width, so tiles run under its column; that column is
    /// still the rail, where the pointer goes to reveal it.
    @Test func theRailAndTabBarNeverFocus() async throws {
        let (store, _) = await make(panels: true, autohide: true)
        let t = await store.pointerTargets()
        let fa = try #require(t.tiles[a])
        #expect(fa.minX < 48)
        #expect(t.window(at: CGPoint(x: fa.minX + 2, y: fa.midY)) == nil)   // under the rail
        #expect(t.window(at: CGPoint(x: fa.midX, y: 40)) == nil)            // the tab bar
        #expect(t.window(at: CGPoint(x: 60, y: fa.midY)) == a)
    }

    @Test func aDisplayShowingAFullscreenSpaceOffersNothing() async {
        let e = WindowRef(id: 4, pid: 2)
        let tileOnD2 = win(e, CGRect(x: 1100, y: 100, width: 300, height: 200))
        let (plain, _) = await make([tileOnD2])
        #expect(await plain.pointerTargets().tiles[e] != nil)
        let (store, _) = await make([tileOnD2, win(c, d2.frame, fullscreen: true)])
        let t = await store.pointerTargets()
        #expect(t.tiles[e] == nil && t.tiles[c] == nil)
        #expect(t.tiles[a] != nil)   // D1 is unaffected
    }

    // MARK: config

    @Test func keysDefaultOffAndRoundTrip() throws {
        let d = Config()
        #expect(!d.focusFollowsMouse && d.focusFollowsMouseDelayMs == 150)
        let c = try Config.parse(toml: "focus-follows-mouse = true\nfocus-follows-mouse-delay-ms = 300\n")
        #expect(c.focusFollowsMouse && c.focusFollowsMouseDelayMs == 300)
        let back = try Config.parse(toml: c.render())
        #expect(back.focusFollowsMouse && back.focusFollowsMouseDelayMs == 300)
        #expect(Config.unknownKeys(toml: "focus-follows-mouse = true\nfocus-follows-mouse-delay-ms = 300\n").isEmpty)
        #expect(Config.unknownKeys(toml: c.render()).isEmpty)
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
