import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

/// #109: the user-visible error channel's model.
@Suite struct ProblemsTests {
    @Test func reportingTheSameProblemTwiceIsNotAChange() {
        var p = Problems()
        let first = p.report(.telemetryFailing(host: "otel.example"))
        let again = p.report(.telemetryFailing(host: "otel.example"))   // the rate limit: repeats are silent
        #expect(first && !again)
        #expect(p.all.count == 1)
    }

    @Test func aNewMessageUnderTheSameKeyReplacesTheOld() {
        var p = Problems()
        p.report(.configInvalid("line 3"))
        let changed = p.report(.configInvalid("line 9"))
        #expect(changed)
        #expect(p.all.map(\.message).joined().contains("line 9"))
        #expect(p.all.count == 1)
    }

    @Test func clearingIsTheFix() {
        var p = Problems()
        p.report(.configInvalid("line 3"))
        let cleared = p.clear(Problem.Key.config)
        let again = p.clear(Problem.Key.config)
        #expect(cleared && !again)
        #expect(p.isEmpty)
    }

    @Test func errorsComeFirstThenByKey() {
        var p = Problems()
        p.report(.screenRecordingMissing)
        p.report(.telemetryFailing(host: "h"))
        p.report(.configInvalid("x"))
        p.report(.hotkeysInactive("y"))
        #expect(p.all.map(\.key) == [Problem.Key.config, Problem.Key.hotkeys,
                                     Problem.Key.screenRecording, Problem.Key.telemetry])
        #expect(Problem.Severity.warning < .error)
    }

    @Test func replaceOwnsOnlyItsPrefix() {
        var p = Problems()
        p.report(.configInvalid("x"))
        let added = p.replace(prefix: Problem.Key.axWritePrefix, with: [.axWriteFailing(app: "a"), .axWriteFailing(app: "b")])
        let reordered = p.replace(prefix: Problem.Key.axWritePrefix, with: [.axWriteFailing(app: "b"), .axWriteFailing(app: "a")])
        let fixed = p.replace(prefix: Problem.Key.axWritePrefix, with: [.axWriteFailing(app: "b")])
        #expect(added && !reordered && fixed)
        #expect(p.all.map(\.key) == [Problem.Key.config, Problem.Key.axWritePrefix + "b"])
        p.replace(prefix: Problem.Key.axWritePrefix, with: [])
        #expect(p.all.map(\.key) == [Problem.Key.config])
    }

    @Test func theCenterPublishesOnlyChanges() {
        let center = ProblemCenter()
        let seen = Box()
        center.observe { seen.append($0.count) }
        center.report(.screenRecordingMissing)
        center.report(.screenRecordingMissing)
        center.clear(Problem.Key.config)            // nothing to clear
        center.clear(Problem.Key.screenRecording)
        #expect(seen.values == [0, 1, 0])           // the initial call, the report, the clear
    }

    @Test func wireStateCarriesProblemsAndOldPayloadsStillDecode() throws {
        let w = World.empty(screens: ["D1"], defaultLayout: .column)
        let s = WireState(world: w, problems: [.configInvalid("x")])
        #expect(s.capabilities.contains("problems"))
        let json = try JSONValue(encoding: s)
        #expect(try json.decode(WireState.self) == s)
        // A pre-#109 daemon's payload: no `problems` key.
        guard case .object(var o) = json else { Issue.record("not an object"); return }
        o["problems"] = nil
        #expect(try JSONValue.object(o).decode(WireState.self).problems == [])
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Int] = []
    var values: [Int] { lock.withLock { _values } }
    func append(_ v: Int) { lock.withLock { _values.append(v) } }
}
