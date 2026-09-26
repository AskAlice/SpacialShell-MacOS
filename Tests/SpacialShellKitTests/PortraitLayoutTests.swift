import Testing
import Foundation
@testable import SpacialShellKit

/// #122 (M4 G6): on a rect taller than wide, the built-ins lay out along the long axis, so a
/// portrait display stacks rows instead of cutting slivers of columns.
@Suite struct PortraitLayoutTests {
    let landscape = CGRect(x: 0, y: 0, width: 1600, height: 900)
    let portrait = CGRect(x: 0, y: 0, width: 900, height: 1600)

    func frames(_ l: BuiltinLayout, _ n: Int, _ r: CGRect, gap: CGFloat = 0, focused: Int = 0) -> [CGRect] {
        LayoutEngine.frames(l, count: n, focused: focused, in: r, gap: gap, split: SplitView(columns: 3)).compactMap { $0 }
    }

    @Test func landscapeIsUnchanged() {
        let col = frames(.column, 3, landscape)
        #expect(col.allSatisfy { $0.height == 900 } && col.map(\.minX) == [0, 1600.0 / 3, 3200.0 / 3])
        let half = frames(.half, 3, landscape)
        #expect(half[0] == CGRect(x: 0, y: 0, width: 800, height: 900))
        #expect(half[1] == CGRect(x: 800, y: 0, width: 800, height: 450))
        #expect(frames(.grid, 2, landscape).map(\.minY) == [0, 0], "two windows side by side")
    }

    @Test func columnAndSplitStackAsRowsInPortrait() {
        for l in [BuiltinLayout.column, .split] {
            let fs = frames(l, 3, portrait, gap: 10)
            #expect(fs.count == 3, "\(l)")
            #expect(fs.allSatisfy { $0.width == 900 && $0.minX == 0 }, "\(l): full-width rows")
            #expect(fs.map(\.minY) == fs.map(\.minY).sorted() && fs[1].minY - fs[0].maxY == 10, "\(l): top to bottom, gap apart")
            #expect(abs(fs.last!.maxY - 1600) < 1e-6, "\(l): fills the height")
        }
    }

    @Test func halfTakesTheTopHalfAndTheRestShareTheBottom() {
        let fs = frames(.half, 3, portrait)
        #expect(fs[0] == CGRect(x: 0, y: 0, width: 900, height: 800))
        #expect(fs[1] == CGRect(x: 0, y: 800, width: 450, height: 800))
        #expect(fs[2] == CGRect(x: 450, y: 800, width: 450, height: 800))
        #expect(frames(.half, 1, portrait) == [portrait])
    }

    @Test func gridHasAtLeastAsManyRowsAsColumnsInPortrait() {
        for n in 2...9 {
            let fs = frames(.grid, n, portrait)
            let rows = Set(fs.map(\.minY)).count, widest = Dictionary(grouping: fs, by: \.minY).values.map(\.count).max()!
            #expect(rows >= widest, "n=\(n): \(rows) rows, \(widest) columns")
            #expect(fs.count == n)
            // Row-major, and the last row widened to fill, as in landscape.
            #expect(fs.map(\.minY) == fs.map(\.minY).sorted(), "n=\(n)")
            #expect(Dictionary(grouping: fs, by: \.minY).values.allSatisfy { abs($0.map(\.width).reduce(0, +) - 900) < 1e-6 })
        }
        #expect(frames(.grid, 2, portrait).map(\.minX) == [0, 0], "two windows stacked")
    }

    @Test func squareIsLandscape() {
        let sq = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        #expect(frames(.column, 2, sq).map(\.minY) == [0, 0])
    }

    /// The floor still counts in the long axis: a portrait rect holds as many rows as its height
    /// allows, where columns would have run out at its width.
    @Test func thePortraitFloorPagesByHeight() {
        let tall = CGRect(x: 0, y: 0, width: 400, height: 1600)
        #expect(frames(.column, 30, tall).count == 1600 / 80)
    }

    /// Resize (#113) works on the portrait shape: the page's lines are horizontal, and its key
    /// is its own, so a landscape display's column sizes survive a visit to a portrait one.
    @Test func resizeFollowsTheOrientation() throws {
        let def = LayoutDef.builtins.first { $0.id == .column }!
        let page = try #require(LayoutEngine.page(def, count: 3, focused: 0, in: portrait, gap: 0))
        #expect(page.x.isEmpty && page.y.count == 2)
        let land = try #require(LayoutEngine.page(def, count: 3, focused: 0, in: landscape, gap: 0))
        #expect(page.key != land.key)
        let p = Resize.step(page, nil, index: 0, axis: .height, grow: true)
        #expect(p.moved)
        let fs = LayoutEngine.frames(def, count: 3, focused: 0, in: portrait, gap: 0, portions: [page.key: p.portions!])
        #expect(fs[0]!.height > 1600.0 / 3 + 1)
    }
}
