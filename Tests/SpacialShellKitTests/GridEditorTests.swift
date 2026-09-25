import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

/// #10 — the layout editor's pure model, the settings.json edits it makes, the popover/switcher
/// view state and `set-layout`. The canvas in SpacialShellUI only draws what these produce.
@Suite struct GridEditorTests {
    func z(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutZone { LayoutZone(x: x, y: y, w: w, h: h) }
    func drawn(_ id: LayoutID, _ zones: [LayoutZone], name: String = "Drawn") -> LayoutDef {
        LayoutDef(id: id, name: name, body: .zones(zones))
    }

    // MARK: - presets

    @Test func presetsAreTheFiveGridsOnTheLattice() {
        #expect(GridEditor.Preset.one.zones == [z(0, 0, 1, 1)])
        #expect(GridEditor.Preset.twoColumns.zones == [z(0, 0, 0.5, 1), z(0.5, 0, 0.5, 1)])
        // Thirds are exact: 16/48 is the same double as 1/3.
        #expect(GridEditor.Preset.threeColumns.zones == [z(0, 0, 1.0 / 3, 1), z(1.0 / 3, 0, 1.0 / 3, 1), z(2.0 / 3, 0, 1.0 / 3, 1)])
        #expect(GridEditor.Preset.grid2x2.zones == [z(0, 0, 0.5, 0.5), z(0.5, 0, 0.5, 0.5), z(0, 0.5, 0.5, 0.5), z(0.5, 0.5, 0.5, 0.5)])
        #expect(GridEditor.Preset.grid3x2.zones.count == 6)
        var e = GridEditor(preset: .grid2x2)
        e.apply(.threeColumns)
        #expect(e.zones == GridEditor.Preset.threeColumns.zones)
    }

    // MARK: - merge

    /// The approved walkthrough, step 5: ⇧-click the two left cells of a 2×2 into one tall zone.
    @Test func shiftClickingTwoAdjacentCellsMergesThem() {
        var e = GridEditor(preset: .grid2x2)
        e.shiftClick(0)
        #expect(e.selected == 0)
        e.shiftClick(2)
        #expect(e.selected == nil)
        #expect(e.zones == [z(0, 0, 0.5, 1), z(0.5, 0, 0.5, 0.5), z(0.5, 0.5, 0.5, 0.5)])
    }

    @Test func aPairThatIsNotARectangleDoesNotMerge() {
        var e = GridEditor(preset: .grid2x2)
        let diagonal = e.merge(0, 3)
        #expect(!diagonal)
        e.shiftClick(0); e.shiftClick(3)
        #expect(e.cells.count == 4 && e.selected == 3) // the second pick becomes the pick
        e.shiftClick(3)
        #expect(e.selected == nil)                     // clicking the pick again drops it
        let column = e.merge(0, 2)
        let lShape = e.merge(0, 1)                     // tall + one short cell
        #expect(column && !lShape && e.cells.count == 3)
    }

    // MARK: - fill order

    /// Design §2: row-major, y then x, whatever order the cells were made in.
    @Test func zonesComeOutRowMajorAndTheNumbersSayHow() {
        var e = GridEditor(preset: .grid2x2)
        e.merge(1, 3)                                  // right column, stored at index 1
        #expect(e.zones == [z(0, 0, 0.5, 0.5), z(0.5, 0, 0.5, 1), z(0, 0.5, 0.5, 0.5)])
        #expect(e.cells.indices.map(e.number(of:)) == [1, 2, 3])
        #expect(e.cells[2] == GridEditor.Cell(x: 0, y: 24, w: 24, h: 24) && e.number(of: 2) == 3)
    }

    // MARK: - splitters

    @Test func splittersAreDerivedFromSharedEdges() {
        var e = GridEditor(preset: .grid2x2)
        #expect(e.splitters.map { [$0.at, $0.from, $0.to] } == [[24, 0, 48], [24, 0, 48]])
        #expect(e.splitters.map(\.axis) == [.vertical, .horizontal])
        e.merge(0, 2)
        // The horizontal edge now only runs down the right half.
        let h = e.splitters.first { $0.axis == .horizontal }
        #expect(h?.from == 24 && h?.to == 48)
        #expect(GridEditor(preset: .one).splitters.isEmpty)
        #expect(GridEditor(preset: .grid3x2).splitters.count == 3)
    }

    /// The walkthrough's step 6: drag the splitter to 60 %. It snaps to 29/48, and takes both
    /// cells on the right with it.
    @Test func draggingASplitterSnapsToTheLatticeAndMovesEveryCellOnIt() throws {
        var e = GridEditor(preset: .grid2x2)
        e.merge(0, 2)
        let v = try #require(e.splitters.first { $0.axis == .vertical })
        let moved = e.move(v, to: 0.6)
        #expect(moved.at == 29 && moved.percent == "60%")
        #expect(e.zones == [z(0, 0, 29.0 / 48, 1), z(29.0 / 48, 0, 19.0 / 48, 0.5), z(29.0 / 48, 0.5, 19.0 / 48, 0.5)])
        // Clamped: no cell drops below one step.
        let low = e.move(moved, to: -1), high = e.move(low, to: 2)
        #expect(low.at == 1 && high.at == 47)
    }

    /// A drag keeps moving the cells it started with, even once it lines up with another edge.
    @Test func aDragKeepsItsCellsWhenItCrossesAnotherEdge() throws {
        // Left column split at 1/4, right column at 3/4: two separate horizontal splitters.
        var e = try #require(GridEditor(editing: drawn("x", [z(0, 0, 0.5, 0.25), z(0.5, 0, 0.5, 0.75),
                                                             z(0, 0.25, 0.5, 0.75), z(0.5, 0.75, 0.5, 0.25)])))
        let left = try #require(e.splitters.first { $0.axis == .horizontal && $0.at == 12 })
        var s = e.move(left, to: 0.75)
        // Lined up, the edges read as one splitter across the canvas…
        #expect(e.splitters.contains { $0.axis == .horizontal && $0.from == 0 && $0.to == 48 })
        // …but the drag still holds only the left column's cells.
        s = e.move(s, to: 0.8)
        #expect(s.at == 38 && s.from == 0 && s.to == 24)
        #expect(e.cells.filter { $0.y == 0 }.map(\.h) == [38, 36])
    }

    @Test func aPointFindsTheSplitterNearIt() {
        let e = GridEditor(preset: .twoColumns)
        let tol = (x: 0.01, y: 0.01)
        #expect(e.splitter(near: (x: 0.505, y: 0.3), tolerance: tol)?.at == 24)
        #expect(e.splitter(near: (x: 0.3, y: 0.3), tolerance: tol) == nil)
    }

    // MARK: - opening what is saved

    @Test func aCleanLayoutRoundTripsThroughTheEditor() throws {
        let def = drawn("code-3", [z(0, 0, 0.625, 1), z(0.625, 0, 0.375, 0.5), z(0.625, 0.5, 0.375, 0.5)], name: "Code, three")
        let e = try #require(GridEditor(editing: def))
        #expect(e.def == def && !e.isNew)
    }

    /// Design §2: zones the grid cannot express open read-only.
    @Test func overlapHolesAndOffLatticeZonesDoNotOpenForEditing() {
        #expect(GridEditor(editing: drawn("o", [z(0, 0, 0.6, 1), z(0.5, 0, 0.5, 1)])) == nil)      // overlap
        #expect(GridEditor(editing: drawn("h", [z(0, 0, 0.5, 1)])) == nil)                         // a hole
        #expect(GridEditor(editing: drawn("t", [z(0, 0, 0.3, 1), z(0.3, 0, 0.7, 1)])) == nil)      // 0.3 is not n/48
        #expect(GridEditor(editing: LayoutDef.builtins[0]) == nil)                                 // nothing to draw
    }

    @Test func duplicatingABuiltinStartsFromItsNearestGrid() {
        let half = GridEditor(duplicating: LayoutDef.builtins.first { $0.id == .half }!)
        #expect(half.zones == [z(0, 0, 0.5, 1), z(0.5, 0, 0.5, 0.5), z(0.5, 0.5, 0.5, 0.5)])
        #expect(half.name == "Half copy" && half.id == "half-copy" && half.isNew)
        #expect(GridEditor(duplicating: LayoutDef.builtins[0]).zones == [z(0, 0, 1, 1)])
    }

    // MARK: - name and id

    @Test func theIdFollowsTheNameUntilItIsTyped() {
        var e = GridEditor()
        e.setName("Code, three")
        #expect(e.id == "code-three")
        e.setID("code-3")
        e.setName("Code, 3 panes")
        #expect(e.id == "code-3")
        // An existing layout keeps its id: the workspaces using it hold the id.
        var old = GridEditor(editing: drawn("keep", GridEditor.Preset.one.zones))!
        old.setName("Renamed"); old.setID("other")
        #expect(old.id == "keep" && old.name == "Renamed")
    }

    @Test func saveIsRefusedWithAReason() {
        var e = GridEditor()
        #expect(e.problem(taken: []) == "Give the layout a name.")
        e.setName("Grid"); e.setID("grid")
        #expect(e.problem(taken: []) == "\"grid\" is a built-in layout. Pick another id.")
        e.setID("Has Space")
        #expect(e.problem(taken: []) == "The id can use lowercase letters, digits, - and _.")
        e.setID("code-3")
        #expect(e.problem(taken: ["code-3"]) == "A layout with the id \"code-3\" already exists.")
        #expect(e.problem(taken: []) == nil)
        // Editing a saved layout does not collide with itself.
        #expect(GridEditor(editing: drawn("code-3", GridEditor.Preset.one.zones))!.problem(taken: ["code-3"]) == nil)
    }

    // MARK: - Copy as TOML

    /// Design §3.3: the block the editor copies is exactly what `[[layout]]` reads back.
    @Test func copyAsTOMLParsesBackToTheSameLayout() throws {
        var e = GridEditor(preset: .grid3x2)
        e.merge(0, 3)
        e.setName("Wide \"quoted\" \\ name")
        let def = e.def
        let toml = try #require(def.toml)
        #expect(toml.hasPrefix("[[layout]]\nid = \"wide-quoted-name\"\n"))
        let parsed = try Config.parse(toml: toml)
        #expect(parsed.layouts == [def])
        var withSymbol = def; withSymbol.symbol = "sidebar.left"
        #expect(try Config.parse(toml: withSymbol.toml!).layouts == [withSymbol])
        #expect(LayoutDef.builtins[0].toml == nil)
    }

    // MARK: - settings.json

    @Test func savingWritesSettingsAndSurvivesARestart() throws {
        // Thirds: the zone at 2/3 must come back as exactly 1/3 wide, not 1 − 2/3.
        let def = GridEditor(editing: drawn("code-3", GridEditor.Preset.grid3x2.zones))!.def
        var o = SettingsOverrides()
        o.saveLayout(def)
        o.setLayout(def.id, onBar: true, current: LayoutCatalogue.builtins.bar)
        // A restart: settings.json is written and read back.
        let reread = try JSONDecoder().decode(SettingsOverrides.self, from: JSONEncoder().encode(o))
        #expect(reread == o)
        let cat = LayoutCatalogue(config: Settings.effective(config: Config(), overrides: reread))
        #expect(cat[def.id] == def && cat.bar.last == def.id)
        // Save again replaces in place.
        var renamed = def; renamed.name = "Renamed"
        o.saveLayout(renamed)
        #expect(o.layouts == [renamed])
    }

    /// Design §3.1: settings.json wins per id; Reset (removing the entry) lets the file show through.
    @Test func resetRevealsTheFileLayoutAndDeleteRemovesADrawnOne() throws {
        var file = try Config.parse(toml: GridEditorTests.fileTOML)
        file.defaultLayout = "code-3"
        let edited = drawn("wide", GridEditor.Preset.twoColumns.zones, name: "Edited")
        var o = SettingsOverrides()
        o.saveLayout(edited)
        o.saveLayout(drawn("mine", GridEditor.Preset.one.zones))
        var cat = LayoutCatalogue(config: Settings.effective(config: file, overrides: o))
        #expect(cat["wide"]?.name == "Edited" && cat.fileIDs == ["wide"])
        o.removeLayout("wide")
        cat = LayoutCatalogue(config: Settings.effective(config: file, overrides: o))
        #expect(cat["wide"]?.name == "Ultrawide four")
        o.removeLayout("mine")
        #expect(o.layouts == nil)
        #expect(LayoutCatalogue(config: Settings.effective(config: file, overrides: o))["mine"] == nil)
    }

    @Test func theBarToggleWritesTheWholeBarAndStopsAtEight() {
        var o = SettingsOverrides()
        let five = LayoutCatalogue.builtins.bar
        let off = o.setLayout(.grid, onBar: false, current: five)
        #expect(off && o.layoutBar == [.maximize, .split, .column, .half])
        let again = o.setLayout(.maximize, onBar: true, current: o.layoutBar!)   // already there: unchanged
        #expect(again && o.layoutBar == [.maximize, .split, .column, .half])
        let eight: [LayoutID] = five + ["a", "b", "c"]
        let ninth = o.setLayout("d", onBar: true, current: eight)
        #expect(!ninth && o.layoutBar == [.maximize, .split, .column, .half])
    }

    // MARK: - delete

    /// Design §8.6.
    @Test func theDeleteSheetCountsTheWorkspacesAndNamesTheFallback() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: "code-3")
        #expect(w.workspaces(using: "code-3") == 2)
        w.screens["D2"]!.workspaces[0].layout = .grid
        #expect(w.workspaces(using: "code-3") == 1)
        #expect(GridEditor.deleteWarning(usage: 3, fallback: .maximize)
                == "3 workspaces use this layout; they will use maximize until you choose another.")
        #expect(GridEditor.deleteWarning(usage: 1, fallback: .grid)
                == "1 workspace uses this layout; it will use grid until you choose another.")
        #expect(GridEditor.deleteWarning(usage: 0, fallback: .grid) == "No workspace uses this layout.")
        var c = Config(); c.layouts = [drawn("code-3", GridEditor.Preset.one.zones)]
        c.defaultLayout = .grid
        #expect(LayoutCatalogue(config: c).fallback(afterDeleting: "code-3") == .grid)
        c.defaultLayout = "code-3"                      // deleting the default itself
        #expect(LayoutCatalogue(config: c).fallback(afterDeleting: "code-3") == .maximize)
    }

    // MARK: - the popover, the switcher and the ⋯ menu

    static let fileTOML = """
    [[layout]]
    id = "wide"
    name = "Ultrawide four"
    zones = [{ x = 0.0, y = 0.0, w = 0.25, h = 1.0 }, { x = 0.25, y = 0.0, w = 0.75, h = 1.0 }]
    """

    @Test func theMenuIsSectionedAndTheSwitcherShowsTheActiveLayout() throws {
        var file = try Config.parse(toml: GridEditorTests.fileTOML)
        var o = SettingsOverrides()
        o.saveLayout(drawn("code-3", GridEditor.Preset.twoColumns.zones, name: "Code, three"))
        file = Settings.effective(config: file, overrides: o)
        let cat = LayoutCatalogue(config: file)
        let s = ScreenShellState(display: "D1", isFocusedScreen: true, rail: [], tabs: [], layout: "code-3", layouts: cat)
        #expect(s.menuSections.map(\.title) == ["Built-in", "From config.toml", "Drawn"])
        #expect(s.menuSections.map { $0.items.map(\.id.rawValue) }
                == [["maximize", "split", "column", "half", "grid"], ["wide"], ["code-3"]])
        // Not on the bar, but active: drawn after the set so the bar shows what is on screen.
        #expect(s.switcher.map(\.id) == cat.bar + ["code-3"])
        #expect(s.layouts.first { $0.id == "code-3" }?.onBar == false)
        #expect(s.defaultLayout == .maximize && s.layoutWarning == nil)
        // Missing: the fallback is highlighted (it is on the bar, so nothing is appended), badged.
        let missing = ScreenShellState(display: "D1", isFocusedScreen: true, rail: [], tabs: [], layout: "gone", layouts: cat)
        #expect(missing.shownLayout == .maximize && missing.switcher.map(\.id) == cat.bar)
        #expect(missing.layoutWarning == "layout \"gone\" is missing — using maximize")
        // No file layouts, no "From config.toml" section.
        #expect(ScreenShellState(display: "D1", isFocusedScreen: true, rail: [], tabs: [], layout: .grid)
            .menuSections.map(\.title) == ["Built-in"])
    }

    // MARK: - set-layout (design §6, Q5)

    @Test func setLayoutTargetsTheFocusedWorkspaceAndRefusesUnknownIds() {
        var c = Config(); c.layouts = [drawn("code-3", GridEditor.Preset.one.zones)]
        let w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        let wire = WireState(world: w, layouts: LayoutCatalogue(config: c))
        let focused = w.screens[w.focus.screen]!.active.id
        #expect(wire.setLayout("code-3", workspace: nil) == .success(.setWorkspaceLayout(focused, "code-3")))
        let other = w.screens[w.focus.screen == "D1" ? "D2" : "D1"]!.active.id
        #expect(wire.setLayout("grid", workspace: other.uuidString) == .success(.setWorkspaceLayout(other, .grid)))
        #expect(wire.setLayout("foo", workspace: nil)
                == .failure(SetLayoutRefusal("unknown layout \"foo\" (known: maximize, split, column, half, grid, code-3)")))
        #expect(wire.setLayout("grid", workspace: "nope") == .failure(SetLayoutRefusal("unknown workspace \"nope\"")))
        #expect(wire.setLayout(nil, workspace: nil) == .failure(SetLayoutRefusal("set-layout needs a layout id")))
    }

    /// The popover and editor commands are the app layer's: the model ignores them.
    @Test func layoutSurfaceCommandsAreNoOpsInTheModel() {
        let w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        for c in [Command.editLayout(nil, workspace: nil), .setDefaultLayout(.grid), .showLayoutOnBar(.grid, false)] {
            let (after, effects) = CommandRunner.apply(c, to: w)
            #expect(after == w && effects.isEmpty)
        }
    }
}
