import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ThumbnailRefreshTests {
    let t0 = ContinuousClock.now
    typealias R = ThumbnailRefresh

    /// One step with the gate open and the screen awake; `taken` is each window's thumbnail time.
    func step(_ r: inout R, _ ids: [WindowID], _ taken: [WindowID: ContinuousClock.Instant] = [:],
              gate: Bool = true, awake: Bool = true, at s: Double = 0) -> R.Decision {
        r.next(windows: ids, taken: { taken[$0] }, gateOpen: gate, screenAwake: awake, now: t0 + .seconds(s))
    }

    @Test func missingThumbnailsComeFirstThenTheOldest() {
        var r = R()
        let taken: [WindowID: ContinuousClock.Instant] = [1: t0 - .seconds(40), 2: t0 - .seconds(90)]
        #expect(step(&r, [1, 2, 3], taken) == .capture(3))     // never taken: preload
        r.finished()
        #expect(step(&r, [1, 2, 3], taken) == .capture(2))     // then the oldest
        r.finished()
        #expect(step(&r, [1, 2, 3], taken) == .capture(1))
    }

    @Test func tiesGoInRailOrder() {
        var r = R()
        #expect(step(&r, [5, 4, 6]) == .capture(5))
    }

    @Test func nothingDueWaitsForTheOldestToReachTheCadence() {
        var r = R()
        let taken: [WindowID: ContinuousClock.Instant] = [1: t0 - .seconds(10), 2: t0 - .seconds(20)]
        #expect(step(&r, [1, 2], taken) == .wait(R.cadence - .seconds(20)))
        #expect(step(&r, [1, 2], taken, at: 10) == .capture(2))
    }

    @Test func oneInFlight() {
        var r = R()
        #expect(step(&r, [1, 2]) == .capture(1))
        #expect(step(&r, [1, 2]) == .idle)                   // the landing asks again
        r.finished()
        #expect(step(&r, [1, 2]) == .capture(2))
    }

    @Test func aFailedCaptureWaitsItsTurn() {
        var r = R()
        #expect(step(&r, [1]) == .capture(1))
        r.finished()                                          // no picture came back
        #expect(step(&r, [1], at: 1) == .wait(R.cadence - .seconds(1)))
        #expect(step(&r, [1], at: 30) == .capture(1))
    }

    @Test func perMinuteCap() {
        var r = R()
        let ids = (0..<UInt32(R.perMinute + 5)).map { WindowID($0) }
        for i in 0..<R.perMinute {
            #expect(step(&r, ids, at: Double(i)) == .capture(ids[i]))
            r.finished()
        }
        let at = Double(R.perMinute)
        #expect(step(&r, ids, at: at) == .wait(.seconds(60 - at)))
        #expect(step(&r, ids, at: 60) == .capture(ids[R.perMinute]))   // the first start aged out
    }

    @Test func neverWhileTheGateIsClosedOrTheScreenIsOff() {
        var r = R()
        #expect(step(&r, [1], gate: false) == .idle)
        #expect(step(&r, [1], awake: false) == .idle)
        #expect(step(&r, []) == .idle)
        #expect(step(&r, [1]) == .capture(1))                 // nothing was spent meanwhile
    }

    @Test func candidatesAreRailWindowsThatCanBeCaptured() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        for id: WindowID in 1...5 { w.adopt(WindowRef(id: id, pid: 1), kind: .tile, on: "D1") }
        w.setHidden(WindowRef(id: 2, pid: 1), true)
        w.setFullscreen(WindowRef(id: 3, pid: 1), true)
        w.setOnActiveSpace(WindowRef(id: 4, pid: 1), false)
        w.ephemeral.insert(WindowRef(id: 9, pid: 2))           // no rail icon
        #expect(R.candidates(in: w).map(\.id).sorted() == [1, 5])
    }
}
