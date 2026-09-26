import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

/// #123 (M4 G7): material-shell's ratio (dwindle) layout. Each window takes `ratio` of the space
/// the windows before it left, alternating axis, starting along the long one.
@Suite struct RatioLayoutTests {
    let r = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let k = LayoutEngine.ratio
    func frames(_ n: Int, in rect: CGRect? = nil, gap: CGFloat = 0, focused: Int = 0) -> [CGRect?] {
        LayoutEngine.frames(.ratio, count: n, focused: focused, in: rect ?? r, gap: gap)
    }
    func near(_ a: CGRect?, _ b: CGRect) -> Bool {
        guard let a else { return false }
        return abs(a.minX - b.minX) < 1e-6 && abs(a.minY - b.minY) < 1e-6 && abs(a.width - b.width) < 1e-6 && abs(a.height - b.height) < 1e-6
    }

    @Test func theDefaultIsTheGoldenRatio() { #expect(abs(k - 0.618) < 1e-9) }

    @Test func oneWindowFillsTheRect() { #expect(frames(1) == [r]) }

    @Test func eachTakesTheRatioOfWhatIsLeftAlternatingAxis() {
        let fs = frames(4)
        let w0 = 1600 * k, h1 = 1000 * k, w2 = (1600 - w0) * k
        #expect(near(fs[0], CGRect(x: 0, y: 0, width: w0, height: 1000)), "left, full height")
        #expect(near(fs[1], CGRect(x: w0, y: 0, width: 1600 - w0, height: h1)), "top right")
        #expect(near(fs[2], CGRect(x: w0, y: h1, width: w2, height: 1000 - h1)), "bottom right, left part")
        #expect(near(fs[3], CGRect(x: w0 + w2, y: h1, width: 1600 - w0 - w2, height: 1000 - h1)), "the last takes the rest")
    }

    @Test func earlierWindowsGetTheLargerShare() {
        let areas = frames(5).map { $0!.width * $0!.height }
        #expect(zip(areas, areas.dropFirst()).dropLast().allSatisfy { $0 > $1 }, "\(areas)")
    }

    @Test func tilesAreOneGapApartAndFlushWithTheRect() {
        let fs = frames(3, gap: 10).map { $0! }
        #expect(fs[0].minX == 0 && fs[0].minY == 0 && abs(fs[0].maxY - 1000) < 1e-6)
        #expect(abs(fs[1].minX - fs[0].maxX - 10) < 1e-6)
        #expect(abs(fs[2].minY - fs[1].maxY - 10) < 1e-6)
        #expect(abs(fs[1].maxX - 1600) < 1e-6 && abs(fs[2].maxY - 1000) < 1e-6)
    }

    /// #122: on a portrait rect the first cut is across, so the first window is a full-width band.
    @Test func portraitStartsAlongTheLongAxis() {
        let tall = CGRect(x: 0, y: 0, width: 1000, height: 1600)
        let fs = frames(2, in: tall)
        #expect(near(fs[0], CGRect(x: 0, y: 0, width: 1000, height: 1600 * k)))
    }

    /// Focus does not reshape the page: tile order, not focus, decides who is largest (the M4
    /// paging rule — moving focus inside a page moves nothing).
    @Test func focusMovesNothing() {
        #expect(frames(4, focused: 3) == frames(4, focused: 0))
    }

    /// #54: a crowded ratio row pages like any built-in; every framed tile meets the floor.
    @Test func theFloorPages() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 500)
        let fs = LayoutEngine.frames(.ratio, count: 12, focused: 11, in: small, gap: 8)
        #expect(fs[11] != nil)
        #expect(fs.compactMap { $0 }.count < 12)
        #expect(fs.compactMap { $0 }.allSatisfy(LayoutEngine.fits))
    }

    /// Resize (#113) sees the ratio's lines, and a step moves the first window's edge.
    @Test func resizes() throws {
        let def = try #require(LayoutCatalogue.builtins[.ratio])
        let page = try #require(LayoutEngine.page(def, count: 3, focused: 0, in: r, gap: 8))
        #expect(page.key == "ratio#3" && page.x.count == 1 && page.y.count == 1)
        #expect(abs(page.x[0] - k) < 1e-9)
        let s = Resize.step(page, nil, index: 0, axis: .width, grow: true)
        #expect(s.moved)
        let grown = LayoutEngine.frames(def, count: 3, focused: 0, in: r, gap: 8, portions: [page.key: s.portions!])
        #expect(grown[0]!.width > frames(3, gap: 8)[0]!.width)
    }

    @Test func itIsABuiltinEverywhereLayoutsAre() throws {
        #expect(LayoutID.ratio.rawValue == "ratio")
        let def = try #require(LayoutCatalogue.builtins[.ratio])
        #expect(def.isBuiltin && def.symbol != nil)
        #expect(LayoutCatalogue.builtins.bar.last == .ratio, "#123, 2026-09-26: on the default ring, after grid")
        #expect(LayoutCatalogue.builtins.next(after: .grid) == .ratio)
        var c = Config(); c.layoutBar = [.maximize, .ratio]
        #expect(LayoutCatalogue(config: c).next(after: .maximize) == .ratio, "and a custom bar can carry it")
        c.layoutBar = [.maximize, .grid]
        #expect(LayoutCatalogue(config: c).next(after: .grid) == .maximize, "or leave it off")
        #expect(KeyBindings.command(named: "set-layout-ratio") == .setLayout(.ratio))
        #expect(try Config.parse(toml: #"default-layout = "ratio""#).defaultLayout == .ratio)
        // Duplicating it in the editor starts from a drawn dwindle.
        #expect(GridEditor(duplicating: def).cells.count == 3)
    }
}
