import Testing
import Foundation
import CoreGraphics
@testable import SpacialShellKit

/// Issue #74 — an app's first window goes to its category's row, rows created in
/// `category-order`; other apps get a row each; memory still wins; a drag is never undone.
@Suite struct CategoryRoutingTests {
    let order = Config.defaultCategoryOrder          // web, terminal, coding, media, utilities
    var n = 0

    /// Lands a fresh window of an app of `category` on `d` and files it, the way the store does.
    @discardableResult
    mutating func open(_ w: inout World, _ category: AppCategory?, on d: DisplayID = "D1", max: Int = 12,
                       order: [AppCategory]? = nil, remembered: UUID? = nil) -> UUID? {
        n += 1
        let id = w.landing(remembered: remembered, crowdOn: nil, routeOn: d, category: category,
                           order: order ?? self.order, maxWorkspaces: max)
        w.adopt(WindowRef(id: WindowID(n), pid: Int32(n)), kind: .tile, on: d, workspace: id)
        return id
    }
    func categories(_ w: World, _ d: DisplayID = "D1") -> [AppCategory?] {
        w.screens[d]!.workspaces.dropLast().map(\.category)
    }

    // MARK: rung 2 — category rows

    @Test mutating func aCategorysAppsShareOneMarkedRow() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let safari = open(&w, .web)
        let chrome = open(&w, .web)
        #expect(safari != nil && safari == chrome)
        #expect(categories(w) == [.web])
        #expect(w.invariantViolations().isEmpty)
    }
    @Test mutating func newRowsGoWhereTheOrderSays() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        open(&w, .coding)
        open(&w, .web)                  // no earlier row → before the first later one
        open(&w, .utilities)            // after the last earlier one
        open(&w, .terminal)             // between web and coding
        #expect(categories(w) == [.web, .terminal, .coding, .utilities])
    }
    @Test mutating func orderedRowsGoAboveUnorderedOnesButBelowPinnedSeeds() {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code")]
        var w = World.seeded(screens: ["D1"], config: c)
        open(&w, nil)                   // an uncategorized app: a row of its own
        open(&w, .web)
        let rows = w.screens["D1"]!.workspaces.dropLast()
        #expect(rows.map(\.name) == ["Code", "Workspace", "Workspace"])
        #expect(rows.map(\.category) == [nil, .web, nil], "pinned seed stays first; web above the other app")
    }
    @Test mutating func theActiveWorkspaceStaysActive() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let active = w.screens["D1"]!.active.id
        open(&w, .web)
        #expect(w.screens["D1"]!.active.id == active)
    }
    @Test mutating func everyDisplayGetsItsOwnRows() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        let one = open(&w, .web, on: "D1")
        let two = open(&w, .web, on: "D2")
        #expect(one != two)
        #expect(w.location(ofWorkspace: two!)?.screen == "D2")
        #expect(categories(w, "D2") == [.web])
    }

    // MARK: "other" apps

    @Test mutating func otherAppsGetARowEachAtTheBottom() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let slack = open(&w, .communication)            // a category not in the order
        let mystery = open(&w, nil)
        open(&w, .web)
        #expect(slack != mystery)
        #expect(categories(w) == [.web, .communication, nil])
        #expect(open(&w, .communication) != slack, "unordered categories do not share a row")
    }
    @Test mutating func pastMaxWorkspacesNewAppsJoinTheLastRow() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        open(&w, nil, max: 2); let second = open(&w, nil, max: 2)
        #expect(open(&w, nil, max: 2) == second)
        #expect(open(&w, .web, max: 2) == second, "a category row is not created past the cap either")
        #expect(w.screens["D1"]!.workspaces.count == 3)             // two rows + the trailing empty
        #expect(w.invariantViolations().isEmpty)
    }

    // MARK: precedence

    @Test mutating func rememberedPlacementBeatsCategory() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let mine = open(&w, nil)!
        #expect(open(&w, .web, remembered: mine) == mine)
        #expect(!categories(w).contains(.web))
    }
    @Test func categoryBeatsCrowdAndCrowdBeatsOther() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let web = w.landing(remembered: nil, crowdOn: "D1", routeOn: "D1", category: .web, order: order)!
        #expect(w.workspaces(of: web).category == .web && !w.workspaces(of: web).reserved)
        let crowd = w.landing(remembered: nil, crowdOn: "D1", routeOn: "D1", category: nil, order: order)!
        #expect(w.workspaces(of: crowd).reserved, "the crowd rung made it, not the other rung")
    }
    @Test func anEmptyOrderTurnsRoutingOff() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let before = w
        #expect(w.landing(remembered: nil, crowdOn: nil, routeOn: "D1", category: .web, order: []) == nil)
        #expect(w.landing(remembered: nil, crowdOn: nil, routeOn: "D1", category: nil, order: []) == nil)
        #expect(w == before)
    }
    @Test func noDisplayMeansNoRouting() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        #expect(w.landing(remembered: nil, crowdOn: nil, routeOn: nil, category: .web, order: order) == nil)
    }

    // MARK: manual order wins

    @Test mutating func aHandSortedStackIsNeverResorted() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        open(&w, .web); let terminal = open(&w, .terminal)!
        (w, _) = CommandRunner.apply(.moveWorkspace(terminal, toIndex: 0), to: w)
        #expect(categories(w) == [.terminal, .web])
        #expect(open(&w, .terminal) == terminal, "the moved row is still found by its marker")
        open(&w, .coding)                                   // after the last earlier row (web)
        open(&w, .web)
        #expect(categories(w) == [.terminal, .web, .coding])
    }

    // MARK: persistence

    @Test mutating func theMarkerSurvivesARelaunch() throws {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let web = open(&w, .web)!
        let s = PersistedState(world: w, placements: ["com.apple.Safari": web])
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(s))
        let fresh = back.restore(into: World.empty(screens: ["D1"], defaultLayout: .maximize))
        #expect(fresh.workspaces(of: web).category == .web)
    }
    @Test func stateFromBeforeTheMarkerLoadsAsNil() throws {
        let json = """
        { "screens" : { "D1" : { "activeIndex" : 0, "workspaces" : [
            { "id" : "11111111-2222-3333-4444-555555555555", "layout" : "half", "name" : "Code", "pinned" : true, "symbol" : "terminal" } ] } },
          "version" : 1 }
        """
        let s = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        #expect(s.screens["D1"]!.workspaces[0].category == nil)
        let ws = #"{"id":"11111111-2222-3333-4444-555555555555","name":"W","symbol":"s","layout":"maximize","windows":[],"floating":[],"pinned":false,"reserved":false}"#
        #expect(try JSONDecoder().decode(Workspace.self, from: Data(ws.utf8)).category == nil)
    }

    // MARK: config

    @Test func configKeysDecodeRenderAndDefault() throws {
        #expect(Config().categoryOrder == [.web, .terminal, .coding, .media, .utilities])
        #expect(Config().maxWorkspaces == 12)
        let c = try Config.parse(toml: "category-order = [\"media\", \"web\"]\nmax-workspaces = 5")
        #expect(c.categoryOrder == [.media, .web] && c.maxWorkspaces == 5)
        #expect(try Config.parse(toml: "category-order = []").categoryOrder.isEmpty)
        #expect(try Config.parse(toml: c.render()) == c)
        var off = Config(); off.categoryOrder = []
        #expect(try Config.parse(toml: off.render()) == off)
    }
}

