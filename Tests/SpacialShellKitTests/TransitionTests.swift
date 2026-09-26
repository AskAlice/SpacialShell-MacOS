import Testing
import Foundation
@testable import SpacialShellKit

/// #64: every switch is seen as movement. The planner is pure — what the tiling showed before, what
/// it shows now — and says where each moving window travels from and to. AX top-left coordinates.
@Suite struct TransitionTests {
    let viewport = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let full = CGRect(x: 8, y: 8, width: 984, height: 584)          // maximize, gap 8
    let w1 = WindowRef(id: 1, pid: 1), w2 = WindowRef(id: 2, pid: 1), w3 = WindowRef(id: 3, pid: 1)
    let wsA = UUID(), wsB = UUID()

    func row(_ ws: UUID, _ index: Int, order: [UUID]? = nil, _ windows: [WindowRef],
             focused: WindowRef?, frames: [WindowRef: CGRect]) -> ShownRow {
        ShownRow(workspace: ws, index: index, order: order ?? [wsA, wsB], row: windows,
                 focused: focused, frames: frames)
    }

    func move(_ ms: [Transition.Move], _ r: WindowRef) -> Transition.Move? { ms.first { $0.ref == r } }

    /// #67: Fn+D under maximize — the strip is a carousel. The outgoing window leaves to the left,
    /// the incoming arrives from the right, by one place.
    @Test func tabRightSlidesTheStripLeft() {
        let before = row(wsA, 0, [w1, w2, w3], focused: w1, frames: [w1: full])
        let after = row(wsA, 0, [w1, w2, w3], focused: w2, frames: [w2: full])
        let ms = Transition.moves(before: before, after: after, viewport: viewport, gap: 8)
        let step = full.width + 8
        #expect(move(ms, w1) == .init(ref: w1, from: full, to: full.offsetBy(dx: -step, dy: 0)))
        #expect(move(ms, w2) == .init(ref: w2, from: full.offsetBy(dx: step, dy: 0), to: full))
        #expect(ms.count == 2)
    }

    /// Fn+A is the mirror.
    @Test func tabLeftSlidesTheStripRight() {
        let before = row(wsA, 0, [w1, w2, w3], focused: w2, frames: [w2: full])
        let after = row(wsA, 0, [w1, w2, w3], focused: w1, frames: [w1: full])
        let ms = Transition.moves(before: before, after: after, viewport: viewport, gap: 8)
        let step = full.width + 8
        #expect(move(ms, w2)?.to == full.offsetBy(dx: step, dy: 0))
        #expect(move(ms, w1)?.from == full.offsetBy(dx: -step, dy: 0))
    }

    /// "Slide the strip by the number of places moved": a tab click two places over travels two.
    @Test func aJumpOfTwoPlacesTravelsTwo() {
        let before = row(wsA, 0, [w1, w2, w3], focused: w1, frames: [w1: full])
        let after = row(wsA, 0, [w1, w2, w3], focused: w3, frames: [w3: full])
        let ms = Transition.moves(before: before, after: after, viewport: viewport, gap: 8)
        #expect(move(ms, w3)?.from == full.offsetBy(dx: 2 * (full.width + 8), dy: 0))
    }

    /// Tiling layouts: a window on screen before and after goes straight from its old frame to its
    /// new one; the strip is the arrangement itself, not a second code path.
    @Test func aWindowShownBothTimesMovesBetweenItsFrames() {
        let left = CGRect(x: 8, y: 8, width: 488, height: 584), right = CGRect(x: 504, y: 8, width: 488, height: 584)
        let before = row(wsA, 0, [w1, w2, w3], focused: w1, frames: [w1: left, w2: right])
        let after = row(wsA, 0, [w1, w2, w3], focused: w2, frames: [w2: left, w3: right])
        let ms = Transition.moves(before: before, after: after, viewport: viewport, gap: 8)
        #expect(move(ms, w2) == .init(ref: w2, from: right, to: left))
        #expect(move(ms, w1)?.to == left.offsetBy(dx: -(left.width + 8), dy: 0))
        #expect(move(ms, w3)?.from == right.offsetBy(dx: left.width + 8, dy: 0))
    }

    /// #66: Fn+S — the outgoing row leaves upward, the incoming arrives from below.
    @Test func workspaceDownSlidesUp() {
        let before = row(wsA, 0, [w1], focused: w1, frames: [w1: full])
        let after = row(wsB, 1, [w2], focused: w2, frames: [w2: full])
        let ms = Transition.moves(before: before, after: after, viewport: viewport, gap: 8)
        #expect(move(ms, w1)?.to == full.offsetBy(dx: 0, dy: -viewport.height))
        #expect(move(ms, w2)?.from == full.offsetBy(dx: 0, dy: viewport.height))
    }

    /// Fn+W is the mirror.
    @Test func workspaceUpSlidesDown() {
        let before = row(wsB, 1, [w2], focused: w2, frames: [w2: full])
        let after = row(wsA, 0, [w1], focused: w1, frames: [w1: full])
        let ms = Transition.moves(before: before, after: after, viewport: viewport, gap: 8)
        #expect(move(ms, w2)?.to == full.offsetBy(dx: 0, dy: viewport.height))
        #expect(move(ms, w1)?.from == full.offsetBy(dx: 0, dy: -viewport.height))
    }

