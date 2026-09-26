import Testing
import Foundation
@testable import SpacialShellKit

/// #139 (G31): the persistence toggle and the reset.
@Suite struct StatePersistenceTests {
    @Test func onByDefaultOffReadsAndWritesNothing() {
        #expect(Config().persistState)
        let on = StatePersistence(enabled: true)
        #expect(on.reads && on.writes)
        let off = StatePersistence(enabled: false)
        #expect(!off.reads && !off.writes)
    }

    @Test func aResetStopsWritesForTheSessionEvenIfSwitchedBackOn() {
        var p = StatePersistence(enabled: true)
        p.reset()
        #expect(!p.writes && p.wasReset)
        p.enabled = false
        p.enabled = true
        #expect(!p.writes, "only the next launch starts writing again")
        // Switching off and on without a reset resumes writing.
        var q = StatePersistence(enabled: true)
        q.enabled = false
        #expect(!q.writes)
        q.enabled = true
        #expect(q.writes)
    }

    @Test func resetIsListedAsAWarningThatDoesNotInterrupt() {
        #expect(Problem.stateReset.severity == .warning)
        #expect(!Problem.stateReset.interrupts)
        #expect(Problem.stateReset.key == "state.reset")
    }

    @Test func configKeyParsesRendersAndIsKnown() throws {
        let toml = "persist-state = false"
        #expect(try !Config.parse(toml: toml).persistState)
        #expect(Config.unknownKeys(toml: toml).isEmpty)
        var c = Config()
        c.persistState = false
        #expect(try !Config.parse(toml: c.render()).persistState)
        #expect(try Config.parse(toml: Config().render()).persistState)
    }

    @Test func theSettingsWindowCanOverrideIt() throws {
        var o = SettingsOverrides()
        #expect(Settings.effective(config: Config(), overrides: o).persistState)
        o.persistState = false
        #expect(!Settings.effective(config: Config(), overrides: o).persistState)
        let back = try JSONDecoder().decode(SettingsOverrides.self, from: JSONEncoder().encode(o))
        #expect(back.persistState == false)
    }

    /// The state file itself is untouched by #139: a file from before it still decodes, and one
    /// written now is what an older build reads.
    @Test func persistedStateStaysBackwardCompatible() throws {
        let w = World.empty(screens: ["D1"], defaultLayout: .column)
        let data = try JSONEncoder().encode(PersistedState(world: w))
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(Set(keys) == ["version", "screens", "zen", "placements"])
        let old = #"{"version":1,"screens":{"D1":{"workspaces":[],"activeIndex":0}}}"#
        #expect(try JSONDecoder().decode(PersistedState.self, from: Data(old.utf8)).screens["D1"]?.activeIndex == 0)
    }
}
