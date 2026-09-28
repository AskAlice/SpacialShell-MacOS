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

    /// #181: opening the spatial view refreshes the stale thumbnails of the chips in the rows it
    /// shows, a batch per row, the active row first and then outwards, so the pictures the user is
    /// looking at land first. Not the "also in this row" icons, and never a placeholder (#128),
    /// whose id is its own and has no window to take.
    @Test func openingTheSpatialViewRefreshesTheStaleChipsInViewActiveRowFirst() {
        func ref(_ id: WindowID, pid: Int32 = 1) -> WindowRef { WindowRef(id: id, pid: pid) }
        func chips(_ refs: [WindowRef]) -> [SpatialChip] { refs.map { SpatialChip(ref: $0, frame: .zero) } }
        let rows = [
            SpatialRow(id: UUID(), index: 0, name: "Off the top", chips: chips([ref(1)])),
            SpatialRow(id: UUID(), index: 1, name: "Above", chips: chips([ref(2), ref(3)])),
            SpatialRow(id: UUID(), index: 2, name: "Active", chips: chips([ref(4), ref(5, pid: -7)]),
                       offscreen: [ref(6)], isActive: true),
            SpatialRow(id: UUID(), index: 3, name: "Below", chips: chips([ref(7)])),
            SpatialRow(id: UUID(), index: 4, name: "Fresh", chips: chips([ref(8)])),
        ]
        let state = SpatialState(display: "D1", rows: rows, aspect: 1.6)
        let fresh: Set<WindowID> = [3, 8]
        let batches = R.onOpen(state, visible: 1..<5, isStale: { !fresh.contains($0) })
        #expect(batches == [[ref(4)], [ref(2)], [ref(7)]])
    }

    @Test func openingTheSpatialViewWithEverythingFreshTakesNothing() {
        let row = SpatialRow(id: UUID(), index: 0, name: "Web",
                             chips: [SpatialChip(ref: WindowRef(id: 1, pid: 1), frame: .zero)], isActive: true)
        let state = SpatialState(display: "D1", rows: [row], aspect: 1.6)
        #expect(R.onOpen(state, visible: 0..<1, isStale: { _ in false }).isEmpty)
        #expect(R.onOpen(state, visible: 0..<0, isStale: { _ in true }).isEmpty)
    }

    /// #189: opening the overview refreshes the stale thumbnails of the windows it lists, in its
    /// order, a few at a time so the first cells' pictures land first. Never a placeholder (#128);
    /// not a hidden, fullscreen or off-Space window, which a capture cannot resolve (its cell keeps
    /// whatever picture it had). A visitor (ephemeral) window is taken like any other.
    @Test func openingTheOverviewRefreshesItsStaleWindowsAFewAtATime() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        for id: WindowID in 1...9 { w.adopt(WindowRef(id: id, pid: 1), kind: .tile, on: "D1") }
        w.setHidden(WindowRef(id: 2, pid: 1), true)
        w.setFullscreen(WindowRef(id: 3, pid: 1), true)
        w.setOnActiveSpace(WindowRef(id: 4, pid: 1), false)
        w.ephemeral.insert(WindowRef(id: 20, pid: 2))
        let listed = (1...9).map { WindowRef(id: $0, pid: 1) } + [WindowRef(id: 30, pid: -7), WindowRef(id: 20, pid: 2)]
        let fresh: Set<WindowID> = [6]
        let batches = R.onOverview(listed, in: w, isStale: { !fresh.contains($0) })
        #expect(R.overviewBatch == 4)
        #expect(batches.map { $0.map(\.id) } == [[1, 5, 7, 8], [9, 20]])
        #expect(R.onOverview(listed, in: w, isStale: { _ in false }).isEmpty)
    }
}
