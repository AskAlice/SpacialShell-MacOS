import Testing
import Foundation
@testable import SpacialShellKit

/// #107 (G22): when a keyboard or `spacialctl` command moves focus to another display, the pointer
/// goes to the centre of the newly focused window — or of the display, when its row is empty.
/// Never for a mouse action, a native focus report, a move within one display, or a pointer that
/// is already inside the target.
@Suite struct PointerWarpTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let d2 = DisplayInfo(id: "D2", frame: CGRect(x: 1000, y: 0, width: 800, height: 600), visibleFrame: CGRect(x: 1000, y: 0, width: 800, height: 600), isMain: false)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1)
    /// On D1 — where the user is — and nowhere near D2.
    let onD1 = CGPoint(x: 10, y: 10)

    func win(_ r: WindowRef, _ f: CGRect) -> WindowSnapshot {
        WindowSnapshot(ref: r, frame: f, title: "t", bundleID: "com.x", kind: .tile, parent: nil, isMinimized: false, isFullscreen: false)
    }
    /// `a` and `b` on D1 (`a` focused), `c` on D2 unless `emptyD2`.
    func make(emptyD2: Bool = false, warp: Bool = true) async -> (WorldStore, FakeBackend) {
        var ws = [win(a, CGRect(x: 0, y: 0, width: 300, height: 200)), win(b, CGRect(x: 0, y: 0, width: 300, height: 200))]
        if !emptyD2 { ws.append(win(c, CGRect(x: 1100, y: 100, width: 300, height: 200))) }
        let s = Snapshot(displays: [d1, d2], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false)], windows: ws, focused: a)
        var config = Config(); config.showPanels = false; config.categoryOrder = []; config.pointerWarp = warp
        let be = FakeBackend(snapshot: s)
        await be.setPointer(onD1)
        let store = WorldStore(backend: be, config: config, world: nil, zeroSliverBundleIDs: [], onChange: { _, _ in })
        await store.start()
        await be.reset()
        return (store, be)
    }
    func warps(_ be: FakeBackend) async -> [CGPoint] {
        await be.calls.compactMap { if case .warpPointer(let p) = $0 { p } else { nil } }
    }
    func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    @Test func focusingAnotherDisplayWarpsToTheFocusedWindowsCentre() async throws {
        let (store, be) = await make()
        await store.run(.focusScreen(.next))
        #expect(await store.world.focus == Focus(screen: "D2", window: c))
        let frame = try #require(await be.frames[c])
        #expect(await warps(be) == [centre(frame)])
    }

    @Test func anEmptyRowWarpsToTheDisplaysCentre() async {
        let (store, be) = await make(emptyD2: true)
        await store.run(.focusScreen(.next))
        #expect(await store.world.focus.screen == "D2")
        #expect(await warps(be) == [centre(d2.frame)])
    }

    @Test func movingAWindowToAnotherDisplayWarpsToIt() async throws {
        let (store, be) = await make()
        await store.run(.moveWindowToScreen(.next))
        #expect(await store.world.focus == Focus(screen: "D2", window: a))
        let frame = try #require(await be.frames[a])
        #expect(d2.frame.contains(centre(frame)))
        #expect(await warps(be) == [centre(frame)])
    }

    @Test func noWarpWhenThePointerIsAlreadyInsideTheTarget() async throws {
        let (store, be) = await make()
        await be.setPointer(CGPoint(x: 1150, y: 150))     // inside `c`, off-centre
        await store.run(.focusScreen(.next))
        #expect(await store.world.focus.window == c)
        #expect(await warps(be).isEmpty)
    }

    @Test func noWarpWhenSwitchedOff() async {
        let (store, be) = await make(warp: false)
        await store.run(.focusScreen(.next))
        #expect(await store.world.focus.screen == "D2")
        #expect(await warps(be).isEmpty)
    }

    @Test func noWarpWithinOneDisplay() async {
        let (store, be) = await make()
        await store.run(.focusWindow(.right))
        #expect(await store.world.focus == Focus(screen: "D1", window: b))
        #expect(await warps(be).isEmpty)
    }

    /// A tab or rail click on the other display is a mouse action: the pointer is the user's.
    @Test func noWarpForAMouseCommand() async {
        let (store, be) = await make()
        await store.run(.focusWindowRef(c))
        #expect(await store.world.focus == Focus(screen: "D2", window: c))
        #expect(await warps(be).isEmpty)
    }

    /// The user clicked a window on the other display; macOS reports it.
    @Test func noWarpForANativeFocusReport() async {
        let (store, be) = await make()
        await store.apply(.focusChanged(c))
        #expect(await store.world.focus == Focus(screen: "D2", window: c))
        #expect(await warps(be).isEmpty)
    }

    @Test func pointerWarpKey() throws {
        #expect(Config().pointerWarp)
        let file = try Config.parse(toml: "pointer-warp = false")
        #expect(!file.pointerWarp)
        #expect(try !Config.parse(toml: file.render()).pointerWarp)
        var gui = SettingsOverrides(); gui.pointerWarp = true
        #expect(Settings.effective(config: file, overrides: gui).pointerWarp)
    }
}
