import Testing
import Foundation
import AppKit
import SpacialShellKit
@testable import SpacialShellPlatform

/// What can be pinned without an Accessibility grant: the event stream, the termination restore's
/// tolerance of windows it can't reach, and the fact that a refresh session always carries the
/// display topology. The AX behaviour itself is covered by `PlatformIntegrationTests`.
@Suite @MainActor struct AXWindowBackendTests {
    private func backend() -> AXWindowBackend {
        var config = Config()
        // Bounds the one test that sweeps every running app: the assertions never depend on AX
        // data (only on the topology, which is read before any AX call), so the shortest workable
        // timeout is the right one here.
        config.axTimeoutMs = 100
        config.refreshIntervalMs = 60_000 // no periodic refresh; nothing here calls start() anyway
        return AXWindowBackend(config: config)
    }

    @Test func eventsIsALiveStreamAConsumerReceives() async {
        let backend = backend()
        var events = backend.events.makeAsyncIterator()
        backend._testYield(.screenLocked)
        backend._testYield(.screenUnlocked)
        #expect(await events.next() == .screenLocked)
        #expect(await events.next() == .screenUnlocked)
    }

    @Test func restoreForTerminationWithAnEmptyWorldIsANoOp() async {
        let backend = backend()
        var events = backend.events.makeAsyncIterator()

        backend.restoreAllForTermination(world: World.seeded(screens: [], config: Config()), displays: [], observed: [:])

        // A world whose windows belong to no registered app: still a no-op, still no crash.
        let display = DisplayInfo(
            id: "D1",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
            visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675),
            isMain: true,
        )
        var world = World.seeded(screens: [display.id], config: Config())
        world.screens[display.id]!.workspaces[0].windows = [WindowRef(id: 1, pid: -1)]
        // …and a window retired while parked, which reaches the restore only through `stranded`.
        backend.restoreAllForTermination(
            world: world,
            displays: [display],
            observed: [:],
            stranded: [WindowRef(id: 2, pid: -1): CGRect(x: 0, y: 0, width: 640, height: 480)],
        )

        // Nothing was emitted by either call: the next event is the marker we put in ourselves.
        backend._testYield(.screenLocked)
        #expect(await events.next() == .screenLocked)
    }

    /// `stop()` is terminal: every observer goes, every task is cancelled, and the event stream
    /// finishes so no consumer is left awaiting a backend that will never speak again.
    @Test func startThenStopFinishesTheEventStreamAndIsIdempotent() async {
        let backend = backend()
        backend.start()
        backend.stop()
        backend.stop() // terminal, but calling it twice must not trip over its own teardown
        backend.start() // …and a stopped backend does not come back to life

        let drained = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in backend.events {}; return true }
            group.addTask { try? await Task.sleep(for: .seconds(3)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(drained)
    }

    @Test(.timeLimit(.minutes(1))) func currentSnapshotCarriesTheDisplayTopology() async {
        guard !DisplayTopology.current().isEmpty else { return } // headless session
        let snapshot = await backend().currentSnapshot()
        // Windows and apps depend on the Accessibility grant this process may not have; the
        // topology does not, and a snapshot without it would make `WorldStore` reseed the world.
        let hasMain = snapshot.displays.contains(where: \.isMain)
        #expect(!snapshot.displays.isEmpty && hasMain)
    }
}
