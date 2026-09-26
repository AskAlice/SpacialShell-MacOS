import Testing
import Foundation
@testable import SpacialShellKit

/// M3 B3's rail menus (#111, #112): set category (G1), set symbol, remove, and the app menu's
/// app-layer verbs.
@Suite struct RailMenuCommandTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 2), c = WindowRef(id: 3, pid: 3)
    let order = Config.defaultCategoryOrder          // web, terminal, coding, media, utilities

    /// D1: [a] [b] [c] [+], the row holding `b` active and focused.
    func base() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        for r in [a, b, c] {
            let id = w.landing(remembered: nil, crowdOn: nil, routeOn: "D1", category: nil, order: order)
            w.adopt(r, kind: .tile, on: "D1", workspace: id)
        }
        return CommandRunner.apply(.focusWindowRef(b), to: w).0
    }
    func run(_ w: World, _ cmd: Command) -> (World, [Effect]) {
        let r = CommandRunner.apply(cmd, to: w)
        #expect(r.0.invariantViolations().isEmpty, "after \(cmd): \(r.0.invariantViolations())")
        return r
    }
    func rows(_ w: World) -> [Workspace] { w.screens["D1"]!.workspaces }

    // MARK: set category (#112, G1)

    @Test func setCategoryMakesTheRowTheOneRoutingUses() {
        var w = base()
        let row = rows(w)[2].id
        (w, _) = run(w, .setWorkspaceCategory(row, .web))
        #expect(rows(w)[2].category == .web)
        let landed = w.landing(remembered: nil, crowdOn: nil, routeOn: "D1", category: .web, order: order)
        #expect(landed == row, "the next browser joins the row the user named, not a new one")
    }
    @Test func aCategoryIsOnOneRowPerDisplay() {
        var w = base()
        (w, _) = run(w, .setWorkspaceCategory(rows(w)[0].id, .web))
        (w, _) = run(w, .setWorkspaceCategory(rows(w)[2].id, .web))
        #expect(rows(w).map(\.category) == [nil, nil, .web, nil])
    }
    @Test func noneClearsTheCategory() {
        var w = base()
        (w, _) = run(w, .setWorkspaceCategory(rows(w)[1].id, .coding))
        (w, _) = run(w, .setWorkspaceCategory(rows(w)[1].id, nil))
        #expect(rows(w).allSatisfy { $0.category == nil })
    }
    /// #74's rule for a dragged row applies: manual order holds for the session. The row keeps its
    /// place now and the next launch sorts it.
    @Test func setCategoryDoesNotReSortUntilTheNextLaunch() throws {
        var w = base()
        let ids = rows(w).map(\.id)
        (w, _) = run(w, .setWorkspaceCategory(ids[2], .web))
        #expect(rows(w).map(\.id) == ids, "not moved live")
        #expect(w.screens["D1"]!.active.id == ids[1])
        let saved = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(
            PersistedState(world: w, placements: ["a": ids[0], "b": ids[1], "c": ids[2]])))
        let relaunched = saved.restore(into: World.empty(screens: ["D1"], defaultLayout: .maximize), order: order)
        #expect(relaunched.screens["D1"]!.workspaces.map(\.id).prefix(3) == [ids[2], ids[0], ids[1]],
                "persisted in state.json and placed by the order at launch")
        #expect(relaunched.screens["D1"]!.workspaces[0].category == .web)
    }
    @Test func theTrailingRowHasNoIdentity() {
        let w = base()
        let plus = rows(w).last!.id
        for cmd: Command in [.setWorkspaceCategory(plus, .web), .setWorkspaceSymbol(plus, "globe"), .removeWorkspace(plus)] {
            let (after, e) = run(w, cmd)
            #expect(after == w && e.isEmpty, "\(cmd) is refused on \"+\"")
        }
    }

    // MARK: set symbol

    @Test func setSymbol() {
        var w = base()
        (w, _) = run(w, .setWorkspaceSymbol(rows(w)[0].id, "terminal"))
        #expect(rows(w)[0].symbol == "terminal")
        let (same, e) = run(w, .setWorkspaceSymbol(UUID(), "globe"))
        #expect(same == w && e.isEmpty, "an unknown workspace changes nothing")
    }

    // MARK: remove (the M2 removeWorkspace ruling, W13)

    @Test func removingAnInactiveRowMergesUpAndLeavesFocusAlone() {
        var w = base()
        (w, _) = run(w, .setWorkspaceCategory(rows(w)[2].id, .media))
        let (after, e) = run(w, .removeWorkspace(rows(w)[2].id))
        #expect(rows(after).map(\.windows) == [[a], [b, c], []])
        #expect(after.focus.window == b && after.screens["D1"]!.active.windows == [b, c])
        #expect(!rows(after).contains { $0.category == .media }, "its identity goes with it")
        #expect(e == [.relayout])
    }
    @Test func removingTheFirstRowMergesDown() {
        let w = base()
        let (after, _) = run(w, .removeWorkspace(rows(w)[0].id))
        #expect(rows(after).map(\.windows) == [[b, a], [c], []])
    }
    @Test func removingTheActiveRowFollowsItsWindows() {
        var w = base()
        (w, _) = run(w, .removeWorkspace(rows(w)[1].id))
        #expect(rows(w).map(\.windows) == [[a, b], [c], []])
        #expect(w.screens["D1"]!.active.windows == [a, b])
        #expect(w.focus.window == b, "focus stays on the window it was on, in its new row")
    }
    @Test func removingAnEmptyActivePinnedRowLandsOnItsNeighbour() {
        var cfg = Config(); cfg.workspaces = [WorkspaceSeed(name: "Chat")]
        var w = World.seeded(screens: ["D1"], config: cfg)   // [Chat (pinned, active)] [+]
        w.adopt(a, kind: .tile, on: "D1", workspace: w.screens["D1"]!.workspaces[1].id)
        let chat = w.screens["D1"]!.workspaces[0].id
        let (after, e) = run(w, .removeWorkspace(chat))
        #expect(after.location(ofWorkspace: chat) == nil, "pinned rows can be removed")
        #expect(after.screens["D1"]!.active.windows == [a] && after.focus.window == a)
        #expect(e == [.focus(a), .relayout])
    }

    // MARK: the app menu (#111)

    @Test func appMenuVerbsAreAppLayerAndUnbound() {
        let w = base()
        for cmd: Command in [.reloadConfig, .showAbout, .quit] {
            #expect(cmd.isAppLayer)
            let (after, e) = run(w, cmd)
            #expect(after == w && e.isEmpty)
            #expect(KeyBindings.name(of: cmd) == nil, "menu-only: not a hotkey or `spacialctl run` verb")
        }
    }

    // MARK: view state

    @Test func railItemsCarryCategoryAndLayout() {
        var w = base()
        (w, _) = run(w, .setWorkspaceCategory(rows(w)[0].id, .terminal))
        (w, _) = run(w, .setWorkspaceLayout(rows(w)[0].id, .split))
        let item = ShellUI.state(for: "D1", in: w)!.rail[0]
        #expect(item.category == .terminal && item.layout == .split)
    }
}
