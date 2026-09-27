import Testing
import Foundation
@testable import SpacialShellKit

/// #114 (M4 G5): split is an N-column sliding view — N per workspace, the view slides by one when
/// focus crosses its edge, resize portions apply within it, and N survives the state file.
@Suite struct SplitColumnsTests {
    let big = CGRect(x: 0, y: 0, width: 100_000, height: 100_000)
    let refs = (1...5).map { WindowRef(id: WindowID($0), pid: 1) }

    func world(_ layout: LayoutID = .split, windows n: Int = 5) -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: layout)
        for r in refs.prefix(n) { w.adopt(r, kind: .tile, on: "D1") }
        return run(.focusTab(1), w)
    }
    /// The tiled indices the active row frames, as the reconciler asks the engine.
    func shown(_ w: World, in rect: CGRect? = nil) -> [Int] {
        let ws = w.screens["D1"]!.active, row = w.tiled(in: ws)
        let f = ws.anchor.flatMap { row.firstIndex(of: $0) } ?? 0
        let fs = LayoutEngine.frames(LayoutCatalogue.builtins.resolve(ws.layout).def, count: row.count, focused: f,
                                     in: rect ?? big, gap: 0, portions: ws.portions, split: ws.split(in: row))
        return fs.indices.filter { fs[$0] != nil }
    }
    func run(_ c: Command, _ w: World) -> World { CommandRunner.apply(c, to: w, in: .test()).0 }

    @Test func slideHoldsTheFocusedWindowAsCloseToTheHintAsItCan() {
        #expect(SplitView.slide(0, focused: 1, k: 2, count: 5) == 0, "inside the view: nothing moves")
        #expect(SplitView.slide(0, focused: 2, k: 2, count: 5) == 1, "past the right edge: by one")
        #expect(SplitView.slide(3, focused: 2, k: 2, count: 5) == 2, "past the left edge: by one")
        #expect(SplitView.slide(9, focused: 4, k: 3, count: 5) == 2, "never past the end of the row")
        #expect(SplitView.slide(-3, focused: 0, k: 2, count: 5) == 0)
    }

    @Test func theEngineShowsNColumnsFromTheView() {
        let r = CGRect(x: 0, y: 0, width: 900, height: 600)
        let f = LayoutEngine.frames(.split, count: 5, focused: 2, in: r, gap: 0, split: SplitView(columns: 3, start: 1))
        #expect(f.indices.filter { f[$0] != nil } == [1, 2, 3])
        #expect(f[1] == CGRect(x: 0, y: 0, width: 300, height: 600) && f[3] == CGRect(x: 600, y: 0, width: 300, height: 600))
        let two = LayoutEngine.frames(.split, count: 2, focused: 0, in: r, gap: 0, split: SplitView(columns: 4))
        #expect(two.allSatisfy { $0 != nil }, "fewer windows than columns: all of them, as columns")
        // #54: six columns in 500 pt do not fit 120 pt each; the view narrows and still holds focus.
        let narrow = LayoutEngine.frames(.split, count: 8, focused: 6, in: CGRect(x: 0, y: 0, width: 500, height: 300), gap: 10,
                                         split: SplitView(columns: 6))
        #expect(narrow.compactMap { $0 }.count == 3 && narrow[6] != nil)
    }

    @Test func focusPastTheEdgeSlidesTheViewByOne() {
        var w = world()
        #expect(shown(w) == [0, 1])
        w = run(.focusWindow(.right), w); #expect(shown(w) == [0, 1], "moving inside the view moves nothing")
        w = run(.focusWindow(.right), w); #expect(shown(w) == [1, 2])
        w = run(.focusWindow(.right), w); #expect(shown(w) == [2, 3])
        w = run(.focusWindow(.left), w); #expect(shown(w) == [2, 3])
        w = run(.focusWindow(.left), w); #expect(shown(w) == [1, 2])
        w = run(.focusTab(5), w); #expect(shown(w) == [3, 4])
        w = run(.adjustSplitColumns(1), w); #expect(shown(w) == [2, 3, 4], "a wider view keeps the focused window in it")
        #expect(w.invariantViolations().isEmpty)
    }

    @Test func theViewFollowsItsWindowsWhenOneLeftOfItCloses() {
        var w = run(.focusTab(4), world())
        #expect(shown(w) == [2, 3])
        w.remove(refs[0])
        #expect(shown(w) == [1, 2], "still windows 3 and 4, now at 1 and 2")
    }

    @Test func columnCommandsClampAndOnlyAdjustOnASplitRow() {
        var w = world()
        let id = w.screens["D1"]!.active.id
        var o = CommandRunner.run(.adjustSplitColumns(-1), on: w, in: .test())
        #expect(o.report == .noop("split already shows 2 columns"))
        o = CommandRunner.run(.adjustSplitColumns(1), on: w, in: .test())
        #expect(o.effects == [.relayout] && o.world.screens["D1"]!.active.splitColumns == 3)
        w = run(.setSplitColumns(id, 99), w)
        #expect(w.screens["D1"]!.active.splitColumns == SplitView.columnRange.upperBound)
        #expect(shown(w) == [0, 1, 2, 3, 4])
        #expect(CommandRunner.run(.adjustSplitColumns(1), on: world(.column), in: .test()).report == .noop("the layout is not split"))
        #expect(CommandRunner.run(.setSplitColumns(UUID(), 3), on: w, in: .test()).report != .done)
        #expect(KeyBindings.command(named: "split-columns-more") == .adjustSplitColumns(1))
        #expect(KeyBindings.command(named: "split-columns-fewer") == .adjustSplitColumns(-1))
        #expect(!KeyBindings.table(for: Config()).values.contains(.adjustSplitColumns(1)), "unbound by default")
        #expect(ShellUI.testState(for: "D1", in: w)!.rail.first(where: \.isActive)!.splitColumns == SplitView.columnRange.upperBound)
    }

    @Test func portionsApplyWithinTheVisibleColumns() {
        var w = run(.adjustSplitColumns(1), world())
        let page = w.resizePage(layouts: .builtins)!.page
        #expect(page.key == "split#3" && page.x.count == 2)
        w = run(.resizeWindow(.width, grow: true), w)
        #expect(w.screens["D1"]!.active.portions["split#3"] != nil)
        let ws = w.screens["D1"]!.active, row = w.tiled(in: ws)
        let fs = LayoutEngine.frames(LayoutCatalogue.builtins[.split]!, count: row.count, focused: 0,
                                     in: CGRect(x: 0, y: 0, width: 1000, height: 600), gap: 0,
                                     portions: ws.portions, split: ws.split(in: row))
        #expect(abs(fs[0]!.width - 1000 * (1.0 / 3 + Resize.step)) < 0.01 && fs[3] == nil)
    }

    @Test func columnsSurviveTheStateFileAndTheDefaultWritesNothing() throws {
        var w = World.seeded(screens: ["D1"], config: Config())
        w.screens["D1"]!.workspaces[0].pinned = true
        w.screens["D1"]!.workspaces[0].splitColumns = 4
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(PersistedState(world: w)))
        #expect(back.restore(into: World.seeded(screens: ["D1"], config: Config())).screens["D1"]!.workspaces[0].splitColumns == 4)

        w.screens["D1"]!.workspaces[0].splitColumns = SplitView.defaultColumns
        let plain = String(decoding: try JSONEncoder().encode(PersistedState(world: w)), as: UTF8.self)
        #expect(!plain.contains("splitColumns"), "the default writes nothing, so older builds read it unchanged")
        let old = try JSONDecoder().decode(PersistedState.self, from: Data(plain.utf8))
        #expect(old.restore(into: World.seeded(screens: ["D1"], config: Config())).screens["D1"]!.workspaces[0].splitColumns == 2)
    }
}
