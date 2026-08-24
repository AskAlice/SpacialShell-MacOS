import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ShellUIStateTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 2), c = WindowRef(id: 3, pid: 3)

    func base() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .float, on: "D1"); w.adopt(c, kind: .tile, on: "D2")
        return w   // focus a on D1[0]
    }

    @Test func railMirrorsTheStack() {
        let s = ShellUI.state(for: "D1", in: base())!
        #expect(s.rail.count == 2)                                  // occupied + trailing empty
        #expect(s.rail[0].isActive && s.rail[0].windowCount == 2)
        #expect(!s.rail[1].isActive && s.rail[1].isTrailingEmpty)
        #expect(s.isFocusedScreen)
        #expect(!ShellUI.state(for: "D2", in: base())!.isFocusedScreen)
    }

    @Test func pinnedEmptyIsNotDrawnAsTheWayDown() {
        var w = base()
        w.screens["D1"]!.workspaces[0].pinned = true
        w.screens["D1"]!.workspaces[0].windows = []
        w.screens["D1"]!.workspaces[0].floating = []
        w.normalize()
        let s = ShellUI.state(for: "D1", in: w)!
        #expect(s.rail.first!.isPinned && !s.rail.first!.isTrailingEmpty)
        #expect(s.rail.last!.isTrailingEmpty)
    }

    @Test func tabsCarryFlagsForTheActiveRow() {
        var w = base()
        w.setHidden(a, true)
        let s = ShellUI.state(for: "D1", in: w)!
        #expect(s.tabs.map(\.ref) == [a, b])
        #expect(s.tabs[0].isHidden && !s.tabs[0].isFocused)
        #expect(s.tabs[1].isFloating && s.tabs[1].isFocused)        // focus fell to b when a hid
        #expect(s.layout == .maximize)
    }

    @Test func unknownDisplayIsNil() {
        #expect(ShellUI.state(for: "nope", in: base()) == nil)
    }
}

@Suite struct ShellCommandTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1)

    func base() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1"); w.adopt(c, kind: .tile, on: "D2")
        return w   // focus a on D1[0]
    }
    func run(_ w: World, _ c: Command) -> (World, [Effect]) {
        let r = CommandRunner.apply(c, to: w)
        #expect(r.0.invariantViolations().isEmpty, "after \(c): \(r.0.invariantViolations())")
        return r
    }

    @Test func activateWorkspaceOnOtherScreenMovesFocusThere() {
        let (w, e) = run(base(), .activateWorkspace("D2", 0))
        #expect(w.focus.screen == "D2" && w.focus.window == c)
        #expect(e == [.focus(c), .relayout])
    }
    @Test func activateTrailingEmptyLandsNowhereReal() {
        let (w, e) = run(base(), .activateWorkspace("D1", 1))
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == nil)
        #expect(e == [.relayout])
    }
    @Test func activateWorkspaceOutOfRangeIsANoOp() {
        let before = base()
        let (w, e) = run(before, .activateWorkspace("D1", 9))
        #expect(w == before && e.isEmpty)
    }

    @Test func selectWindowCrossesScreensAndAnchors() {
        let (w, e) = run(base(), .selectWindow(c))
        #expect(w.focus == Focus(screen: "D2", window: c))
        #expect(w.screens["D2"]!.active.anchor == c)
        #expect(e == [.focus(c), .relayout])
    }
    @Test func selectHiddenWindowIsANoOp() {
        var w = base(); w.setHidden(b, true)
        let before = w
        let (after, e) = run(w, .selectWindow(b))
        #expect(after == before && e.isEmpty)
    }
    @Test func selectEphemeralFocusesWithoutAWorkspace() {
        var w = base(); let v = WindowRef(id: 9, pid: 9); w.adopt(v, kind: .ephemeral, on: "D1")
        let (after, e) = run(w, .selectWindow(v))
        #expect(after.focus.window == v && e == [.focus(v)])
    }

    @Test func setLayoutHitsTheNamedScreensActiveWorkspace() {
        let (w, e) = run(base(), .setLayout("D2", .grid))
        #expect(w.screens["D2"]!.active.layout == .grid)
        #expect(w.screens["D1"]!.active.layout == .maximize)       // untouched
        #expect(w.focus.screen == "D1")                            // a layout click does not move focus
        #expect(e == [.relayout])
    }

    @Test func closeWindowOnlyEmitsTheEffect() {
        let before = base()
        let (w, e) = run(before, .closeWindow(c))
        #expect(w == before && e == [.close(c)])
    }

    @Test func toggleOverviewIsANoOpInTheModel() throws {
        let before = base()
        let (w, e) = run(before, .toggleOverview)
        #expect(w == before && e.isEmpty)
        // …but it is a real, bound command: Fn+Tab in the fn preset.
        let t = KeyBindings.table(for: try Config.parse(toml: ""))
        #expect(t[KeyBindings.parse("fn-tab")!] == .toggleOverview)
    }

    @Test func toggleShellUIFlipsAndRelayouts() {
        let (w, e) = run(base(), .toggleShellUI)
        #expect(!w.shellUIVisible && e == [.relayout])
        let (w2, _) = run(w, .toggleShellUI)
        #expect(w2.shellUIVisible)
    }
}

@Suite struct PanelInsetTests {
    let a = WindowRef(id: 1, pid: 1)
    let display = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
                              visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 575), isMain: true)

    @Test func insetsComeOffTheTopAndLeadingEdges() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        let cfg = LayoutConfig(gap: 8, insets: PanelInsets(top: 38, leading: 48))
        let out = Reconciler.desired(world: w, displays: [display], config: cfg,
                                     observed: [:], prePark: [:], parkedNow: [], zeroSliver: [])
        // visibleFrame minus panels, minus gap, minus the 1 pt height guard:
        let expected = CGRect(x: 0 + 48 + 8, y: 25 + 38 + 8, width: 1000 - 48 - 16, height: 575 - 38 - 16 - 1)
        #expect(out[a] == .frame(expected))
    }

    @Test func zeroInsetsAreTheM1Rect() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        let out = Reconciler.desired(world: w, displays: [display], config: LayoutConfig(gap: 8),
                                     observed: [:], prePark: [:], parkedNow: [], zeroSliver: [])
        let expected = CGRect(x: 8, y: 33, width: 984, height: 558)
        #expect(out[a] == .frame(expected))
    }
}

@Suite struct UIConfigTests {
    @Test func uiTableParses() throws {
        let c = try Config.parse(toml: """
        [ui]
        enabled = true
        rail-width = 56
        bar-height = 40
        """)
        #expect(c.ui.enabled && c.ui.railWidth == 56 && c.ui.barHeight == 40)
    }
    @Test func missingUiTableIsTheDefault() throws {
        let c = try Config.parse(toml: "gap = 4")
        #expect(c.ui == UIConfig())
        #expect(c.ui.enabled && c.ui.railWidth == 48 && c.ui.barHeight == 38)
    }
    @Test func partialUiTableFillsDefaults() throws {
        let c = try Config.parse(toml: """
        [ui]
        enabled = false
        """)
        #expect(!c.ui.enabled && c.ui.railWidth == 48)
    }
}