    /// Leaving an emptied row reaps it, which renumbers the rows: the target that was index 1 is
    /// index 0 afterwards. Direction comes from where the target sat *before*, so it is still down.
    @Test func directionSurvivesTheRowBeingReaped() {
        let before = row(wsA, 0, order: [wsA, wsB], [], focused: nil, frames: [:])
        let after = row(wsB, 0, order: [wsB], [w2], focused: w2, frames: [w2: full])
        let ms = Transition.moves(before: before, after: after, viewport: viewport, gap: 8)
        #expect(move(ms, w2)?.from == full.offsetBy(dx: 0, dy: viewport.height))
    }

    /// Custom grid layouts design §9 (#9): a page flip — a page of several windows replaced by a
    /// wholly different one, as a 2×2 zone page or a #54 column page does — slides one whole
    /// viewport, so leaving and arriving windows never cross inside the clip.
    @Test func aPageFlipSlidesOneWholeViewport() {
        let w4 = WindowRef(id: 4, pid: 1), w5 = WindowRef(id: 5, pid: 1), w6 = WindowRef(id: 6, pid: 1)
        let tl = CGRect(x: 8, y: 8, width: 488, height: 288), tr = CGRect(x: 504, y: 8, width: 488, height: 288)
        let bl = CGRect(x: 8, y: 304, width: 488, height: 288)
        let all = [w1, w2, w3, w4, w5, w6]
        // Focus w3 → w4 crosses the page edge: page [w1 w2 w3] becomes page [w4 w5 w6].
        let before = row(wsA, 0, all, focused: w3, frames: [w1: tl, w2: tr, w3: bl])
        let after = row(wsA, 0, all, focused: w4, frames: [w4: tl, w5: tr, w6: bl])
        let ms = Transition.moves(before: before, after: after, viewport: viewport, gap: 8)
        let page = viewport.width + 8
        #expect(move(ms, w1)?.to == tl.offsetBy(dx: -page, dy: 0))
        #expect(move(ms, w3)?.to == bl.offsetBy(dx: -page, dy: 0))
        #expect(move(ms, w4)?.from == tl.offsetBy(dx: page, dy: 0))
        #expect(move(ms, w6)?.from == bl.offsetBy(dx: page, dy: 0))
        #expect(ms.count == 6)
        // And back: the mirror.
        let back = Transition.moves(before: after, after: before, viewport: viewport, gap: 8)
        #expect(move(back, w4)?.to == tl.offsetBy(dx: page, dy: 0))
        #expect(move(back, w1)?.from == tl.offsetBy(dx: -page, dy: 0))
    }

    /// Nothing moved on screen (a backstop snapshot, a layout-neutral command): no transition.
    @Test func anUnchangedRowPlansNothing() {
        let r = row(wsA, 0, [w1, w2], focused: w1, frames: [w1: full])
        #expect(Transition.moves(before: r, after: r, viewport: viewport, gap: 8).isEmpty)
    }

    /// #140 (G13): a layout change moves every window inside the viewport; that is a re-tile.
    @Test func aLayoutChangeIsARetile() {
        let left = CGRect(x: 8, y: 8, width: 488, height: 584), right = CGRect(x: 504, y: 8, width: 488, height: 584)
        let top = CGRect(x: 8, y: 8, width: 984, height: 288), bottom = CGRect(x: 8, y: 304, width: 984, height: 288)
        let before = row(wsA, 0, [w1, w2], focused: w1, frames: [w1: left, w2: right])
        let after = row(wsA, 0, [w1, w2], focused: w1, frames: [w1: top, w2: bottom])
        let t = Transition(display: "d", viewport: viewport,
                           moves: Transition.moves(before: before, after: after, viewport: viewport, gap: 8))
        #expect(t.moves.count == 2)
        #expect(t.isRetile)
    }

    /// A switch is never a re-tile: something travels out of the viewport (or in), whole.
    @Test func aSwitchIsNotARetile() {
        let tab = Transition(display: "d", viewport: viewport, moves: Transition.moves(
            before: row(wsA, 0, [w1, w2], focused: w1, frames: [w1: full]),
            after: row(wsA, 0, [w1, w2], focused: w2, frames: [w2: full]), viewport: viewport, gap: 8))
        let rowDown = Transition(display: "d", viewport: viewport, moves: Transition.moves(
            before: row(wsA, 0, [w1], focused: w1, frames: [w1: full]),
            after: row(wsB, 1, [w2], focused: w2, frames: [w2: full]), viewport: viewport, gap: 8))
        #expect(!tab.isRetile)
        #expect(!rowDown.isRetile)
        #expect(!Transition(display: "d", viewport: viewport, moves: []).isRetile)
    }

    /// No direction (a window closed, a new one adopted): what stays visible still moves between
    /// its frames, but nothing slides in or out from an invented edge.
    @Test func withoutADirectionNothingSlidesInOrOut() {
        let before = row(wsA, 0, [w1], focused: w1, frames: [w1: full])
        let after = row(wsA, 0, [w1, w2], focused: w1, frames: [w1: CGRect(x: 8, y: 8, width: 488, height: 584),
                                                               w2: CGRect(x: 504, y: 8, width: 488, height: 584)])
        let ms = Transition.moves(before: before, after: after, viewport: viewport, gap: 8)
        #expect(ms.map(\.ref) == [w1])
    }
}
