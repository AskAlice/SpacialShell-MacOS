import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

/// #110 (M3 B2): the store publishes `(World, ShellSnapshot)`, carries window titles and app names
/// in it, follows title changes without a sweep or a reconcile, and stays quiet when nothing changed.
@Suite struct SnapshotFeedTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1)

    final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ShellSnapshot] = []
        func add(_ s: ShellSnapshot) { lock.withLock { items.append(s) } }
        var all: [ShellSnapshot] { lock.withLock { items } }
    }

    func win(_ r: WindowRef, title: String) -> WindowSnapshot {
        WindowSnapshot(ref: r, frame: CGRect(x: 0, y: 0, width: 300, height: 200), title: title, bundleID: "com.x",
                       kind: .tile, parent: nil, isMinimized: false, isFullscreen: false)
    }
    func snap(_ ws: [WindowSnapshot]) -> Snapshot {
        Snapshot(displays: [d1], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false, name: "Terminal")],
                 windows: ws, focused: ws.first?.ref)
    }
    func make(_ s: Snapshot) async -> (WorldStore, FakeBackend, Published) {
        let be = FakeBackend(snapshot: s)
        var c = Config(); c.showPanels = false; c.categoryOrder = []
        let published = Published()
        let store = WorldStore(backend: be, config: c, world: nil, zeroSliverBundleIDs: [],
                               onChange: { _, snapshot in published.add(snapshot) })
        await store.start()
        return (store, be, published)
    }
    func row(_ s: ShellSnapshot?, _ r: WindowRef) -> ShellSnapshot.WindowRow? {
        s?.screens.flatMap(\.windows).first { $0.window == r }
    }

    @Test func thePublishCarriesTitlesAndAppNames() async {
        let (_, _, published) = await make(snap([win(a, title: "~/code — zsh"), win(b, title: "")]))
        let last = published.all.last
        #expect(row(last, a)?.title == "~/code — zsh" && row(last, a)?.appName == "Terminal")
        #expect(row(last, b)?.title == "")
        #expect(last?.titles == [a: "~/code — zsh"])          // untitled windows fall back in the UI
    }

    @Test func aTitleChangeRepublishesWithoutAReconcile() async {
        let (store, be, published) = await make(snap([win(a, title: "one"), win(b, title: "two")]))
        await be.reset()
        let before = published.all.count
        await store.apply(.windowTitleChanged(a, "one, edited"))
        #expect(published.all.count == before + 1)
        #expect(row(published.all.last, a)?.title == "one, edited")
        #expect(await be.calls.isEmpty)                         // no frame writes, no raise
        // The same title again, and a window the store has never seen: nothing is published.
        await store.apply(.windowTitleChanged(a, "one, edited"))
        await store.apply(.windowTitleChanged(WindowRef(id: 99, pid: 1), "stranger"))
        #expect(published.all.count == before + 1)
        #expect(await store.shellSnapshot().titles[WindowRef(id: 99, pid: 1)] == nil)
    }

    @Test func anUnchangedRefreshPublishesNothing() async {
        let s = snap([win(a, title: "one"), win(b, title: "two")])
        let (store, _, published) = await make(s)
        let before = published.all.count
        await store.apply(.snapshot(s))                         // the 2 s backstop, nothing new
        #expect(published.all.count == before)
        // …but a refresh that brings a new title does publish it.
        await store.apply(.snapshot(snap([win(a, title: "one"), win(b, title: "three")])))
        #expect(row(published.all.last, b)?.title == "three")
        #expect(published.all.last.map { $0.generation } == published.all.dropLast().last.map { $0.generation + 1 })
    }

    @Test func aVanishedWindowTakesItsTitle() async {
        let (store, _, _) = await make(snap([win(a, title: "one"), win(b, title: "two")]))
        await store.apply(.snapshot(snap([win(a, title: "one")])))
        #expect(await store.shellSnapshot().titles == [a: "one"])
        await store.apply(.windowTitleChanged(b, "back?"))       // too late: it is gone
        #expect(await store.shellSnapshot().titles == [a: "one"])
    }

    @Test func tabsCarryTheFeedsTitles() {
        var w = World.seeded(screens: ["D1"], config: Config())
        w.adopt(a, kind: .tile, on: "D1")
        w.adopt(b, kind: .tile, on: "D1")
        let state = ShellUI.state(for: "D1", in: w, titles: [a: "Report — Pages"])
        #expect(state?.tabs.map(\.title) == ["Report — Pages", ""])
    }

    /// The pure builder: maximize shows only its anchor, a floating window is always shown, a
    /// hidden one never, and a visitor has no workspace.
    @Test func theSnapshotSaysWhatTheLayoutWouldShow() {
        var w = World.seeded(screens: ["D1"], config: Config())
        let c = WindowRef(id: 3, pid: 2), d = WindowRef(id: 4, pid: 2), v = WindowRef(id: 5, pid: 2)
        for r in [a, b, c, d] { w.adopt(r, kind: .tile, on: "D1") }
        w.adopt(v, kind: .ephemeral, on: "D1")
        let ws = w.screens["D1"]!.active
        w.screens["D1"]!.workspaces[w.screens["D1"]!.activeIndex].layout = .maximize
        w.screens["D1"]!.workspaces[w.screens["D1"]!.activeIndex].anchor = a
        w.screens["D1"]!.workspaces[w.screens["D1"]!.activeIndex].floating.insert(c)
        w.setHidden(d, true)
        let s = ShellSnapshot(world: w, generation: 1, displays: [d1], config: Config(), layouts: .builtins,
                              titles: [:], appNames: [1: "Terminal"], bundleIDs: [:], locked: false)
        #expect(row(s, a)?.isVisibleUnderLayout == true && row(s, b)?.isVisibleUnderLayout == false)
        #expect(row(s, c)?.isVisibleUnderLayout == true && row(s, c)?.isFloating == true)
        #expect(row(s, d)?.isVisibleUnderLayout == false && row(s, d)?.isHidden == true)
        #expect(row(s, v)?.workspaceId == nil && row(s, a)?.workspaceId == ws.id)
        #expect(row(s, a)?.appName == "Terminal" && row(s, c)?.appName == "")
        #expect(s.screens.first?.frame == RectDTO(d1.frame) && s.screens.first?.activeWorkspaceId == ws.id)
        #expect(s.screens.first?.insets.top == 34)             // the default panels, not zen
    }
}
