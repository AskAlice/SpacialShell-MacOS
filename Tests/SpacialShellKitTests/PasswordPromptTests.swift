import Testing
import Foundation
@testable import SpacialShellKit

/// #195: a window holding a focused password field holds secure input for the whole system, so it
/// is never parked out of sight: while it does, it is shown centred on the focused display, raised
/// without being focused, wherever its row is. `SecureInputWatcher` reports them to the store.
@Suite struct PasswordPromptTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), prompt = WindowRef(id: 2, pid: 2)
    /// `PeekStoreTests`' geometry: no panels, gap 8; the prompt is 300 × 200, centred in it.
    let rect = CGRect(x: 8, y: 33, width: 984, height: 658)
    var shown: CGRect { CGRect(x: rect.midX - 150, y: rect.midY - 100, width: 300, height: 200) }

    func win(_ r: WindowRef, bundle: String, kind: WindowKind = .tile) -> WindowSnapshot {
        WindowSnapshot(ref: r, frame: CGRect(x: 0, y: 0, width: 300, height: 200), title: "t", bundleID: bundle, kind: kind,
                       parent: nil, isMinimized: false, isFullscreen: false)
    }

    /// `a` focused in the active row, the prompt (another app) parked in the row above.
    func make(promptKind: WindowKind = .tile) async -> (WorldStore, FakeBackend) {
        var c = Config(); c.showPanels = false; c.categoryOrder = []
        let s = Snapshot(displays: [d1], apps: [AppInfo(pid: 1, bundleID: "com.a", isHidden: false), AppInfo(pid: 2, bundleID: "com.exodus", isHidden: false)],
                         windows: [win(a, bundle: "com.a"), win(prompt, bundle: "com.exodus", kind: promptKind)], focused: a)
        let be = FakeBackend(snapshot: s)
        let store = WorldStore(backend: be, config: c, world: nil, zeroSliverBundleIDs: [], onChange: { _, _ in })
        await store.start()
        await store.run(.moveWindowToWorkspace(.down))   // `a` → a row of its own, focused; the prompt stays, parked
        await be.reset()
        return (store, be)
    }

    @Test func aParkedPromptIsShownOnTheActiveRowWithoutMovingFocus() async {
        let (store, be) = await make()
        let before = await store.world
        #expect(before.location(of: prompt)!.index != before.screens["D1"]!.activeIndex)

        await store.apply(.secureInputWindows([prompt]))
        let calls = await be.calls
        #expect(calls.contains(.setFrame(prompt, shown)))
        #expect(calls.contains(.raiseWithoutActivating(prompt)))
        #expect(!calls.contains(.raise(prompt)), "shown, not focused")
        #expect(await store.world == before, "the model does not change: the prompt keeps its row")

        // The raise made it its app's focused window, and macOS says so: our echo, not the user.
        await store.apply(.focusChanged(prompt))
        await store.apply(.appActivated(pid: prompt.pid))
        #expect(await store.world == before)

        await be.reset()
        await store.apply(.secureInputWindows([prompt]))
        #expect(await be.calls.isEmpty, "a repeat report neither moves nor raises it again")
    }

    @Test func aClearedPromptIsParkedAgain() async {
        let (store, be) = await make()
        await store.apply(.secureInputWindows([prompt]))
        await be.reset()
        await store.apply(.secureInputWindows([]))
        let calls = await be.calls
        #expect(calls.contains { if case .setPosition(prompt, _) = $0 { true } else { false } }, "back to its row's parking corner")
        #expect(!calls.contains(.raise(prompt)) && !calls.contains(.raiseWithoutActivating(prompt)))
    }

    /// A floating prompt parked again keeps where it was before it was shown, not the centred frame.
    @Test func aFloatingPromptComesBackWhereItWas() async {
        let (store, be) = await make(promptKind: .float)
        await store.apply(.secureInputWindows([prompt]))
        await store.apply(.secureInputWindows([]))
        await be.reset()
        await store.run(.focusWorkspace(.up))   // the prompt's own row
        #expect(await be.calls.contains(.setFrame(prompt, CGRect(x: 0, y: 0, width: 300, height: 200))))
    }

    @Test func anEmptyReportChangesNothing() async {
        let (store, be) = await make()
        let before = await store.world
        await store.apply(.secureInputWindows([]))
        #expect(await be.calls.isEmpty)
        #expect(await store.world == before)
    }

    @Test func aWindowTheShellDoesNotPlaceIsIgnored() async {
        let (store, be) = await make()
        await store.apply(.secureInputWindows([WindowRef(id: 99, pid: 9)]))
        #expect(await be.calls.isEmpty)
    }

    /// The pure half: only a window that would be parked is moved, onto the focused display.
    @Test func theReconcilerShowsOnlyWhatItWouldPark() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(prompt, kind: .tile, on: "D1")
        w = CommandRunner.apply(.moveWindowToWorkspace(.down), to: w, in: .test()).0
        func desired(_ prompts: Set<WindowRef>) -> [WindowRef: Placement] {
            Reconciler.desired(world: w, displays: [d1], config: LayoutConfig(gap: 8, layouts: .builtins), observed: [prompt: win(prompt, bundle: "").frame],
                               prePark: [:], parkedNow: [prompt], zeroSliver: [], prompts: prompts)
        }
        guard case .parked = desired([])[prompt] else { Issue.record("parked without a report"); return }
        #expect(desired([prompt])[prompt] == .frame(shown))
        #expect(desired([prompt])[a] == desired([])[a], "the visible row is laid out as before")
        #expect(desired([a]) == desired([]), "a prompt already on screen stays where it is")
    }
}