extension World {
    fileprivate func workspaces(of id: UUID) -> Workspace {
        let loc = location(ofWorkspace: id)!
        return screens[loc.screen]!.workspaces[loc.index]
    }
}

// MARK: in the store

extension WorldStoreTests {
    func routing() -> Config { var c = m1Config(); c.categoryOrder = Config.defaultCategoryOrder; return c }

    /// The first window of an app is routed, and that row becomes its placement, so the rest of
    /// its windows follow. The category comes from the table, and — for an app the table does not
    /// know — from the `LSApplicationCategoryType` the platform put on `AppInfo`.
    @Test func theStoreRoutesByCategoryAndRemembersIt() async {
        let safari = WindowRef(id: 1, pid: 1), safari2 = WindowRef(id: 2, pid: 1), ide = WindowRef(id: 3, pid: 3)
        let s = Snapshot(displays: [d1],
                         apps: [AppInfo(pid: 1, bundleID: "com.apple.Safari", isHidden: false),
                                AppInfo(pid: 3, bundleID: "com.example.IDE", isHidden: false,
                                        systemCategory: "public.app-category.developer-tools")],
                         windows: [win(safari, bundle: "com.apple.Safari"), win(safari2, bundle: "com.apple.Safari"),
                                   win(ide, bundle: "com.example.IDE")],
                         focused: nil)
        let (store, _) = await make(s, config: routing())
        let w = await store.world
        let web = w.workspace(containing: safari)!
        #expect(web.category == .web && w.workspace(containing: safari2)?.id == web.id)
        #expect(w.workspace(containing: ide)?.category == .coding)
        #expect(await store.currentPlacements()["com.apple.Safari"] == web.id)
        #expect(w.invariantViolations().isEmpty)
    }
    /// A window `adopt` will not file (ephemeral here) must not leave an empty row behind.
    @Test func aWindowThatIsNotFiledCreatesNoRow() async {
        let calc = WindowRef(id: 1, pid: 1)
        let (store, _) = await make(snap([win(calc, kind: .ephemeral, bundle: "com.example.Calc")]), config: routing())
        #expect(await store.world.screens["D1"]!.workspaces.count == 1)
    }
}
