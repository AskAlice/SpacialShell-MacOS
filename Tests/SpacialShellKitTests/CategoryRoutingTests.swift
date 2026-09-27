import Testing
import Foundation
import CoreGraphics
@testable import SpacialShellKit

/// Issue #74 — an app's window goes to its category's row, rows created in `category-order`;
/// other apps get a row each; category beats memory, memory decides the rest; a drag holds for
/// the session and the next launch sorts category rows back to the top.
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
    @Test mutating func orderedRowsGoAbovePinnedSeedsAndUnorderedOnes() {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code")]
        var w = World.seeded(screens: ["D1"], config: c)
        open(&w, nil)                   // an uncategorized app: a row of its own
        open(&w, .web)
        let rows = w.screens["D1"]!.workspaces.dropLast()
        #expect(rows.map(\.name) == ["Workspace", "Code", "Workspace"])
        #expect(rows.map(\.category) == [.web, nil, nil], "web on top; the pinned seed and the other app keep their order")
        #expect(w.screens["D1"]!.active.name == "Code", "the active row is still the one the user was on")
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

    /// Ruling changed 2026-09-25 (#74, last comment): app type beats memory for an ordered category.
    @Test mutating func categoryBeatsRememberedPlacement() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let mine = open(&w, nil)!
        let web = open(&w, .web, remembered: mine)
        #expect(web != mine && categories(w).contains(.web))
    }
    @Test mutating func memoryStillWinsForAppsOutsideTheOrder() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let mine = open(&w, nil)!
        #expect(open(&w, .communication, remembered: mine) == mine)
        #expect(open(&w, nil, remembered: mine) == mine)
        #expect(open(&w, .media, order: [.web], remembered: mine) == mine, "a category switched off is outside the order")
    }
    /// The user's report: Brave remembered on the secondary display, but its window is on the
    /// primary at relaunch — it takes the primary's web row, not the remembered one.
    @Test mutating func aBrowserRememberedOnD2ButOnD1LandsInD1sWebRow() throws {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        let onD2 = open(&w, .web, on: "D2")!
        let s = PersistedState(world: w, placements: ["com.brave.Browser.origin": onD2])
        var fresh = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(s))
            .restore(into: World.empty(screens: ["D1", "D2"], defaultLayout: .maximize), order: order)
        let id = open(&fresh, .web, on: "D1", remembered: s.placements["com.brave.Browser.origin"])!
        #expect(id != onD2)
        #expect(fresh.location(ofWorkspace: id)?.screen == "D1")
        #expect(categories(fresh, "D1") == [.web])
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
        (w, _) = CommandRunner.apply(.moveWorkspace(terminal, toIndex: 0), to: w, in: .test())
        #expect(categories(w) == [.terminal, .web])
        #expect(open(&w, .terminal) == terminal, "the moved row is still found by its marker")
        open(&w, .coding)                                   // after the last earlier row (web)
        open(&w, .web)
        #expect(categories(w) == [.terminal, .web, .coding])
    }

    // MARK: sorted at launch

    /// A drag holds for the session (above); the next launch puts category rows back on top in
    /// order, while rows without a category keep the order the user dragged them into.
    @Test mutating func launchSortsCategoryRowsBackAndLeavesTheRestAlone() throws {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code")]
        var w = World.seeded(screens: ["D1"], config: c)
        let web = open(&w, .web)!, other = open(&w, nil)!, terminal = open(&w, .terminal)!
        #expect(w.screens["D1"]!.workspaces.dropLast().map(\.id).first == web)
        (w, _) = CommandRunner.apply(.moveWorkspace(terminal, toIndex: 0), to: w, in: .test())
        (w, _) = CommandRunner.apply(.moveWorkspace(other, toIndex: 1), to: w, in: .test())
        w.activate(index: w.location(ofWorkspace: other)!.index, on: "D1")
        #expect(categories(w) == [.terminal, nil, .web, nil])                       // terminal, other, web, Code
        let s = PersistedState(world: w, placements: ["a": web, "b": other, "c": terminal])
        let fresh = s.restore(into: World.seeded(screens: ["D1"], config: c), order: order)
        let rows = fresh.screens["D1"]!.workspaces.dropLast()
        #expect(rows.map(\.id).prefix(2) == [web, terminal])
        #expect(rows.map(\.name).suffix(2) == ["Workspace", "Code"], "other stays above Code, where it was dragged")
        #expect(fresh.screens["D1"]!.active.id == other, "the active row is kept through the sort")
        #expect(fresh.invariantViolations().isEmpty)
    }
    @Test func sortingWithoutAnOrderOrWithNothingToSortChangesNothing() {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "A"), WorkspaceSeed(name: "B")]
        var w = World.seeded(screens: ["D1"], config: c)
        w.activate(index: 1, on: "D1")
        let before = w
        w.sortCategoryRows(order); #expect(w == before)
        w.sortCategoryRows([]); #expect(w == before)
    }
    @Test func sortIsStableAndSkipsPinnedAndUnorderedRows() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        func row(_ c: AppCategory?, pinned: Bool = false) -> Workspace {
            Workspace(name: c?.rawValue ?? "none", layout: .maximize, pinned: pinned, category: c)
        }
        w.screens["D1"]!.workspaces = [row(.communication), row(.media), row(.web, pinned: true), row(nil), row(.web)]
        w.screens["D1"]!.activeIndex = 3
        w.sortCategoryRows(order)
        let rows = w.screens["D1"]!.workspaces
        #expect(rows.map(\.category) == [.web, .media, .communication, .web, nil])
        #expect(rows[3].pinned, "a pinned category row is not sorted")
        #expect(w.screens["D1"]!.activeIndex == 4 && rows[4].category == nil)
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

    @Test func configKeysDecodeAndDefault() throws {
        #expect(Config().categoryOrder == [.web, .terminal, .coding, .media, .utilities])
        #expect(Config().maxWorkspaces == 12)
        let c = try Config.parse(toml: "category-order = [\"media\", \"web\"]\nmax-workspaces = 5")
        #expect(c.categoryOrder == [.media, .web] && c.maxWorkspaces == 5)
        #expect(try Config.parse(toml: "category-order = []").categoryOrder.isEmpty)
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
    /// #98: moving a whole app is an explicit placement. Its memory moves with it, and from then on
    /// it beats the category, so the app's next window lands where the user put the app.
    @Test func movingAnAppOverridesItsCategory() async throws {
        let safari = WindowRef(id: 1, pid: 1), ide = WindowRef(id: 3, pid: 3), later = WindowRef(id: 4, pid: 1)
        let apps = [AppInfo(pid: 1, bundleID: "com.apple.Safari", isHidden: false),
                    AppInfo(pid: 3, bundleID: "com.example.IDE", isHidden: false,
                            systemCategory: "public.app-category.developer-tools")]
        let s = Snapshot(displays: [d1], apps: apps,
                         windows: [win(safari, bundle: "com.apple.Safari"), win(ide, bundle: "com.example.IDE")], focused: nil)
        let (store, _) = await make(s, config: routing())
        await store.run(.focusWindowRef(safari))
        await store.run(.moveAppToWorkspace(.down))
        let moved = await store.world.workspace(containing: safari)!
        #expect(moved.category != .web)
        #expect(await store.currentPlacements()["com.apple.Safari"] == moved.id)
        #expect(await store.currentMovedApps() == ["com.apple.Safari"])
        await store.apply(.snapshot(Snapshot(displays: [d1], apps: apps,
                                             windows: s.windows + [win(later, bundle: "com.apple.Safari")], focused: nil)))
        #expect(await store.world.workspace(containing: later)?.id == moved.id)
        // Stored: the override survives a relaunch, and a file from before it loads as none.
        let state = PersistedState(world: await store.world, placements: await store.currentPlacements(),
                                   movedApps: await store.currentMovedApps())
        #expect(try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state)).movedApps == ["com.apple.Safari"])
        let old = try JSONDecoder().decode(PersistedState.self, from: Data(#"{"screens":{}}"#.utf8))
        #expect(old.movedApps.isEmpty)
    }
    /// A window `adopt` will not file (ephemeral here) must not leave an empty row behind.
    @Test func aWindowThatIsNotFiledCreatesNoRow() async {
        let calc = WindowRef(id: 1, pid: 1)
        let (store, _) = await make(snap([win(calc, kind: .ephemeral, bundle: "com.example.Calc")]), config: routing())
        #expect(await store.world.screens["D1"]!.workspaces.count == 1)
    }
}
