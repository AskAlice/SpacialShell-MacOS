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
        for l in Layout.allCases { for n in 1...9 { for f in 0..<n {
            #expect(!overlaps(LayoutEngine.frames(l, count: n, focused: f, in: r, gap: 6)), "\(l) n=\(n) f=\(f)")
        } } }
    }
    @Test func focusedOutOfRangeIsClamped() {
        #expect(LayoutEngine.frames(.maximize, count: 2, focused: 9, in: r, gap: 0)[1] != nil)
    }
}
