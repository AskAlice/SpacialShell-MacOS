import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

/// #129 (material-shell P17, M2): pinned tabs, and placeholders dragged like windows.
@Suite struct PinnedTabTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 2)

    /// One row: a, b, c, focus on b.
    func row() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .split)
        for r in [a, b, c] { w.adopt(r, kind: .tile, on: "D1") }
        return CommandRunner.apply(.focusWindowRef(b), to: w, in: .test()).0
    }

    // MARK: pin / unpin

    @Test func theTabMenuPinsAndUnpinsAnyTab() {
        var w = row()
        w = CommandRunner.apply(.togglePinRef(c), to: w, in: .test()).0
        #expect(w.pinnedTabs == [c] && w.focus.window == b)             // focus and rows stay put
        w = CommandRunner.apply(.togglePinRef(c), to: w, in: .test()).0
        #expect(w.pinnedTabs.isEmpty)
        #expect(w.invariantViolations().isEmpty)
    }

    @Test func togglePinActsOnTheFocusedWindowAndHasAName() {
        let w = CommandRunner.apply(.togglePin, to: row(), in: .test()).0
        #expect(w.pinnedTabs == [b])
        #expect(KeyBindings.command(named: "toggle-pin") == .togglePin)
        #expect(KeyBindings.chords(for: .togglePin, config: Config()).isEmpty)   // unbound by default
        var empty = World.empty(screens: ["D1"], defaultLayout: .split)
        empty.normalize()
        #expect(CommandRunner.run(.togglePin, on: empty, in: .test()).report == .failed(.noFocusedWindow))
    }

    // MARK: a pinned window that closes leaves a placeholder

    @Test func aClosedPinnedWindowLeavesAPlaceholderInItsSlot() {
        var w = CommandRunner.apply(.togglePinRef(b), to: row(), in: .test()).0
        w.setFloating(b, true)
        let left = w.leavePlaceholder(for: b, bundleID: "com.notes", title: "Groceries")
        guard let p = left else { Issue.record("no placeholder left"); return }
        let ws = w.screens["D1"]!.workspaces[0]
        #expect(ws.windows == [a, p, c])
        #expect(ws.floating == [p])
        #expect(w.placeholders[p] == Placeholder(bundleID: "com.notes", title: "Groceries"))
        #expect(w.pinnedTabs == [p])
        #expect(w.focus.window == a)                                     // to the neighbour, as a close
        #expect(w.invariantViolations().isEmpty)
    }

    @Test func anUnpinnedWindowLeavesNothing() {
        let before = row()
        var w = before
        #expect(w.leavePlaceholder(for: b, bundleID: "com.notes", title: "") == nil)
        #expect(w == before)
    }

    @Test func aPinnedPlaceholderCannotBeClosedUntilUnpinned() {
        var w = CommandRunner.apply(.togglePinRef(b), to: row(), in: .test()).0
        let p = w.leavePlaceholder(for: b, bundleID: "com.notes", title: "")!
        let refused = CommandRunner.run(.closeWindowRef(p), on: w, in: .test())
        #expect(refused.world.placeholders[p] != nil)
        if case .noop = refused.report {} else { Issue.record("closing a pinned placeholder: \(refused.report)") }
        w = CommandRunner.apply(.togglePinRef(p), to: w, in: .test()).0
        w = CommandRunner.apply(.closeWindowRef(p), to: w, in: .test()).0
        #expect(w.placeholders.isEmpty && w.screens["D1"]!.workspaces[0].windows == [a, c])
        #expect(w.invariantViolations().isEmpty)
    }

    /// The pin belongs to the slot: the window that comes back into it is pinned too.
    @Test func thePinStaysWithTheSlotWhenItsWindowComesBack() {
        var w = CommandRunner.apply(.togglePinRef(b), to: row(), in: .test()).0
        let p = w.leavePlaceholder(for: b, bundleID: "com.notes", title: "")!
        let back = WindowRef(id: 9, pid: 9)
        w.fill(p, with: back, kind: .tile)
        #expect(w.pinnedTabs == [back])
        #expect(w.screens["D1"]!.workspaces[0].windows == [a, back, c])
        #expect(w.invariantViolations().isEmpty)
    }

    /// Through the store: the window disappears from the snapshot (its app quit, or it was closed)
    /// and its pinned tab stays, as a placeholder that a later window of the app fills.
    @Test func theStoreKeepsAPinnedTabWhenItsWindowVanishes() async {
        func win(_ r: WindowRef, _ bundle: String) -> WindowSnapshot {
            WindowSnapshot(ref: r, frame: CGRect(x: 0, y: 0, width: 300, height: 200), title: "doc", bundleID: bundle,
                           kind: .tile, parent: nil, isMinimized: false, isFullscreen: false)
        }
        func snap(_ ws: [WindowSnapshot]) -> Snapshot { Snapshot(displays: [d1], apps: [], windows: ws, focused: ws.first?.ref) }
        var config = Config(); config.showPanels = false; config.categoryOrder = []
        let be = FakeBackend(snapshot: snap([win(a, "com.a"), win(c, "com.c")]))
        let store = WorldStore(backend: be, config: config, world: nil, zeroSliverBundleIDs: [], onChange: { _, _ in })
        await store.start()
        await store.run(.togglePinRef(c))
        await store.apply(.snapshot(snap([win(a, "com.a")])))
        var w = await store.world
        let row = w.screens["D1"]!.workspaces[0].windows
        #expect(row.count == 2 && row[0] == a && row[1].isPlaceholder)
        #expect(w.placeholders[row[1]]?.bundleID == "com.c" && w.placeholders[row[1]]?.title == "doc")
        #expect(w.pinnedTabs == [row[1]])
        #expect(w.invariantViolations().isEmpty)

        let again = WindowRef(id: 30, pid: 3)
        await store.apply(.snapshot(snap([win(a, "com.a"), win(again, "com.c")])))
        w = await store.world
        #expect(w.screens["D1"]!.workspaces[0].windows == [a, again])
        #expect(w.pinnedTabs == [again])
    }

    // MARK: persistence

    @Test func pinsSurviveARelaunch() throws {
        let w = CommandRunner.apply(.togglePinRef(b), to: row(), in: .test()).0
        let state = PersistedState(world: w, bundleIDs: [a: "com.a", b: "com.b", c: "com.c"])
        let back = try JSONDecoder().decode(PersistedState.self, from: try JSONEncoder().encode(state))
        #expect(back.screens["D1"]!.workspaces[0].windows?.map(\.pinned) == [nil, true, nil])
        let fresh = back.restore(into: World.empty(screens: ["D1"], defaultLayout: .split))
        let slots = fresh.screens["D1"]!.workspaces[0].windows
        #expect(fresh.pinnedTabs == [slots[1]])
        #expect(fresh.invariantViolations().isEmpty)
    }

    /// Backward compatibility: a #128 state file (tabs, no `pinned`) loads with nothing pinned.
    @Test func aStateFileFromBeforePinsStillLoads() throws {
        let json = #"""
        {"version":1,"zen":false,"placements":{},
         "screens":{"D1":{"activeIndex":0,"workspaces":[
           {"id":"00000000-0000-0000-0000-000000000001","name":"W","symbol":"s","layout":"split","pinned":false,
            "windows":[{"bundleID":"com.a","title":"x"},{"bundleID":"com.b","title":"","floating":true}]}]}}}
        """#
        let loaded = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        let fresh = loaded.restore(into: World.empty(screens: ["D1"], defaultLayout: .split))
        #expect(fresh.placeholders.count == 2 && fresh.pinnedTabs.isEmpty)
        #expect(fresh.invariantViolations().isEmpty)
    }

    // MARK: dragging placeholders (M2) — the moves windows make, drag-swap included

    func withPlaceholder() -> (World, WindowRef) {
        var w = row()
        let p = w.addPlaceholder(Placeholder(bundleID: "com.p", title: ""), to: w.screens["D1"]!.workspaces[0].id)!
        w.normalize()
        return (w, p)                                                    // row: a, b, c, p
    }

    @Test func aPlaceholderSwapsWithATileInItsRow() {
        let (w, p) = withPlaceholder()
        let (next, effects) = CommandRunner.apply(.dropWindow(p, onto: a), to: w, in: .test())
        #expect(next.screens["D1"]!.workspaces[0].windows == [p, b, c, a])
        #expect(next.focus.window == b && !effects.contains(.focus(p)))  // focus has nothing to follow
        #expect(next.invariantViolations().isEmpty)
        // …and a window dropped onto a placeholder swaps with it, following as ever.
        let (back, _) = CommandRunner.apply(.dropWindow(a, onto: p), to: w, in: .test())
        #expect(back.screens["D1"]!.workspaces[0].windows == [p, b, c, a] && back.focus.window == a)
        #expect(back.invariantViolations().isEmpty)
    }

    @Test func aPlaceholderDraggedToAnotherDisplayTakesThatSlot() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .split)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(c, kind: .tile, on: "D2")
        let p = w.addPlaceholder(Placeholder(bundleID: "com.p", title: ""), to: w.screens["D1"]!.workspaces[0].id)!
        w.normalize()
        let (next, _) = CommandRunner.apply(.dropWindow(p, onto: c), to: w, in: .test())
        #expect(next.screens["D2"]!.workspaces[0].windows == [p, c])
        #expect(next.screens["D1"]!.workspaces[0].windows == [a])
        #expect(next.focus == w.focus)
        #expect(next.invariantViolations().isEmpty)
        // The tab drag to the other display's bar and the rail drop, as windows do (#32, #95).
        let bar = CommandRunner.apply(.moveWindowRefBefore(p, c), to: w, in: .test()).0
        #expect(bar.screens["D2"]!.workspaces[0].windows == [p, c] && bar.focus == w.focus)
        let rail = CommandRunner.apply(.moveWindowRefToWorkspace(p, w.screens["D2"]!.workspaces[0].id, follow: false), to: w, in: .test()).0
        #expect(rail.screens["D2"]!.workspaces[0].windows == [c, p] && rail.invariantViolations().isEmpty)
    }

    // MARK: the UI state

    @Test func tabsSayWhetherTheyArePinnedAndClosable() {
        var w = CommandRunner.apply(.togglePinRef(b), to: row(), in: .test()).0
        _ = w.leavePlaceholder(for: b, bundleID: "com.notes", title: "")
        w = CommandRunner.apply(.togglePinRef(c), to: w, in: .test()).0
        let tabs = ShellUI.state(for: "D1", in: w)!.tabs
        #expect(tabs.map(\.isPinned) == [false, true, true])
        #expect(tabs.map(\.canClose) == [true, false, true])
        let wire = WireState(world: w)
        #expect(wire.screens[0].workspaces[0].windows.map { $0.isPinned } == [nil, true, true])
    }
}
