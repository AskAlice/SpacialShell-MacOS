import Testing
import Foundation
@testable import SpacialShellKit

/// #173: the border and four-finger edge drag, at its own seam — pointer and swipe events in,
/// verdicts out, with no store booted. The store's own tests of the same drags stay in
/// `ResizeTests`; these are their decisions, one event at a time.
@Suite struct EdgeDragTests {
    static let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1)
    /// No gap, so a pointer at x is at unit x / 2000, and the border between two even tiles is x = 1000.
    static let rect = CGRect(x: 0, y: 0, width: 2000, height: 1000)
    static func x(_ u: Double) -> CGPoint { CGPoint(x: u * 2000, y: 500) }

    /// The store's side of the seam, without the store: the world, the reconcile's frames, the
    /// pump's loop and the highlight the panel would show.
    final class Rig {
        var world: World
        var drag = EdgeDrag()
        var highlight: CGRect?

        init(_ layout: LayoutID = .split, portion: Double? = nil, focus: WindowRef = a) {
            var w = World.empty(screens: ["D1"], defaultLayout: layout)
            w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
            if let portion { w.screens["D1"]!.workspaces[0].portions["split#2"] = Portions(x: [portion]) }
            world = CommandRunner.run(.focusWindowRef(focus), on: w, in: .test()).world
            frame()
        }

        var ws: Workspace { world.screens["D1"]!.active }
        var portion: Double? { ws.portions["split#2"]?.x.first }
        var frames: [WindowRef: CGRect] {
            let row = world.tiled(in: ws)
            let fs = LayoutEngine.frames(LayoutCatalogue.builtins.resolve(ws.layout).def, count: row.count, focused: 0,
                                         in: EdgeDragTests.rect, gap: 0, portions: ws.portions)
            return Dictionary(uniqueKeysWithValues: zip(row, fs).compactMap { r, f in f.map { (r, $0) } })
        }
        var scene: EdgeDrag.Scene {
            EdgeDrag.Scene(world: world, layouts: .builtins, gap: 0, rects: ["D1": EdgeDragTests.rect], tiles: frames)
        }

        @discardableResult func note(_ v: EdgeDrag.Verdict) -> EdgeDrag.Verdict {
            if case .highlight(let r) = v { highlight = r }
            return v
        }
        /// A reconcile pass: the borders as it framed them.
        func frame() { note(drag.framed(frames.mapValues { .frame($0) }, in: scene)) }
        /// The pump: every step the hand is owed, each laid out.
        func pump() {
            while drag.behind {
                if let c = drag.step(in: scene) { world = CommandRunner.run(c, on: world, in: .test()).world; frame() }
            }
        }
        /// The release: the pump catches up, then the hand lets go.
        func settle() -> [Command] { pump(); return drag.settle(in: scene) }
    }

    func near(_ v: Double?, _ u: Double) -> Bool { v.map { abs($0 - u) < 1e-9 } == true }

    // MARK: the pointer (#113)

    @Test func hoverHighlightsTheBorderAndAPressOnItTakesIt() {
        let rig = Rig(), on = Self.x(0.5)
        #expect(rig.note(rig.drag.move(to: on, buttonDown: false)) == .highlight(CGRect(x: 998, y: 0, width: 4, height: 1000)))
        #expect(rig.note(rig.drag.move(to: Self.x(0.3), buttonDown: false)) == .highlight(nil), "off it, gone")
        #expect(rig.drag.move(to: on, buttonDown: true) == .highlight(nil), "a held button hovers nothing")
        #expect(rig.drag.press(at: Self.x(0.3), locked: false) == .highlight(nil) && rig.drag.hand == nil)
        #expect(rig.drag.press(at: on, locked: true) == .highlight(nil) && rig.drag.hand == nil, "locked, nothing to take")
        #expect(rig.drag.press(at: on, locked: false) == .highlight(CGRect(x: 998, y: 0, width: 4, height: 1000)))
        #expect(rig.drag.hand?.line == 0 && rig.drag.hand?.bySwipe == false)
    }

    @Test func draggingTheBorderLaysOutLiveSnapsAndStopsAtTheFloor() {
        let rig = Rig()
        rig.drag.press(at: Self.x(0.5), locked: false)
        #expect(rig.drag.move(to: Self.x(0.76), buttonDown: true) == .layOut)
        let ws = rig.ws.id
        #expect(rig.drag.step(in: rig.scene) == .setPortions(ws, key: "split#2", Portions(x: [0.75])), "76 % snaps onto 75 %")
        #expect(!rig.drag.behind && rig.drag.step(in: rig.scene) == nil, "caught up")
        rig.drag.move(to: Self.x(0.99), buttonDown: true); rig.pump()
        #expect(near(rig.portion, 1 - Resize.minPortion), "the floor")
        #expect(rig.highlight?.midX == 1800, "the highlight follows the line it holds")

        #expect(rig.drag.release(at: Self.x(0.7)) == .settle)
        #expect(rig.settle().isEmpty && near(rig.portion, 0.7), "lands where it was let go")
        #expect(rig.drag.hand == nil && rig.drag.border(at: Self.x(0.7))?.midX == 1400)
        #expect(rig.drag.release(at: Self.x(0.7)) == .nothing, "nothing in the hand: a window drag's release")
    }

    /// #178: a resize that leaves a tile at 90 % collapses to maximize on it — at the settle only.
    @Test func aBorderReleasedAtNearlyFullCollapses() {
        let rig = Rig()
        rig.drag.press(at: Self.x(0.5), locked: false)
        rig.drag.move(to: Self.x(0.02), buttonDown: true); rig.pump()
        #expect(rig.ws.layout == .split, "live, it stays split")
        rig.drag.release(at: Self.x(0.02))
        #expect(rig.settle() == [.focusWindowRef(Self.b), .setWorkspaceLayout(rig.ws.id, .maximize), .setPortions(rig.ws.id, key: "split#2", nil)])
    }

    /// #178's moved-guard: a click, or a nudge within a snap's radius, on a border the keys left at
    /// 90 % is not a resize.
    @Test func aClickOrANudgeOnABorderAlreadyAtNearlyFullStaysSplit() {
        let rig = Rig(portion: 0.9)
        for to in [0.9, 0.895] {
            rig.drag.press(at: Self.x(0.9), locked: false)
            rig.drag.move(to: Self.x(to), buttonDown: true)
            rig.drag.release(at: Self.x(to))
            #expect(rig.settle().isEmpty, "\(to)")
        }
    }

    // MARK: four fingers (#162, #186)

    @Test func aFourFingerDragPreviewsLiveAndSettlesOnTheLiftOnce() {
        let rig = Rig()
        func swipe(_ p: SwipeDrag.Phase, _ t: Double) -> EdgeDrag.Verdict { rig.note(rig.drag.swipe(SwipeDrag(p, fingers: 4, travel: t), in: rig.scene)) }
        #expect(swipe(.began, 0.2) == .layOut && rig.drag.hand?.swipeStart == 0.5)
        rig.pump(); #expect(near(rig.portion, 0.6), "gain 0.5: travel 0.2 → +0.1")
        #expect(rig.highlight?.midX == 1200, "the edge is highlighted, as under the mouse")
        swipe(.moved, 0.52); rig.pump(); #expect(near(rig.portion, 0.75), "0.76 snaps")
        swipe(.moved, 1.8); rig.pump(); #expect(near(rig.portion, 0.9), "the floor")
        #expect(swipe(.ended, 0.4) == .settle)
        #expect(rig.settle().isEmpty && near(rig.portion, 0.7) && rig.drag.hand == nil)
        #expect(swipe(.moved, -0.3) == .noop("no edge in the hand"))
        #expect(swipe(.ended, -0.3) == .noop("no edge in the hand"))
        #expect(swipe(.began, -0.2) == .layOut && near(rig.drag.hand?.swipeStart, 0.7), "from where the last one left it")
    }

    /// #186: the border follows the fingers whichever tile is focused.
    @Test func theBorderFollowsTheFingersFromTheRightTileToo() {
        let rig = Rig(focus: Self.b)
        rig.drag.swipe(SwipeDrag(.began, fingers: 4, travel: 0.2), in: rig.scene); rig.pump()
        #expect(near(rig.portion, 0.6))
    }

    @Test func aFourFingerDragEndingAtNearlyFullCollapses() {
        let rig = Rig(focus: Self.b)
        rig.drag.swipe(SwipeDrag(.began, fingers: 4, travel: -0.2), in: rig.scene)
        rig.drag.swipe(SwipeDrag(.ended, fingers: 4, travel: -1.2), in: rig.scene)
        #expect(rig.settle() == [.focusWindowRef(Self.b), .setWorkspaceLayout(rig.ws.id, .maximize), .setPortions(rig.ws.id, key: "split#2", nil)])
    }

    @Test func inMaximizeTheFingersFindNoEdge() {
        let rig = Rig(.maximize)
        #expect(rig.drag.swipe(SwipeDrag(.began, fingers: 4, travel: 0.1), in: rig.scene)
                == .noop("the focused tile has no edge to move sideways in this layout"))
        #expect(rig.drag.swipe(SwipeDrag(.moved, fingers: 4, travel: 0.3), in: rig.scene) == .noop("no edge in the hand"))
        #expect(rig.drag.hand == nil && !rig.drag.behind)
    }

    // MARK: one hand

    @Test func theMouseAndFourFingersDoNotFightOverTheEdge() {
        let rig = Rig()
        rig.drag.press(at: Self.x(0.5), locked: false)
        #expect(rig.drag.swipe(SwipeDrag(.began, fingers: 4, travel: 0.2), in: rig.scene) == .noop("a border is already in the hand"))
        rig.drag.release(at: Self.x(0.5)); _ = rig.settle()

        #expect(rig.drag.swipe(SwipeDrag(.began, fingers: 4, travel: 0.2), in: rig.scene) == .layOut)
        #expect(rig.drag.move(to: Self.x(0.45), buttonDown: false) == .nothing)
        #expect(rig.drag.press(at: Self.x(0.45), locked: false) == .nothing)
        #expect(rig.drag.release(at: Self.x(0.45)) == .nothing)
        #expect(rig.drag.swipe(SwipeDrag(.ended, fingers: 4, travel: 0.2), in: rig.scene) == .settle)
        #expect(rig.settle().isEmpty && near(rig.portion, 0.6))
    }

    /// A lost mouse-up lets go of the pointer's line, not the fingers'; a lock lets go of either.
    @Test func dropLetsGoWhereTheLineLastWas() {
        let rig = Rig()
        #expect(rig.drag.drop() == .nothing, "nothing to drop")
        rig.drag.press(at: Self.x(0.5), locked: false)
        #expect(rig.drag.drop(pointerOnly: true) == .highlight(nil) && rig.drag.hand == nil)
        rig.drag.swipe(SwipeDrag(.began, fingers: 4, travel: 0.2), in: rig.scene)
        #expect(rig.drag.drop(pointerOnly: true) == .nothing && rig.drag.hand != nil)
        #expect(rig.drag.drop() == .highlight(nil) && rig.drag.hand == nil && !rig.drag.behind)
    }
}
