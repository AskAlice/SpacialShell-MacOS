import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct LayoutTests {
    let r = CGRect(x: 0, y: 0, width: 1000, height: 600)
    func eq(_ a: CGRect?, _ b: CGRect, _ tol: CGFloat = 0.01) -> Bool {
        guard let a else { return false }
        return abs(a.minX-b.minX) < tol && abs(a.minY-b.minY) < tol && abs(a.width-b.width) < tol && abs(a.height-b.height) < tol
    }
    func overlaps(_ fs: [CGRect?]) -> Bool {
        let rects = fs.compactMap { $0 }
        for i in rects.indices { for j in rects.indices where j > i {
            if rects[i].intersects(rects[j]) && rects[i].intersection(rects[j]).width > 0.01 && rects[i].intersection(rects[j]).height > 0.01 { return true }
        } }
        return false
    }

    @Test func zeroWindowsIsEmpty() { #expect(LayoutEngine.frames(.grid, count: 0, focused: 0, in: r, gap: 0).isEmpty) }
    @Test func maximizeShowsOnlyFocused() {
        let f = LayoutEngine.frames(.maximize, count: 3, focused: 1, in: r, gap: 8)
        #expect(f[0] == nil && f[2] == nil && eq(f[1], r))
    }
    @Test func splitShowsFocusedAndRightNeighbour() {
        let f = LayoutEngine.frames(.split, count: 4, focused: 1, in: r, gap: 0)
        #expect(f[0] == nil && f[3] == nil)
        #expect(eq(f[1], CGRect(x: 0, y: 0, width: 500, height: 600)))
        #expect(eq(f[2], CGRect(x: 500, y: 0, width: 500, height: 600)))
    }
    @Test func splitAtLastUsesLeftNeighbour() {
        let f = LayoutEngine.frames(.split, count: 3, focused: 2, in: r, gap: 0)
        #expect(f[0] == nil && f[1] != nil && f[2] != nil)
        #expect(f[1]!.minX < f[2]!.minX)
    }
    @Test func splitWithOneFillsRect() { #expect(eq(LayoutEngine.frames(.split, count: 1, focused: 0, in: r, gap: 8)[0], r)) }
    @Test func columnDividesWithGaps() {
        let f = LayoutEngine.frames(.column, count: 4, focused: 0, in: r, gap: 10)
        #expect(f.allSatisfy { $0 != nil })
        #expect(eq(f[0], CGRect(x: 0, y: 0, width: 242.5, height: 600)))
        #expect(eq(f[3], CGRect(x: 757.5, y: 0, width: 242.5, height: 600)))
    }
    @Test func halfStacksRest() {
        let f = LayoutEngine.frames(.half, count: 4, focused: 0, in: r, gap: 0)
        #expect(eq(f[0], CGRect(x: 0, y: 0, width: 500, height: 600)))
        #expect(eq(f[1], CGRect(x: 500, y: 0, width: 500, height: 200)))
        #expect(eq(f[3], CGRect(x: 500, y: 400, width: 500, height: 200)))
    }
    @Test func gridFiveIsThreeByTwoWithWideLastRow() {
        let f = LayoutEngine.frames(.grid, count: 5, focused: 0, in: r, gap: 0)
        #expect(f.compactMap { $0 }.count == 5)
        #expect(eq(f[0], CGRect(x: 0, y: 0, width: 1000.0/3.0, height: 300)))
        #expect(eq(f[3], CGRect(x: 0, y: 300, width: 500, height: 300)))
        #expect(eq(f[4], CGRect(x: 500, y: 300, width: 500, height: 300)))
    }
    @Test func neverOverlapsAcrossLayouts() {
        for l in BuiltinLayout.allCases { for n in 1...9 { for f in 0..<n {
            #expect(!overlaps(LayoutEngine.frames(l, count: n, focused: f, in: r, gap: 6)), "\(l) n=\(n) f=\(f)")
        } } }
    }
    // #54 — the floor. A row too crowded to give every window 120×80 shows the ones that fit and
    // parks (nil) the rest, instead of handing out slivers.
    let narrow = CGRect(x: 0, y: 0, width: 500, height: 300)
    func usable(_ f: CGRect) -> Bool { f.width >= LayoutEngine.minSize.width && f.height >= LayoutEngine.minSize.height }

    @Test func columnOverflowParksInsteadOfShrinking() {
        // (500 + 10) / (120 + 10) → 3 columns fit.
        let f = LayoutEngine.frames(.column, count: 8, focused: 0, in: narrow, gap: 10)
        #expect(f.count == 8)
        #expect(f.compactMap { $0 }.count == 3)
        #expect(f.compactMap { $0 }.allSatisfy(usable))
        #expect(f[0] != nil && f[1] != nil && f[2] != nil)   // first page holds the focused window
    }
    @Test func overflowKeepsTheFocusedWindowOnScreen() {
        for l in BuiltinLayout.allCases { for n in 1...40 { for foc in 0..<n {
            let f = LayoutEngine.frames(l, count: n, focused: foc, in: narrow, gap: 6)
            #expect(f.count == n, "\(l) n=\(n)")
            #expect(f[foc] != nil, "\(l) n=\(n) focused \(foc) parked")
            #expect(f.compactMap { $0 }.allSatisfy(usable), "\(l) n=\(n) f=\(foc)")
            #expect(!overlaps(f), "\(l) n=\(n) f=\(foc)")
        } } }
    }
    @Test func overflowPagesAreContiguousAndLastPageIsFull() {
        // 3 fit; 8 windows → pages start at 0, 3, then clamp to 5 so the last page is never short.
        func shown(_ foc: Int) -> [Int] {
            let f = LayoutEngine.frames(.column, count: 8, focused: foc, in: narrow, gap: 10)
            return f.indices.filter { f[$0] != nil }
        }
        #expect(shown(1) == [0, 1, 2])
        #expect(shown(4) == [3, 4, 5])
        #expect(shown(7) == [5, 6, 7])
        // Shown windows keep their left-to-right order on screen.
        let f = LayoutEngine.frames(.column, count: 8, focused: 4, in: narrow, gap: 10)
        #expect(f[3]!.minX < f[4]!.minX && f[4]!.minX < f[5]!.minX)
    }
    @Test func fittingRowsAreUnchanged() {
        // The floor only engages when it must: 4 columns in 1000 pt is the pre-#54 layout exactly.
        let f = LayoutEngine.frames(.column, count: 4, focused: 2, in: r, gap: 10)
        #expect(f.allSatisfy { $0 != nil })
        #expect(eq(f[0], CGRect(x: 0, y: 0, width: 242.5, height: 600)))
    }
    @Test func rectBelowTheFloorStillShowsTheFocusedWindow() {
        // Nothing can meet the floor; the focused window gets what there is rather than nothing.
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 60)
        let f = LayoutEngine.frames(.grid, count: 3, focused: 1, in: tiny, gap: 0)
        #expect(f[0] == nil && f[2] == nil && eq(f[1], tiny))
    }
    @Test func focusedOutOfRangeIsClamped() {
        #expect(LayoutEngine.frames(.maximize, count: 2, focused: 9, in: r, gap: 0)[1] != nil)
    }
}
