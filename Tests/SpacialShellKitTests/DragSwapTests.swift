import Testing
import Foundation
@testable import SpacialShellKit

/// #108: drag a tiled window by its title bar onto another tile to swap them.
@Suite struct DragSwapTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1), d = WindowRef(id: 4, pid: 1)

    // MARK: the command

    func world() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .split)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1"); w.adopt(c, kind: .tile, on: "D1")
        w.adopt(d, kind: .tile, on: "D2")
        return w
    }
    func run(_ w: World, _ cmd: Command) -> (World, [Effect]) {
        let r = CommandRunner.apply(cmd, to: w, in: .test())
        #expect(r.0.invariantViolations().isEmpty, "after \(cmd): \(r.0.invariantViolations())")
        return r
    }

    @Test func droppingOnATileOfTheSameRowSwapsThem() {
        let (w, e) = run(world(), .dropWindow(a, onto: c))
        #expect(w.screens["D1"]!.active.windows == [c, b, a], "a swap, not a slide")
        #expect(w.focus == Focus(screen: "D1", window: a) && w.screens["D1"]!.active.anchor == a)
        #expect(e == [.focus(a), .relayout])
    }

    @Test func droppingOnAnotherDisplaysTileTakesItsSlotAndFollows() {
        let (w, e) = run(world(), .dropWindow(b, onto: d))
        #expect(w.screens["D1"]!.active.windows == [a, c])
        #expect(w.screens["D2"]!.active.windows == [b, d], "b takes d's slot; d moves along")
        #expect(w.focus == Focus(screen: "D2", window: b))
        #expect(e == [.focus(b), .relayout])
    }

    @Test func floatingWindowsAndSelfDropsChangeNothing() {
        var w0 = world()
        w0.setFloating(c, true)
        for cmd: Command in [.dropWindow(a, onto: a), .dropWindow(a, onto: c), .dropWindow(c, onto: a)] {
            let (w, e) = CommandRunner.apply(cmd, to: w0, in: .test())
            #expect(w == w0 && e.isEmpty, "\(cmd)")
        }
    }

    // MARK: the drop target

    @Test func tilesAreTheFramedTiledWindowsOfActiveRowsOnly() {
        var w = world()
        w.setFloating(c, true)
        let fa = CGRect(x: 0, y: 0, width: 100, height: 100), fb = CGRect(x: 100, y: 0, width: 100, height: 100)
        let desired: [WindowRef: Placement] = [a: .frame(fa), b: .frame(fb), c: .frame(fb), d: .untouched]
        #expect(DropTarget.tiles(world: w, desired: desired) == [a: fa, b: fb])
    }

    @Test func theTargetIsTheOtherTileUnderThePointer() {
        let fa = CGRect(x: 0, y: 0, width: 100, height: 100), fb = CGRect(x: 108, y: 0, width: 100, height: 100)
        let tiles = [a: fa, b: fb]
        #expect(DropTarget.tile(at: CGPoint(x: 150, y: 50), dragging: a, in: tiles) == b)
        #expect(DropTarget.tile(at: CGPoint(x: 50, y: 50), dragging: a, in: tiles) == nil, "its own tile is no target")
        #expect(DropTarget.tile(at: CGPoint(x: 104, y: 50), dragging: a, in: tiles) == nil, "the gap is no target")
    }

    // MARK: the store

    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let d2 = DisplayInfo(id: "D2", frame: CGRect(x: 1000, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 1000, y: 25, width: 1000, height: 675), isMain: false)
    final class Box: @unchecked Sendable { var targets: [CGRect?] = []; var t = ContinuousClock.now }

    func win(_ r: WindowRef) -> WindowSnapshot {
        WindowSnapshot(ref: r, frame: CGRect(x: 0, y: 0, width: 300, height: 200), title: "t", bundleID: "com.x",
                       kind: .tile, parent: nil, isMinimized: false, isFullscreen: false)
    }
    /// `a` and `b` side by side on D1 (split), `d` alone on D2.
    func make(_ box: Box) async -> (WorldStore, FakeBackend) {
        var cfg = Config(); cfg.showPanels = false; cfg.categoryOrder = []; cfg.defaultLayout = .split
        let snap = Snapshot(displays: [d1, d2], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false)],
                            windows: [win(a), win(b)], focused: a)
        let be = FakeBackend(snapshot: snap)
        let store = WorldStore(backend: be, config: cfg, world: nil, zeroSliverBundleIDs: [], now: { box.t },
                               onDropTarget: { box.targets.append($0) }, onChange: { _, _ in })
        await store.start()
        #expect(await store.world.screens["D1"]!.active.windows == [a, b])
        return (store, be)
    }
    /// Grab `r` by its title bar and carry it `by`, the way macOS reports it: button down, then moves.
    func grab(_ r: WindowRef, by v: CGVector, _ store: WorldStore, _ be: FakeBackend) async -> CGPoint {
        let f = await be.frames[r]!
        let p = CGPoint(x: f.midX, y: f.minY + 10)
        await store.apply(.pointerDown(p))
        for step in 1...3 {
            let k = CGFloat(step) / 3
            await store.apply(.windowMoved(r, f.offsetBy(dx: v.dx * k, dy: v.dy * k)))
        }
        return CGPoint(x: p.x + v.dx, y: p.y + v.dy)
    }

    @Test func releasingOverAnotherTileSwapsThemAndNothingFightsTheHandMidDrag() async {
        let box = Box()
        let (store, be) = await make(box)
        let fa = await be.frames[a]!, fb = await be.frames[b]!
        await be.reset()
        let p = await grab(a, by: CGVector(dx: fb.midX - fa.midX, dy: 30), store, be)
        await store.run(.focusWindowRef(b))                                  // anything that reconciles mid-drag
        #expect(await be.calls.allSatisfy { !touches($0, a) || $0 == .raise(a) }, "the dragged window was written mid-drag")
        #expect(box.targets == [fb], "the indicator is on b's tile")

        await store.apply(.pointerUp(p))
        let w = await store.world
        #expect(w.screens["D1"]!.active.windows == [b, a] && w.focus.window == a)
        let (na, nb) = await (be.frames[a], be.frames[b])
        #expect(na == fb && nb == fa)
        #expect(box.targets.last == .some(nil), "the indicator is hidden at the drop")
        #expect(w.invariantViolations().isEmpty)
    }

    @Test func releasingOverNoTileSnapsItBack() async {
        let box = Box()
        let (store, be) = await make(box)
        let fa = await be.frames[a]!
        let p = await grab(a, by: CGVector(dx: 0, dy: 60), store, be)   // still over its own tile
        #expect(box.targets.isEmpty, "its own tile is no target")
        await store.apply(.pointerUp(p))
        #expect(await store.world.screens["D1"]!.active.windows == [a, b])
        #expect(await be.frames[a] == fa, "snapped back to its tile")
    }

    @Test func releasingOverAnotherDisplaysTileTakesItsSlot() async {
        let box = Box()
        let (store, be) = await make(box)
        await store.apply(.snapshot(Snapshot(displays: [d1, d2], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false)],
                                             windows: [win(a), win(b), WindowSnapshot(ref: d, frame: CGRect(x: 1100, y: 100, width: 300, height: 200),
                                                                                      title: "t", bundleID: "com.y", kind: .tile, parent: nil,
                                                                                      isMinimized: false, isFullscreen: false)],
                                             focused: a)))
        #expect(await store.world.location(of: d)?.screen == "D2")
        let fa = await be.frames[a]!, fd = await be.frames[d]!
        let p = await grab(a, by: CGVector(dx: fd.midX - fa.midX, dy: 0), store, be)
        #expect(box.targets.last == .some(fd))
        await store.apply(.pointerUp(p))
        let w = await store.world
        #expect(w.screens["D2"]!.active.windows == [a, d] && w.screens["D1"]!.active.windows == [b])
        #expect(w.focus == Focus(screen: "D2", window: a))
        #expect(w.invariantViolations().isEmpty)
    }

    /// #57 at the drop: over another display with no tile there, the window moves into that
    /// display's active row — once, on release, not mid-drag.
    @Test func releasingOverAnEmptyDisplayRehomesItThere() async {
        let box = Box()
        let (store, be) = await make(box)
        await be.reset()
        let p = await grab(a, by: CGVector(dx: 1000, dy: 0), store, be)
        #expect(await be.calls.isEmpty, "written mid-drag")
        #expect(await store.world.location(of: a)?.screen == "D1", "rehomed mid-drag")
        await store.apply(.pointerUp(p))
        let w = await store.world
        #expect(w.location(of: a)?.screen == "D2" && w.focus == Focus(screen: "D2", window: a))
        #expect(await be.frames[a].map { d2.frame.contains(CGPoint(x: $0.midX, y: $0.midY)) } == true)
    }

    /// material-shell's M3: Fn+S while the window is in the hand carries it to the row below.
    @Test func fnSWhileDraggingCarriesTheWindowDown() async {
        let box = Box()
        let (store, be) = await make(box)
        let fa = await be.frames[a]!
        _ = await grab(a, by: CGVector(dx: 0, dy: 20), store, be)
        let below = await store.world.screens["D1"]!.workspaces[1].id
        await store.run(.focusWorkspace(.down))
        var w = await store.world
        #expect(w.location(of: a).map { $0.index } == 1 && w.screens["D1"]!.active.id == below)
        #expect(w.screens["D1"]!.workspaces[0].windows == [b])
        // Released over nothing: it lands in its new row's tile.
        await store.apply(.pointerUp(CGPoint(x: fa.midX, y: 5)))
        w = await store.world
        #expect(w.screens["D1"]!.active.windows == [a] && w.invariantViolations().isEmpty)
        #expect(await be.frames[a].map { $0.width > fa.width } == true, "tiled alone in the new row")
    }

    /// A mouse-up the backend never saw (released over the shell's own panels): the next sweep,
    /// which only runs with the button up, ends the drag and the window goes home.
    @Test func aLostMouseUpEndsTheDragAtTheNextSnapshot() async {
        let box = Box()
        let (store, be) = await make(box)
        let fa = await be.frames[a]!
        _ = await grab(a, by: CGVector(dx: 0, dy: 20), store, be)
        var s = await be.snapshot
        s.windows = [WindowSnapshot(ref: a, frame: fa.offsetBy(dx: 0, dy: 20), title: "t", bundleID: "com.x", kind: .tile,
                                    parent: nil, isMinimized: false, isFullscreen: false), win(b)]
        await be.reset()
        await store.apply(.snapshot(s))
        #expect(await be.calls.contains(.setFrame(a, fa)), "still suspended after the sweep")
        #expect(await store.world.screens["D1"]!.active.windows == [a, b])
    }

    /// Not a drag: a move with no button down (an app moving itself), or a resize from the left
    /// edge (the size changes). Both are snapped back as before.
    @Test func movesThatAreNotADragAreSnappedBackAtOnce() async {
        let box = Box()
        let (store, be) = await make(box)
        let fa = await be.frames[a]!
        await store.apply(.windowMoved(a, fa.offsetBy(dx: 30, dy: 30)))
        #expect(await be.frames[a] == fa)
        await store.apply(.pointerDown(CGPoint(x: fa.minX + 2, y: fa.midY)))
        await store.apply(.windowMoved(a, CGRect(x: fa.minX - 40, y: fa.minY, width: fa.width + 40, height: fa.height)))
        #expect(await be.frames[a] == fa)
        #expect(box.targets.isEmpty)
    }
}
