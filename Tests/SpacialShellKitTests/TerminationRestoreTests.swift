import Testing
import Foundation
@testable import SpacialShellKit

/// #190: the way out's restore. Every parked window gets a frame inside a display's visible frame,
/// every write is made at once and awaited within one deadline, and every one that did not land is
/// reported with why — none is skipped silently.
@Suite struct TerminationRestoreTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let d2 = DisplayInfo(id: "D2", frame: CGRect(x: 1000, y: 0, width: 800, height: 600),
                         visibleFrame: CGRect(x: 1000, y: 0, width: 800, height: 600), isMain: false)

    /// Forty windows over three screens' workspaces, one of whose displays is gone, plus one parked
    /// window no workspace holds any more: each lands inside a visible frame, whatever its size.
    @Test func everyParkedWindowGetsAFrameInsideADisplaysVisibleFrame() {
        var world = World.seeded(screens: ["D1", "D2", "D3"], config: Config())
        var parked: Set<WindowRef> = []
        var observed: [WindowRef: CGRect] = [:]
        for i in 0..<40 {
            let r = WindowRef(id: WindowID(i + 1), pid: Int32(i % 4 + 1))
            let screen = ["D1", "D2", "D3"][i % 3]
            let ws = world.screens[screen]!.workspaces.count - 1
            world.screens[screen]!.workspaces[ws].windows.append(r)
            parked.insert(r)
            // Some bigger than any display, some with no observed frame at all.
            if i % 5 != 0 { observed[r] = CGRect(x: 999, y: 699, width: i % 2 == 0 ? 3000 : 400, height: 300) }
        }
        let orphan = WindowRef(id: 900, pid: 9)
        parked.insert(orphan)
        let stranded = WindowRef(id: 901, pid: 9)

        let frames = TerminationRestore.frames(world: world, displays: [d1, d2], observed: observed,
                                               stranded: [stranded: CGRect(x: 0, y: 0, width: 640, height: 480)], parked: parked)

        #expect(Set(frames.keys) == parked.union([stranded]))
        for (r, f) in frames {
            let display = world.screenContaining(r) == "D2" ? d2 : d1   // D3 is gone: the main display
            #expect(display.visibleFrame.contains(f), "\(r.id) at \(f) is outside \(display.id)")
        }
        #expect(frames[WindowRef(id: 2, pid: 2)]?.size == CGSize(width: 400, height: 300))   // its size kept
    }

    @Test func noDisplaysMeansNoFramesButNoCrash() {
        let frames = TerminationRestore.frames(world: World.seeded(screens: [], config: Config()), displays: [],
                                               observed: [:], stranded: [:], parked: [WindowRef(id: 1, pid: 1)])
        #expect(frames.isEmpty)
    }

    /// A failed write, an app the backend no longer has, and a write that never answers: each is
    /// reported with its error, and the wait ends at the deadline.
    @Test func everyWriteThatDidNotLandIsReported() {
        let ok = WindowRef(id: 1, pid: 1), failed = WindowRef(id: 2, pid: 1)
        let noApp = WindowRef(id: 3, pid: 2), hung = WindowRef(id: 4, pid: 3)
        let frame = CGRect(x: 10, y: 10, width: 100, height: 100)
        let started = ContinuousClock.now
        let failures = TerminationRestore.run([ok: frame, failed: frame, noApp: frame, hung: frame], deadline: 0.3) { ref, _, done in
            switch ref {
            case failed: done(.failure(.ax(-25200)))
            case noApp: done(.failure(.notFound))
            case hung: break                                          // never answers
            default: done(.success(()))
            }
        }
        #expect(failures == [failed: .ax(-25200), noApp: .notFound, hung: .timeout])
        #expect(ContinuousClock.now - started < .seconds(1))
    }

    /// The writes go out together, so one slow app cannot use up every other window's time: all
    /// fifty are in flight before the first answers. Counted, not timed — a wall-clock bound failed
    /// on a loaded machine (load average ~80) though the writes were concurrent.
    @Test func manyWritesRunAtOnce() {
        let frames = Dictionary(uniqueKeysWithValues: (1...50).map { (WindowRef(id: WindowID($0), pid: Int32($0)), CGRect(x: 0, y: 0, width: 10, height: 10)) })
        let written = Written(), inFlight = InFlight()
        let failures = TerminationRestore.run(frames, deadline: 30) { ref, _, done in
            inFlight.start()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { inFlight.end(); written.add(ref); done(.success(())) }
        }
        #expect(failures.isEmpty)
        #expect(written.refs == Set(frames.keys))
        #expect(inFlight.peak == frames.count, "every write was started before any answered")
    }

    @Test func nothingParkedReturnsAtOnce() {
        let started = ContinuousClock.now
        #expect(TerminationRestore.run([:], deadline: 2) { _, _, _ in Issue.record("no write expected") }.isEmpty)
        #expect(ContinuousClock.now - started < .milliseconds(100))
    }

    /// One window's write, judged by where the window ends up (#190, iPhone Mirroring and an
    /// Electron app answered -25200 on hardware): an app that refuses the resize but takes the move
    /// is back; one that refuses the whole write gets a position-only retry; one that refuses that
    /// too is reported refused, with the retry's AX error.
    @Test(arguments: [
        // (first write's error, moves on it, retry's error, moves on the retry) → error, writes made; nil = success
        (nil as BackendError?, true, nil as BackendError?, false, nil as BackendError?, 1),
        (.ax(-25200), true, nil, false, nil, 1),                        // refused the size, took the move
        (.ax(-25200), false, nil, true, nil, 2),                        // position only took
        (.ax(-25200), false, .ax(-25205), false, .ax(-25205), 2),       // refused
        (.timeout, false, nil, true, .timeout, 1),                      // hung: no retry to spend the deadline on
    ])
    func aWriteIsJudgedByWhereTheWindowEndsUp(first: BackendError?, movesFirst: Bool, retry: BackendError?,
                                              movesOnRetry: Bool, outcome: BackendError?, writes: Int) {
        let target = CGRect(x: 100, y: 80, width: 600, height: 400)
        var calls: [CGSize?] = []
        var at = CGPoint(x: 1919, y: 1079)
        let result = TerminationRestore.place(target, write: { origin, size in
            calls.append(size)
            let (error, moves) = calls.count == 1 ? (first, movesFirst) : (retry, movesOnRetry)
            if moves { at = origin }
            return error.map { .failure($0) } ?? .success(())
        }, origin: { at })
        if case .failure(let e) = result { #expect(e == outcome) } else { #expect(outcome == nil) }
        #expect(calls.count == writes)
        if writes == 2 { #expect(calls == [target.size, nil]) }   // the retry is position-only
    }

    private final class InFlight: @unchecked Sendable {
        private let lock = NSLock()
        private var now = 0, top = 0
        func start() { lock.withLock { now += 1; top = max(top, now) } }
        func end() { lock.withLock { now -= 1 } }
        var peak: Int { lock.withLock { top } }
    }

    private final class Written: @unchecked Sendable {
        private let lock = NSLock()
        private var set: Set<WindowRef> = []
        func add(_ r: WindowRef) { lock.withLock { _ = set.insert(r) } }
        var refs: Set<WindowRef> { lock.withLock { set } }
    }
}
