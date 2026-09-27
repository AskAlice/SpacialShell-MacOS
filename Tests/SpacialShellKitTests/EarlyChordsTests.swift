import Foundation
import Testing
@testable import SpacialShellKit

/// #184: the hotkey tap is armed first thing in boot, before the store runs. A bound chord it
/// swallows in that window is held, and replayed in press order once the store is running; one
/// older than 2 s by then is dropped, because stale navigation is worse than none.
@Suite struct EarlyChordsTests {
    /// The injected clock. Starts anywhere; tests move it by hand.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = ContinuousClock.now
        var now: ContinuousClock.Instant { lock.withLock { current } }
        func advance(_ by: Duration) { lock.withLock { current = current.advanced(by: by) } }
    }

    private let clock = Clock()
    private func chords() -> EarlyChords { EarlyChords { [clock] in clock.now } }

    @Test func aChordBeforeReadyIsHeldNotRun() {
        var early = chords()
        #expect(early.receive(.focusWorkspace(.down)) == nil)
        #expect(early.receive(.focusWindow(.right)) == nil)
        #expect(!early.isReady)
    }

    @Test func readyReplaysTheHeldChordsInPressOrder() {
        var early = chords()
        _ = early.receive(.focusWorkspace(.down))
        clock.advance(.milliseconds(300))
        _ = early.receive(.focusWindow(.right))
        clock.advance(.milliseconds(300))
        _ = early.receive(.focusWorkspace(.up))
        clock.advance(.milliseconds(500))
        #expect(early.ready() == .init(commands: [.focusWorkspace(.down), .focusWindow(.right), .focusWorkspace(.up)],
                                       dropped: 0))
        #expect(early.isReady)
    }

    /// Measured at replay time: a chord pressed early in a long boot has gone stale by the time the
    /// store runs. Exactly 2 s is still fresh.
    @Test func aChordOlderThanTwoSecondsAtReplayIsDropped() {
        var early = chords()
        _ = early.receive(.focusWorkspace(.down))    // 2.5 s old at ready
        clock.advance(.milliseconds(500))
        _ = early.receive(.focusWindow(.left))       // exactly 2 s old at ready
        clock.advance(.milliseconds(1500))
        _ = early.receive(.focusWorkspace(.up))      // 0.5 s old at ready
        clock.advance(.milliseconds(500))
        #expect(early.ready() == .init(commands: [.focusWindow(.left), .focusWorkspace(.up)], dropped: 1))
    }

    @Test func afterReadyAChordPassesStraightThrough() {
        var early = chords()
        _ = early.receive(.focusWorkspace(.down))
        _ = early.ready()
        clock.advance(.seconds(10))
        #expect(early.receive(.focusWindow(.right)) == .focusWindow(.right))
        #expect(early.receive(.focusWorkspace(.up)) == .focusWorkspace(.up))
        // Nothing was held on the way: a second `ready` has nothing to replay.
        #expect(early.ready() == .init(commands: [], dropped: 0))
    }

    /// Commands that change mode (the overview, the spatial view, zen) or context (a workspace, the
    /// focused window) are held like any other: resolved when pressed, replayed in press order, none
    /// promoted or merged.
    @Test func aModeOrContextChangeWhileHeldReordersNothing() {
        var early = chords()
        let pressed: [Command] = [
            .toggleSpatialView, .focusWorkspace(.down), .toggleOverview, .focusWindow(.right),
            .toggleShellUI, .toggleOverview, .focusWorkspace(.up),
        ]
        for command in pressed {
            _ = early.receive(command)
            clock.advance(.milliseconds(100))
        }
        #expect(early.ready() == .init(commands: pressed, dropped: 0))
    }

    /// A boot that hangs does not grow the queue without bound: what is already stale when a new
    /// chord arrives is let go then, and the rest keep their order.
    @Test func whatIsAlreadyStaleIsLetGoAsNewChordsArrive() {
        var early = chords()
        _ = early.receive(.focusWorkspace(.down))
        clock.advance(.seconds(5))
        _ = early.receive(.focusWindow(.right))
        #expect(early.heldCount == 1)
        clock.advance(.milliseconds(100))
        #expect(early.ready() == .init(commands: [.focusWindow(.right)], dropped: 1))
    }
}

