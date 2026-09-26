import Testing
import Foundation
@testable import SpacialShellKit

/// #125 (M4 G12): a window that cannot grow to fill its tile (a maximum size, or a resize it
/// refused) sits centred in the tile, not stuck in its top-left corner.
@Suite struct FixedSizeTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1)
    /// Maximize, gap 10: the tile `Reconciler.desired` hands `a`.
    let tile = CGRect(x: 10, y: 35, width: 980, height: 654)

    func one() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        return w
    }
    func desired(_ w: World, refused: [WindowRef: Refusal]) -> [WindowRef: Placement] {
        Reconciler.desired(world: w, displays: [d1], config: LayoutConfig(gap: 10), observed: [:], prePark: [:],
                           parkedNow: [], zeroSliver: [], refused: refused)
    }

    // MARK: - learning a refusal from an echo

    @Test func aSmallerEchoOfOurOwnWriteIsARefusal() {
        let r = Refusal(asked: tile, got: CGRect(x: 10, y: 35, width: 400, height: 300))
        #expect(r == Refusal(asked: tile, size: CGSize(width: 400, height: 300)))
        #expect(Refusal(asked: tile, got: tile) == nil, "granted")
        #expect(Refusal(asked: tile, got: tile.insetBy(dx: 0.4, dy: 0.4)) == nil, "rounding is not a refusal")
        #expect(Refusal(asked: tile, got: CGRect(x: 10, y: 35, width: 1200, height: 654)) == nil,
                "too big is the minimum-size case, not this one")
        #expect(Refusal(asked: tile, got: CGRect(x: 10, y: 35, width: 980, height: 500)) != nil, "one axis is enough")
    }

    // MARK: - the reconciler centres it

    @Test func aRefusedWindowIsCentredInItsTile() {
        let d = desired(one(), refused: [a: Refusal(asked: tile, size: CGSize(width: 400, height: 300))])
        #expect(d[a] == .frame(CGRect(x: 10 + (980 - 400) / 2, y: 35 + (654 - 300) / 2, width: 400, height: 300)))
    }

    /// Fixed in one axis only (System Settings resizes only vertically): centred across, full height.
    @Test func onlyTheRefusedAxisIsCentred() {
        let d = desired(one(), refused: [a: Refusal(asked: tile, size: CGSize(width: 680, height: 654))])
        #expect(d[a] == .frame(CGRect(x: 160, y: 35, width: 680, height: 654)))
    }

    /// A window bigger than its tile in one axis keeps the tile's edge there, as before (#54's
    /// floor bounds the tile, not the window); the other axis still centres.
    @Test func anAxisWiderThanTheTileIsLeftAlone() {
        let d = desired(one(), refused: [a: Refusal(asked: tile, size: CGSize(width: 1200, height: 300))])
        #expect(d[a] == .frame(CGRect(x: 10, y: 212, width: 980, height: 300)))
    }

    /// A refusal is about the tile it was asked for. A different tile is asked for in full, so a
    /// window that only snapped to its own increments (a terminal's cell grid) is never stuck small.
    @Test func aNewTileIsAskedForInFull() {
        var w = one(); w.adopt(b, kind: .tile, on: "D1")
        w = CommandRunner.apply(.setWorkspaceLayout(w.screens["D1"]!.active.id, .column), to: w).0
        let d = desired(w, refused: [a: Refusal(asked: tile, size: CGSize(width: 400, height: 300))])
        guard case .frame(let f)? = d[a] else { Issue.record("a framed"); return }
        #expect(f.width > 400 && f.minX == 10, "the column tile, whole")
    }

    // MARK: - end to end through the store

    func m1Config() -> Config { var c = Config(); c.showPanels = false; c.categoryOrder = []; return c }

    @Test func theStoreLearnsTheRefusalAndCentresOnce() async {
        let s = Snapshot(displays: [d1], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false)],
                         windows: [WindowSnapshot(ref: a, frame: CGRect(x: 0, y: 0, width: 300, height: 200), title: "t", bundleID: "com.x",
                                                  kind: .tile, parent: nil, isMinimized: false, isFullscreen: false)],
                         focused: a)
        let be = FakeBackend(snapshot: s)
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: [], onChange: { _, _ in })
        await store.start()
        let full = CGRect(x: 8, y: 33, width: 984, height: 658)
        #expect(await be.calls.contains(.setFrame(a, full)))
        await be.reset()
        // The app kept its 400 × 300: the echo of our write comes back at the tile's corner.
        await store.apply(.windowResized(a, CGRect(x: 8, y: 33, width: 400, height: 300)))
        let centred = CGRect(x: 8 + (984 - 400) / 2, y: 33 + (658 - 300) / 2, width: 400, height: 300)
        #expect(await be.calls.filter { if case .setFrame = $0 { true } else { false } } == [.setFrame(a, centred)])
        // Its echo is ours; nothing more is written.
        await be.reset()
        await store.apply(.windowMoved(a, centred))
        #expect(await be.calls.filter { if case .setFrame = $0 { true } else { false } }.isEmpty)
    }
}
