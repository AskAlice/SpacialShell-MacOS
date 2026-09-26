import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

/// #128 (M3 B4, part 2): placeholder tabs — saved windows that come back as tabs in their slots,
/// and the live windows that take those slots back.
@Suite struct PlaceholderTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)

    /// A world with one row holding `live` then a placeholder per entry of `saved`.
    func world(live: [WindowRef] = [], saved: [(String, String)]) -> (World, [WindowRef]) {
        var w = World.empty(screens: ["D1"], defaultLayout: .split)
        for r in live { w.adopt(r, kind: .tile, on: "D1") }
        let id = w.screens["D1"]!.workspaces[0].id
        let refs = saved.map { w.addPlaceholder(Placeholder(bundleID: $0.0, title: $0.1), to: id)! }
        w.normalize()
        return (w, refs)
    }

    // MARK: identity

    @Test func aPlaceholderRefIsNegativeAndStablePerApp() {
        let p = WindowRef.placeholderPid(bundleID: "com.apple.Terminal")
        #expect(p < 0)
        #expect(p == WindowRef.placeholderPid(bundleID: "com.apple.Terminal"))
        #expect(p != WindowRef.placeholderPid(bundleID: "com.apple.Safari"))
        #expect(WindowRef(id: 1, pid: p).isPlaceholder && !WindowRef(id: 1, pid: 42).isPlaceholder)
        let (_, refs) = world(saved: [("com.apple.Terminal", "a"), ("com.apple.Terminal", "b")])
        #expect(refs[0] != refs[1] && refs[0].pid == refs[1].pid)   // one app, one pid, distinct refs
    }

    // MARK: matching (Veshell / material-shell S9)

    @Test func aWindowNeverMatchesAnotherAppsPlaceholder() {
        let (w, _) = world(saved: [("com.editor", "notes.md")])
        let m = PlaceholderMatch.match([.init(ref: WindowRef(id: 1, pid: 5), bundleID: "com.browser", title: "notes.md")], in: w)
        #expect(m.isEmpty)
    }

    @Test func theSameTitleWinsOverSequence() {
        let (w, refs) = world(saved: [("com.term", "~/a — zsh"), ("com.term", "~/b — zsh")])
        let win = WindowRef(id: 1, pid: 5)
        #expect(PlaceholderMatch.match([.init(ref: win, bundleID: "com.term", title: "~/b — zsh")], in: w) == [win: refs[1]])
    }

    @Test func withoutATitleMatchTheSequenceDecides() {
        let (w, refs) = world(saved: [("com.term", "one"), ("com.term", "two")])
        let x = WindowRef(id: 1, pid: 5), y = WindowRef(id: 2, pid: 5)
        let m = PlaceholderMatch.match([.init(ref: x, bundleID: "com.term", title: "zsh"),
                                        .init(ref: y, bundleID: "com.term", title: "zsh")], in: w)
        #expect(m == [x: refs[0], y: refs[1]])
    }

    /// The tab the user clicked is where the app's next window goes, ahead of the rail order.
    @Test func aPlaceholderWaitingForALaunchIsPreferred() {
        var (w, refs) = world(saved: [("com.term", "one"), ("com.term", "two")])
        w.placeholders[refs[1]]?.launching = true
        let x = WindowRef(id: 1, pid: 5)
        #expect(PlaceholderMatch.match([.init(ref: x, bundleID: "com.term", title: "")], in: w) == [x: refs[1]])
    }

    @Test func moreWindowsThanPlaceholdersLeavesTheRestUnmatched() {
        let (w, refs) = world(saved: [("com.term", "")])
        let x = WindowRef(id: 1, pid: 5), y = WindowRef(id: 2, pid: 5)
        #expect(PlaceholderMatch.match([.init(ref: x, bundleID: "com.term", title: ""),
                                        .init(ref: y, bundleID: "com.term", title: "")], in: w) == [x: refs[0]])
    }

    // MARK: fill

    @Test func aMatchTakesThePlaceholdersSlot() {
        let a = WindowRef(id: 1, pid: 1), c = WindowRef(id: 3, pid: 1)
        var (w, refs) = world(live: [a], saved: [("com.term", "t")])
        w.adopt(c, kind: .tile, on: "D1")                              // row: a, placeholder, c
        let x = WindowRef(id: 9, pid: 7)
        w.fill(refs[0], with: x, kind: .tile)
        #expect(w.screens["D1"]!.workspaces[0].windows == [a, x, c])
        #expect(w.placeholders.isEmpty)
        #expect(w.invariantViolations().isEmpty)
    }

    @Test func aFloatingPlaceholderIsFilledFloating() {
        var w = World.empty(screens: ["D1"], defaultLayout: .split)
        let p = w.addPlaceholder(Placeholder(bundleID: "com.x", title: ""), floating: true, to: w.screens["D1"]!.workspaces[0].id)!
        w.normalize()
        let x = WindowRef(id: 9, pid: 7)
        w.fill(p, with: x, kind: .tile)
        #expect(w.screens["D1"]!.workspaces[0].floating == [x])
        #expect(w.invariantViolations().isEmpty)
    }

    // MARK: I6 — a placeholder never hides a live window

    /// It takes no tile: the layout lays out the live windows as if it were not there, and the
    /// reconciler has nothing to write for it.
    @Test func aPlaceholderTakesNoTileAndIsNeverWritten() {
        let a = WindowRef(id: 1, pid: 1)
        var (w, refs) = world(saved: [("com.term", "t")])
        w.adopt(a, kind: .tile, on: "D1")
        w.screens["D1"]!.workspaces[0].layout = .maximize
        // Even as the row's first tab, in maximize — the one-window layout it would crowd out.
        w.screens["D1"]!.workspaces[0].windows = [refs[0], a]
        w.normalize()
        let desired = Reconciler.desired(world: w, displays: [d1], config: LayoutConfig(gap: 8), observed: [:], prePark: [:],
                                         parkedNow: [], zeroSliver: [])
        #expect(desired[refs[0]] == nil)
        if case .frame? = desired[a] {} else { Issue.record("the live window lost its tile to a placeholder: \(String(describing: desired[a]))") }
        #expect(w.focus.window == a && w.screens["D1"]!.workspaces[0].anchor == a)
        #expect(w.invariantViolations().isEmpty)
    }

    @Test func invariantsCatchAFocusedOrStrayPlaceholder() {
        var (w, refs) = world(live: [WindowRef(id: 1, pid: 1)], saved: [("com.term", "t")])
        w.focus.window = refs[0]
        #expect(w.invariantViolations().contains { $0.contains("is a placeholder") })
        w.normalize()
        #expect(w.invariantViolations().isEmpty)                        // normalize puts focus on a window
        var stray = w
        stray.screens["D1"]!.workspaces[0].windows.append(WindowRef(id: 77, pid: -5))
        #expect(stray.invariantViolations().contains { $0.contains("no placeholder") })
    }

    // MARK: commands

    @Test func clickingAPlaceholderLaunchesItsAppAndMarksIt() {
        let a = WindowRef(id: 1, pid: 1)
        let (w, refs) = world(live: [a], saved: [("com.term", "t")])
        let (next, effects) = CommandRunner.apply(.focusWindowRef(refs[0]), to: w)
        #expect(effects.contains(.launch("com.term")))
        #expect(next.placeholders[refs[0]]?.launching == true)
        #expect(next.focus.window == a)                                  // focus stays on a window
        #expect(next.invariantViolations().isEmpty)
    }

    @Test func closingAPlaceholderForgetsItsSlot() {
        let a = WindowRef(id: 1, pid: 1)
        let (w, refs) = world(live: [a], saved: [("com.term", "t")])
        let (next, effects) = CommandRunner.apply(.closeWindowRef(refs[0]), to: w)
        #expect(!effects.contains(.close(refs[0])))                      // nothing to ask the backend
        #expect(next.placeholders.isEmpty && next.screens["D1"]!.workspaces[0].windows == [a])
        #expect(next.invariantViolations().isEmpty)
    }

    @Test func keyboardNavigationStepsOverPlaceholders() {
        let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1)
        var (w, _) = world(live: [a], saved: [("com.term", "t")])
        w.adopt(b, kind: .tile, on: "D1")                              // row: a, placeholder, b
        let (next, _) = CommandRunner.apply(.focusWindow(.right), to: w)
        #expect(next.focus.window == b)
    }

    @Test func tabNOnAPlaceholderOpensIt() {
        let a = WindowRef(id: 1, pid: 1)
        let (w, _) = world(live: [a], saved: [("com.term", "t")])
        let (_, effects) = CommandRunner.apply(.focusTab(2), to: w)
        #expect(effects.contains(.launch("com.term")))
    }

    /// A tab drag onto a rail row moves a placeholder like any tab; focus has nothing to follow.
    @Test func aPlaceholderMovesBetweenRowsWithoutTakingFocus() {
        let a = WindowRef(id: 1, pid: 1)
        var (w, refs) = world(live: [a], saved: [("com.term", "t")])
        let other = w.screens["D1"]!.workspaces[1].id                   // the trailing "+" row
        for follow in [false, true] {
            let (next, _) = CommandRunner.apply(.moveWindowRefToWorkspace(refs[0], other, follow: follow), to: w)
            #expect(next.workspace(containing: refs[0])?.id == other)
            #expect(next.focus.window == a && next.screens["D1"]!.activeIndex == 0)
            #expect(next.invariantViolations().isEmpty)
        }
        w = CommandRunner.apply(.moveWindowRefBefore(refs[0], a), to: w).0
        #expect(w.screens["D1"]!.workspaces[0].windows == [refs[0], a])
    }

    /// It has no window to float. (It does swap, since #129 — see `PinnedTabTests`.)
    @Test func aPlaceholderDoesNotFloat() {
        let a = WindowRef(id: 1, pid: 1)
        let (w, refs) = world(live: [a], saved: [("com.term", "t")])
        #expect(CommandRunner.run(.toggleFloatRef(refs[0]), on: w).world == w)
    }

    // MARK: persistence

    @Test func savedTabsComeBackAsPlaceholdersInTheirSlots() throws {
        let a = WindowRef(id: 1, pid: 10), b = WindowRef(id: 2, pid: 11), c = WindowRef(id: 3, pid: 12)
        var w = World.empty(screens: ["D1"], defaultLayout: .split)
        for r in [a, b, c] { w.adopt(r, kind: .tile, on: "D1") }
        w.setFloating(b, true)
        let state = PersistedState(world: w, bundleIDs: [a: "com.term", b: "com.notes", c: "com.term"],
                                   titles: [a: "~/a — zsh", b: "Groceries", c: "~/c — zsh"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("spacial-\(UUID()).json")
        try state.save(to: url)
        let loaded = try #require(try PersistedState.load(from: url))
        #expect(loaded == state)

        let fresh = loaded.restore(into: World.empty(screens: ["D1"], defaultLayout: .split))
        let row = fresh.screens["D1"]!.workspaces[0]
        #expect(row.id == w.screens["D1"]!.workspaces[0].id)           // kept without any placement naming it
        #expect(row.windows.count == 3 && row.windows.allSatisfy(\.isPlaceholder))
        #expect(row.windows.map { fresh.placeholders[$0]!.title } == ["~/a — zsh", "Groceries", "~/c — zsh"])
        #expect(row.floating == [row.windows[1]])
        #expect(fresh.focus.window == nil)
        #expect(fresh.invariantViolations().isEmpty)
    }

    /// Placeholders that were never matched are saved again, so they survive a second relaunch.
    @Test func anUnmatchedPlaceholderIsSavedAgain() {
        let (w, _) = world(saved: [("com.term", "t")])
        let again = PersistedState(world: w).restore(into: World.empty(screens: ["D1"], defaultLayout: .split))
        #expect(again.placeholders.values.map(\.title) == ["t"])
    }

    /// Backward compatibility: a state file from before #128 has no `windows` on any row. It
    /// loads, restores with no placeholders, and a row with no tabs still writes no `windows` key —
    /// so the file an old build reads back is the file it wrote.
    @Test func aStateFileFromBeforePlaceholdersStillLoads() throws {
        let json = #"""
        {"version":1,"zen":false,"placements":{"com.x":"00000000-0000-0000-0000-000000000001"},
         "screens":{"D1":{"activeIndex":0,"workspaces":[
           {"id":"00000000-0000-0000-0000-000000000001","name":"Code","symbol":"terminal","layout":"split","pinned":false}]}}}
        """#
        let loaded = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        #expect(loaded.screens["D1"]!.workspaces[0].windows == nil)
        let fresh = loaded.restore(into: World.empty(screens: ["D1"], defaultLayout: .split))
        #expect(fresh.placeholders.isEmpty)
        #expect(fresh.screens["D1"]!.workspaces[0].reserved)            // the #5 placement hold, unchanged
        #expect(fresh.invariantViolations().isEmpty)

        let written = String(decoding: try JSONEncoder().encode(PersistedState(world: fresh)), as: UTF8.self)
        #expect(!written.contains("\"windows\""))
    }

    // MARK: the store

    func win(_ r: WindowRef, bundle: String, title: String = "t") -> WindowSnapshot {
        WindowSnapshot(ref: r, frame: CGRect(x: 0, y: 0, width: 300, height: 200), title: title, bundleID: bundle,
                       kind: .tile, parent: nil, isMinimized: false, isFullscreen: false)
    }
    func snap(_ ws: [WindowSnapshot]) -> Snapshot {
        Snapshot(displays: [d1], apps: [], windows: ws, focused: ws.first?.ref)
    }
    func config() -> Config { var c = Config(); c.showPanels = false; c.categoryOrder = []; return c }

    /// The whole #128 loop: relaunch with a saved row, the app's window arrives and takes its slot;
    /// the one that does not come back stays a placeholder, survives every snapshot, and is never
    /// written to.
    @Test func aRelaunchedWindowTakesItsSlotAndTheRestWait() async {
        let (restored, refs) = world(saved: [("com.term", "~/a — zsh"), ("com.notes", "Groceries")])
        let term = WindowRef(id: 50, pid: 5)
        let be = FakeBackend(snapshot: snap([win(term, bundle: "com.term", title: "~/a — zsh")]))
        let store = WorldStore(backend: be, config: config(), world: restored, zeroSliverBundleIDs: [], onChange: { _, _ in })
        await store.start()
        var w = await store.world
        #expect(w.screens["D1"]!.workspaces[0].windows == [term, refs[1]])
        #expect(w.placeholders.keys.sorted { $0.id < $1.id } == [refs[1]])
        #expect(w.focus.window == term)
        #expect(w.invariantViolations().isEmpty)

        await store.apply(.snapshot(snap([win(term, bundle: "com.term", title: "~/a — zsh")])))
        w = await store.world
        #expect(w.placeholders[refs[1]] != nil, "a placeholder vanished with the snapshot")
        #expect(!(await be.calls).contains { touches($0, refs[1]) })

        // Clicking it asks the backend to open the app; its window then fills the slot.
        await store.run(.focusWindowRef(refs[1]))
        #expect(await be.calls.contains(.launch("com.notes")))
        let notes = WindowRef(id: 60, pid: 6)
        await store.apply(.snapshot(snap([win(term, bundle: "com.term", title: "~/a — zsh"), win(notes, bundle: "com.notes")])))
        w = await store.world
        #expect(w.screens["D1"]!.workspaces[0].windows == [term, notes])
        #expect(w.placeholders.isEmpty)
        #expect(w.invariantViolations().isEmpty)
    }

    /// The snapshot feed and `spacialctl state` name a placeholder's app and title, and flag it.
    @Test func theFeedsFlagPlaceholders() {
        let a = WindowRef(id: 1, pid: 1)
        let (w, refs) = world(live: [a], saved: [("com.term", "~/a — zsh")])
        let snapshot = ShellSnapshot(world: w, generation: 1, displays: [d1], config: config(), layouts: .builtins,
                                     titles: [:], appNames: [:], bundleIDs: [a: "com.x"], locked: false)
        let rows = snapshot.screens[0].windows
        #expect(rows.first { $0.window == refs[0] }?.isPlaceholder == true)
        #expect(rows.first { $0.window == refs[0] }?.bundleID == "com.term")
        #expect(rows.first { $0.window == a }?.isPlaceholder == nil)
        #expect(snapshot.titles[refs[0]] == "~/a — zsh")
        let wire = WireState(world: w, bundleIDs: [a: "com.x"])
        #expect(wire.screens[0].workspaces[0].windows.map { $0.isPlaceholder } == [nil, true])

        let tabs = ShellUI.state(for: "D1", in: w, titles: snapshot.titles)!.tabs
        #expect(tabs.map(\.isPlaceholder) == [false, true])
        #expect(tabs[1].title == "~/a — zsh")
    }
}
