import Testing
import Foundation
import OpenTelemetryApi
@testable import SpacialShellKit

@Suite struct WorldStoreTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1)
    /// M1 geometry: the frame maths in this suite predates the shell panels, and what it tests
    /// (adoption, echoes, parking, locking) is inset-agnostic — `PanelInsetTests` owns the insets.
    func m1Config() -> Config { var c = Config(); c.showPanels = false; c.categoryOrder = []; return c }
    func win(_ r: WindowRef, _ f: CGRect = CGRect(x: 0, y: 0, width: 300, height: 200), kind: WindowKind = .tile, bundle: String? = "com.x", min: Bool = false, fs: Bool = false, parent: WindowRef? = nil, onSpace: Bool = true) -> WindowSnapshot {
        WindowSnapshot(ref: r, frame: f, title: "t", bundleID: bundle, kind: kind, parent: parent, isMinimized: min, isFullscreen: fs,
                       onActiveSpace: onSpace)
    }
    func snap(_ ws: [WindowSnapshot], focused: WindowRef? = nil, login: Bool = false) -> Snapshot {
        Snapshot(displays: [d1], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false)], windows: ws, focused: focused, loginwindowFrontmost: login)
    }
    func make(_ s: Snapshot, config: Config? = nil, world: World? = nil, placements: [String: UUID] = [:]) async -> (WorldStore, FakeBackend) {
        let be = FakeBackend(snapshot: s)
        let store = WorldStore(backend: be, config: config ?? m1Config(), world: world, zeroSliverBundleIDs: ["us.zoom.xos"],
                               placements: placements, onChange: { _ in })
        await store.start()
        return (store, be)
    }

    @Test func startAdoptsAndTiles() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        let w = await store.world
        #expect(w.screens["D1"]!.active.windows == [a, b] && w.focus.window == a)
        let calls = await be.calls
        #expect(calls.contains(.setFrame(a, CGRect(x: 8, y: 33, width: 984, height: 658))))
        #expect(calls.contains(.setPosition(b, CGPoint(x: 999, y: 699))))
        #expect(calls.contains(.raise(a)))
    }
    @Test func exportForTerminationCarriesTheCurrentWorld() async {
        let (store, _) = await make(snap([win(a), win(b)], focused: a))
        let world = await store.world
        let export = await store.exportForTermination()
        #expect(export.world == world && export.displays == [d1] && export.observed[a] != nil)
        // Maximize layout: `a` is the anchor and tiled, `b` is parked in the corner. Only `b` is
        // stranded anywhere the user cannot reach, so only `b` is the restore's business —
        // centring `a` as well would scramble a layout that is perfectly fine (I4).
        #expect(export.parked == [b])
    }
    /// A window retired after three failed writes *while parked* leaves the model entirely, so
    /// nothing would ever unpark it — spec §7.4 says quitting must not strand it in the corner.
    @Test func retiredWhileParkedWindowIsExportedAsStranded() async {
        // Two windows, maximize layout: `a` is the anchor, `b` is parked in the corner.
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        #expect(await store.debugSideTables().parked.contains(b))
        await be.fail(b)
        for y in [100.0, 200.0, 300.0] {
            await store.apply(.windowMoved(b, CGRect(x: y, y: y, width: 300, height: 200)))
        }
        #expect(await store.world.ignored.contains(b))          // retired, unreachable by the reconciler
        let export = await store.exportForTermination()
        #expect(export.stranded[b] != nil && export.stranded[a] == nil)
    }
    /// C1: macOS reports an empty screen list mid-hot-plug, at wake and around the lock screen.
    /// Acting on one used to reseed the world from nothing — every workspace dropped, and the
    /// re-adoption that followed force-unwrapped a screen that no longer existed.
    @Test func emptyDisplaySnapshotIsIgnored() async {
        let (store, _) = await make(snap([win(a)], focused: a))
        let before = await store.world
        await store.apply(.snapshot(Snapshot(displays: [], apps: [], windows: [], focused: nil)))
        let after = await store.world
        #expect(after == before)
        #expect(after.invariantViolations().isEmpty)
    }
    @Test func newWindowInSnapshotIsAdoptedAtEnd() async {
        let (store, be) = await make(snap([win(a)], focused: a))
        await store.apply(.snapshot(snap([win(a), win(b)], focused: b)))
        let w = await store.world
        #expect(w.screens["D1"]!.active.windows == [a, b] && w.focus.window == b)
        #expect(await be.calls.contains(.setPosition(a, CGPoint(x: 999, y: 699))))   // maximize now anchored on b
    }
    @Test func vanishedWindowIsRemovedUnlessLoginwindow() async {
        let (store, _) = await make(snap([win(a), win(b)], focused: a))
        await store.apply(.snapshot(snap([win(a)], focused: a, login: true)))
        #expect(await store.world.screens["D1"]!.active.windows == [a, b])
        await store.apply(.snapshot(snap([win(a)], focused: a)))
        #expect(await store.world.screens["D1"]!.active.windows == [a])
    }
    @Test func lockFreezesUntilUnlock() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.reset()
        await store.apply(.screenLocked)
        await store.apply(.snapshot(snap([], focused: nil)))
        #expect(await store.world.screens["D1"]!.active.windows == [a, b])
        #expect(await be.calls.isEmpty)
        await be.push(.snapshot(snap([win(a), win(b)], focused: a)))
        await store.apply(.screenUnlocked)
        #expect(await store.world.screens["D1"]!.active.windows == [a, b])
    }
    @Test func ourOwnMovesAreIgnoredExternalMovesSnapBack() async {
        let (store, be) = await make(snap([win(a)], focused: a))
        await be.reset()
        await store.apply(.windowMoved(a, CGRect(x: 8, y: 33, width: 984, height: 658)))   // echo of our write
        #expect(await be.calls.isEmpty)
        await store.apply(.windowMoved(a, CGRect(x: 100, y: 100, width: 984, height: 658)))
        #expect(await be.calls == [.setFrame(a, CGRect(x: 8, y: 33, width: 984, height: 658))])
    }
    @Test func focusOnParkedWindowActivatesItsWorkspace() async {
        let (store, _) = await make(snap([win(a), win(b)], focused: a))
        await store.run(.moveWindowToWorkspace(.down))          // a → ws1 active
        await store.apply(.focusChanged(b))                     // user cmd-tabbed to b (parked in ws0)
        let w = await store.world
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus.window == b)
    }
    @Test func configOverridesHeuristicKind() async {
        var c = m1Config(); c.float = [AppRule(bundleId: "com.x")]
        let be = FakeBackend(snapshot: snap([win(a)], focused: a))
        let store = WorldStore(backend: be, config: c, world: nil, zeroSliverBundleIDs: [], onChange: { _ in })
        await store.start()
        #expect(await store.world.screens["D1"]!.active.floating == [a])
    }
    /// Spec §4.3 (amended 2026-09-14): a native-fullscreen window keeps its tab and stays reachable
    /// — once something else takes focus, the tab is the way back to its fullscreen Space — but
    /// macOS owns its frame, so it is never framed or parked. Leaving fullscreen retiles it in place.
    @Test func fullscreenKeepsItsTabAndIsNeverWritten() async {
        func wrote(_ r: WindowRef, _ calls: [FakeBackend.Call]) -> Bool {
            calls.contains { switch $0 { case .setFrame(let w, _), .setPosition(let w, _): w == r; default: false } }
        }
        let (store, be) = await make(snap([win(a), win(b, fs: true)], focused: a))
        var w = await store.world
        #expect(w.screens["D1"]!.active.windows == [a, b] && w.fullscreen == [b] && w.ignored.isEmpty)
        #expect(await !wrote(b, be.calls))

        await store.run(.focusWindow(.right))                   // Fn+D reaches it, and raising it is the way back
        #expect(await store.world.focus.window == b)
        #expect(await be.calls.contains(.raise(b)))
        await store.run(.moveWindowToWorkspace(.down))          // its workspace going inactive must not park it
        #expect(await !wrote(b, be.calls))

        await be.reset()
        await store.apply(.snapshot(snap([win(a), win(b)], focused: b)))
        w = await store.world
        #expect(w.fullscreen.isEmpty && w.location(of: b) != nil)
        #expect(await wrote(b, be.calls))
        #expect(w.invariantViolations().isEmpty)
    }
    /// M3a A6 (#55): a window on another native Space cannot be shown by moving it — the write
    /// lands on a window nobody can see. It keeps its tab, is never framed or parked (even when its
    /// workspace goes inactive or AX reports it moved), and is laid out again the moment a snapshot
    /// finds it back on the active Space.
    @Test func offSpaceWindowIsNeverWrittenAndReturnsToLayout() async {
        func wrote(_ r: WindowRef, _ calls: [FakeBackend.Call]) -> Bool {
            calls.contains { switch $0 { case .setFrame(let w, _), .setPosition(let w, _): w == r; default: false } }
        }
        let (store, be) = await make(snap([win(a), win(b, onSpace: false)], focused: a))
        var w = await store.world
        #expect(w.screens["D1"]!.active.windows == [a, b] && w.offSpace == [b])
        #expect(await !wrote(b, be.calls))

        await store.apply(.windowMoved(b, CGRect(x: 90, y: 90, width: 300, height: 200)))
        await store.run(.focusWindow(.right))
        await store.run(.moveWindowToWorkspace(.down))          // its workspace going inactive must not park it
        await store.run(.focusWorkspace(.up))
        #expect(await !wrote(b, be.calls))

        await be.reset()
        await store.apply(.snapshot(snap([win(a), win(b)], focused: a)))   // the user switched to its Space
        w = await store.world
        #expect(w.offSpace.isEmpty)
        #expect(await wrote(b, be.calls))
        #expect(w.invariantViolations().isEmpty)
    }

    /// A6's "re-adopt" (#55): a window retired while on the active Space keeps its frame while it
    /// is away, so "until it changes" never fired and it stayed tab-less after the user came back
    /// to it. Coming back to the active Space is itself the change that revives it.
    @Test func aRetiredWindowComesBackWithItsSpace() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.fail(b)
        for y in [100.0, 200.0, 300.0] {
            await store.apply(.windowMoved(b, CGRect(x: y, y: y, width: 300, height: 200)))
        }
        #expect(await store.world.ignored.contains(b))
        // Same frame as its last snapshot throughout: only the Space changes.
        await store.apply(.snapshot(snap([win(a), win(b, onSpace: false)], focused: a)))
        #expect(await store.world.ignored.contains(b))           // away: nothing to do yet
        await store.apply(.snapshot(snap([win(a), win(b)], focused: a)))
        let w = await store.world
        #expect(!w.ignored.contains(b) && w.location(of: b) != nil)
        #expect(w.invariantViolations().isEmpty)
    }

    /// Spec §11 as amended 2026-09-15. A failed *raise* never retires a window: raising fails for
    /// transient reasons — the window is in its own fullscreen Space, the app is mid-transition —
    /// and retiring on it left a live window on screen with no tab anywhere (#36).
    ///
    /// A *fullscreen* window is the case that bites: it gets no frame writes, so nothing ever
    /// resets the failure counter between raises, and three focus changes retire it.
    @Test func failedRaisesNeverRetire() async {
        let (store, be) = await make(snap([win(a), win(b, fs: true)], focused: a))
        await be.failRaise(b)
        for _ in 0..<4 {
            await store.run(.focusWindow(.right))   // focus b → raise(b) fails
            await store.run(.focusWindow(.left))    // focus a → raise(a) succeeds
        }
        let w = await store.world
        #expect(!w.ignored.contains(b) && w.location(of: b) != nil)
    }

    /// Spec §11's "until it changes", which the first implementation never honoured: `ignored` was a
    /// one-way door, so a window retired once stayed unreachable for the life of the process (#36).
    @Test func aRetiredWindowComesBackWhenItChanges() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.fail(b)
        for y in [100.0, 200.0, 300.0] {
            await store.apply(.windowMoved(b, CGRect(x: y, y: y, width: 300, height: 200)))
        }
        #expect(await store.world.ignored.contains(b))          // retired after three failed writes
        await store.apply(.snapshot(snap([win(a), win(b, CGRect(x: 40, y: 40, width: 500, height: 400))], focused: a)))
        let w = await store.world
        #expect(!w.ignored.contains(b) && w.location(of: b) != nil)
        #expect(w.invariantViolations().isEmpty)
    }

    /// The user's invariant (#36): a window macOS reports as focused is by definition managed, so a
    /// retired one is re-adopted rather than left "just under everything" with no tab.
    @Test func nativeFocusOnARetiredWindowBringsItBack() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.fail(b)
        for y in [100.0, 200.0, 300.0] {
            await store.apply(.windowMoved(b, CGRect(x: y, y: y, width: 300, height: 200)))
        }
        #expect(await store.world.ignored.contains(b))
        await store.apply(.focusChanged(b))
        let w = await store.world
        #expect(!w.ignored.contains(b) && w.location(of: b) != nil && w.focus.window == b)
    }

    /// Decision 2026-09-15 (#49): macOS shows only the fullscreen Space on that display, so a
    /// workspace switch there is invisible until fullscreen ends. Leave it first, and the switch
    /// means something.
    @Test func switchingWorkspaceLeavesFullscreenFirst() async {
        let (store, be) = await make(snap([win(a), win(b, fs: true)], focused: a))
        await be.reset()
        await store.run(.focusWorkspace(.down))
        #expect(await be.calls.contains(.setFullscreen(b, false)))
    }

    /// #49: macOS re-reports a fullscreen window as focused for as long as its Space is front. Those
    /// echoes used to be dropped when the window's workspace was not active, leaving the model with
    /// no focused window — and the next `Fn+S` acting on whatever screen it still believed in.
    @Test func echoedFocusOnAFullscreenWindowActivatesItsWorkspace() async {
        let (store, _) = await make(snap([win(a), win(b, fs: true)], focused: a))
        await store.run(.moveWindowToWorkspace(.down))        // a → ws1, which becomes active
        #expect(await store.world.screens["D1"]!.activeIndex == 1)
        await store.apply(.focusChanged(b))                   // first event
        await store.apply(.focusChanged(b))                   // …and its echo
        let w = await store.world
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus.window == b)
    }

    /// Decision 2026-09-15 (#48): a tab is a promise that clicking it delivers the window. A
    /// minimized window used to keep its (dimmed) tab while the click did nothing at all — the
    /// user's Signal window, logged as `minimized=true`, with a tab that led nowhere.
    @Test func clickingAHiddenWindowsTabBringsItBack() async {
        let (store, be) = await make(snap([win(a), win(b, min: true)], focused: a))
        #expect(await store.world.hidden == [b])
        await be.reset()
        await store.run(.focusWindowRef(b))
        let w = await store.world
        #expect(!w.hidden.contains(b) && w.focus.window == b)
        #expect(await be.calls.contains(.unhide(b)))
        #expect(w.invariantViolations().isEmpty)
    }

    /// I6 precedence: a window cannot be both put away and filling a display. Minimizing a
    /// fullscreen window clears the fullscreen flag, and a stale fullscreen report cannot resurrect
    /// it while the window stays minimized — otherwise the layout skips it twice and it is
    /// reachable by nothing.
    @Test func hiddenWinsOverFullscreen() async {
        let (store, _) = await make(snap([win(a), win(b, fs: true)], focused: a))
        #expect(await store.world.fullscreen == [b])
        await store.apply(.snapshot(snap([win(a), win(b, min: true, fs: true)], focused: a)))
        let w = await store.world
        #expect(w.hidden.contains(b) && !w.fullscreen.contains(b))
        #expect(w.invariantViolations().isEmpty)
    }

    /// #52: a run that ends without its §7.4 restore — a crash, an OOM kill, a force quit, or (until
    /// #30) an ordinary SIGTERM — leaves parked windows in a corner, and nothing else will move a
    /// floating one: the reconciler leaves it `.untouched` by design. The boot sweep is the only
    /// thing standing between the user and a window they cannot click.
    @Test func bootRescuesWindowsLeftBeyondReach() async {
        let corner = CGRect(x: 999, y: 699, width: 300, height: 200)   // where the last run parked it
        let be = FakeBackend(snapshot: snap([win(a), win(b, corner, kind: .float)], focused: a))
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: [], onChange: { _ in })
        await store.start()
        let rescued = await be.calls.compactMap { call -> CGRect? in
            if case .setFrame(let r, let f) = call, r == b { return f } else { return nil }
        }.last
        #expect(rescued != nil, "a floating window left off-screen was not rescued")
        #expect(rescued.map { d1.visibleFrame.intersects($0) } == true)
    }

    /// …but a window parked *on purpose* — its workspace is inactive, and the rail is how the user
    /// gets it back — must be left where the reconciler put it. Rescuing those would drag every
    /// inactive workspace onto the screen at boot.
    @Test func bootDoesNotRescueDeliberatelyParkedWindows() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await store.run(.moveWindowToWorkspace(.down))          // a → ws1; b stays parked in ws0
        #expect(await store.debugSideTables().parked.contains(b))
        await be.reset()
        await store.run(.rescueWindows)
        let framed = await be.calls.contains { call in
            if case .setFrame(let r, _) = call { return r == b } else { return false }
        }
        #expect(!framed, "a deliberately parked window was dragged back on screen")
    }

    /// #73: a popup recovered from the rail tray is unhidden, raised and — having ended up off
    /// every display — centred on the focused one. It stays a popup: no workspace, no tab.
    @Test func recoverWindowBringsAPopupBackWithoutFilingIt() async {
        let p = WindowRef(id: 3, pid: 1)
        let popup = CGRect(x: 100, y: 100, width: 300, height: 200)
        let (store, be) = await make(snap([win(a), win(p, popup, kind: .ephemeral)], focused: a))
        await store.apply(.snapshot(snap([win(a), win(p, CGRect(x: 5000, y: 5000, width: 300, height: 200), kind: .ephemeral)],
                                         focused: a)))
        await be.reset()
        await store.run(.recoverWindow(p))
        let calls = await be.calls
        #expect(calls.contains(.unhide(p)) && calls.contains(.raise(p)))
        let rescued = calls.compactMap { call -> CGRect? in
            if case .setFrame(let r, let f) = call, r == p { return f } else { return nil }
        }.last
        #expect(rescued.map { d1.visibleFrame.contains($0) } == true, "the popup was left off every display")
        let w = await store.world
        #expect(w.ephemeral.contains(p) && w.location(of: p) == nil && w.focus.window == p)
    }

    /// #57: counts could not answer "which window is where, and is it parked", so diagnosing a
    /// window that held focus while sitting off-screen meant reading the window server instead of
    /// asking the shell. `spacialctl state` now carries the rows.
    @Test func wireStateCarriesWindowRows() async {
        let (store, _) = await make(snap([win(a, bundle: "com.a"), win(b, bundle: "com.b")], focused: a))
        let state = await store.wireState()
        let row = state.screens[0].workspaces[0].windows
        #expect(row.count == 2)
        #expect(row.first { $0.id == a.id }?.bundleID == "com.a")
        #expect(row.first { $0.id == a.id }?.isFocused == true)
        // `b` is parked under maximize — the fact the model knows and the outside could not see.
        #expect(row.first { $0.id == b.id }?.isParked == true)
        #expect(row.first { $0.id == b.id }?.frame?.count == 4)
        #expect(state.v == 2 && state.capabilities.contains("window-rows"))
    }

    /// I6's corollary, *switching to an app always shows a window* (#56, cause of #57). Measured
    /// live before the fix: activating Finder, whose only window was parked in an inactive
    /// workspace, produced **no store event at all** — macOS named it in the menu bar while the
    /// window stayed at a parking corner, 7% visible.
    @Test func activatingAnAppSurfacesItsParkedWindow() async {
        let other = WindowRef(id: 3, pid: 9)      // a second app, so the row is not trivially active
        let (store, be) = await make(snap([win(a), win(other, bundle: "com.other")], focused: a))
        await store.run(.moveWindowToWorkspace(.down))        // a → ws1, so `other` is left parked in ws0
        #expect(await store.debugSideTables().parked.contains(other))
        #expect(await store.world.screens["D1"]!.activeIndex == 1)
        await be.reset()

        await store.apply(.appActivated(pid: 9))

        let w = await store.world
        #expect(w.screens["D1"]!.activeIndex == 0, "the activated app's workspace was not activated")
        #expect(w.focus.window == other)
        #expect(await be.calls.contains { call in
            if case .setFrame(let r, _) = call { return r == other } else { return false }
        }, "the parked window was never given a frame")
        #expect(w.invariantViolations().isEmpty)
    }

    /// …but an app that already has a visible, focused window must not be disturbed: re-activating
    /// the app you are already in should change nothing.
    @Test func activatingTheAppYouAreAlreadyInChangesNothing() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        let before = await store.world
        await be.reset()
        await store.apply(.appActivated(pid: 1))
        #expect(await store.world == before)
    }

    /// The workspace ping-pong (#NN): "i was switching workspaces and it started repeatedly cycling
    /// different workspaces". Two displays, each already showing a different app. Activating either
    /// app must do nothing — before the fix the test asked whether the activated app owned the
    /// single *global* focus, which is false for whichever display is not focused, so the shell
    /// surfaced an app that was already on screen, switching that display's workspace; the switch
    /// activated the app it left, and the two displays traded workspaces for as long as it ran.
    @Test func anAppAlreadyOnScreenOnAnotherDisplayIsNeverResurfaced() async {
        let d2 = DisplayInfo(id: "D2", frame: CGRect(x: 1000, y: 0, width: 1000, height: 700),
                             visibleFrame: CGRect(x: 1000, y: 25, width: 1000, height: 675), isMain: false)
        let far = WindowRef(id: 7, pid: 9)
        let s = Snapshot(displays: [d1, d2],
                         apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false),
                                AppInfo(pid: 9, bundleID: "com.other", isHidden: false)],
                         windows: [win(a, CGRect(x: 0, y: 0, width: 300, height: 200)),
                                   win(far, CGRect(x: 1000, y: 0, width: 300, height: 200), bundle: "com.other")],
                         focused: a, loginwindowFrontmost: false)
        let (store, be) = await make(s)
        // Each display shows one app, and focus is on D1 — so `far` is on screen but unfocused.
        #expect(await store.world.screens["D2"]!.active.windows == [far])
        let before = await store.world
        await be.reset()

        await store.apply(.appActivated(pid: 9))

        #expect(await store.world == before, "an app that is already on screen was resurfaced")
        #expect(await be.calls.isEmpty, "nothing on screen changed, yet the shell wrote to AX")
    }

    /// The loop's second beat: once an app has been surfaced, every further activation of it —
    /// the echo of our own raise, a second Dock click — must be a no-op. (The visibility test above
    /// is what makes this hold; the `lastRaised` guard in `apply` is belt-and-braces for the case
    /// where the raise failed and the model believes a window is on screen that is not.)
    @Test func reActivatingAnAppAlreadySurfacedChangesNothing() async {
        let other = WindowRef(id: 3, pid: 9)
        let (store, _) = await make(snap([win(a), win(other, bundle: "com.other")], focused: a))
        await store.run(.moveWindowToWorkspace(.down))   // a → ws1; `other` is parked in ws0
        await store.apply(.appActivated(pid: 9))         // a human activation: surfaces `other`
        let surfaced = await store.world
        #expect(surfaced.focus.window == other)

        // macOS now reports the activation our raise of `other` caused. Nothing may move.
        await store.apply(.appActivated(pid: 9))
        #expect(await store.world == surfaced)
    }

    /// The workspace loop, second cause (#69): "i just had it glitch out a ton looping bretween
    /// switching different workspaces". Fast Fn+W/Fn+S raises app X, then app Y, before macOS has
    /// reported X's activation. X's echo then arrives when `lastRaised` is already Y, reads as a
    /// human choosing X, and surfaces X — whose raise echoes after the *next* raise, and so on:
    /// logged live as two apps trading focus ~10×/s. Every recent raise's echo is ours, not just
    /// the last one's.
    @Test func aLateEchoOfAnEarlierRaiseDoesNotSwitchBack() async {
        let other = WindowRef(id: 3, pid: 9)
        let (store, _) = await make(snap([win(a), win(other, bundle: "com.other")], focused: a))
        await store.run(.moveWindowToWorkspace(.down))   // a → ws1; `other` stays in ws0
        await store.run(.focusWorkspace(.up))            // raises `other`
        await store.run(.focusWorkspace(.down))          // raises `a` before `other`'s echo lands
        let settled = await store.world
        #expect(settled.screens["D1"]!.activeIndex == 1 && settled.focus.window == a)

        await store.apply(.appActivated(pid: 9))         // the late echo of raising `other`
        #expect(await store.world == settled, "a stale activation echo switched the workspace back")

        await store.apply(.focusChanged(other))          // …and its late focus echo
        #expect(await store.world.screens["D1"]!.activeIndex == 1, "a stale focus echo switched the workspace back")
    }

    /// #67: the same within one row. Fn+D, Fn+D quickly: the late focus echo of the first raise
    /// must not pull focus back a tab (it did, then the second echo pushed it forward again).
    @Test func aLateEchoInsideTheRowDoesNotStepFocusBack() async {
        let c = WindowRef(id: 3, pid: 1)
        let (store, _) = await make(snap([win(a), win(b), win(c)], focused: a))
        await store.run(.focusWindow(.right))            // raises b
        await store.run(.focusWindow(.right))            // raises c before b's echo lands
        #expect(await store.world.focus.window == c)
        await store.apply(.focusChanged(b))              // b's late echo
        #expect(await store.world.focus.window == c, "a stale in-row echo stepped focus back")
        await store.apply(.focusChanged(c))              // c's own echo: still c
        #expect(await store.world.focus.window == c)
    }

    /// #84: right after Fn+D, macOS re-reports the window it still has (unchanged) before our
    /// raise lands. That report must not pull focus back a tab; a second later, an unchanged
    /// report means macOS really did not move, and the model follows it.
    @Test func aStaleUnchangedReportRightAfterACommandDoesNotPullFocusBack() async {
        final class Clock: @unchecked Sendable { var t = ContinuousClock.now }
        let clock = Clock()
        let c = WindowRef(id: 3, pid: 1)
        let be = FakeBackend(snapshot: snap([win(a), win(b), win(c)], focused: a))
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: [],
                               now: { clock.t }, onChange: { _ in })
        await store.start()
        await store.apply(.focusChanged(a))                 // macOS has a; the model agrees
        await store.run(.focusWindow(.right))               // Fn+D → b
        #expect(await store.world.focus.window == b)
        await store.apply(.focusChanged(a))                 // stale, unchanged: before our raise landed
        #expect(await store.world.focus.window == b, "a stale report pulled focus back a tab")
        clock.t = clock.t.advanced(by: .seconds(2))
        await store.apply(.focusChanged(a))                 // still a, long after: macOS really is on a
        #expect(await store.world.focus.window == a)
    }

    /// The echo allowance is short-lived: long after the raise, activating that app is a human
    /// choice again and surfaces it (#56 must keep working).
    @Test func anActivationLongAfterOurRaiseStillSurfaces() async {
        final class Clock: @unchecked Sendable { var t = ContinuousClock.now }
        let clock = Clock()
        let other = WindowRef(id: 3, pid: 9)
        let be = FakeBackend(snapshot: snap([win(a), win(other, bundle: "com.other")], focused: a))
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: [],
                               now: { clock.t }, onChange: { _ in })
        await store.start()
        await store.run(.moveWindowToWorkspace(.down))
        await store.run(.focusWorkspace(.up))
        await store.run(.focusWorkspace(.down))
        clock.t = clock.t.advanced(by: .seconds(5))

        await store.apply(.appActivated(pid: 9))

        let w = await store.world
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus.window == other)
    }

    /// Records what the store asked the animator to draw, and how many backend writes had already
    /// happened at each step — the overlay must be up before the first frame is written.
    actor FakeAnimator: SwitchAnimator {
        let be: FakeBackend
        let accept: Bool
        var prepared: [[Transition]] = []
        var writesAtPrepare: [Int] = []
        var writesAtPlay: [Int] = []
        /// Runs once, inside the first `prepare` — the seam for "a newer pass lands mid-switch".
        var duringPrepare: (@Sendable () async -> Void)?
        init(be: FakeBackend, accept: Bool = true) { self.be = be; self.accept = accept }
        func setDuringPrepare(_ f: @escaping @Sendable () async -> Void) { duringPrepare = f }
        var since: [ContinuousClock.Instant] = []
        func prepare(_ t: [Transition], trace: SpanContext?, since: ContinuousClock.Instant) async -> Bool {
            prepared.append(t); writesAtPrepare.append(await be.calls.count); self.since.append(since)
            if let f = duringPrepare { duringPrepare = nil; await f() }
            return accept
        }
        func play(trace: SpanContext?) async { writesAtPlay.append(await be.calls.count) }
        var prefetched: [[[Transition]]] = []
        func prefetch(_ predicted: [[Transition]]) async { prefetched.append(predicted) }
    }

    /// #77: the prediction is the planner's own output — Fn+D in a row of three predicts exactly
    /// the transition the real `.focusWindow(.right)` then prepares, and likewise Fn+A (which wraps).
    @Test func thePredictedTabSwitchIsTheOneThatRuns() async {
        let c = WindowRef(id: 3, pid: 1)
        for (slot, command) in [(1, Command.focusWindow(.right)), (0, .focusWindow(.left))] {
            let (store, _, anim) = await makeAnimated(snap([win(a), win(b), win(c)], focused: a))
            let predicted = await anim.prefetched.last?[slot]
            #expect(predicted?.isEmpty == false)
            await store.run(command)
            #expect(await anim.prepared.last == predicted, "\(command)")
        }
    }

    /// Fn+S predicts the slide into the empty row below; Fn+W on the top row has nothing above it,
    /// so it predicts no transition at all. Then, from the lower row, Fn+W is the way back.
    @Test func thePredictedRowSwitchesAreTheOnesThatRun() async {
        let (store, _, anim) = await makeAnimated(snap([win(a), win(b)], focused: a))
        #expect(await store.world.screens["D1"]!.activeIndex == 0)
        let atTop = await anim.prefetched.last
        #expect(atTop?[2] == [], "no row above: nothing to prefetch")
        await store.run(.moveWindowToWorkspace(.down))    // a → ws1, which leaves a row both ways
        let fromBelow = await anim.prefetched.last
        #expect(fromBelow?[2].isEmpty == false)
        await store.run(.focusWorkspace(.up))
        #expect(await anim.prepared.last == fromBelow?[2])
        let back = await anim.prefetched.last
        await store.run(.focusWorkspace(.down))
        #expect(await anim.prepared.last == back?[3])
    }

    /// A finished pass hands the overlay the four predictions; a superseded one does not (the
    /// newer pass that superseded it speaks for the screen). `animations = false` never prefetches.
    @Test func onlyAFinishedPassPrefetches() async {
        let (store, _, anim) = await makeAnimated(snap([win(a), win(b)], focused: a))
        #expect(await anim.prefetched.last?.count == WorldStore.predictedCommands.count)
        let before = await anim.prefetched.count
        await anim.setDuringPrepare { await store.run(.toggleOverview) }
        await store.run(.focusWindow(.right))
        #expect(await anim.prefetched.count == before + 1, "the inner pass prefetches; the superseded outer one must not")

        var off = m1Config(); off.animations = false
        let (quiet, _, idle) = await makeAnimated(snap([win(a), win(b)], focused: a), config: off)
        await quiet.run(.focusWindow(.right))
        #expect(await idle.prefetched.isEmpty)
    }

    /// #97: the overlay measures the latency to the slide from the command, not from its own call.
    @Test func prepareIsToldWhenTheCommandBegan() async {
        let (store, _, anim) = await makeAnimated(snap([win(a), win(b)], focused: a))
        let before = ContinuousClock.now
        await store.run(.focusWindow(.right))
        let since = await anim.since.last
        #expect(since.map { $0 >= before && $0 <= .now } == true)
    }

    func makeAnimated(_ s: Snapshot, config: Config? = nil, accept: Bool = true) async -> (WorldStore, FakeBackend, FakeAnimator) {
        let be = FakeBackend(snapshot: s)
        let anim = FakeAnimator(be: be, accept: accept)
        let store = WorldStore(backend: be, config: config ?? m1Config(), world: nil, zeroSliverBundleIDs: [],
                               animator: anim, onChange: { _ in })
        await store.start()
        return (store, be, anim)
    }

    /// #67: Fn+D under maximize is a transition — the outgoing window leaves left, the incoming
    /// arrives from the right — and the overlay is prepared before any frame is written, then
    /// played once they all are.
    @Test func aTabSwitchIsAnimatedAroundTheWrites() async {
        let (store, be, anim) = await makeAnimated(snap([win(a), win(b)], focused: a))
        #expect(await anim.prepared.isEmpty, "adopting the windows at start is not a switch")
        await be.reset()

        await store.run(.focusWindow(.right))

        let prepared = await anim.prepared
        #expect(prepared.count == 1)
        let moves = prepared.first?.first?.moves ?? []
        #expect(Set(moves.map(\.ref)) == [a, b])
        let out = moves.first { $0.ref == a }, into = moves.first { $0.ref == b }
        #expect(out.map { $0.to.minX < $0.from.minX } == true, "the outgoing window did not leave to the left")
        #expect(into.map { $0.from.minX > $0.to.minX } == true, "the incoming window did not arrive from the right")
        #expect(await anim.writesAtPrepare == [0], "the overlay must be up before the first write")
        let writes = await be.calls.count, atPlay = await anim.writesAtPlay
        #expect(writes > 0 && atPlay == [writes], "play must follow the writes")
    }

    /// #66: Fn+S is a transition too, travelling up.
    @Test func aWorkspaceSwitchIsAnimated() async {
        let (store, _, anim) = await makeAnimated(snap([win(a), win(b)], focused: a))
        await store.run(.moveWindowToWorkspace(.down))    // a → ws1 (a switch itself)
        let before = await anim.prepared.count
        await store.run(.focusWorkspace(.up))             // back to b's row

        let prepared = await anim.prepared
        #expect(prepared.count == before + 1)
        let moves = prepared.last?.first?.moves ?? []
        let into = moves.first { $0.ref == b }
        #expect(into.map { $0.from.minY < $0.to.minY } == true, "going up the rail, the row arrives from above")
    }

    /// A floating window (System Settings, which is not resizable) is part of its row: it leaves
    /// with the row and comes back with it, instead of popping in when the slide lands.
    @Test func aFloatingWindowTravelsWithItsRow() async {
        let (store, _, anim) = await makeAnimated(snap([win(a), win(b, kind: .float)], focused: a))
        await store.run(.moveWindowToWorkspace(.down))    // a → ws1; ws0 (with float b) leaves
        let out = (await anim.prepared.last?.first?.moves ?? []).first { $0.ref == b }
        #expect(out.map { $0.to.minY < $0.from.minY } == true, "going down the rail, the float leaves upward")

        await store.run(.focusWorkspace(.up))
        let back = (await anim.prepared.last?.first?.moves ?? []).first { $0.ref == b }
        #expect(back.map { $0.from.minY < $0.to.minY } == true, "going up the rail, the float arrives from above")
    }

    /// A pass superseded after the overlay is up (the echo of its own raise reconciles again,
    /// routinely) still plays it. It used to return without `play`, and the frozen pictures sat
    /// over the screen until the watchdog cut them: a switch that "did not animate" (#66).
    @Test func aSupersededSwitchStillPlays() async {
        let (store, _, anim) = await makeAnimated(snap([win(a), win(b)], focused: a))
        await anim.setDuringPrepare { await store.run(.toggleOverview) }
        await store.run(.focusWindow(.right))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await anim.prepared.count == 1)
        #expect(await anim.writesAtPlay.count == 1, "the overlay must be played, not left to the watchdog")
    }

    /// `animations = false` places instantly: the animator is never asked.
    @Test func animationsOffNeverPrepares() async {
        var c = m1Config(); c.animations = false
        let (store, _, anim) = await makeAnimated(snap([win(a), win(b)], focused: a), config: c)
        await store.run(.focusWindow(.right))
        #expect(await anim.prepared.isEmpty)
    }

    /// An animator that declines (no grant, a switch mid-flight) gets no `play`, and the switch
    /// still happens.
    @Test func aDeclinedPrepareStillSwitches() async {
        let (store, _, anim) = await makeAnimated(snap([win(a), win(b)], focused: a), accept: false)
        await store.run(.focusWindow(.right))
        #expect(await anim.prepared.count == 1)
        #expect(await anim.writesAtPlay.isEmpty)
        #expect(await store.world.focus.window == b)
    }

    @Test func minimizedIsHidden() async {
        let (store, _) = await make(snap([win(a), win(b, min: true)], focused: a))
        #expect(await store.world.hidden == [b])
    }
    @Test func ephemeralIsCenteredOnAdoption() async {
        let (_, be) = await make(snap([win(a, CGRect(x: 0, y: 0, width: 400, height: 300), bundle: "com.apple.calculator")], focused: nil))
        #expect(await be.calls.contains(.setFrame(a, CGRect(x: 300, y: 212.5, width: 400, height: 300))))
    }
    @Test func commandCloseCallsBackend() async {
        let (store, be) = await make(snap([win(a)], focused: a))
        await store.run(.closeFocusedWindow)
        #expect(await be.calls.contains(.close(a)))
    }
    @Test func interleavedSnapshotDuringPlanDoesNotResurrectSideTables() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.reset()
        await be.armGate(onWriteNumber: 1)                       // plan is [setFrame(b), setPosition(a)]
        let run = Task { await store.run(.focusWindow(.right)) }
        while await !be.isGateArmed() { try? await Task.sleep(for: .milliseconds(5)) }
        await store.apply(.snapshot(snap([win(b)], focused: b)))  // a vanished while our plan is mid-flight
        await be.releaseGate()
        await run.value
        let w = await store.world
        #expect(w.location(of: a) == nil && !w.ignored.contains(a))
        let tables = await store.debugSideTables()
        #expect(!tables.parked.contains(a) && tables.prePark[a] == nil && tables.observed[a] == nil)
        #expect(await !be.calls.contains(.setPosition(a, CGPoint(x: 999, y: 699))))   // stale write never issued
    }
    @Test func intentEchoDoesNotAbortInFlightPlan() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.reset()
        await be.armGate(onWriteNumber: 1)                       // plan is [setFrame(b), setPosition(a)]
        let run = Task { await store.run(.focusWindow(.right)) }
        while await !be.isGateArmed() { try? await Task.sleep(for: .milliseconds(5)) }
        let planned = CGRect(x: 8, y: 33, width: 984, height: 658)
        await store.apply(.windowMoved(b, planned))              // AX echo of the very write in flight
        await be.releaseGate()
        await run.value
        let calls = await be.calls
        #expect(calls.contains(.setFrame(b, planned)))
        #expect(calls.contains(.setPosition(a, CGPoint(x: 999, y: 699))))   // plan ran to completion
    }
    @Test func threeFailedWritesMoveWindowToIgnored() async {
        let (store, be) = await make(snap([win(a)], focused: a))
        await be.fail(a)
        for y in [100.0, 200.0, 300.0] {
            await store.apply(.windowMoved(a, CGRect(x: y, y: y, width: 984, height: 658)))
        }
        #expect(await store.world.ignored.contains(a))
        #expect(await store.world.location(of: a) == nil)
        await be.reset()
        await store.apply(.snapshot(snap([win(a)], focused: nil)))       // stays ignored, never placed again
        let calls = await be.calls
        #expect(!calls.contains { touches($0, a) })
    }
    @Test func commandsAreIgnoredWhileLocked() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await store.apply(.screenLocked)
        await be.reset()
        await store.run(.focusWindow(.right))
        #expect(await be.calls.isEmpty)
        #expect(await store.world.focus.window == a)
        await store.apply(.screenUnlocked)
        await be.reset()
        await store.run(.focusWindow(.right))
        #expect(await store.world.focus.window == b)
        #expect(await !be.calls.isEmpty)
    }
    /// Spec §7.7 freeze. Setting `locked` only stops the *next* pass from starting — a plan
    /// already mid-flight kept writing frames at a locked screen, where AX reports the lock
    /// screen's geometry rather than the user's. The lock now bumps `generation`, which is the
    /// signal every await in `reconcile()` already checks.
    @Test func lockMidPlanStopsFurtherWrites() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.reset()
        await be.armGate(onWriteNumber: 1)                       // plan is [setFrame(b), setPosition(a)]
        let run = Task { await store.run(.focusWindow(.right)) }
        while await !be.isGateArmed() { try? await Task.sleep(for: .milliseconds(5)) }
        await store.apply(.screenLocked)                         // the screen locks mid-plan
        await be.releaseGate()
        await run.value
        // The write that was already in flight lands; nothing after it is issued.
        #expect(await be.calls == [.setFrame(b, CGRect(x: 8, y: 33, width: 984, height: 658))])
    }
    @Test func onChangeFiresWithWorld() async {
        let be = FakeBackend(snapshot: snap([win(a)], focused: a))
        let box = ChangeBox()
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: [], onChange: { w in Task { await box.set(w) } })
        await store.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await box.value?.screens["D1"]?.active.windows == [a])
    }

    /// Deferred from Task 13's review: a store-level counterpart to `PropertyTests`, which drives
    /// `World` directly. This drives the actor through `FakeBackend`, so it also exercises
    /// adoption-from-snapshot, vanish-on-refresh, native focus, and the parking side tables —
    /// everything `PropertyTests` cannot see because it never goes through `WorldStore`.
    struct LiveWindow { var ref: WindowRef; var kind: WindowKind; var minimized = false; var fullscreen = false; var offSpace = false; var parent: WindowRef? }

    func randomSnapshot(_ live: [LiveWindow], focused: WindowRef?) -> Snapshot {
        snap(live.map { win($0.ref, kind: $0.kind, min: $0.minimized, fs: $0.fullscreen, parent: $0.parent, onSpace: !$0.offSpace) }, focused: focused)
    }

    @Test(arguments: 0..<50)
    func randomSnapshotsPreserveInvariants(seed: Int) async {
        var rng = TestRNG(seed: UInt64(seed) &+ 7_000)
        let be = FakeBackend(snapshot: snap([]))
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: ["us.zoom.xos"], onChange: { _ in })
        await store.start()

        let cmds: [Command] = [
            .focusWorkspace(.up), .focusWorkspace(.down), .focusWorkspaceIndex(Int.random(in: 1...4, using: &rng)),
            .focusWindow(.left), .focusWindow(.right), .closeFocusedWindow,
            .moveWindow(.left), .moveWindow(.right), .moveWindowToWorkspace(.up), .moveWindowToWorkspace(.down),
            .cycleLayout, .toggleShellUI, .focusScreen(.prev), .focusScreen(.next),
            .moveWindowToScreen(.prev), .moveWindowToScreen(.next), .toggleFloat,
        ]
        var live: [LiveWindow] = []
        var nextID: WindowID = 1

        for step in 0..<30 {
            switch Int.random(in: 0..<10, using: &rng) {
            case 0...3:   // snapshot event: mutate the live-window set, then resend it whole
                switch Int.random(in: 0..<5, using: &rng) {
                case 0 where live.count < 10:
                    let kind: WindowKind = [.tile, .tile, .tile, .float, .ephemeral, .ignore].randomElement(using: &rng)!
                    let parent = Bool.random(using: &rng) ? live.randomElement(using: &rng)?.ref : nil
                    live.append(LiveWindow(ref: WindowRef(id: nextID, pid: 1), kind: kind, parent: parent))
                    nextID += 1
                case 1 where !live.isEmpty:
                    live.remove(at: Int.random(in: 0..<live.count, using: &rng))
                case 2 where !live.isEmpty:
                    live[Int.random(in: 0..<live.count, using: &rng)].minimized.toggle()
                case 3 where !live.isEmpty:
                    live[Int.random(in: 0..<live.count, using: &rng)].fullscreen.toggle()
                case 4 where !live.isEmpty:
                    live[Int.random(in: 0..<live.count, using: &rng)].offSpace.toggle()
                default: break   // list too small/large for the picked mutation: resend unchanged
                }
                let focused = live.isEmpty ? nil : (Bool.random(using: &rng) ? live.randomElement(using: &rng)?.ref : nil)
                await store.apply(.snapshot(randomSnapshot(live, focused: focused)))
            case 4...6:   // run a random command
                await store.run(cmds.randomElement(using: &rng)!)
            default:   // external move (AX echo or a real drag)
                if let l = live.randomElement(using: &rng) {
                    let f = CGRect(x: Double.random(in: 0...500, using: &rng), y: Double.random(in: 0...500, using: &rng), width: 300, height: 200)
                    await store.apply(.windowMoved(l.ref, f))
                }
            }
            let w = await store.world   // bind before calling: `#expect((await store.world).invariantViolations()...)` doesn't compile.
            let v = w.invariantViolations()
            #expect(v.isEmpty, "seed \(seed) step \(step): \(v)")
            if !v.isEmpty { return }
        }
    }

    /// Clicking the rail's "+" activates the trailing empty workspace. Nothing focuses there — an
    /// empty workspace has no window — so native focus legitimately stays where it was. The
    /// click's own mouse-up then schedules a refresh (`AXWindowBackend` global monitor), and the
    /// snapshot it produces reports that *unchanged* focus. `applyNativeFocus` used to treat the
    /// echo as news and re-activate the old workspace, so the new one bounced away before the
    /// user could put anything in it. An unchanged focus is news about nothing.
    @Test func activatingAnEmptyWorkspaceSurvivesAnEchoSnapshot() async {
        let (store, _) = await make(snap([win(a), win(b)], focused: a))
        let trailing = await store.world.screens["D1"]!.workspaces.last!.id
        await store.run(.focusWorkspaceID(trailing))
        #expect(await store.world.screens["D1"]!.activeIndex == 1)   // the empty workspace
        #expect(await store.world.focus.window == nil)               // nothing there to focus

        // The echo: same windows, same focused window — nothing actually changed.
        await store.apply(.snapshot(snap([win(a), win(b)], focused: a)))
        #expect(await store.world.screens["D1"]!.activeIndex == 1)   // still there
    }

    /// The other half of the same rule: a focus change that is *real* must still pull the active
    /// workspace across, or clicking a window in another workspace would stop switching to it.
    @Test func aRealFocusChangeStillMovesTheActiveWorkspace() async {
        let (store, _) = await make(snap([win(a), win(b)], focused: a))
        await store.run(.moveWindowToWorkspace(.down))                // a → ws1, which goes active
        let ws0 = await store.world.screens["D1"]!.workspaces[0].id
        await store.run(.focusWorkspaceID(ws0))                       // back to ws0, where b lives
        await store.apply(.snapshot(snap([win(a), win(b)], focused: b)))   // world settles on b
        #expect(await store.world.screens["D1"]!.activeIndex == 0)

        // User clicks `a`, which lives on ws1. Genuinely new focus, so the world follows it.
        await store.apply(.snapshot(snap([win(a), win(b)], focused: a)))
        #expect(await store.world.screens["D1"]!.activeIndex == 1)
        #expect(await store.world.focus.window == a)
    }

    // MARK: placement memory (issue #5)

    /// A relaunch: the state file's placements are handed to the store, and the first snapshot
    /// adopts each app back into the workspace it was in — while an app the state has never seen
    /// still lands by today's rules, in the active workspace.
    @Test func rememberedAppsAreAdoptedBackIntoTheirWorkspace() async {
        var c = m1Config(); c.workspaces = [WorkspaceSeed(name: "Code"), WorkspaceSeed(name: "Web")]
        let seeded = World.seeded(screens: ["D1"], config: c)
        let web = seeded.screens["D1"]!.workspaces[1].id
        let (store, _) = await make(snap([win(a, bundle: "com.browser"), win(b, bundle: "com.stranger")], focused: b),
                                    config: c, world: seeded, placements: ["com.browser": web])
        let w = await store.world
        #expect(w.screens["D1"]!.workspaces[1].windows == [a])   // remembered
        #expect(w.screens["D1"]!.workspaces[0].windows == [b])   // never seen: active workspace, no error
        #expect(w.invariantViolations().isEmpty)
    }
    /// A placement naming a workspace this world does not have must not resurrect it.
    @Test func aRememberedWorkspaceThatIsGoneFallsBack() async {
        let (store, _) = await make(snap([win(a, bundle: "com.x")], focused: a), placements: ["com.x": UUID()])
        let w = await store.world
        #expect(w.screens["D1"]!.workspaces.count == 2)          // the one it landed in + the trailing empty
        #expect(w.screens["D1"]!.active.windows == [a])
        #expect(w.invariantViolations().isEmpty)
    }
    /// The memory follows the model, so an app quit and reopened later in the session comes back
    /// to where the user last put it — and the state file saved at quit is already current.
    @Test func placementMemoryFollowsTheWindow() async {
        let (store, _) = await make(snap([win(a, bundle: "com.x")], focused: a))
        await store.run(.moveWindowToWorkspace(.down))
        let moved = await store.world.workspace(containing: a)!.id
        #expect(await store.currentPlacements()["com.x"] == moved)
        #expect(await store.exportForTermination().placements["com.x"] != nil)
    }
    // MARK: native macOS window tabs (issue #27)

    /// A native macOS tab group reaches the store as one managed window plus `.ignore` siblings
    /// sitting on the group's single shared frame — the platform layer demotes them, because a
    /// background tab is only recognisable against its siblings. The ignored tabs must draw no
    /// frame write at all: under `maximize` the reconciler would park them in the corner, and
    /// since a tab group shares one frame, parking any member drags the whole group — the tab the
    /// user is looking at included — off-screen. That is the bug this models.
    @Test func ignoredNativeTabsAreNeitherTiledNorParked() async {
        let shared = CGRect(x: 100, y: 100, width: 400, height: 300)
        let (store, be) = await make(snap([win(a, shared), win(b, shared, kind: .ignore)], focused: a))
        let w = await store.world
        #expect(w.screens["D1"]!.active.windows == [a])     // one window in the row, not two
        #expect(w.ignored.contains(b))
        let calls = await be.calls
        #expect(calls.contains(.setFrame(a, CGRect(x: 8, y: 33, width: 984, height: 658))))
        #expect(!calls.contains { touches($0, b) })
    }

    /// Switching tabs: macOS reports focus on the background tab's AX window. It is not in the
    /// model, so the shell must sit still — no re-anchoring, and above all no writes.
    @Test func focusOnAnIgnoredNativeTabMovesNothing() async {
        let shared = CGRect(x: 100, y: 100, width: 400, height: 300)
        let (store, be) = await make(snap([win(a, shared), win(b, shared, kind: .ignore)], focused: a))
        await be.reset()
        await store.apply(.focusChanged(b))
        let w = await store.world
        #expect(w.focus.window == a)
        #expect(await be.calls.isEmpty)
        #expect(w.invariantViolations().isEmpty)
    }

    // MARK: fullscreen focus protection (issue #28)

    final class Clock: @unchecked Sendable { var t = ContinuousClock.now }
    let video = WindowRef(id: 10, pid: 1)       // the fullscreen video, on D1
    let pushy = WindowRef(id: 20, pid: 9)       // a background app that grabs focus by itself

    /// A fullscreen `video` in front on D1, `pushy` in the same workspace behind it, and — when
    /// `twoDisplays` — an empty D2. `fullscreen: false` is the same scene with no fullscreen at all.
    func fullscreenScene(twoDisplays: Bool, fullscreen: Bool = true, clock: Clock = Clock()) async -> (WorldStore, FakeBackend) {
        let d2 = DisplayInfo(id: "D2", frame: CGRect(x: 1000, y: 0, width: 1000, height: 700),
                             visibleFrame: CGRect(x: 1000, y: 25, width: 1000, height: 675), isMain: false)
        let s = Snapshot(displays: twoDisplays ? [d1, d2] : [d1],
                         apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false),
                                AppInfo(pid: 9, bundleID: "com.pushy", isHidden: false)],
                         windows: [win(video, CGRect(x: 0, y: 0, width: 1000, height: 700), fs: fullscreen),
                                   win(pushy, bundle: "com.pushy")],
                         focused: video)
        let be = FakeBackend(snapshot: s)
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: [],
                               now: { clock.t }, onChange: { _ in })
        await store.start()
        #expect(await store.world.focus.window == video)
        await be.reset()
        return (store, be)
    }

    /// The request: a window deciding on its own that it needs focus must not pull the user out of
    /// fullscreen. With a second display free, it goes there — into that display's active
    /// workspace — and the fullscreen window is put back in front.
    @Test func aFocusGrabDuringFullscreenMovesToTheFreeDisplay() async {
        let (store, be) = await fullscreenScene(twoDisplays: true)

        await store.apply(.appActivated(pid: 9))

        var w = await store.world
        #expect(w.screens["D2"]!.active.windows == [pushy], "the requester was not moved to the free display")
        #expect(w.focus.window == video, "the fullscreen window lost the focus")
        #expect(await be.calls.contains(.raise(video)), "the fullscreen window was not put back in front")
        #expect(w.invariantViolations().isEmpty)

        // macOS follows the activation with a focus report for the requester. Same answer.
        await store.apply(.snapshot(await be.currentSnapshot().with(focused: pushy)))
        w = await store.world
        #expect(w.screens["D2"]!.active.windows == [pushy] && w.focus.window == video)
    }

    /// One display: nowhere to send the requester, so the request waits. Fullscreen stays in
    /// front, and the requester gets its focus once fullscreen ends.
    @Test func aFocusGrabOnASingleDisplayIsDeferredUntilFullscreenEnds() async {
        let (store, be) = await fullscreenScene(twoDisplays: false)

        await store.apply(.focusChanged(pushy))

        var w = await store.world
        #expect(w.focus.window == video && w.fullscreen == [video])
        #expect(await be.calls.contains(.raise(video)))
        #expect(w.location(of: pushy)?.screen == "D1", "nothing to move to on one display")

        await be.reset()
        await store.apply(.snapshot(snap([win(video, CGRect(x: 0, y: 0, width: 1000, height: 700)),
                                          win(pushy, bundle: "com.pushy")], focused: video)))   // user leaves fullscreen
        w = await store.world
        #expect(w.fullscreen.isEmpty)
        #expect(w.focus.window == pushy, "the deferred request was not honoured when fullscreen ended")
        #expect(await be.calls.contains(.raise(pushy)))
        #expect(w.invariantViolations().isEmpty)
    }

    /// A focus change right after a key press or a click is the user's own doing, and goes through
    /// exactly as it always has — until the input window runs out.
    @Test func aFocusChangeRightAfterHumanInputGoesThrough() async {
        let clock = Clock()
        let (store, _) = await fullscreenScene(twoDisplays: true, clock: clock)

        await store.apply(.humanInput)
        clock.t = clock.t.advanced(by: .milliseconds(500))
        await store.apply(.focusChanged(pushy))

        let w = await store.world
        #expect(w.focus.window == pushy, "a human focus change was overridden")
        #expect(w.location(of: pushy)?.screen == "D1", "a human focus change moved the window")

        // Long after the input, the same thing is an intrusion again.
        let (late, _) = await fullscreenScene(twoDisplays: true, clock: clock)
        await late.apply(.humanInput)
        clock.t = clock.t.advanced(by: .seconds(2))
        await late.apply(.focusChanged(pushy))
        #expect(await late.world.focus.window == video)
    }

    /// No fullscreen anywhere: nothing about focus handling changes.
    @Test func withoutFullscreenAFocusGrabIsHonoured() async {
        let (store, _) = await fullscreenScene(twoDisplays: true, fullscreen: false)

        await store.apply(.focusChanged(pushy))

        let w = await store.world
        #expect(w.focus.window == pushy)
        #expect(w.location(of: pushy)?.screen == "D1")
        #expect(w.screens["D2"]!.active.windows.isEmpty)
    }

    // MARK: which display a window belongs to (issue #57)

    var d2: DisplayInfo {
        DisplayInfo(id: "D2", frame: CGRect(x: 1000, y: 0, width: 1000, height: 700),
                    visibleFrame: CGRect(x: 1000, y: 25, width: 1000, height: 675), isMain: false)
    }
    /// D1's and D2's single-window tile, in `m1Config` geometry.
    var tileD1: CGRect { CGRect(x: 8, y: 33, width: 984, height: 658) }
    var tileD2: CGRect { CGRect(x: 1008, y: 33, width: 984, height: 658) }
    func twoDisplays(_ ws: [WindowSnapshot], focused: WindowRef?) -> Snapshot {
        Snapshot(displays: [d1, d2], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false)], windows: ws, focused: focused)
    }
    func writes(_ r: WindowRef, _ calls: [FakeBackend.Call]) -> [CGRect] {
        calls.compactMap { if case .setFrame(r, let f) = $0 { f } else { nil } }
    }

    /// #72: macOS owns a fullscreen window's display. Found fullscreen on D2 while the model files
    /// it under D1, the model follows — so D2 (not D1) is the display showing fullscreen, and D1's
    /// panels stay up.
    @Test func aFullscreenWindowIsFiledUnderTheDisplayItIsOn() async {
        let (store, _) = await make(twoDisplays([win(a), win(b)], focused: a))
        #expect(await store.world.location(of: b)?.screen == "D1")
        await store.apply(.snapshot(twoDisplays([win(a), win(b, d2.frame, fs: true)], focused: a)))
        let w = await store.world
        #expect(w.location(of: b)?.screen == "D2")
        #expect(w.showsFullscreenSpace("D2") && !w.showsFullscreenSpace("D1"))
    }

    /// Nothing moves a floating window back, so one found on another display takes its tab there.
    @Test func aFloatingWindowFoundOnAnotherDisplayTakesItsTabThere() async {
        let (store, be) = await make(twoDisplays([win(a), win(b, kind: .float)], focused: a))
        await be.reset()
        let there = CGRect(x: 1200, y: 100, width: 300, height: 200)
        await store.apply(.snapshot(twoDisplays([win(a), win(b, there, kind: .float)], focused: a)))
        #expect(await store.world.location(of: b)?.screen == "D2")
        #expect(writes(b, await be.calls).isEmpty, "a floating window is never moved")
    }

    /// Moving a floating window to another display moves the window, not just its tab: it is
    /// written centred onto the new display, so the frame-owner rule does not file it straight
    /// back (System Settings bounced between displays and ended up parked out of sight).
    @Test func movingAFloatingWindowToAnotherDisplayCarriesItThere() async {
        let (store, be) = await make(twoDisplays([win(a), win(b, kind: .float)], focused: b))
        await store.run(.focusWindowRef(b))
        await be.reset()
        await store.run(.moveWindowToScreen(.next))
        #expect(await store.world.location(of: b)?.screen == "D2")
        let landed = writes(b, await be.calls).last
        #expect(landed.map { d2.frame.contains(CGPoint(x: $0.midX, y: $0.midY)) } == true, "the window must be written onto D2")
        // The next snapshot finds it there: it stays filed on D2.
        await store.apply(.snapshot(twoDisplays([win(a), win(b, landed!, kind: .float)], focused: b)))
        #expect(await store.world.location(of: b)?.screen == "D2")
    }

    /// #89: System Settings' main window tiles; its alert (not AXStandardWindow) stays a floating
    /// window with no tab, so it cannot push the main window out of a maximize row.
    @Test func systemSettingsAlertDoesNotBecomeATab() async {
        let main = WindowRef(id: 30, pid: 30), alert = WindowRef(id: 31, pid: 30)
        let sp = "com.apple.systempreferences"
        let ws = [WindowSnapshot(ref: main, frame: CGRect(x: 0, y: 0, width: 700, height: 500), title: "Privacy", bundleID: sp,
                                 kind: .float, parent: nil, isMinimized: false, isFullscreen: false, isStandard: true),
                  WindowSnapshot(ref: alert, frame: CGRect(x: 100, y: 100, width: 260, height: 180), title: "", bundleID: sp,
                                 kind: .float, parent: nil, isMinimized: false, isFullscreen: false, isStandard: false)]
        var c = m1Config(); c.tile = Config.defaultTile
        let be = FakeBackend(snapshot: snap(ws, focused: main))
        let store = WorldStore(backend: be, config: c, world: nil, zeroSliverBundleIDs: [], onChange: { _ in })
        await store.start()
        let w = await store.world
        let loc = w.location(of: main)!
        #expect(!w.screens[loc.screen]!.workspaces[loc.index].floating.contains(main), "the main window tiles")
        let aloc = w.location(of: alert)
        #expect(aloc == nil || w.screens[aloc!.screen]!.workspaces[aloc!.index].floating.contains(alert), "the alert must not tile")
    }

    /// Rule 1: a new window placed by memory into a workspace on *another* display is moved there
    /// — the model files it under D2, so the reconciler writes D2's frame, whichever display it
    /// opened on. In an inactive workspace it is parked in D2's corner: model and write agree.
    @Test func aWindowPlacedByMemoryOnAnotherDisplayIsMovedThere() async {
        let seeded = World.seeded(screens: ["D1", "D2"], config: m1Config())
        let remembered = seeded.screens["D2"]!.active.id
        let (store, be) = await make(twoDisplays([win(a)], focused: a), world: seeded, placements: ["com.x": remembered])

        var w = await store.world
        #expect(w.location(of: a)?.screen == "D2")
        #expect(await writes(a, be.calls) == [tileD2], "opened on D1, filed under D2, but never moved there")

        // Now the remembered workspace is inactive: a second window of the app lands in it, parked on D2.
        await store.run(.focusWorkspace(.down))
        #expect(await store.world.screens["D2"]!.active.id != remembered)
        await be.reset()
        await store.apply(.snapshot(twoDisplays([win(a), win(b)], focused: nil)))
        w = await store.world
        #expect(w.location(of: b)?.screen == "D2" && w.workspace(containing: b)?.id == remembered)
        let parks = await be.calls.compactMap { if case .setPosition(b, let o) = $0 { o } else { nil } }
        #expect(parks.count == 1 && parks.allSatisfy { d2.frame.minX...d2.frame.maxX ~= $0.x }, "parked somewhere other than D2: \(parks)")
        #expect(w.invariantViolations().isEmpty)
    }

    /// Rule 2: the user drags a tiled window onto D2. The model follows it into D2's active
    /// workspace, and it is tiled there — not snapped back to D1.
    @Test func aWindowTheUserDragsToAnotherDisplayIsRehomedThere() async {
        let clock = Clock()
        let be = FakeBackend(snapshot: twoDisplays([win(a)], focused: a))
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: [],
                               now: { clock.t }, onChange: { _ in })
        await store.start()
        #expect(await store.world.location(of: a)?.screen == "D1")
        await be.reset()

        await store.apply(.humanInput)                          // mouse down on the title bar
        clock.t = clock.t.advanced(by: .milliseconds(300))
        await store.apply(.windowMoved(a, tileD1.offsetBy(dx: 700, dy: 0)))   // centre now on D2

        let w = await store.world
        #expect(w.location(of: a)?.screen == "D2" && w.screens["D2"]!.active.windows == [a])
        #expect(w.focus == Focus(screen: "D2", window: a))
        #expect(await writes(a, be.calls) == [tileD2], "the dragged window was snapped back instead of rehomed")
        #expect(w.invariantViolations().isEmpty)
    }

    /// Rule 2, floating: the same drag rehomes a floating window, which stays floating and where
    /// the user dropped it.
    @Test func aFloatingWindowDraggedToAnotherDisplayIsRehomedAndLeftWhereDropped() async {
        var c = m1Config(); c.float = [AppRule(bundleId: "com.x")]
        let clock = Clock()
        let be = FakeBackend(snapshot: twoDisplays([win(a)], focused: a))
        let store = WorldStore(backend: be, config: c, world: nil, zeroSliverBundleIDs: [],
                               now: { clock.t }, onChange: { _ in })
        await store.start()
        await be.reset()

        await store.apply(.humanInput)
        await store.apply(.windowMoved(a, CGRect(x: 1200, y: 100, width: 300, height: 200)))

        let w = await store.world
        #expect(w.location(of: a)?.screen == "D2" && w.screens["D2"]!.active.floating == [a])
        #expect(await writes(a, be.calls).isEmpty, "a floating window was moved from where it was dropped")
    }

    /// Rule 3: the model wins whenever the move is not the user's — no recent input, or a frame
    /// that changed size (a drag never does; macOS clamping our write to a minimum size does). The
    /// reconciler puts the window back on the display its tab is on, from a move event or a snapshot.
    @Test func aWindowFoundOnTheWrongDisplayIsMovedBackUnlessTheUserDraggedIt() async {
        let clock = Clock()
        let be = FakeBackend(snapshot: twoDisplays([win(a)], focused: a))
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: [],
                               now: { clock.t }, onChange: { _ in })
        await store.start()
        await be.reset()

        // Input long ago: not a drag.
        await store.apply(.humanInput)
        clock.t = clock.t.advanced(by: .seconds(2))
        await store.apply(.windowMoved(a, tileD1.offsetBy(dx: 700, dy: 0)))
        #expect(await store.world.location(of: a)?.screen == "D1")
        #expect(await be.calls == [.setFrame(a, tileD1)])

        // Recent input, but the frame changed size: not a drag either.
        await be.reset()
        await store.apply(.humanInput)
        await store.apply(.windowMoved(a, CGRect(x: 1100, y: 33, width: 1200, height: 658)))
        #expect(await store.world.location(of: a)?.screen == "D1")
        #expect(await be.calls == [.setFrame(a, tileD1)])

        // A snapshot that finds it on D2 with nobody touching it.
        await be.reset()
        clock.t = clock.t.advanced(by: .seconds(2))
        await store.apply(.snapshot(twoDisplays([win(a, tileD2)], focused: a)))
        #expect(await store.world.location(of: a)?.screen == "D1")
        #expect(await be.calls.contains(.setFrame(a, tileD1)))
    }
}
extension Snapshot {
    func with(focused: WindowRef?) -> Snapshot { var s = self; s.focused = focused; return s }
}
func touches(_ c: FakeBackend.Call, _ r: WindowRef) -> Bool {
    switch c {
    case .setFrame(let x, _), .setPosition(let x, _), .raise(let x), .close(let x), .setFullscreen(let x, _), .unhide(let x): return x == r
    case .warpPointer: return false
    }
}
actor ChangeBox { var value: World?; func set(_ w: World) { value = w }
}
