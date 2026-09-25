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

    /// #55: "on another Space" is its own badge — distinct from hidden (dimmed) and fullscreen.
    @Test func tabsMarkOffSpaceWindows() {
        var w = base()
        w.setOnActiveSpace(a, false)
        let s = ShellUI.state(for: "D1", in: w)!
        #expect(s.tabs[0].isOffSpace && !s.tabs[0].isHidden && !s.tabs[0].isFullscreen)
        #expect(!s.tabs[1].isOffSpace)
    }

    @Test func unknownDisplayIsNil() {
        #expect(ShellUI.state(for: "nope", in: base()) == nil)
    }

    /// #29: the dimmed cheat sheet is on the focused display only, only while its workspace is
    /// empty, off on a fullscreen Space and with the key off, and unaffected by Zen.
    @Test func emptyCheatSheetRule() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        #expect(w.focus.screen == "D1")
        #expect(ShellUI.showsEmptyCheatSheet("D1", in: w, config: Config()))
        #expect(!ShellUI.showsEmptyCheatSheet("D2", in: w, config: Config()))   // empty, but not focused
        #expect(!ShellUI.showsEmptyCheatSheet("nope", in: w, config: Config()))

        var off = Config(); off.emptyCheatsheet = false
        #expect(!ShellUI.showsEmptyCheatSheet("D1", in: w, config: off))

        w.zen = true
        #expect(ShellUI.showsEmptyCheatSheet("D1", in: w, config: Config()))    // Zen does not hide it

        w.adopt(a, kind: .tile, on: "D1")                                     // a window arrives
        #expect(!ShellUI.showsEmptyCheatSheet("D1", in: w, config: Config()))

        w.focus.screen = "D2"; w.focus.window = nil                           // focus moves away
        #expect(ShellUI.showsEmptyCheatSheet("D2", in: w, config: Config()))
        #expect(!ShellUI.showsEmptyCheatSheet("D1", in: w, config: Config()))

        w.adopt(b, kind: .tile, on: "D2"); w.setFullscreen(b, true)            // a fullscreen Space
        w.screens["D2"]!.activeIndex = 1                                      // its trailing empty row
        #expect(w.screens["D2"]!.active.isEmpty)
        #expect(!ShellUI.showsEmptyCheatSheet("D2", in: w, config: Config()))
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

/// #73: the rail tray — which windows it lists, in what order, and that bringing one back from it
/// never re-files anything.
@Suite struct RailTrayTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 2)
    let d = WindowRef(id: 4, pid: 2), p = WindowRef(id: 5, pid: 3), q = WindowRef(id: 6, pid: 4)
    let x = WindowRef(id: 7, pid: 5)

    /// D1 ws0 [a, b(float)] · D1 ws1 [c] · D2 [d]; popups p (owned by d) and q (no owner); x ignored.
    func world() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .float, on: "D1")
        w.adopt(d, kind: .tile, on: "D2")
        w.adopt(q, kind: .ephemeral, on: "D1"); w.adopt(p, kind: .ephemeral, on: "D1")
        w.parents[p] = d
        w.adopt(x, kind: .ignore, on: "D1")
        w.adopt(c, kind: .tile, on: "D1", workspace: w.screens["D1"]!.workspaces[1].id)
        return w
    }

    @Test func listsHiddenThenPopupsEachInRailOrder() {
        var w = world()
        w.setHidden(d, true); w.setHidden(c, true); w.setHidden(b, true)
        // Hidden in rail order (D1 ws0, D1 ws1, D2), then popups: p by its owner d, q last.
        #expect(ShellUI.tray(in: w) == [b, c, d, p, q])
        // The same list on every display.
        #expect(ShellUI.state(for: "D1", in: w)!.tray == [b, c, d, p, q])
        #expect(ShellUI.state(for: "D2", in: w)!.tray == [b, c, d, p, q])
    }

    @Test func emptyWhenNothingIsOutOfReach() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(x, kind: .ignore, on: "D1")
        #expect(ShellUI.tray(in: w).isEmpty)                    // visible and ignored are both out
    }

    /// Recovering changes focus (and, for a hidden window, which workspace is showing) and nothing
    /// else: every window keeps its workspace, row position and floating state, a popup stays a popup.
    @Test func recoveryNeverRefiles() {
        var w = world()
        w.setHidden(b, true); w.setHidden(c, true)
        let everyone = [a, b, c, d, p, q, x]
        func rows(_ w: World) -> [[WindowRef]] { w.screenOrder.flatMap { w.screens[$0]!.workspaces.map(\.windows) } }
        func pins(_ w: World) -> [Set<WindowRef>] { w.screenOrder.flatMap { w.screens[$0]!.workspaces.map(\.floating) } }
        for r in [b, c, d, p, q] {
            let (out, effects) = CommandRunner.apply(.recoverWindow(r), to: w)
            #expect(out.invariantViolations().isEmpty)
            for s in everyone {
                #expect(out.location(of: s)?.screen == w.location(of: s)?.screen
                        && out.location(of: s)?.index == w.location(of: s)?.index, "\(s) moved recovering \(r)")
            }
            #expect(out.ephemeral == w.ephemeral && out.ignored == w.ignored)
            #expect(rows(out) == rows(w) && pins(out) == pins(w))
            #expect(out.focus.window == r && effects.contains(.focus(r)))
            w = out
        }
    }

    /// A hidden window comes back exactly as its tab click would bring it; a popup, which the
    /// model never marks hidden, is still asked to unhide — nothing else would un-minimize it.
    @Test func recoveryUnhides() {
        var w = world()
        w.setHidden(c, true)
        let (out, effects) = CommandRunner.apply(.recoverWindow(c), to: w)
        #expect(out == CommandRunner.apply(.focusWindowRef(c), to: w).0)
        #expect(!out.hidden.contains(c) && effects.contains(.unhide(c)))
        #expect(CommandRunner.apply(.recoverWindow(p), to: w).1 == [.unhide(p), .focus(p)])
        #expect(CommandRunner.apply(.recoverWindow(x), to: w).1.isEmpty)   // not the tray's to offer
    }
}