/// #184: what the tap talks to. The tap exists from stage 2b; what its callbacks drive (the store,
/// the cheat sheet, the spatial view, the backend) exists from stage 7. Until `connect`, commands are
/// held and the rest is dropped.
@Suite struct HotkeyOutletTests {
    final class Journal: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        var lines: [String] { lock.withLock { stored } }
        func add(_ line: String) { lock.withLock { stored.append(line) } }
        func clear() { lock.withLock { stored = [] } }
    }

    private let clock = EarlyChordsTests.Clock()
    private let journal = Journal()

    private func outlet() -> HotkeyOutlet<String> { HotkeyOutlet { [clock] in clock.now } }

    private func handlers() -> HotkeyOutlet<String>.Handlers {
        let journal = journal
        return .init(
            command: { journal.add("run \($0)") },
            flags: { journal.add("flags \($0)") },
            keyDown: { journal.add("keyDown") },
            repeated: { journal.add("repeat \($0)") })
    }

    @Test func beforeConnectOnlyCommandsAreKeptAndTheyReplayOnConnect() {
        let hotkeys = outlet()
        hotkeys.keyDown()
        hotkeys.flags("fn")
        hotkeys.command(.focusWorkspace(.down))
        hotkeys.repeated(.focusWorkspace(.down))
        hotkeys.keyDown()
        hotkeys.command(.toggleOverview)
        #expect(journal.lines.isEmpty)

        let replay = hotkeys.connect(handlers())
        #expect(replay == .init(commands: [.focusWorkspace(.down), .toggleOverview], dropped: 0))
        #expect(journal.lines == ["run \(Command.focusWorkspace(.down))", "run \(Command.toggleOverview)"])

        journal.clear()
        hotkeys.keyDown()
        hotkeys.flags("fn")
        hotkeys.command(.focusWindow(.right))
        hotkeys.repeated(.focusWindow(.right))
        #expect(journal.lines == [
            "keyDown", "flags fn", "run \(Command.focusWindow(.right))", "repeat \(Command.focusWindow(.right))",
        ])
    }

    /// Only the first `connect` counts: boot connects once, and a second one must not swap the
    /// handlers or replay anything again.
    @Test func aSecondConnectChangesNothing() {
        let hotkeys = outlet()
        hotkeys.command(.focusWorkspace(.down))
        _ = hotkeys.connect(handlers())
        let other = Journal()
        let second = hotkeys.connect(.init(command: { other.add("run \($0)") }, flags: { _ in }, keyDown: {}, repeated: { _ in }))
        #expect(second == .init(commands: [], dropped: 0))
        hotkeys.command(.focusWindow(.left))
        #expect(other.lines.isEmpty)
        #expect(journal.lines == ["run \(Command.focusWorkspace(.down))", "run \(Command.focusWindow(.left))"])
    }
}

/// #184, the acceptance test: boot through the #172 lifecycle runner with a fake tap. The tap is
/// the first watcher up, before the store starts; chords pressed before `store.start()` finishes are
/// replayed after it, in order; one older than 2 s by then is dropped.
@MainActor
@Suite struct EarlyChordsBootTests {
    private let clock = EarlyChordsTests.Clock()
    private let journal = HotkeyOutletTests.Journal()

    /// The tap as the runtime sees it: a watcher whose key presses go to the outlet.
    private final class FakeTap: Watcher {
        let outlet: HotkeyOutlet<String>
        let journal: HotkeyOutletTests.Journal
        private var table: [String: Command] = [:]
        private var armed = false

        init(_ outlet: HotkeyOutlet<String>, _ journal: HotkeyOutletTests.Journal) {
            self.outlet = outlet
            self.journal = journal
        }

        func apply(_ config: Config) {
            table = config.gestures
                ? ["fn-s": .focusWorkspace(.down), "fn-w": .focusWorkspace(.up)]
                : ["fn-s": .moveWindowToWorkspace(.down), "fn-w": .moveWindowToWorkspace(.up)]
        }
        func start() { armed = true; journal.add("tap.start") }
        func stop() { armed = false; journal.add("tap.stop") }

        /// A key press: swallowed and handed on only while armed, as the real tap does.
        func press(_ chord: String) {
            guard armed, let command = table[chord] else { journal.add("to macOS: \(chord)"); return }
            outlet.command(command)
        }
    }

    @Test func theTapIsUpBeforeTheStoreAndEarlyChordsReplayAfterIt() {
        let watchers = Watchers { _ in }
        let hotkeys = HotkeyOutlet<String> { [clock] in clock.now }
        let tap = FakeTap(hotkeys, journal)
        var config = Config()
        config.gestures = true

        // Stage 2b: the tap first. A chord before it would reach macOS (Globe+S → Siri).
        tap.press("fn-s")
        watchers.start(tap, "the hotkey tap", config: config)
        tap.press("fn-s")                       // 0.0 s: pressed during the snapshot and adoption
        clock.advance(.milliseconds(1500))
        tap.press("fn-w")                       // 1.5 s

        // Stage 6: the store starts. A rebind while chords are held changes none of them.
        journal.add("store.start")
        config.gestures = false
        watchers.apply(config)
        clock.advance(.milliseconds(800))       // 2.3 s: the first chord is now stale

        // Stage 7: connected; the held chords replay.
        let replay = hotkeys.connect(.init(
            command: { [journal] in journal.add("run \($0)") },
            flags: { _ in }, keyDown: {}, repeated: { _ in }))
        tap.press("fn-s")                       // straight through, on the new binding

        #expect(replay == .init(commands: [.focusWorkspace(.up)], dropped: 1))
        #expect(journal.lines == [
            "to macOS: fn-s",
            "tap.start",
            "store.start",
            "run \(Command.focusWorkspace(.up))",
            "run \(Command.moveWindowToWorkspace(.down))",
        ])
    }
}
