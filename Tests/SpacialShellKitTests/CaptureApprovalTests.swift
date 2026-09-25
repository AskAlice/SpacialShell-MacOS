import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct CaptureApprovalTests {
    let t0 = ContinuousClock.now

    @Test func unknownRunsOneAtATimeAndPrefetchWaitsForProof() {
        var a = CaptureApproval()
        #expect(!a.admitsPrefetch)
        #expect(a.begin(now: t0) == .run)
        #expect(a.begin(now: t0) == .wait)
        a.end(.listed, now: t0)              // a listing is not proof: still one at a time
        #expect(a.state == .unknown)
        #expect(a.begin(now: t0) == .run)
        #expect(a.begin(now: t0) == .wait)
        a.end(.failed, now: t0)              // neither is an unrelated failure
        #expect(a.state == .unknown)
        #expect(!a.admitsPrefetch)
    }

    @Test func aCaptureOpensTheGateToConcurrency() {
        var a = CaptureApproval()
        #expect(a.begin(now: t0) == .run)
        a.end(.captured, now: t0)
        #expect(a.state == .approved)
        #expect(a.admitsPrefetch)
        #expect(a.begin(now: t0) == .run)
        #expect(a.begin(now: t0) == .run)
        #expect(a.begin(now: t0) == .run)
    }

    @Test func aDeclineSkipsEverythingForTheBackoffThenAsksAgain() {
        var a = CaptureApproval()
        #expect(a.begin(now: t0) == .run)
        #expect(a.begin(now: t0) == .wait)
        a.end(.declined, now: t0)
        #expect(a.begin(now: t0) == .skip)   // the waiter, woken, gets "unavailable"
        #expect(a.begin(now: t0 + CaptureApproval.backoff - .seconds(1)) == .skip)
        #expect(!a.admitsPrefetch)
        #expect(a.begin(now: t0 + CaptureApproval.backoff) == .run)
        #expect(a.state == .unknown)
        #expect(a.begin(now: t0 + CaptureApproval.backoff) == .wait)
    }

    @Test func aRevokedGrantClosesAnOpenGate() {
        var a = CaptureApproval()
        _ = a.begin(now: t0); a.end(.captured, now: t0)
        _ = a.begin(now: t0); _ = a.begin(now: t0)
        a.end(.declined, now: t0)
        a.end(.captured, now: t0)            // a straggler landing late does not reopen it
        #expect(a.state == .declined(until: t0 + CaptureApproval.backoff))
        #expect(a.begin(now: t0) == .skip)
    }
}
