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

    @Test func focusWorkspaceIDOnOtherScreenMovesFocusThere() {
        let w0 = base()
        let target = w0.screens["D2"]!.workspaces[0].id
        let (w, e) = run(w0, .focusWorkspaceID(target))
        #expect(w.focus.screen == "D2" && w.focus.window == c)
        #expect(e == [.focus(c), .relayout])
    }
    @Test func focusTrailingEmptyLandsNowhereReal() {
        let w0 = base()
        let target = w0.screens["D1"]!.workspaces[1].id
        let (w, e) = run(w0, .focusWorkspaceID(target))
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == nil)
        #expect(e == [.relayout])
    }
    @Test func unknownWorkspaceIDIsANoOp() {
        let before = base()
        let (w, e) = run(before, .focusWorkspaceID(UUID()))
        #expect(w == before && e.isEmpty)
    }

    @Test func focusWindowRefCrossesScreensAndAnchors() {
        let (w, e) = run(base(), .focusWindowRef(c))
        #expect(w.focus == Focus(screen: "D2", window: c))
        #expect(w.screens["D2"]!.active.anchor == c)
        #expect(e == [.focus(c), .relayout])
    }
    /// Decision 2026-09-15 (#48), replacing "a hidden window's tab is a no-op": a tab is a promise
    /// that clicking it delivers the window. A minimized or ⌘H-hidden window is brought back —
    /// `hidden` is cleared so focus can land on it (invariant 5), the backend is told to un-hide it,
    /// and the reconciler places it by its row's layout.
    @Test func focusHiddenWindowBringsItBack() {
        var w = base(); w.setHidden(b, true)
        let (after, e) = run(w, .focusWindowRef(b))
        #expect(!after.hidden.contains(b) && after.focus.window == b)
        #expect(e == [.unhide(b), .focus(b), .relayout])
        #expect(after.invariantViolations().isEmpty)
    }
    @Test func focusEphemeralWorksWithoutAWorkspace() {
        var w = base(); let v = WindowRef(id: 9, pid: 9); w.adopt(v, kind: .ephemeral, on: "D1")
        let (after, e) = run(w, .focusWindowRef(v))
        #expect(after.focus.window == v && e == [.focus(v)])
    }

    @Test func setWorkspaceLayoutHitsOnlyItsTarget() {
        let w0 = base()
        let target = w0.screens["D2"]!.workspaces[0].id
        let (w, e) = run(w0, .setWorkspaceLayout(target, .grid))
        #expect(w.screens["D2"]!.active.layout == .grid)
        #expect(w.screens["D1"]!.active.layout == .maximize)       // untouched
        #expect(w.focus.screen == "D1")                            // a layout click does not move focus
        #expect(e == [.relayout])
    }

    @Test func closeWindowRefOnlyEmitsTheEffect() {
        let before = base()
        let (w, e) = run(before, .closeWindowRef(c))
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
}

@Suite struct ZenTests {
    let a = WindowRef(id: 1, pid: 1)
    let display = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
                              visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 575), isMain: true)

    /// The whole Zen round trip at the reconciler boundary: panels on = inset rect, Zen = M1 rect.
    @Test func zenGivesTheEdgesBack() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        // Pinned so the arithmetic below stays readable and does not move with the default.
        var cfg = Config(); cfg.panelWidth = 48; cfg.panelHeight = 34
        func rect(_ world: World) -> Placement? {
            let insets = ["D1": ShellInsets(config: cfg, hidden: world.zen)]
            return Reconciler.desired(world: world, displays: [display], config: LayoutConfig(gap: 8),
                                      observed: [:], prePark: [:], parkedNow: [], zeroSliver: [],
                                      insets: insets)[a]
        }
        // panel-width 48, panel-height 34, gap 8, height−1:
        #expect(rect(w) == .frame(CGRect(x: 56, y: 67, width: 936, height: 524)))
        w = CommandRunner.apply(.toggleShellUI, to: w).0
        #expect(w.zen)
        #expect(rect(w) == .frame(CGRect(x: 8, y: 33, width: 984, height: 558)))
    }

    @Test func zenSurvivesThePersistenceRoundTrip() throws {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.zen = true
        let data = try JSONEncoder().encode(PersistedState(world: w))
        let loaded = try JSONDecoder().decode(PersistedState.self, from: data)
        #expect(loaded.zen)
        #expect(loaded.restore(into: World.empty(screens: ["D1"], defaultLayout: .maximize)).zen)
    }

    @Test func m1StateFilesWithoutZenStillLoad() throws {
        let json = #"{"version":1,"screens":{}}"#
        let loaded = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        #expect(!loaded.zen)
    }
}
