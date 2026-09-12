import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct PersistedStateTests {
    @Test func roundTripsThroughJSON() throws {
        var w = World.seeded(screens: ["D1"], config: { var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code", symbol: "terminal", layout: .half)]; return c }())
        w.screens["D1"]!.activeIndex = 0
        let s = PersistedState(world: w)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("spacial-\(UUID()).json")
        try s.save(to: url)
        let back = try PersistedState.load(from: url)
        #expect(back == s)
        #expect(back?.screens["D1"]?.workspaces.first?.name == "Code")
    }
    @Test func loadMissingFileIsNil() throws {
        #expect(try PersistedState.load(from: URL(fileURLWithPath: "/nonexistent/x.json")) == nil)
    }
    @Test func restoreRebuildsPinnedWorkspacesAndActiveIndex() throws {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code", layout: .half), WorkspaceSeed(name: "Web", layout: .split)]
        var w = World.seeded(screens: ["D1"], config: c)
        w.activate(index: 1, on: "D1")
        let s = PersistedState(world: w)
        let fresh = s.restore(into: World.empty(screens: ["D1", "D2"], defaultLayout: .maximize))
        #expect(fresh.screens["D1"]!.workspaces.map(\.name) == ["Code", "Web", "Workspace"])
        #expect(fresh.screens["D1"]!.workspaces[1].layout == .split)
        #expect(fresh.screens["D1"]!.activeIndex == 1)
        #expect(fresh.screens["D2"]!.workspaces.count == 1)     // unknown screen untouched
        #expect(fresh.invariantViolations().isEmpty)
    }
    @Test func seededWorldPinsConfigWorkspaces() {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code")]
        let w = World.seeded(screens: ["D1"], config: c)
        #expect(w.screens["D1"]!.workspaces.map(\.pinned) == [true, false])
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func restoreIntoSeededWorldDoesNotDuplicatePinnedByName() throws {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code", layout: .half), WorkspaceSeed(name: "Web", layout: .split)]
        let w1 = World.seeded(screens: ["D1"], config: c)
        let s = PersistedState(world: w1)
        let w2 = World.seeded(screens: ["D1"], config: c)
        let r = s.restore(into: w2)
        #expect(r.screens["D1"]!.workspaces.map(\.name) == ["Code", "Web", "Workspace"])
        #expect(r.screens["D1"]!.workspaces[0].id == w1.screens["D1"]!.workspaces[0].id)
        #expect(r.invariantViolations().isEmpty)
    }

    // MARK: placement memory (issue #5 — windows return to their own workspaces after a restart)

    /// The whole round trip: two apps across two workspaces, quit, relaunch into a fresh world,
    /// and both are adopted back where they were — with new pids and new window ids, since a
    /// `WindowRef` dies with the process and only the bundle id outlives it.
    @Test func appsAreAdoptedBackIntoTheWorkspaceTheyWereIn() throws {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code"), WorkspaceSeed(name: "Web")]
        var w = World.seeded(screens: ["D1"], config: c)
        let code = WindowRef(id: 1, pid: 10), web = WindowRef(id: 2, pid: 20)
        w.adopt(code, kind: .tile, on: "D1")
        w.activate(index: 1, on: "D1")
        w.adopt(web, kind: .tile, on: "D1")
        let placements = PersistedState.placements(world: w, bundleIDs: [code: "com.editor", web: "com.browser"])

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("spacial-\(UUID()).json")
        try PersistedState(world: w, placements: placements).save(to: url)
        let state = try #require(try PersistedState.load(from: url))

        var fresh = state.restore(into: World.seeded(screens: ["D1"], config: c))
        let code2 = WindowRef(id: 91, pid: 99), web2 = WindowRef(id: 92, pid: 98)
        fresh.adopt(code2, kind: .tile, on: "D1", workspace: state.placements["com.editor"])
        fresh.adopt(web2, kind: .tile, on: "D1", workspace: state.placements["com.browser"])
        #expect(fresh.screens["D1"]!.workspaces[0].windows == [code2])
        #expect(fresh.screens["D1"]!.workspaces[1].windows == [web2])
        #expect(fresh.invariantViolations().isEmpty)
    }
    @Test func placementsAreOneEntryPerAppAtItsLastWorkspace() {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code"), WorkspaceSeed(name: "Web")]
        var w = World.seeded(screens: ["D1"], config: c)
        let one = WindowRef(id: 1, pid: 10), two = WindowRef(id: 2, pid: 10)
        w.adopt(one, kind: .tile, on: "D1")
        w.activate(index: 1, on: "D1")
        w.adopt(two, kind: .tile, on: "D1")
        let p = PersistedState.placements(world: w, bundleIDs: [one: "com.editor", two: "com.editor"])
        #expect(p == ["com.editor": w.screens["D1"]!.workspaces[1].id])   // one key per app, not per window
    }
    /// An unpinned workspace is dropped today because nothing is coming back to it. One an app
    /// *is* coming back to has to survive the reaper, empty, until that app's window is adopted.
    @Test func restoreHoldsOpenAnUnpinnedWorkspaceAnAppMustComeBackTo() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let win = WindowRef(id: 1, pid: 10)
        w.adopt(win, kind: .tile, on: "D1")
        let id = w.screens["D1"]!.workspaces[0].id
        let s = PersistedState(world: w, placements: PersistedState.placements(world: w, bundleIDs: [win: "com.x"]))
        #expect(s.placements["com.x"] == id)

        var fresh = s.restore(into: World.empty(screens: ["D1"], defaultLayout: .maximize))
        #expect(fresh.screens["D1"]!.workspaces.first?.id == id)
        #expect(fresh.screens["D1"]!.workspaces.first?.reserved == true)
        #expect(fresh.invariantViolations().isEmpty)

        fresh.adopt(WindowRef(id: 91, pid: 99), kind: .tile, on: "D1", workspace: id)
        #expect(fresh.screens["D1"]!.workspaces.first?.windows == [WindowRef(id: 91, pid: 99)])
        #expect(fresh.screens["D1"]!.workspaces.first?.reserved == false)   // its windows are back
        #expect(fresh.invariantViolations().isEmpty)
    }
    @Test func restoreDropsAnUnpinnedWorkspaceNoAppIsComingBackTo() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(WindowRef(id: 1, pid: 10), kind: .tile, on: "D1")
        let s = PersistedState(world: w)                 // no placement memory (window had no bundle id)
        let fresh = s.restore(into: World.empty(screens: ["D1"], defaultLayout: .maximize))
        #expect(fresh.screens["D1"]!.workspaces.count == 1)
        #expect(fresh.invariantViolations().isEmpty)
    }
    /// A workspace whose screen is gone at relaunch is not restored, so the placement naming it
    /// resolves to nothing — its app lands by the ordinary rules, on the screen it is on now.
    @Test func aPlacementOnAVanishedScreenFallsBack() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        let win = WindowRef(id: 1, pid: 10)
        w.adopt(win, kind: .tile, on: "D2")
        let s = PersistedState(world: w, placements: PersistedState.placements(world: w, bundleIDs: [win: "com.x"]))

        var fresh = s.restore(into: World.empty(screens: ["D1"], defaultLayout: .maximize))   // D2 unplugged
        let back = WindowRef(id: 91, pid: 99)
        fresh.adopt(back, kind: .tile, on: "D1", workspace: s.placements["com.x"])
        #expect(fresh.screens.count == 1)
        #expect(fresh.screens["D1"]!.workspaces[0].windows == [back])
        #expect(fresh.invariantViolations().isEmpty)
    }
    @Test func stateFilesWithoutPlacementsStillLoad() throws {
        let json = #"{"version":1,"screens":{}}"#
        let loaded = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        #expect(loaded.placements.isEmpty)
        #expect(loaded.version == 1)
    }
}
