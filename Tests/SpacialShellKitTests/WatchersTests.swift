import Testing
@testable import SpacialShellKit

/// #172: the watchers' shared lifecycle. The real ones sit on event taps, the Dock and NSWorkspace;
/// these fakes write down what reached them, in one journal, so the order across watchers shows.
@MainActor
@Suite struct WatchersTests {
    private final class Journal {
        var lines: [String] = []
        var logged: [String] = []
    }

    private struct StartFailed: Error {}

    private final class Fake: Watcher {
        let name: String
        let journal: Journal
        let failsToStart: Bool

        init(_ name: String, _ journal: Journal, failsToStart: Bool = false) {
            self.name = name
            self.journal = journal
            self.failsToStart = failsToStart
        }

        func apply(_ config: Config) { journal.lines.append("\(name).apply(gestures=\(config.gestures))") }
        func start() throws {
            journal.lines.append("\(name).start")
            if failsToStart { throw StartFailed() }
        }
        func observe(_ world: World) { journal.lines.append("\(name).observe(\(world.screenOrder))") }
        func stop() { journal.lines.append("\(name).stop") }
    }

    /// Only `observe` has a default: a watcher that does not care about the world says nothing.
    private final class Quiet: Watcher {
        let journal: Journal
        init(_ journal: Journal) { self.journal = journal }
        func apply(_ config: Config) {}
        func start() {}
        func stop() { journal.lines.append("quiet.stop") }
    }

    private let journal = Journal()
    private func watchers() -> Watchers { Watchers { [journal] in journal.logged.append($0) } }

    private func config(gestures: Bool) -> Config {
        var c = Config()
        c.gestures = gestures
        return c
    }

    @Test func eachStartsWhereItIsRegisteredWithItsConfigAppliedFirst() {
        let w = watchers()
        w.start(Fake("a", journal), "a", config: config(gestures: true))
        journal.lines.append("boot: something between")
        w.start(Fake("b", journal), "b", config: config(gestures: true))
        w.start(Fake("c", journal), "c", config: config(gestures: true))
        #expect(journal.lines == [
            "a.apply(gestures=true)", "a.start",
            "boot: something between",
            "b.apply(gestures=true)", "b.start",
            "c.apply(gestures=true)", "c.start",
        ])
    }

    @Test func oneConfigChangeReachesEveryWatcherOnceInStartOrder() {
        let w = watchers()
        for name in ["a", "b", "c"] { w.start(Fake(name, journal), name, config: config(gestures: false)) }
        journal.lines = []
        w.apply(config(gestures: true))
        #expect(journal.lines == ["a.apply(gestures=true)", "b.apply(gestures=true)", "c.apply(gestures=true)"])
    }

    @Test func everyWorldReachesEveryWatcher() {
        let w = watchers()
        w.start(Fake("a", journal), "a", config: Config())
        w.start(Quiet(journal), "quiet", config: Config())
        w.start(Fake("b", journal), "b", config: Config())
        journal.lines = []
        w.observe(World.seeded(screens: ["D1"], config: Config()))
        w.observe(World.seeded(screens: ["D1", "D2"], config: Config()))
        #expect(journal.lines == [
            #"a.observe(["D1"])"#, #"b.observe(["D1"])"#,
            #"a.observe(["D1", "D2"])"#, #"b.observe(["D1", "D2"])"#,
        ])
    }

    @Test func stopRunsEveryStopOnceInReverseStartOrder() {
        let w = watchers()
        w.start(Fake("a", journal), "a", config: Config())
        w.start(Quiet(journal), "quiet", config: Config())
        w.start(Fake("b", journal), "b", config: Config())
        journal.lines = []
        w.stop()
        w.stop()   // SIGTERM, then applicationWillTerminate: the second is a no-op
        #expect(journal.lines == ["b.stop", "quiet.stop", "a.stop"])
    }

    @Test func afterStopNothingMoreReachesThemAndNothingNewStarts() {
        let w = watchers()
        w.start(Fake("a", journal), "a", config: Config())
        w.stop()
        journal.lines = []
        w.apply(config(gestures: true))
        w.observe(World.seeded(screens: ["D1"], config: Config()))
        // A boot still under way when the quit came must not arm a watcher nobody will stop.
        let late = w.start(Fake("late", journal), "late", config: Config())
        #expect(late == nil)
        #expect(journal.lines.isEmpty)
    }

    @Test func aWatcherThatFailsToStartIsLoggedAndLeftOutWhileTheRestRun() {
        let w = watchers()
        w.start(Fake("a", journal), "a", config: config(gestures: false))
        let error = w.start(Fake("b", journal, failsToStart: true), "the b tap", config: config(gestures: false))
        w.start(Fake("c", journal), "c", config: config(gestures: false))
        #expect(error is StartFailed)
        #expect(journal.logged.count == 1)
        #expect(journal.logged.first?.contains("the b tap") == true)
        #expect(journal.lines == [
            "a.apply(gestures=false)", "a.start",
            "b.apply(gestures=false)", "b.start",
            "c.apply(gestures=false)", "c.start",
        ])

        journal.lines = []
        w.apply(config(gestures: true))
        w.observe(World.seeded(screens: ["D1"], config: Config()))
        w.stop()
        #expect(!journal.lines.contains { $0.hasPrefix("b.") })
        #expect(journal.lines == [
            "a.apply(gestures=true)", "c.apply(gestures=true)",
            #"a.observe(["D1"])"#, #"c.observe(["D1"])"#,
            "c.stop", "a.stop",
        ])
    }
}
