import Testing
import CoreGraphics
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

/// #188: Fn+` / ⌘` — every window of the focused app, on every workspace and display, most
/// recently used first; hold the modifier to step, let go to switch.
@Suite struct AppWindowSwitcherTests {
    // App 7 has four windows over two workspaces; app 8 has one beside them.
    let a1 = WindowRef(id: 1, pid: 7), a2 = WindowRef(id: 2, pid: 7), a3 = WindowRef(id: 3, pid: 7),
        a4 = WindowRef(id: 4, pid: 7), other = WindowRef(id: 5, pid: 8)

    /// Row 1: a1, a2, other. Row 2: a3, a4. Focus visits `order` by clicks; `recent` is the MRU the
    /// controller keeps from each published world.
    func world(visiting order: [WindowRef]) -> (World, [WindowRef]) {
        var w = World.empty(screens: ["D1"], defaultLayout: .split)
        for r in [a1, a2, other] { w.adopt(r, kind: .tile, on: "D1") }
        let second = w.screens["D1"]!.workspaces[1].id
        w.screens["D1"]!.workspaces[1].name = "Second"
        for r in [a3, a4] { w.adopt(r, kind: .tile, on: "D1", workspace: second) }
        var recent = AppWindowSwitcher.noting(w, in: [])
        for r in order {
            w = CommandRunner.apply(.focusWindowRef(r), to: w, in: .test()).0
            recent = AppWindowSwitcher.noting(w, in: recent)
        }
        return (w, recent)
    }

    func open(_ order: [WindowRef], reverse: Bool = false) throws -> AppWindowSwitcher {
        let (w, recent) = world(visiting: order)
        return try #require(AppWindowSwitcher(world: w, recent: recent, reverse: reverse))
    }

    @Test func theCurrentWindowComesFirstThenMostRecentAcrossWorkspacesThenRowOrder() throws {
        let s = try open([a1, a3, other, a2])
        // a2 is focused; a3 (row 2) was used after a1; a4 was never focused, so it trails.
        #expect(s.items.map(\.ref) == [a2, a3, a1, a4])
        #expect(s.pid == 7)
    }

    @Test func eachEntryIsNamedByItsWorkspace() throws {
        let s = try open([a1, a3, a2])
        #expect(s.items.first { $0.ref == a3 }?.workspace == "Second")
        #expect(s.items.first { $0.ref == a1 }?.workspace == "Workspace 1")
    }

    @Test func titlesComeFromTheSnapshot() throws {
        let (w, recent) = world(visiting: [a1, a2])
        let s = try #require(AppWindowSwitcher(world: w, recent: recent, titles: [a1: "Inbox", a2: ""]))
        #expect(s.items.first { $0.ref == a1 }?.title == "Inbox")
        #expect(s.items.first { $0.ref == a2 }?.title == nil)
    }

    @Test func theSelectionStartsOnTheSecondEntry() throws {
        let s = try open([a1, a3, a2])
        #expect(s.selected == 1 && s.selectedRef == a3)
    }

    @Test func openedBackwardsItStartsOnTheLastEntry() throws {
        let s = try open([a1, a3, a2], reverse: true)
        #expect(s.selectedRef == s.items.last?.ref)
    }

    @Test func steppingWrapsBothWays() throws {
        var s = try open([a1, a3, a2])                  // [a2, a3, a1, a4], on a3
        s.step(forward: true); #expect(s.selectedRef == a1)
        s.step(forward: true); #expect(s.selectedRef == a4)
        s.step(forward: true); #expect(s.selectedRef == a2)
        s.step(forward: false); #expect(s.selectedRef == a4)
        s.step(forward: false); #expect(s.selectedRef == a1)
    }

    @Test func committingFocusesTheSelectedWindowAndCancellingDoesNothing() throws {
        var s = try open([a1, a3, a2])
        #expect(s.end(committing: true) == .focusWindowRef(a3))
        #expect(s.end(committing: false) == nil)
        s.select(a4)
        #expect(s.end(committing: true) == .focusWindowRef(a4))
        s.select(other)                                  // not listed: the selection stays
        #expect(s.selectedRef == a4)
    }

