import Testing
import AppKit
import SpacialShellKit
@testable import SpacialShellPlatform

/// These pin `AXApp`'s liveness contract, not its AX behaviour: they must pass whether or not the
/// test process holds an Accessibility grant. Without a grant every AX call fails, which is
/// exactly the case that used to leave the app thread's run loop dead (no observer source was
/// ever added) and every caller awaiting a perform that would never run.
@Suite struct AXAppLivenessTests {
    private func isNotFound(_ result: Result<Void, BackendError>) -> Bool {
        if case .failure(.notFound) = result { return true }
        return false
    }

    private func create(_ app: NSRunningApplication) -> AXApp? {
        AXApp.getOrCreate(app, timeoutMs: 200, onEvent: { _ in })
    }

    @Test func refusesOwnPid() {
        // `NSRunningApplication.current` reports pid -1 inside a bare test process (we are not a
        // registered application), so build the handle from our real pid; skip if unavailable.
        guard let me = NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        else { return }
        let created = create(me)
        #expect(created == nil)
    }

    @Test func refusesLoginwindow() {
        let loginwindow = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == loginwindowBundleId }
        guard let loginwindow else { return } // not running in this session
        let created = create(loginwindow)
        #expect(created == nil)
    }

    @Test(.timeLimit(.minutes(1))) func everyCallAnswersAndDestroyIsFinal() async {
        let mine = ProcessInfo.processInfo.processIdentifier
        let target = NSWorkspace.shared.runningApplications
            .first { $0.activationPolicy == .regular && $0.processIdentifier != mine }
        guard let target else { return } // headless session, nothing to talk to
        guard let app = create(target) else {
            Issue.record("getOrCreate returned nil for \(target.bundleIdentifier ?? "?")")
            return
        }

        // Each of these hangs forever if the app thread's run loop isn't alive.
        _ = await app.snapshotWindows()
        _ = await app.focusedWindowRef()
        let bogus: WindowID = 0xDEAD_BEEF
        #expect(isNotFound(await app.setFrame(bogus, CGRect(x: 0, y: 0, width: 10, height: 10))))
        #expect(isNotFound(await app.setPosition(bogus, .zero)))
        #expect(isNotFound(await app.raise(bogus)))
        #expect(isNotFound(await app.close(bogus)))
        app.setFrameForTermination(bogus, CGRect(x: 0, y: 0, width: 10, height: 10))

        app.destroy()
        // After destroy the app is gone for good: no stale windows, no hanging writes.
        let afterDestroy = await app.snapshotWindows()
        #expect(afterDestroy.isEmpty)
        #expect(isNotFound(await app.setFrame(bogus, .zero)))
        let focused = await app.focusedWindowRef()
        #expect(focused == nil)
        app.setFrameForTermination(bogus, .zero) // returns at once, doesn't wait out its budget
        let recreated = create(target)
        #expect(recreated !== app)
        recreated?.destroy()
    }
}
