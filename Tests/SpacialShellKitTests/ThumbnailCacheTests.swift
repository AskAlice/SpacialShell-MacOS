import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ThumbnailCacheTests {
    let t0 = ContinuousClock.now

    @Test func leastRecentlyUsedGoesFirst() {
        var c = ThumbnailCache<String>(capacity: 2)
        c.insert("a", for: 1, taken: t0)
        c.insert("b", for: 2, taken: t0)
        _ = c.image(for: 1)                 // 2 is now the least recently used
        c.insert("c", for: 3, taken: t0)
        #expect(c.count == 2)
        #expect(c.image(for: 1) == "a")
        #expect(c.image(for: 2) == nil)
        #expect(c.image(for: 3) == "c")
    }

    @Test func capIsANamedConstant() {
        var c = ThumbnailCache<Int>()
        for i in 0..<(ThumbnailCache<Int>.capacity + 10) { c.insert(i, for: WindowID(i), taken: t0) }
        #expect(c.count == ThumbnailCache<Int>.capacity)
    }

    @Test func staleIsServedButFlagged() {
        var c = ThumbnailCache<String>()
        #expect(c.isStale(7, now: t0))      // never seen
        c.insert("x", for: 7, taken: t0)
        #expect(!c.isStale(7, now: t0 + .seconds(1)))
        #expect(c.isStale(7, now: t0 + ThumbnailCache<String>.freshFor))
        #expect(c.image(for: 7) == "x")     // still drawn while it refreshes
    }

    @Test func aLateOlderCaptureDoesNotReplaceANewerOne() {
        var c = ThumbnailCache<String>()
        c.insert("new", for: 1, taken: t0 + .seconds(2))
        c.insert("old", for: 1, taken: t0)
        #expect(c.image(for: 1) == "new")
    }

    @Test func closedWindowsAreEvicted() {
        var c = ThumbnailCache<String>()
        c.insert("a", for: 1, taken: t0); c.insert("b", for: 2, taken: t0)
        c.retain([2])
        #expect(c.image(for: 1) == nil)
        #expect(c.image(for: 2) == "b")
    }

    @Test func worldListsEveryKnownWindow() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(WindowRef(id: 1, pid: 1), kind: .tile, on: "D1")
        w.adopt(WindowRef(id: 2, pid: 1), kind: .float, on: "D1")
        w.ephemeral.insert(WindowRef(id: 3, pid: 2))
        #expect(w.allWindowIDs == [1, 2, 3])
    }
}
