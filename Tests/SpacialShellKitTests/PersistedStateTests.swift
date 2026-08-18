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
}
