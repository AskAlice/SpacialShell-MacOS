import Testing
import Foundation
@testable import SpacialShellKit

/// M3a A7 (#56): an activation is resolved to the app's focused window on the spot, so ⌘Tab and
/// the Dock land on a visible window within one reconcile instead of after the debounced sweep.
/// The backend reports that window as `focusChanged` immediately ahead of `appActivated`.
extension WorldStoreTests {
    /// Three rows: `o1` alone in ws0 (the app's anchor, so `candidateWindow` would pick it), `o2`
    /// alone in ws1, `a` alone in ws2 and active. The user ⌘Tabs to the app whose focused window
    /// is `o2`.
    func activationScene() async throws -> (WorldStore, FakeBackend, o1: WindowRef, o2: WindowRef) {
        let o1 = WindowRef(id: 3, pid: 9), o2 = WindowRef(id: 4, pid: 9)
        let s = Snapshot(displays: [d1],
                         apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false),
                                AppInfo(pid: 9, bundleID: "com.other", isHidden: false)],
                         windows: [win(o1, bundle: "com.other"), win(o2, bundle: "com.other"), win(a)],
                         focused: o2, loginwindowFrontmost: false)
        let (store, be) = await make(s)
        await store.run(.moveWindowToWorkspace(.down))            // o2 → ws1
        await store.run(.focusWindowRef(a))
        await store.run(.moveWindowToWorkspace(.down))            // a → ws1
        await store.run(.moveWindowToWorkspace(.down))            // a → ws2
        // The echo of raising `a`, as the backend reports it — so macOS's last word is `a`, not
        // the `o2` of the boot snapshot.
        await store.apply(.focusChanged(a))
        await store.apply(.appActivated(pid: 1))
        let w = await store.world
        let rows = w.screens["D1"]!.workspaces.map(\.windows)
        try #require(Array(rows.prefix(3)) == [[o1], [o2], [a]] && w.screens["D1"]!.activeIndex == 2,
                     "unexpected setup: \(rows)")
        await be.reset()
        return (store, be, o1, o2)
    }

    @Test func anActivationLandsOnItsFocusedWindowsWorkspaceInOneReconcile() async throws {
        let (store, be, _, o2) = try await activationScene()

        await store.apply(.focusChanged(o2))                      // the fast path's report…

        var w = await store.world
        #expect(w.screens["D1"]!.activeIndex == 1, "the focused window's workspace was not activated")
        #expect(w.focus.window == o2)
        #expect(await be.calls.contains(.raise(o2)))
        #expect(await be.calls.filter { if case .raise = $0 { true } else { false } }.count == 1)

        await store.apply(.appActivated(pid: 9))                  // …and the activation behind it
        w = await store.world
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == o2,
                "the activation overrode the focused window with the app's anchor")
        #expect(await be.calls.filter { if case .raise = $0 { true } else { false } }.count == 1,
                "the activation raised a second window")
        #expect(w.invariantViolations().isEmpty)
    }

    /// Whichever order the two reports reach the store in, the focused window wins.
    @Test func anActivationFollowedByItsFocusReportStillLandsOnTheFocusedWindow() async throws {
        let (store, _, _, o2) = try await activationScene()
        await store.apply(.appActivated(pid: 9))
        await store.apply(.focusChanged(o2))
        let w = await store.world
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == o2)
    }

    /// Our own raise activates its app, and the fast path reports that as a focus change as well.
    /// Both halves are echoes: nothing moves, nothing is raised again.
    @Test func theFastPathEchoOfOurOwnRaiseIsIgnored() async throws {
        let (store, be, _, o2) = try await activationScene()
        await store.run(.focusWorkspace(.up))                     // the shell raises o2
        let settled = await store.world
        #expect(settled.screens["D1"]!.activeIndex == 1 && settled.focus.window == o2)
        await be.reset()

        await store.apply(.focusChanged(o2))
        await store.apply(.appActivated(pid: 9))

        #expect(await store.world == settled)
        #expect(await be.calls.isEmpty, "an echo of our own raise was acted on")
    }

    /// Fast switching: the shell raises o2, then a, before o2's echo lands. The late echo — in the
    /// fast path's order — must not pull the user back (#69).
    @Test func aLateFastPathEchoDoesNotSwitchBack() async throws {
        let (store, _, _, o2) = try await activationScene()
        await store.run(.focusWorkspace(.up))                     // raises o2
        await store.run(.focusWorkspace(.down))                   // raises a before o2's echo
        let settled = await store.world
        #expect(settled.screens["D1"]!.activeIndex == 2 && settled.focus.window == a)

        await store.apply(.focusChanged(o2))
        await store.apply(.appActivated(pid: 9))

        #expect(await store.world == settled, "a stale echo switched the workspace back")
    }

    /// #28: the fast path goes through the fullscreen guard like any other focus report.
    @Test func theFastPathCannotPullTheUserOutOfFullscreen() async {
        let (store, be) = await fullscreenScene(twoDisplays: false)

        await store.apply(.focusChanged(pushy))
        await store.apply(.appActivated(pid: 9))

        let w = await store.world
        #expect(w.focus.window == video && w.fullscreen == [video])
        #expect(await be.calls.contains(.raise(video)))
        #expect(!(await be.calls.contains(.raise(pushy))))
    }
}
