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
        config.axTimeoutMs = 200        // keep every AX call in this suite short
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
        backend.restoreAllForTermination(world: world, displays: [display], observed: [:])

        // Nothing was emitted by either call: the next event is the marker we put in ourselves.
        backend._testYield(.screenLocked)
        #expect(await events.next() == .screenLocked)
    }

    @Test func currentSnapshotCarriesTheDisplayTopology() async {
        guard !DisplayTopology.current().isEmpty else { return } // headless session
        let snapshot = await backend().currentSnapshot()
        // Windows and apps depend on the Accessibility grant this process may not have; the
        // topology does not, and a snapshot without it would make `WorldStore` reseed the world.
        let hasMain = snapshot.displays.contains(where: \.isMain)
        #expect(!snapshot.displays.isEmpty && hasMain)
    }
}
