import Testing
import Foundation
@testable import SpacialShellKit

/// #113 (M4 G9 + G10): resizable portions — the line model, steps, detents, the floor, the
/// commands, persistence, and a border drag through the store.
@Suite struct ResizeTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1)
    let big = CGRect(x: 0, y: 0, width: 100_000, height: 100_000)

    func def(_ id: LayoutID) -> LayoutDef { LayoutCatalogue.builtins[id]! }
    func page(_ id: LayoutID, _ n: Int, focused: Int = 0) -> Resize.Page {
        LayoutEngine.page(def(id), count: n, focused: focused, in: big, gap: 0)!
    }
    func near(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 } }

    // MARK: the model

    @Test func pagesAreKeyedByLayoutAndTilesShownAndHaveTheirLines() {
        #expect(page(.split, 3).key == "split#2" && near(page(.split, 3).x, [0.5]) && page(.split, 3).y.isEmpty)
        #expect(page(.column, 3).key == "column#3" && near(page(.column, 3).x, [1.0 / 3, 2.0 / 3]))
        #expect(near(page(.half, 3).x, [0.5]) && near(page(.half, 3).y, [0.5]))
        #expect(page(.maximize, 3).x.isEmpty && page(.maximize, 3).y.isEmpty, "maximize has nothing to resize")
        let zones = LayoutDef(id: "code-3", name: "Code", body: .zones([
            LayoutZone(x: 0, y: 0, w: 0.5, h: 1), LayoutZone(x: 0.5, y: 0, w: 0.5, h: 0.5), LayoutZone(x: 0.5, y: 0.5, w: 0.5, h: 0.5)]))
        let zp = LayoutEngine.page(zones, count: 2, focused: 0, in: big, gap: 0)!
        #expect(zp.key == "code-3" && near(zp.x, [0.5]) && near(zp.y, [0.5]), "a drawn layout's lines come from all its zones")
    }

    @Test func aStepMovesTheTrailingEdgeElseTheLeadingOne() {
        let p = page(.split, 2)
        #expect(near(Resize.step(p, nil, index: 0, axis: .width, grow: true).portions!.x, [0.55]))
        #expect(near(Resize.step(p, nil, index: 0, axis: .width, grow: false).portions!.x, [0.45]))
        #expect(near(Resize.step(p, nil, index: 1, axis: .width, grow: true).portions!.x, [0.45]), "the last column grows leftwards")
        let none = Resize.step(p, nil, index: 0, axis: .height, grow: true)
        #expect(!none.moved && none.portions == nil, "split has no horizontal line")
    }

    @Test func stepsStopOnTheDetents() {
        let p = page(.column, 3)
        var portions: Portions? = nil
        var seen: [Double] = []
        for _ in 0..<5 {
            portions = Resize.step(p, portions, index: 0, axis: .width, grow: true).portions
            seen.append(portions!.x[0])
        }
        let third = 1.0 / 3
        #expect(near(seen, [third + 0.05, third + 0.10, third + 0.15, 0.5, 0.55]), "\(seen): the step that crosses 50 % stops on it")
        let back = Resize.step(p, Portions(x: [0.28, 2.0 / 3]), index: 0, axis: .width, grow: false).portions!
        #expect(near(back.x, [0.25, 2.0 / 3]), "shrinking stops on 25 % too")
        #expect(near(Resize.step(p, Portions(x: [0.5, 0.73]), index: 1, axis: .width, grow: true).portions!.x, [0.5, 0.75]))
    }

    @Test func stepsClampToTheMinimumPortionAndBackToNaturalIsNil() {
        let p = page(.split, 2)
        var portions: Portions? = nil
        for _ in 0..<20 { portions = Resize.step(p, portions, index: 0, axis: .width, grow: false).portions }
        #expect(near(portions!.x, [Resize.minPortion]))
        #expect(!Resize.step(p, portions, index: 0, axis: .width, grow: false).moved, "at the floor a step is a no-op")
        let grown = Resize.step(p, nil, index: 0, axis: .width, grow: true).portions
        #expect(Resize.step(p, grown, index: 0, axis: .width, grow: false).portions == nil, "back to as-designed stores nothing")
    }

    @Test func aGridLineBoundsOnlyTheZonesItEdges() {
        let p = page(.grid, 5)   // 3 over 2: x lines 1/3, 1/2, 2/3
        #expect(near(p.x, [1.0 / 3, 0.5, 2.0 / 3]))
        let moved = Resize.drag(p, nil, axis: .width, line: 0, to: 0.55)!
        #expect(abs(moved.x[0] - 0.55) < 1e-9, "the full row's line passes the short row's")
        #expect(!Resize.step(page(.grid, 3), nil, index: 2, axis: .width, grow: true).moved, "a full-width tile has no width to take")
    }

    @Test func aDragSnapsWithinItsRadius() {
        let p = page(.split, 2)
        #expect(near(Resize.drag(p, nil, axis: .width, line: 0, to: 0.26)!.x, [0.25]))
        #expect(near(Resize.drag(p, nil, axis: .width, line: 0, to: 0.6)!.x, [0.6]))
        #expect(Resize.drag(p, nil, axis: .width, line: 0, to: 0.51) == nil, "onto 50 % is as designed")
        #expect(near(Resize.drag(p, nil, axis: .width, line: 0, to: 0.99)!.x, [1 - Resize.minPortion]))
    }

    /// #162: a four-finger drag's travel maps onto the row one to one (full trackpad = full row),
    /// moves the edge a resize key moves, and lands by a mouse drag's rules.
    @Test func aFourFingerDragMapsTravelOntoTheRow() {
        #expect(Resize.swipeGain == 1)
        #expect(abs(Resize.swiped(from: 0.5, travel: 0.1) - 0.6) < 1e-9)
        #expect(abs(Resize.swiped(from: 0.5, travel: -0.2) - 0.3) < 1e-9, "the edge follows the fingers left")
        #expect(abs(Resize.swiped(from: 0, travel: 1) - 1) < 1e-9, "the whole trackpad crosses the whole row")
        let p = page(.split, 2)
        #expect(Resize.swipeLine(p, index: 0) == 0 && Resize.swipeLine(p, index: 1) == 0, "the one line, from either side")
        #expect(Resize.swipeLine(page(.column, 3), index: 1) == 1, "the middle column's trailing edge")
        #expect(Resize.swipeLine(page(.column, 3), index: 2) == 1, "the last column's leading edge")
        #expect(Resize.swipeLine(page(.maximize, 2), index: 0) == nil, "maximize has no edge")
        // Past there it is `drag`: the detents and the floor.
        #expect(near(Resize.drag(p, nil, axis: .width, line: 0, to: Resize.swiped(from: 0.5, travel: 0.26))!.x, [0.75]))
        #expect(near(Resize.drag(p, nil, axis: .width, line: 0, to: Resize.swiped(from: 0.5, travel: 0.8))!.x, [1 - Resize.minPortion]))
    }

    // MARK: the engine

    let rect = CGRect(x: 10, y: 20, width: 1000, height: 600)

    @Test func theEngineFramesThePortions() {
        let f = LayoutEngine.frames(def(.split), count: 2, focused: 0, in: rect, gap: 8, portions: ["split#2": Portions(x: [0.75])])
        #expect(abs(f[0]!.width - (0.75 * 1008 - 8)) < 1e-6 && abs(f[1]!.minX - (10 + 0.75 * 1008)) < 1e-6)
        #expect(abs(f[1]!.maxX - rect.maxX) < 1e-6)
        let plain = LayoutEngine.frames(def(.split), count: 2, focused: 0, in: rect, gap: 8)
        #expect(LayoutEngine.frames(def(.split), count: 2, focused: 0, in: rect, gap: 8, portions: ["column#2": Portions(x: [0.75])]) == plain,
                "another page's portions change nothing")
    }

    @Test func theFloorHoldsByBlendingBackTowardsNatural() {
        // 10 % of 1008 pt less the gap is under 120 pt: the engine gives what the floor allows.
        let f = LayoutEngine.frames(def(.column), count: 3, focused: 0, in: rect, gap: 8,
                                    portions: ["column#3": Portions(x: [0.1, 2.0 / 3])])
        #expect(f.allSatisfy { $0!.width >= LayoutEngine.minSize.width - 1e-6 })
        #expect(f[0]!.width < LayoutEngine.frames(def(.column), count: 3, focused: 0, in: rect, gap: 8)[0]!.width, "still narrower than natural")
    }

    @Test func bordersAreTheGapsBetweenFramedTilesAndPointerMapsBackToTheLine() {
        let gap: CGFloat = 8
        let p = LayoutEngine.page(def(.half), count: 3, focused: 0, in: rect, gap: gap)!
        let f = LayoutEngine.frames(def(.half), count: 3, focused: 0, in: rect, gap: gap)
        let borders = Resize.borders(p, frames: f)
        #expect(borders.filter { $0.axis == .width }.count == 2, "master against each of the stack")
        #expect(borders.filter { $0.axis == .height }.count == 1)
        let v = borders.first { $0.axis == .width }!
        #expect(v.rect.minX == f[0]!.maxX && v.rect.width == gap)
        #expect(v.contains(CGPoint(x: v.rect.minX - 5, y: v.rect.midY)) && !v.contains(CGPoint(x: v.rect.minX - 20, y: v.rect.midY)))
        #expect(abs(Resize.unit(v.rect.midX, axis: .width, in: rect, gap: gap) - 0.5) < 1e-9)
    }

    // MARK: the commands

    func world(_ layout: LayoutID = .split) -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: layout)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        return w   // focus a
    }

    @Test func resizeBalanceAndSetPortionsCommands() {
        var (w, e) = CommandRunner.apply(.resizeWindow(.width, grow: true), to: world())
        #expect(e == [.relayout] && near(w.screens["D1"]!.active.portions["split#2"]!.x, [0.55]))
        (w, e) = CommandRunner.apply(.balance, to: w)
        #expect(e == [.relayout] && w.screens["D1"]!.active.portions.isEmpty)
        #expect(CommandRunner.apply(.balance, to: w).1.isEmpty, "nothing to balance")
        #expect(CommandRunner.apply(.resizeWindow(.width, grow: true), to: world(.maximize)).1.isEmpty, "maximize does not resize")
        let id = w.screens["D1"]!.active.id
        (w, _) = CommandRunner.apply(.setPortions(id, key: "split#2", Portions(x: [0.3])), to: w)
        (w, e) = CommandRunner.apply(.setPortions(id, key: "split#2", nil), to: w)
        #expect(e == [.relayout] && w.screens["D1"]!.active.portions.isEmpty)
        #expect(w.invariantViolations().isEmpty)
    }

    /// #160: in maximize a resize (Fn+⌃A/D, or a four-finger swipe left/right) does nothing, and
    /// says why rather than claiming a limit.
    @Test func maximizeResizeIsANoopWithAReason() {
        for grow in [true, false] {
            let out = CommandRunner.run(.resizeWindow(.width, grow: grow), on: world(.maximize))
            #expect(out.report == .noop("the focused tile has no edge to move sideways in this layout"))
            #expect(out.effects.isEmpty && out.world.screens["D1"]!.active.portions.isEmpty)
        }
        // A real limit keeps its own reason.
        var w = world()
        for _ in 0..<20 { w = CommandRunner.apply(.resizeWindow(.width, grow: false), to: w).0 }
        #expect(CommandRunner.run(.resizeWindow(.width, grow: false), on: w).report == .noop("already at the limit"))
    }

    @Test func theChordsFollowThePreset() {
        var cfg = Config()
        let fn = KeyBindings.table(for: cfg)
        #expect(fn[KeyBindings.parse("fn-ctrl-d")!] == .resizeWindow(.width, grow: true))
        #expect(fn[KeyBindings.parse("fn-ctrl-w")!] == .resizeWindow(.height, grow: false))
        #expect(fn[KeyBindings.parse("fn-ctrl-equal")!] == .balance)
        cfg.keybindingPreset = .ctrlAlt
        let ca = KeyBindings.table(for: cfg)
        #expect(ca[KeyBindings.parse("ctrl-alt-cmd-a")!] == .resizeWindow(.width, grow: false))
        #expect(ca[KeyBindings.parse("ctrl-alt-a")!] == .focusWindow(.left), "resize takes no navigation chord")
        #expect(KeyBindings.commandNames["balance"] == .balance)
    }

    // MARK: persistence

    @Test func portionsSurviveTheStateFileAndOldFilesStillLoad() throws {
        var w = World.seeded(screens: ["D1"], config: Config())
        w.screens["D1"]!.workspaces[0].pinned = true
        w.screens["D1"]!.workspaces[0].portions = ["column#3": Portions(x: [0.4, 0.7])]
        let data = try JSONEncoder().encode(PersistedState(world: w))
        let back = try JSONDecoder().decode(PersistedState.self, from: data)
        let restored = back.restore(into: World.seeded(screens: ["D1"], config: Config()))
        #expect(restored.screens["D1"]!.workspaces[0].portions == ["column#3": Portions(x: [0.4, 0.7])])

        w.screens["D1"]!.workspaces[0].portions = [:]
        let plain = String(decoding: try JSONEncoder().encode(PersistedState(world: w)), as: UTF8.self)
        #expect(!plain.contains("portions"), "a row with none writes nothing")
        #expect(try JSONDecoder().decode(PersistedState.self, from: Data(plain.utf8)).screens["D1"]!.workspaces[0].portions == nil)
    }

    // MARK: the store

    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    final class Box: @unchecked Sendable { var borders: [CGRect?] = [] }

    func make(_ box: Box, layout: LayoutID = .split) async -> (WorldStore, FakeBackend) {
        var cfg = Config(); cfg.showPanels = false; cfg.categoryOrder = []; cfg.defaultLayout = layout
        func win(_ r: WindowRef) -> WindowSnapshot {
            WindowSnapshot(ref: r, frame: CGRect(x: 0, y: 0, width: 300, height: 200), title: "t", bundleID: "com.x",
                           kind: .tile, parent: nil, isMinimized: false, isFullscreen: false)
        }
        let be = FakeBackend(snapshot: Snapshot(displays: [d1], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false)],
                                                windows: [win(a), win(b)], focused: a))
        let store = WorldStore(backend: be, config: cfg, world: nil, zeroSliverBundleIDs: [],
                               onBorder: { box.borders.append($0) }, onChange: { _, _ in })
        await store.start()
        return (store, be)
    }

    @Test func draggingTheBorderResizesBothLiveAndSnaps() async {
        let box = Box()
        let (store, be) = await make(box)
        let fa = await be.frames[a]!, fb = await be.frames[b]!
        let mid = CGPoint(x: (fa.maxX + fb.minX) / 2, y: fa.midY)
        await store.apply(.pointerMoved(mid))
        #expect(box.borders.last??.midX == mid.x, "hovering the gap highlights it")
        await store.apply(.pointerDown(mid))
        let rect = CGRect(x: 8, y: 33, width: 984, height: 658)          // visible frame less the 8 pt gap, less 1
        let at75 = rect.minX + 0.76 * (rect.width + 8) - 4               // 76 %: within the 75 % detent
        await store.apply(.pointerMoved(CGPoint(x: at75, y: mid.y)))
        await store.apply(.pointerUp(CGPoint(x: at75, y: mid.y)))
        let ws = await store.world.screens["D1"]!.active
        #expect(ws.portions["split#2"].map { near($0.x, [0.75]) } == true, "\(ws.portions)")
        let (na, nb) = await (be.frames[a]!, be.frames[b]!)
        #expect(abs(na.width - (0.75 * 992 - 8)) < 1 && abs(nb.minX - na.maxX - 8) < 1, "both tiles follow the line")
    }

    @Test func aResizeKeyUsesTheRealRect() async {
        let (store, be) = await make(Box())
        await store.run(.resizeWindow(.width, grow: true))
        #expect(await store.world.screens["D1"]!.active.portions["split#2"].map { near($0.x, [0.55]) } == true)
        #expect(abs(await be.frames[a]!.width - (0.55 * 992 - 8)) < 1)
        await store.run(.balance)
        #expect(abs(await be.frames[a]!.width - (0.5 * 992 - 8)) < 1)
    }

    // MARK: the four-finger drag (#162)

    /// Polls until `check` holds: a drag's moves are laid out by the store's pump, off the call.
    func eventually(_ check: () async -> Bool) async -> Bool {
        for _ in 0..<400 {
            if await check() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    func portion(_ store: WorldStore) async -> Double? { await store.world.screens["D1"]!.active.portions["split#2"]?.x.first }

    /// The mouse border drag's path, driven by travel: the edge previews live as the fingers move
    /// (snapping onto 75 %, stopping at the floor), settles where the lift leaves it, and a drag
    /// ends once — anything after the lift finds nothing in the hand.
    @Test func aFourFingerDragPreviewsLiveAndSettlesOnTheLiftOnce() async {
        let box = Box()
        let (store, be) = await make(box)
        func drag(_ phase: SwipeDrag.Phase, _ travel: Double) -> SwipeDrag { SwipeDrag(phase, fingers: 4, travel: travel) }
        func at(_ u: Double) async -> Bool { await portion(store).map { abs($0 - u) < 1e-9 } == true }

        #expect(await store.swipeEdge(drag(.began, 0.1)) == .done)
        #expect(await eventually { await at(0.6) }, "live from the lock")
        #expect(await eventually { abs(await be.frames[a]!.width - (0.6 * 992 - 8)) < 1 }, "and laid out")
        #expect(box.borders.last??.isEmpty == false, "the edge is highlighted, as under the mouse")
        #expect(await store.swipeEdge(drag(.moved, 0.26)) == .done)
        #expect(await eventually { await at(0.75) }, "0.76 snaps onto the 75 % detent")
        #expect(await store.swipeEdge(drag(.moved, 0.9)) == .done)
        #expect(await eventually { await at(1 - Resize.minPortion) }, "the floor")

        #expect(await store.swipeEdge(drag(.ended, 0.2)) == .done)
        #expect(await at(0.7), "settled where the lift left it, by the time the lift returns")
        let (na, nb) = await (be.frames[a]!, be.frames[b]!)
        #expect(abs(na.width - (0.7 * 992 - 8)) < 1 && abs(nb.minX - na.maxX - 8) < 1, "both tiles follow the line")
        #expect(box.borders.last == .some(nil), "the highlight goes with the hand")

        // Once: the lift let go of the edge.
        #expect(await store.swipeEdge(drag(.moved, -0.3)) == .noop("no edge in the hand"))
        #expect(await store.swipeEdge(drag(.ended, -0.3)) == .noop("no edge in the hand"))
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(await at(0.7))
        // A new drag starts from where the last one left the edge.
        #expect(await store.swipeEdge(drag(.began, -0.1)) == .done)
        #expect(await store.swipeEdge(drag(.ended, -0.1)) == .done)
        #expect(await at(0.6))
    }

    /// #160's no-op, with its reason: in maximize there is no edge, so the drag starts nothing and
    /// the rest of it finds nothing in the hand. Nothing moves.
    @Test func aFourFingerDragInMaximizeIsANoop() async {
        let (store, be) = await make(Box(), layout: .maximize)
        let before = await be.frames[a]
        #expect(await store.swipeEdge(SwipeDrag(.began, fingers: 4, travel: 0.1))
                == .noop("the focused tile has no edge to move sideways in this layout"))
        #expect(await store.swipeEdge(SwipeDrag(.moved, fingers: 4, travel: 0.3)) == .noop("no edge in the hand"))
        #expect(await store.swipeEdge(SwipeDrag(.ended, fingers: 4, travel: 0.3)) == .noop("no edge in the hand"))
        #expect(await store.world.screens["D1"]!.active.portions.isEmpty)
        #expect(await be.frames[a] == before)
        #expect(SwipeBindings().command(for: Swipe(fingers: 4, direction: .right)) == nil, "no step either")
    }

    /// The mouse and four fingers share one hand: a border held by the mouse is not taken by a
    /// drag, and the pointer does not move an edge four fingers hold.
    @Test func theMouseAndFourFingersDoNotFightOverTheEdge() async {
        let (store, be) = await make(Box())
        let fa = await be.frames[a]!, fb = await be.frames[b]!
        let mid = CGPoint(x: (fa.maxX + fb.minX) / 2, y: fa.midY)
        await store.apply(.pointerDown(mid))
        #expect(await store.swipeEdge(SwipeDrag(.began, fingers: 4, travel: 0.2)) == .noop("a border is already in the hand"))
        await store.apply(.pointerUp(mid))

        #expect(await store.swipeEdge(SwipeDrag(.began, fingers: 4, travel: 0.1)) == .done)
        await store.apply(.pointerMoved(CGPoint(x: 900, y: mid.y)))
        await store.apply(.pointerDown(CGPoint(x: 900, y: mid.y)))
        await store.apply(.pointerUp(CGPoint(x: 900, y: mid.y)))
        #expect(await store.swipeEdge(SwipeDrag(.ended, fingers: 4, travel: 0.1)) == .done)
        #expect(await portion(store).map { abs($0 - 0.6) < 1e-9 } == true)
    }
}
