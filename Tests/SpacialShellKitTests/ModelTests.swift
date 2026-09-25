import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ModelTests {
    /// #72: a display shows a fullscreen Space only while its fullscreen window is on the active
    /// Space; swiped away (off-Space) or out of fullscreen, the panels come back.
    @Test func aDisplayShowsFullscreenOnlyWhileItsFullscreenWindowIsOnSpace() {
        let v = WindowRef(id: 1, pid: 1), o = WindowRef(id: 2, pid: 2)
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(v, kind: .tile, on: "D2"); w.adopt(o, kind: .tile, on: "D1")
        #expect(!w.showsFullscreenSpace("D2"))
        w.setFullscreen(v, true)
        #expect(w.showsFullscreenSpace("D2") && !w.showsFullscreenSpace("D1"))
        w.setOnActiveSpace(v, false)
        #expect(!w.showsFullscreenSpace("D2"))
        w.setOnActiveSpace(v, true); w.setFullscreen(v, false)
        #expect(!w.showsFullscreenSpace("D2"))
    }

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
    /// C1: an empty topology is transient, never a real arrangement. Honouring it would delete
    /// every screen — and every workspace on it — and leave `focus.screen` naming nothing.
    @Test func setScreensWithEmptyOrderIsNoop() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        let before = w
        w.setScreens([], main: "")
        #expect(w == before)
        #expect(w.invariantViolations().isEmpty)
    }

    // MARK: remembered placement (issue #5)

    @Test func adoptHonoursARememberedWorkspace() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        let trailing = w.screens["D1"]!.workspaces[1].id
        w.adopt(b, kind: .tile, on: "D1", workspace: trailing)
        #expect(w.screens["D1"]!.workspaces[0].windows == [a])
        #expect(w.screens["D1"]!.workspaces[1].windows == [b])
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func adoptIgnoresARememberedWorkspaceThatIsGone() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        let before = w.screens["D1"]!.workspaces.count
        w.adopt(b, kind: .tile, on: "D1", workspace: UUID())      // nothing by that id exists
        #expect(w.screens["D1"]!.workspaces.count == before)      // not resurrected
        #expect(w.screens["D1"]!.active.windows == [a, b])        // today's rules
        #expect(w.invariantViolations().isEmpty)
    }
    /// Placement is keyed by workspace, not by screen: the workspace a window belongs to may have
    /// been restored onto a different display than the one the window happens to open on.
    @Test func adoptFindsARememberedWorkspaceOnAnotherScreen() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        let onD1 = w.screens["D1"]!.workspaces[0].id
        w.adopt(b, kind: .tile, on: "D2", workspace: onD1)
        #expect(w.screens["D1"]!.workspaces[0].windows == [a, b])
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func aParentBeatsARememberedWorkspace() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1")
        let trailing = w.screens["D1"]!.workspaces[1].id
        w.adopt(c, kind: .float, on: "D1", parent: a, workspace: trailing)   // a dialog follows its owner
        #expect(w.screens["D1"]!.workspaces[0].windows == [a, c])
        #expect(w.invariantViolations().isEmpty)
    }
}
