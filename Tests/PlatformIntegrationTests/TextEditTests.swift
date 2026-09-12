import Testing
import AppKit
import Foundation
@testable import SpacialShellKit
@testable import SpacialShellPlatform

/// Runs only with SPACIAL_INTEGRATION=1 and the Accessibility grant for the test host (see
/// docs/testing.md). Deliberately does not use AppleScript / Apple Events (`NSAppleScript`,
/// `tell application`) to create windows — that would need its own Automation TCC grant on top of
/// Accessibility. Instead it opens plain `.txt` files with TextEdit via
/// `NSWorkspace.open(_:withApplicationAt:configuration:)`, which needs no extra permission.
///
/// Ruling: `AXApp`'s registry is process-global and `AXWindowBackend.stop()` is terminal, so this
/// suite creates exactly one backend and calls `stop()` once, at the end of the one test.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SPACIAL_INTEGRATION"] == "1"))
struct TextEditTests {
    static let textEdit = "com.apple.TextEdit"

    /// Opens `n` plain-text documents in TextEdit, one at a time so each lands in its own window,
    /// and returns the running app plus the scratch directory holding the files (so the caller can
    /// clean it up in one shot).
    @MainActor func openTextEditWindows(_ n: Int) async throws -> (app: NSRunningApplication, dir: URL) {
        guard let textEditURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.textEdit) else {
            throw TestSetupError.textEditNotFound
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpacialShellIntegrationTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var app: NSRunningApplication?
        for i in 0..<n {
            let file = dir.appendingPathComponent("doc\(i).txt")
            try "SpacialShell integration test document \(i)\n".write(to: file, atomically: true, encoding: .utf8)
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            cfg.createsNewApplicationInstance = false
            app = try await NSWorkspace.shared.open([file], withApplicationAt: textEditURL, configuration: cfg)
            try await Task.sleep(for: .milliseconds(400))   // let the window actually appear before opening the next
        }
        guard let app else { throw TestSetupError.textEditNotFound }
        return (app, dir)
    }

    enum TestSetupError: Error { case textEditNotFound }

    @Test @MainActor func tilesTwoWindowsMaximizeAndParksTheOther() async throws {
        let (app, dir) = try await openTextEditWindows(2)
        // LIFO: remove the scratch directory, then terminate TextEdit, then stop the one backend —
        // declared in the reverse of that order so `defer` runs it correctly at scope exit.
        defer { try? FileManager.default.removeItem(at: dir) }
        defer { app.terminate() }   // our files are already saved on disk, so no "unsaved changes" prompt.

        let backend = AXWindowBackend(config: Config())
        defer { backend.stop() }    // terminal — must be called exactly once, at the very end.

        let store = WorldStore(backend: backend, config: Config(), world: nil, zeroSliverBundleIDs: [], onChange: { _ in })
        backend.start()
        await store.start()
        try await Task.sleep(for: .seconds(1))

        let w = await store.world
        let te = w.screens.values.flatMap { $0.workspaces.flatMap(\.windows) }.filter { $0.pid == app.processIdentifier }
        #expect(te.count >= 2)

        // #18: identity is minted by SpacialShell now, not read from `_AXUIElementGetWindow`. The
        // property the private call used to give us — a key that stays put for the life of the
        // window — has to hold against a real app or nothing above it works. Two enumerations in
        // a row must agree, and the two windows must not collide.
        // Guarded, not just asserted: every check below is a set comparison, and on an empty set
        // they would all pass vacuously and report success while proving nothing.
        try #require(te.count >= 2)
        let firstIDs = Set(te.map(\.id))
        #expect(firstIDs.count == te.count, "two TextEdit windows minted the same id")
        let reSnapshot = await backend.currentSnapshot()
        let secondIDs = Set(reSnapshot.windows.filter { $0.ref.pid == app.processIdentifier }.map(\.ref.id))
        #expect(firstIDs == secondIDs, "window ids changed between two enumerations")
        #expect(firstIDs.allSatisfy { $0 >= 1_000_000 }, "ids should be minted, not window-server ids")

        // Default layout is `.maximize` (Config() default): one window fills the screen, the rest
        // are parked in the corner sliver (spec §5, §7.4).
        await store.run(.focusWindow(.right))
        try await Task.sleep(for: .milliseconds(500))
        let snap = await backend.currentSnapshot()
        let frames = Dictionary(uniqueKeysWithValues: snap.windows.filter { $0.ref.pid == app.processIdentifier }.map { ($0.ref, $0.frame) })
        guard let display = snap.displays.first(where: \.isMain) else {
            Issue.record("no main display in snapshot")
            return
        }
        let visibleOnes = frames.values.filter { display.visibleFrame.insetBy(dx: -2, dy: -2).contains($0) }
        let parkedOnes = frames.values.filter { $0.minX >= display.visibleFrame.maxX - 2 || $0.minX <= display.visibleFrame.minX - $0.width + 2 }
        #expect(visibleOnes.count == 1 && parkedOnes.count >= 1)

        // Cycling the layout once (maximize → split) shows both windows side by side.
        await store.run(.cycleLayout)
        try await Task.sleep(for: .milliseconds(500))
        let snap2 = await backend.currentSnapshot()
        let both = snap2.windows.filter { $0.ref.pid == app.processIdentifier && display.visibleFrame.insetBy(dx: -2, dy: -2).contains($0.frame) }
        #expect(both.count == 2)

        // And identity survives being moved and resized — the case where a frame/title match would
        // have had to guess, and the reason a minted key is the right answer rather than a derived
        // one. Same ids after two relayouts and a focus change as before any of them.
        let afterLayout = Set(snap2.windows.filter { $0.ref.pid == app.processIdentifier }.map(\.ref.id))
        #expect(afterLayout == firstIDs, "window ids changed across parking, focus and a relayout")
    }
}