    /// The commit is the tab click's command, so the store takes you to the other workspace.
    @Test func theCommitLandsOnTheOtherWorkspace() throws {
        let (w, recent) = world(visiting: [a1, a3, a2])
        let s = try #require(AppWindowSwitcher(world: w, recent: recent))
        let after = CommandRunner.apply(try #require(s.end(committing: true)), to: w, in: .test()).0
        #expect(after.focus.window == a3 && after.screens["D1"]!.activeIndex == 1)
    }

    @Test func withOneWindowOrNoFocusItDoesNotOpen() {
        var w = World.empty(screens: ["D1"], defaultLayout: .split)
        w.adopt(a1, kind: .tile, on: "D1"); w.adopt(other, kind: .tile, on: "D1")
        #expect(w.focus.window == a1)
        #expect(AppWindowSwitcher(world: w, recent: []) == nil)
        w.adopt(a2, kind: .tile, on: "D1")
        #expect(AppWindowSwitcher(world: w, recent: []) != nil)
        w.focus.window = nil
        #expect(AppWindowSwitcher(world: w, recent: []) == nil)
    }

    @Test func placeholdersAreLeftOutAndEphemeralWindowsAreIn() throws {
        var (w, recent) = world(visiting: [a1, a2])
        let row = w.screens["D1"]!.workspaces[0].id
        let added = w.addPlaceholder(Placeholder(bundleID: "com.example.seven", title: "Old"), to: row)
        let ph = try #require(added)
        let popup = WindowRef(id: 9, pid: 7)
        w.adopt(popup, kind: .ephemeral, on: "D1")
        recent = AppWindowSwitcher.noting(w, in: recent)
        let s = try #require(AppWindowSwitcher(world: w, recent: recent))
        #expect(!s.items.map(\.ref).contains(ph))
        #expect(s.items.map(\.ref).last == popup)
        #expect(s.items.last?.workspace == nil)
    }

    /// A focused sheet counts as its owner's tab, as in #137's history.
    @Test func theRecentListIsOfTabsMostRecentFirstWithoutRepeats() {
        let (w, recent) = world(visiting: [a1, a3, a1, a2])
        #expect(Array(recent.prefix(3)) == [a2, a1, a3])
        #expect(Set(recent).count == recent.count)
        #expect(AppWindowSwitcher.noting(w, in: recent) == recent)
        let long = (100..<200).map { WindowRef(id: $0, pid: 1) }
        #expect(AppWindowSwitcher.noting(w, in: long).count == AppWindowSwitcher.recentLimit)
    }

    // MARK: holding

    @Test func whateverModifierOpenedItHoldsItOpenButShift() {
        let fn = AppWindowSwitcher.holdModifiers([.maskSecondaryFn, .maskAlphaShift])
        #expect(fn == .maskSecondaryFn)
        let cmd = AppWindowSwitcher.holdModifiers([.maskCommand, .maskShift])
        #expect(cmd == .maskCommand)
        let ctrlAlt = AppWindowSwitcher.holdModifiers([.maskControl, .maskAlternate])
        #expect(AppWindowSwitcher.isHeld([.maskCommand, .maskShift], by: cmd))
        #expect(!AppWindowSwitcher.isHeld([.maskShift], by: cmd))
        #expect(!AppWindowSwitcher.isHeld([.maskControl], by: ctrlAlt), "letting go of either ends it")
        #expect(!AppWindowSwitcher.isHeld([.maskCommand], by: []), "opened with nothing held (spacialctl): it switches at once")
    }

    @Test func escWithTheHeldModifiersCancelsShiftOrNot() {
        #expect(AppWindowSwitcher.cancelChords(held: .maskCommand) == ["cmd-esc", "cmd-shift-esc"].map(KeyBindings.parse))
        #expect(AppWindowSwitcher.cancelChords(held: [.maskControl, .maskAlternate])
                == ["ctrl-alt-esc", "ctrl-alt-shift-esc"].map(KeyBindings.parse))
        #expect(AppWindowSwitcher.cancelChords(held: .maskSecondaryFn) == ["fn-esc", "fn-shift-esc"].map(KeyBindings.parse))
    }

    // MARK: the keys

    @Test func backtickSwitchesOnBothPresetsAndCommandBacktickOnEvery() throws {
        let fn = KeyBindings.table(for: Config())
        #expect(fn[try #require(KeyBindings.parse("fn-backtick"))] == .switchAppWindow(reverse: false))
        #expect(fn[try #require(KeyBindings.parse("fn-shift-backtick"))] == .switchAppWindow(reverse: true))
        var ctrlAlt = Config(); ctrlAlt.keybindingPreset = .ctrlAlt
        let ca = KeyBindings.table(for: ctrlAlt)
        #expect(ca[try #require(KeyBindings.parse("ctrl-alt-backtick"))] == .switchAppWindow(reverse: false))
        #expect(ca[try #require(KeyBindings.parse("ctrl-alt-shift-backtick"))] == .switchAppWindow(reverse: true))
        for t in [fn, ca] {
            #expect(t[try #require(KeyBindings.parse("cmd-backtick"))] == .switchAppWindow(reverse: false))
            #expect(t[try #require(KeyBindings.parse("cmd-shift-backtick"))] == .switchAppWindow(reverse: true))
        }
        #expect(KeyBindings.command(named: "switch-app-window") == .switchAppWindow(reverse: false))
        #expect(KeyBindings.command(named: "switch-app-window-reverse") == .switchAppWindow(reverse: true))
        #expect(Command.switchAppWindow(reverse: false).isAppLayer && Command.cancelAppWindowSwitch.isAppLayer)
    }

    @Test func theSwitcherCommandsChangeNothingInTheModel() {
        let (w, _) = world(visiting: [a1, a2])
        for c: Command in [.switchAppWindow(reverse: false), .switchAppWindow(reverse: true), .cancelAppWindowSwitch] {
            let (after, effects) = CommandRunner.apply(c, to: w, in: .test())
            #expect(after == w && effects.isEmpty)
        }
    }

    @Test func theCheatSheetListsIt() {
        let row = CheatSheet.rows(for: Config()).first { $0.commandName == "switch-app-window" }
        #expect(row?.chords == ["⌘`", "Fn+`"])
    }
}
