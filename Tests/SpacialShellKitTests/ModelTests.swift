import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ModelTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 2)

    @Test func emptyWorldHasOneEmptyWorkspacePerScreen() {
        let w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        #expect(w.screens.count == 2)
        #expect(w.screens["D1"]!.workspaces.count == 1)
        #expect(w.focus == Focus(screen: "D1", window: nil))
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func adoptAppendsToActiveAndCreatesTrailingEmpty() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        w.adopt(b, kind: .tile, on: "D1")
        #expect(w.screens["D1"]!.workspaces.count == 2)
        #expect(w.screens["D1"]!.workspaces[0].windows == [a, b])
        #expect(w.focus.window == a)              // first adoption takes focus
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func adoptDialogGoesAfterParent() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        w.adopt(c, kind: .float, on: "D1", parent: a)
        #expect(w.screens["D1"]!.workspaces[0].windows == [a, c, b])
        #expect(w.screens["D1"]!.workspaces[0].floating == [c])
        #expect(w.parents[c] == a)
    }
    @Test func adoptEphemeralAndIgnoreDontEnterWorkspaces() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .ephemeral, on: "D1"); w.adopt(b, kind: .ignore, on: "D1")
        #expect(w.ephemeral == [a] && w.ignored == [b])
        #expect(w.screens["D1"]!.workspaces[0].windows.isEmpty)
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func adoptTwiceIsNoop() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(a, kind: .tile, on: "D1")
        #expect(w.screens["D1"]!.workspaces[0].windows == [a])
    }
    @Test func removeMovesFocusToLeftNeighbourThenRight() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1"); w.adopt(c, kind: .tile, on: "D1")
        w.focus.window = b
        w.remove(b); #expect(w.focus.window == a)
        w.remove(a); #expect(w.focus.window == c)
        w.remove(c); #expect(w.focus.window == nil)
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func emptiedNonActiveWorkspaceIsReaped() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        w.activate(index: 1, on: "D1")           // trailing empty becomes active → new trailing appended
        w.adopt(b, kind: .tile, on: "D1")
        #expect(w.screens["D1"]!.workspaces.count == 3)
        w.activate(index: 0, on: "D1")
        w.remove(b)                              // workspace 1 now empty, not active, not last → reaped
        #expect(w.screens["D1"]!.workspaces.count == 2)
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func pinnedWorkspaceSurvivesEmpty() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.screens["D1"]!.workspaces.insert(Workspace(name: "Code", layout: .half, pinned: true), at: 0)
        w.normalize()
        #expect(w.screens["D1"]!.workspaces.count == 2)
        #expect(w.screens["D1"]!.workspaces[0].name == "Code")
    }
    @Test func hiddenWindowsAreExcludedFromVisible() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        w.setHidden(a, true)
        #expect(w.visible(in: w.screens["D1"]!.active) == [b])
        #expect(w.focus.window == b)             // focus left the hidden window
        w.setHidden(a, false)
        #expect(w.visible(in: w.screens["D1"]!.active) == [a, b])
    }
    @Test func removingScreenMergesWorkspacesIntoMain() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D2"); w.focus = Focus(screen: "D2", window: a)
        w.setScreens(["D1"], main: "D1")
        #expect(w.screens["D2"] == nil)
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[a], []])
        #expect(w.focus.screen == "D1")
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func addingScreenCreatesEmptyStack() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.setScreens(["D1", "D2"], main: "D1")
        #expect(w.screens["D2"]!.workspaces.count == 1)
        #expect(w.screenOrder == ["D1", "D2"])
    }
}
