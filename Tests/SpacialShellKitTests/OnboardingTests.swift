import Testing
import Foundation
@testable import SpacialShellKit

/// #130 (M3 B7): the grant-wait window's state and the alert surface's policy.
@Suite struct OnboardingTests {
    @Test func grantWaitCountsWholeSecondsAndSuspectsAStaleRowAfterTwenty() {
        #expect(GrantWait(elapsed: .zero).status == "Waiting for access…")
        #expect(GrantWait(elapsed: .milliseconds(12_900)).status == "Waiting for access… 12 s")
        #expect(GrantWait(elapsed: .seconds(75)).status == "Waiting for access… 1 min 15 s")
        #expect(!GrantWait(elapsed: .milliseconds(19_999)).suspectsStaleGrant)
        #expect(GrantWait(elapsed: .seconds(20)).suspectsStaleGrant)
        #expect(GrantWait(elapsed: .seconds(-3)).elapsed == 0)
    }

    @Test func tapAndSocketFailuresInterruptOtherProblemsOnlyList() {
        #expect(Problem.hotkeysInactive("x").interrupts)
        #expect(Problem.controlSocketInactive("x").interrupts)
        #expect(!Problem.configInvalid("x").interrupts)
        #expect(!Problem.screenRecordingMissing.interrupts)
        #expect(!Problem.telemetryFailing(host: "h").interrupts)
        #expect(!Problem.axWriteFailing(app: "a").interrupts)
        #expect(Problem.hotkeysInactive("x").title == "Part of SpacialShell didn't start")
    }

    @Test func eachProblemAlertsOncePerLaunchErrorsFirst() {
        var alerts = ProblemAlerts()
        var p = Problems()
        p.report(.controlSocketInactive("EADDRINUSE"))
        p.report(.screenRecordingMissing)
        p.report(.hotkeysInactive("tap refused"))
        #expect(alerts.due(in: p.all).map(\.key) == [Problem.Key.hotkeys, Problem.Key.controlSocket])
        #expect(alerts.due(in: p.all).isEmpty, "already announced")
        // Cleared and back: listed again, not announced again.
        p.clear(Problem.Key.hotkeys)
        #expect(alerts.due(in: p.all).isEmpty)
        p.report(.hotkeysInactive("tap refused again"))
        #expect(alerts.due(in: p.all).isEmpty)
    }
}
