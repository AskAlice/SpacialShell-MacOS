import CoreGraphics
import Testing
@testable import SpacialShellKit

/// The M4 keyboard grammar: directional displays (#118), reverse and direct layouts (#119),
/// workspace wrap (#120) and tab N (#143).
@Suite struct KeyboardGrammarTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1)

    func display(_ id: DisplayID, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1920, _ h: CGFloat = 1080) -> DisplayInfo {
        let f = CGRect(x: x, y: y, width: w, height: h)
        return DisplayInfo(id: id, frame: f, visibleFrame: f, isMain: id == "D1")
    }
    /// a, b, c tiled in D1's first row; D2 empty.
    func base() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1"); w.adopt(c, kind: .tile, on: "D1")
        return w
    }
    func run(_ w: World, _ cmd: Command, layouts: LayoutCatalogue = .builtins, displays: [DisplayInfo] = [],
             wrap: Bool = false) -> (World, [Effect]) {
        let r = CommandRunner.apply(cmd, to: w, layouts: layouts, displays: displays, workspaceWrap: wrap)
        #expect(r.0.invariantViolations().isEmpty, "after \(cmd): \(r.0.invariantViolations())")
        return r
    }

    // MARK: #118 display geometry

    @Test func neighbourSideBySide() {
        let ds = [display("D1", 0, 0), display("D2", 1920, 0)]
        #expect(DisplayNeighbours.neighbour(of: "D1", .right, in: ds) == "D2")
        #expect(DisplayNeighbours.neighbour(of: "D2", .left, in: ds) == "D1")
        #expect(DisplayNeighbours.neighbour(of: "D1", .left, in: ds) == nil)
        #expect(DisplayNeighbours.neighbour(of: "D1", .up, in: ds) == nil)
        #expect(DisplayNeighbours.neighbour(of: "unknown", .right, in: ds) == nil)
    }

    /// Up is a smaller y (global frames are y-down), and a neighbour to the right that sits a
    /// little higher is still "right", not "up".
    @Test func neighbourStackedPrefersTheDirectionsCone() {
        let ds = [display("D1", 0, 0), display("D2", 1920, -100), display("D3", 200, -1080)]
        #expect(DisplayNeighbours.neighbour(of: "D1", .up, in: ds) == "D3")
        #expect(DisplayNeighbours.neighbour(of: "D1", .right, in: ds) == "D2")
        #expect(DisplayNeighbours.neighbour(of: "D3", .down, in: ds) == "D1")
    }

    /// The nearest wins among several displays that way.
    @Test func neighbourPicksTheNearest() {
        let ds = [display("D1", 0, 0), display("D2", 1920, 0), display("D3", 3840, 0)]
        #expect(DisplayNeighbours.neighbour(of: "D1", .right, in: ds) == "D2")
        #expect(DisplayNeighbours.neighbour(of: "D3", .left, in: ds) == "D2")
    }

    /// A display above but far off to the side is outside ↑'s cone; with nothing in the cone the
    /// half-plane counts, so ↑ still reaches it.
    @Test func neighbourFallsBackToTheHalfPlane() {
        let ds = [display("D1", 0, 0), display("D2", 3000, -1200)]
        #expect(DisplayNeighbours.neighbour(of: "D1", .up, in: ds) == "D2")
        #expect(DisplayNeighbours.neighbour(of: "D1", .right, in: ds) == "D2")
        #expect(DisplayNeighbours.neighbour(of: "D1", .down, in: ds) == nil)
    }

    // MARK: #118 commands

    @Test func moveWindowToTheDisplayAboveFollows() {
        let ds = [display("D1", 0, 0), display("D2", 0, -1080)]
        let (w, e) = run(base(), .moveWindowToScreenDirection(.up), displays: ds)
        #expect(w.screens["D2"]!.active.windows == [a])
        #expect(w.screens["D1"]!.active.windows == [b, c])
        #expect(w.focus == Focus(screen: "D2", window: a))
        #expect(e == [.focus(a), .relayout])
    }

    @Test func moveWindowToScreenDirectionWithNothingThatWayIsANoOp() {
        let ds = [display("D1", 0, 0), display("D2", 0, -1080)]
        let w = base()
        #expect(run(w, .moveWindowToScreenDirection(.down), displays: ds) == (w, []))
        #expect(run(w, .moveWindowToScreenDirection(.up)) == (w, []), "no display frames, no move")
    }

    @Test func focusTheDisplayBelow() {
        let ds = [display("D1", 0, 0), display("D2", 0, 1080)]
        var w = base()
        (w, _) = run(w, .focusScreenDirection(.down), displays: ds)
        #expect(w.focus == Focus(screen: "D2", window: nil))
        (w, _) = run(w, .focusScreenDirection(.up), displays: ds)
        #expect(w.focus == Focus(screen: "D1", window: a))
        #expect(run(w, .focusScreenDirection(.left), displays: ds).1.isEmpty)
    }

    // MARK: #136 move a workspace to another display

    let d = WindowRef(id: 4, pid: 2)
    let sideBySide = [DisplayInfo](arrayLiteral:
        .init(id: "D1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
              visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true),
        .init(id: "D2", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
              visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isMain: false))
    /// D1: [b] [a, active, grid, resized, web] +; D2: [d] +. Focus a on D1.
    func twoDisplays() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        (w, _) = run(w, .moveWindowToWorkspace(.down))
        w.adopt(d, kind: .tile, on: "D2")
        w.screens["D1"]!.workspaces[1].layout = .grid
        w.screens["D1"]!.workspaces[1].portions["grid#1"] = Portions(x: [0.3])
        w.screens["D1"]!.workspaces[1].category = .web
        return w
    }
    func move(_ w: World, _ dir: Direction, order: [AppCategory] = []) -> CommandOutcome {
        let o = CommandRunner.run(.moveWorkspaceToScreenDirection(dir), on: w, displays: sideBySide, categoryOrder: order)
        #expect(o.world.invariantViolations().isEmpty, "\(o.world.invariantViolations())")
        for (id, s) in o.world.screens {   // exactly one trailing empty row on every display
            #expect(s.workspaces.last!.isEmpty && s.workspaces.filter(\.isEmpty).count == 1, "\(id)")
        }
        return o
    }

    @Test func moveWorkspaceCarriesTheRowAndFocusFollows() {
        let w = twoDisplays(), row = w.screens["D1"]!.active
        let o = move(w, .right)
        #expect(o.report == .done)
        #expect(o.world.screens["D1"]!.workspaces.map(\.windows) == [[b], []])
        #expect(o.world.screens["D1"]!.activeIndex == 0, "the source activates its neighbour")
        let d2 = o.world.screens["D2"]!
        #expect(d2.workspaces.map(\.windows) == [[d], [a], []], "no order: just above the trailing empty")
        #expect(d2.activeIndex == 1 && d2.active.id == row.id)
        #expect(d2.active.layout == .grid && d2.active.portions == row.portions && d2.active.category == .web)
        #expect(o.world.focus == Focus(screen: "D2", window: a))
        #expect(o.effects == [.focus(a), .relayout])
        #expect(d2.previous == d2.workspaces[0].id, "Fn+N can come back to the row it covered")
    }

    @Test func moveWorkspaceLandsInItsCategorySlot() {
        var w = twoDisplays()
        w.screens["D2"]!.workspaces[0].category = .coding
        let o = move(w, .right, order: [.web, .coding])
        #expect(o.world.screens["D2"]!.workspaces.map(\.windows) == [[a], [d], []], "web before coding")
        #expect(o.world.screens["D2"]!.activeIndex == 0 && o.world.focus == Focus(screen: "D2", window: a))
    }

    /// One row per category per display (#112): the arriving row keeps its category.
    @Test func moveWorkspaceTakesItsCategoryFromTheRowThere() {
        var w = twoDisplays()
        w.screens["D2"]!.workspaces[0].category = .web
        let o = move(w, .right, order: [.web])
        #expect(o.world.screens["D2"]!.workspaces.map(\.category) == [.web, nil, nil])
        #expect(o.world.screens["D2"]!.workspaces[0].windows == [a])
    }

    @Test func moveWorkspaceNoOps() {
        let w = twoDisplays()
        #expect(move(w, .left).report == .noop("no display that way"))
        #expect(CommandRunner.run(.moveWorkspaceToScreenDirection(.right), on: w).report == .noop("no display that way"),
                "no display frames, no move")
        var trailing = w
        trailing.activate(index: 2, on: "D1")
        #expect(move(trailing, .right).report == .noop("the empty workspace stays"))
        var only = w
        only.focus = Focus(screen: "D2", window: d)
        #expect(move(only, .left).report == .noop("the only workspace on this display"))
        #expect(move(only, .left).world == only)
    }

    // MARK: #119 layouts

    @Test func cycleLayoutReverseRingsTheBarBackwards() {
        var w = base()
        (w, _) = run(w, .cycleLayoutReverse); #expect(w.screens["D1"]!.active.layout == .grid)
        (w, _) = run(w, .cycleLayoutReverse); #expect(w.screens["D1"]!.active.layout == .half)
        (w, _) = run(w, .cycleLayout); #expect(w.screens["D1"]!.active.layout == .grid)
    }

    @Test func previousFromOutsideTheBarIsItsEnd() {
        var c = Config(); c.layoutBar = [.split, .column]
        let cat = LayoutCatalogue(config: c)
        #expect(cat.previous(before: .grid) == .column)
        #expect(cat.previous(before: .split) == .column)
        #expect(cat.previous(before: .column) == .split)
    }

    @Test func setLayoutTargetsTheActiveRowAndRefusesUnknownIDs() {
        var w = base()
        let (after, e) = run(w, .setLayout(.grid))
        #expect(after.screens["D1"]!.active.layout == .grid && e == [.relayout])
        w = after
        #expect(run(w, .setLayout(.grid)) == (w, []), "already there")
        #expect(run(w, .setLayout("no-such-layout")) == (w, []))
    }

    @Test func setLayoutReachesASavedLayout() {
        var c = Config()
        c.layouts = [LayoutDef(id: "code", name: "Code", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 1)]))]
        let (w, _) = run(base(), .setLayout("code"), layouts: LayoutCatalogue(config: c))
        #expect(w.screens["D1"]!.active.layout == "code")
    }

    // MARK: #120 wrap

    /// Rows [[a, b], [c], [+]], on the second.
    func twoRows() -> World {
        var w = base()
        (w, _) = run(base(), .focusWindow(.left))            // focus c
        (w, _) = run(w, .moveWindowToWorkspace(.down))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[a, b], [c], []])
        return w
    }

    @Test func wrapOffKeepsTheEnds() {
        var w = twoRows()
        (w, _) = run(w, .focusWorkspace(.down)); #expect(w.screens["D1"]!.activeIndex == 2, "the + row")
        (w, _) = run(w, .focusWorkspace(.up)); (w, _) = run(w, .focusWorkspace(.up))
        #expect(w.screens["D1"]!.activeIndex == 0)
        #expect(run(w, .focusWorkspace(.up)).1.isEmpty)
    }

    @Test func wrapOnJoinsTheFirstAndLastNonEmptyRows() {
        var w = twoRows()
        (w, _) = run(w, .focusWorkspace(.down), wrap: true)
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus.window == a)
        (w, _) = run(w, .focusWorkspace(.up), wrap: true)
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == c)
        // From the trailing + row (reached by the rail's "+"), down also wraps to the first.
        w.activate(index: 2, on: "D1")
        (w, _) = run(w, .focusWorkspace(.down), wrap: true)
        #expect(w.screens["D1"]!.activeIndex == 0)
    }

    @Test func wrapWithOneRowIsANoOp() {
        let w = base()
        #expect(run(w, .focusWorkspace(.up), wrap: true).1.isEmpty)
        #expect(run(w, .focusWorkspace(.down), wrap: true).1.isEmpty)
    }

    @Test func workspaceWrapKey() throws {
        #expect(!Config().workspaceWrap)
        let file = try Config.parse(toml: "workspace-wrap = true")
        #expect(file.workspaceWrap)
        #expect(try Config.parse(toml: file.render()).workspaceWrap)
        var gui = SettingsOverrides(); gui.workspaceWrap = false
        #expect(!Settings.effective(config: file, overrides: gui).workspaceWrap)
    }

    // MARK: #143 tab N

    @Test func focusTabClamps() {
        let w = base()
        #expect(run(w, .focusTab(2)).0.focus.window == b)
        #expect(run(w, .focusTab(9)).0.focus.window == c, "past the end: the last tab")
        #expect(run(run(w, .focusTab(3)).0, .focusTab(0)).0.focus.window == a, "below 1: the first tab")
        let (after, e) = run(w, .focusTab(3))
        #expect(e == [.focus(c), .relayout] && after.screens["D1"]!.active.anchor == c)
    }

    @Test func focusTabUnhidesAMinimizedTab() {
        var w = base(); w.setHidden(b, true)
        let (after, e) = run(w, .focusTab(2))
        #expect(after.focus.window == b && !after.hidden.contains(b))
        #expect(e == [.unhide(b), .focus(b), .relayout])
    }

    @Test func focusTabOnAnEmptyRowIsANoOp() {
        let w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        #expect(run(w, .focusTab(1)) == (w, []))
    }

    // MARK: chords

    let fnPreset = KeyBindings.table(for: Config())

    @Test func monitorChordsOnTheGrammar() {
        let t = fnPreset
        #expect(t[KeyBindings.parse("fn-alt-a")!] == .focusScreenDirection(.left))
        #expect(t[KeyBindings.parse("fn-alt-d")!] == .focusScreenDirection(.right))
        #expect(t[KeyBindings.parse("fn-alt-w")!] == .focusScreenDirection(.up))
        #expect(t[KeyBindings.parse("fn-alt-s")!] == .focusScreenDirection(.down))
        // The aliases and #98 stay.
        #expect(t[KeyBindings.parse("fn-leftSquareBracket")!] == .focusScreen(.prev))
        #expect(t[KeyBindings.parse("fn-shift-rightSquareBracket")!] == .moveWindowToScreen(.next))
        #expect(t[KeyBindings.parse("fn-alt-shift-w")!] == .moveAppToWorkspace(.up))
    }

    /// With Fn held, macOS reports ←/→/↑/↓ as Home/End/PgUp/PgDn with the Fn flag set (#31), so
    /// the table binds those codes — exactly the chord the tap builds for Fn+⇧+arrow.
    @Test func fnShiftArrowsAreTheNavigationKeys() {
        let t = fnPreset
        for (code, dir) in [(115, Direction.left), (119, .right), (116, .up), (121, .down)] {
            let hw = Chord(keyCode: UInt16(code), fn: true, control: false, option: false, shift: true, command: false)
            #expect(t[hw] == .moveWindowToScreenDirection(dir))
        }
        #expect(KeyBindings.parse("fn-shift-left") == KeyBindings.parse("fn-shift-home"))
        #expect(KeyBindings.parse("fn-shift-up")?.keyCode == 116)
        #expect(KeyBindings.parse("ctrl-alt-left")?.keyCode == 123, "only an fn arrow is remapped")
        #expect(KeyBindings.display(KeyBindings.parse("fn-shift-home")!) == "Fn+⇧←")
        #expect(t[KeyBindings.parse("ctrl-alt-shift-left")!] == .moveWindow(.left), "the ⌃⌥ arrow aliases stand")
    }

    /// #136: Fn+⌥⇧+arrows, i.e. the navigation keys with ⌥⇧.
    @Test func fnAltShiftArrowsMoveTheWorkspace() {
        let t = fnPreset
        for (code, dir) in [(115, Direction.left), (119, .right), (116, .up), (121, .down)] {
            let hw = Chord(keyCode: UInt16(code), fn: true, control: false, option: true, shift: true, command: false)
            #expect(t[hw] == .moveWorkspaceToScreenDirection(dir))
        }
        #expect(KeyBindings.command(named: "move-workspace-to-screen-up") == .moveWorkspaceToScreenDirection(.up))
        var c = Config(); c.keybindingPreset = .ctrlAlt
        #expect(!KeyBindings.table(for: c).values.contains { if case .moveWorkspaceToScreenDirection = $0 { true } else { false } })
    }

    @Test func reverseCycleAndTabChords() {
        let t = fnPreset
        #expect(t[KeyBindings.parse("fn-shift-space")!] == .cycleLayoutReverse)
        for n in 1...9 { #expect(t[KeyBindings.parse("fn-alt-\(n)")!] == .focusTab(n)) }
        #expect(t[KeyBindings.parse("fn-alt-0")!] == .focusTab(1))
        #expect(KeyBindings.command(named: "focus-tab-4") == .focusTab(4))
        #expect(!t.values.contains { if case .setLayout = $0 { true } else { false } }, "set-layout is unbound by default")
    }

    /// ⌃⌥ already holds ⌥, so the monitor and tab chords would land on the row/tab chords there.
    @Test func ctrlAltPresetLeavesTheFnOnlyChordsUnbound() {
        var c = Config(); c.keybindingPreset = .ctrlAlt
        let t = KeyBindings.table(for: c)
        #expect(t[KeyBindings.parse("ctrl-alt-a")!] == .focusWindow(.left))
        #expect(t[KeyBindings.parse("ctrl-alt-shift-space")!] == .cycleLayoutReverse)
        #expect(t[KeyBindings.parse("ctrl-alt-leftSquareBracket")!] == .focusScreen(.prev))
        #expect(!t.values.contains { if case .focusTab = $0 { true } else { false } })
        #expect(!t.values.contains { if case .focusScreenDirection = $0 { true } else { false } })
        #expect(!t.values.contains { if case .moveWindowToScreenDirection = $0 { true } else { false } })
    }

    @Test func setLayoutIsBindableByName() {
        var c = Config()
        c.keybindings = ["fn-alt-shift-g": "set-layout-grid"]
        c.keybindingOverrides = ["set-layout-code": "fn-alt-shift-c"]
        let t = KeyBindings.table(for: c)
        #expect(t[KeyBindings.parse("fn-alt-shift-g")!] == .setLayout(.grid))
        #expect(t[KeyBindings.parse("fn-alt-shift-c")!] == .setLayout("code"))
        #expect(KeyBindings.name(of: .setLayout("code")) == "set-layout-code")
        #expect(KeyBindings.command(named: "set-layout-") == nil)
        #expect(KeyBindings.command(named: "nonsense") == nil)
    }

    @Test func cheatSheetShowsTheGrammar() {
        let rows = CheatSheet.rows(for: Config())
        func chords(_ name: String) -> [String]? { rows.first { $0.commandName == name }?.chords }
        #expect(chords("focus-screen-up") == ["Fn+⌥W/A/S/D"])
        #expect(chords("move-window-to-screen-up") == ["Fn+⇧↑/←/↓/→"])
        #expect(chords("move-workspace-to-screen-up") == ["Fn+⌥⇧↑/←/↓/→"])   // #136
        #expect(chords("cycle-layout-reverse") == ["Fn+⇧Space"])
        #expect(chords("focus-tab-1") == ["Fn+⌥1…9"])
    }
}
