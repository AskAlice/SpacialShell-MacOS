import Testing
import Foundation
@testable import SpacialShellKit

/// #97: stale-while-revalidate and the capture budget.
@Suite struct SwitchPictureCacheTests {
    typealias Cache = SwitchPictureCache<String>
    let t0 = ContinuousClock.now

    func key(_ id: WindowID, x: CGFloat = 0, display: DisplayID = "D1") -> SwitchPictureKey {
        let r = CGRect(x: x, y: 0, width: 100, height: 100)
        return SwitchPictureKey(Transition(display: display, viewport: r,
                                           moves: [.init(ref: WindowRef(id: id, pid: 1), from: r, to: r)]))
    }

    @Test func aSetOfAnyAgeFliesButIsRefreshed() {
        var c = Cache()
        c.add(key(1), "old", taken: t0)
        #expect(!c.needsRefresh(key(1), now: t0 + .seconds(1)))
        // #207: the prefetch follows every reconcile pass; a set seconds old is not taken again.
        #expect(!c.needsRefresh(key(1), now: t0 + .seconds(10)))
        #expect(c.needsRefresh(key(1), now: t0 + Cache.freshFor), "the prefetch takes it again")
        #expect(c.take(key(1)) == "old", "however old, it still flies")
        #expect(c.needsRefresh(key(2), now: t0), "never seen")
    }

    @Test func aDifferentArrangementIsADifferentKey() {
        var c = Cache()
        c.add(key(1), "a", taken: t0)
        #expect(c.take(key(1, x: 50)) == nil)
        #expect(c.take(key(1, display: "D2")) == nil)
    }

    @Test func theNewestSetWinsAndALateOneDoesNotReplaceIt() {
        var c = Cache()
        c.add(key(1), "flown", taken: t0)
        c.prefetch(key(1), "refreshed", taken: t0 + .seconds(5))
        #expect(c.take(key(1)) == "refreshed", "a stale flown set must not shadow a fresh prefetch")
        c.add(key(1), "late", taken: t0 + .seconds(1))
        #expect(c.take(key(1)) == "refreshed")
    }

    @Test func flownSetsAreCappedMostRecentlyUsedFirst() {
        var c = Cache()
        for i in 1...WindowID(Cache.kept) { c.add(key(i), "\(i)", taken: t0) }
        _ = c.take(key(1))                                  // 2 is now the least recently used
        c.add(key(99), "new", taken: t0)
        #expect(c.take(key(2)) == nil)
        #expect(c.take(key(1)) == "1")
        #expect(c.take(key(99)) == "new")
    }

    @Test func prefetchesNoPredictionWantsGo() {
        var c = Cache()
        c.prefetch(key(1), "a", taken: t0)
        c.prefetch(key(2), "b", taken: t0)
        c.keepPrefetches([key(2)])
        #expect(c.take(key(1)) == nil)
        #expect(c.take(key(2)) == "b")
    }

    @Test func deadWindowsAreDropped() {
        var c = Cache()
        c.add(key(1), "a", taken: t0)
        c.prefetch(key(2), "b", taken: t0)
        c.removeAll { $0.ids.contains(1) || $0.ids.contains(2) }
        #expect(c.take(key(1)) == nil && c.take(key(2)) == nil)
    }

    @Test func aTaskWithinBudgetGivesItsValue() async {
        let fast = Task { 7 }
        #expect(await fast.value(within: .seconds(5)) == 7)
    }

    @Test func anOverrunReturnsNilAtTheBudgetAndTheTaskRunsOn() async {
        let (gate, open) = AsyncStream<Void>.makeStream()
        let slow = Task { () -> Int in
            for await _ in gate { break }
            return 7
        }
        let started = ContinuousClock.now
        #expect(await slow.value(within: .milliseconds(50)) == nil)
        // A hang detector, not a latency check: waiting for `slow` would never end, since the gate
        // only opens below. 5 s flaked on a loaded CI runner where the whole suite stalled ~5 s.
        #expect(ContinuousClock.now - started < .seconds(30), "it stopped waiting at the budget")
        open.yield(); open.finish()
        #expect(await slow.value == 7, "the late value still arrives, for the cache")
    }
}
