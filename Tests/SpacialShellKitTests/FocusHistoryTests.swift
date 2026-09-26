import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

/// #137 (G2, material-shell W15): a focus history of five per workspace — where focus goes when
/// the focused window closes, and what `focus-previous-window` toggles through.
@Suite struct FocusHistoryTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1),
        d = WindowRef(id: 4, pid: 1)

    /// One row a, b, c, d, then focus visits `order` by clicks (as the tab bar sends them).
    func row(visiting order: [WindowRef]) -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .split)
        for r in [a, b, c, d] { w.adopt(r, kind: .tile, on: "D1") }
        for r in order { w = CommandRunner.apply(.focusWindowRef(r), to: w).0 }
        return w
    }
    var history: (World) -> [WindowRef] { { $0.screens["D1"]!.workspaces[0].focusHistory } }

    @Test func historyIsMostRecentFirst() {
        let w = row(visiting: [c, b, d])
        #expect(history(w) == [d, b, c, a])
    }

    @Test func historyIsTrimmedToFive() {
        let e = WindowRef(id: 5, pid: 1), f = WindowRef(id: 6, pid: 1)
        var w = row(visiting: [])
        w.adopt(e, kind: .tile, on: "D1"); w.adopt(f, kind: .tile, on: "D1")
        for r in [b, c, d, e, f] { w = CommandRunner.apply(.focusWindowRef(r), to: w).0 }
        #expect(history(w) == [f, e, d, c, b])
        #expect(World.focusHistoryLimit == 5)
    }

    /// Keys, clicks and macOS's own focus reports all go through `normalize()` or `CommandRunner`,
    /// so each is recorded — here, Fn+D.
    @Test func keyboardFocusIsRecordedToo() {
        let w = CommandRunner.apply(.focusWindow(.right), to: row(visiting: [])).0
        #expect(history(w).prefix(2) == [b, a])
    }

    // MARK: focus on close

    @Test func closingTheFocusedWindowFocusesTheMostRecentOne() {
        var w = row(visiting: [d, b, c])                 // history c, b, d, a
        w.remove(c)
        #expect(w.focus.window == b)                     // not c's left neighbour
        w.remove(b)
        #expect(w.focus.window == d)
        #expect(history(w) == [d, a])                    // closed windows are gone from it
        #expect(w.invariantViolations().isEmpty)
    }

    /// No history to go by (nothing else was ever focused here): the left neighbour, as before.
    @Test func withNoHistoryTheLeftNeighbourTakesOver() {
        var w = row(visiting: [c])
        w.screens["D1"]!.workspaces[0].focusHistory = [c]
        w.remove(c)
        #expect(w.focus.window == b)
    }

    /// A window in the history that is minimized cannot take focus; the next one does.
    @Test func aHiddenWindowInTheHistoryIsSkippedOnClose() {
        var w = row(visiting: [b, d, c])                 // history c, d, b, a
        w.setHidden(d, true)
        w.remove(c)
        #expect(w.focus.window == b)
    }

    /// A window that moved to another row leaves this row's history.
    @Test func aWindowThatLeavesTheRowLeavesItsHistory() {
        let w = row(visiting: [b, c])
        let other = w.screens["D1"]!.workspaces[1].id
        let moved = CommandRunner.apply(.moveWindowRefToWorkspace(b, other, follow: false), to: w).0
        #expect(!history(moved).contains(b))
        #expect(moved.screens["D1"]!.workspaces.first { $0.id == other }!.focusHistory.isEmpty)   // never focused there
    }

    // MARK: focus-previous-window

    @Test func previousWindowTogglesBetweenTheLastTwo() {
        var w = row(visiting: [b, d])
        w = CommandRunner.apply(.focusPreviousWindow, to: w).0
        #expect(w.focus.window == b)
        w = CommandRunner.apply(.focusPreviousWindow, to: w).0
        #expect(w.focus.window == d)
        w = CommandRunner.apply(.focusPreviousWindow, to: w).0
        #expect(w.focus.window == b)
        #expect(w.invariantViolations().isEmpty)
    }

    @Test func previousWindowWithNothingBeforeIsANoop() {
        var w = World.empty(screens: ["D1"], defaultLayout: .split)
        w.adopt(a, kind: .tile, on: "D1")
        let r = CommandRunner.run(.focusPreviousWindow, on: w)
        #expect(r.world.focus.window == a)
        if case .noop = r.report {} else { Issue.record("expected a no-op, got \(r.report)") }
    }

    @Test func previousWindowBringsAMinimizedOneBack() {
        var w = row(visiting: [b, d])
        w.setHidden(b, true)
        let (next, effects) = CommandRunner.apply(.focusPreviousWindow, to: w)
        #expect(next.focus.window == b && !next.hidden.contains(b))
        #expect(effects.contains(.unhide(b)))
    }

    // MARK: placeholders (#128) are never focus targets

    @Test func aPlaceholderIsNeverInTheHistoryNorATarget() {
        var w = row(visiting: [b, d])
        let p = w.addPlaceholder(Placeholder(bundleID: "com.p", title: ""), to: w.screens["D1"]!.workspaces[0].id)!
        w.normalize()
        w = CommandRunner.apply(.focusWindowRef(p), to: w).0         // a click launches; it does not focus
        #expect(!history(w).contains(p) && w.focus.window == d)
        #expect(CommandRunner.apply(.focusPreviousWindow, to: w).0.focus.window == b)
        // Placeholder history entries (a hand-built world) are dropped, never focused.
        w.screens["D1"]!.workspaces[0].focusHistory = [d, p, b]
        w.normalize()
        #expect(history(w) == [d, b])
        w.remove(d)
        #expect(w.focus.window == b)
    }

    // MARK: sheets (#134) — history is of tabs

    /// A focused sheet is recorded as its owner, closing it still hands focus back to that owner
    /// (#134's rule), and the previous window from a sheet is the window before its owner.
    @Test func aSheetCountsAsItsOwner() {
        var w = row(visiting: [c, b])                    // history b, c, a
        let sheet = WindowRef(id: 9, pid: 1)
        w.adopt(sheet, kind: .float, on: "D1", parent: b)
        w = CommandRunner.apply(.focusWindowRef(sheet), to: w).0
        #expect(w.owner(of: sheet) == b)
        #expect(!history(w).contains(sheet) && history(w).first == b)
        #expect(CommandRunner.apply(.focusPreviousWindow, to: w).0.focus.window == c)
        w.remove(sheet)
        #expect(w.focus.window == b)
        #expect(w.invariantViolations().isEmpty)
    }

    // MARK: not persisted; bound to Fn+` and ⌃⌥`

    @Test func historyIsNotPersisted() throws {
        let w = row(visiting: [b, d])
        let json = String(decoding: try JSONEncoder().encode(w.screens["D1"]!.workspaces[0]), as: UTF8.self)
        #expect(!json.contains("focusHistory"))
        let restored = PersistedState(world: w).restore(into: World.empty(screens: ["D1"], defaultLayout: .split))
        #expect(restored.screens["D1"]!.workspaces.allSatisfy { $0.focusHistory.isEmpty })
    }

    @Test func boundToBacktickInBothPresets() {
        #expect(KeyBindings.command(named: "focus-previous-window") == .focusPreviousWindow)
        let fn = KeyBindings.chords(for: .focusPreviousWindow, config: Config()).map(KeyBindings.display)
        #expect(fn == ["Fn+`"])
        var ctrlAlt = Config(); ctrlAlt.keybindingPreset = .ctrlAlt
        #expect(KeyBindings.chords(for: .focusPreviousWindow, config: ctrlAlt).map(KeyBindings.display) == ["⌃⌥`"])
        // Nothing else was on either chord: each resolves to this command alone.
        #expect(KeyBindings.table(for: Config()).filter { KeyBindings.display($0.key) == "Fn+`" }.count == 1)
        #expect(CheatSheet.rows(for: Config()).contains { $0.commandName == "focus-previous-window" && $0.chords == ["Fn+`"] })
    }
}
