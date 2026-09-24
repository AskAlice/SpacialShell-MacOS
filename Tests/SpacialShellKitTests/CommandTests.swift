import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct CommandTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1), d = WindowRef(id: 4, pid: 1)
    func base() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1"); w.adopt(c, kind: .tile, on: "D1")
        return w   // focus a on D1[0]
    }
    func run(_ w: World, _ c: Command) -> (World, [Effect]) {
        let r = CommandRunner.apply(c, to: w)
        #expect(r.0.invariantViolations().isEmpty, "after \(c): \(r.0.invariantViolations())")
        return r
    }

    @Test func focusRightWrapsAndAnchors() {
        var w = base()
        (w, _) = run(w, .focusWindow(.right)); #expect(w.focus.window == b)
        (w, _) = run(w, .focusWindow(.right)); (w, _) = run(w, .focusWindow(.right))
        #expect(w.focus.window == a)
        #expect(w.screens["D1"]!.active.anchor == a)
    }
    @Test func focusLeftFromFirstWraps() {
        var w = base(); (w, _) = run(w, .focusWindow(.left)); #expect(w.focus.window == c)
    }
    @Test func focusEmitsFocusAndRelayout() {
        let (_, e) = run(base(), .focusWindow(.right)); #expect(e == [.focus(b), .relayout])
    }
    @Test func focusWorkspaceDownGoesToTrailingEmptyAndNoFurther() {
        var w = base()
        (w, _) = run(w, .focusWorkspace(.down)); #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == nil)
        (w, _) = run(w, .focusWorkspace(.down)); #expect(w.screens["D1"]!.activeIndex == 1)
        (w, _) = run(w, .focusWorkspace(.up)); #expect(w.focus.window == a)
    }
    @Test func focusWorkspaceIndexIsOneBased() {
        var w = base(); (w, _) = run(w, .focusWorkspaceIndex(2)); #expect(w.screens["D1"]!.activeIndex == 1)
        (w, _) = run(w, .focusWorkspaceIndex(9)); #expect(w.screens["D1"]!.activeIndex == 1)   // no-op
    }
    /// One display: `a, b, c` all on D1, nowhere to spill to.
    func single() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1"); w.adopt(c, kind: .tile, on: "D1")
        return w
    }
    /// Two displays: `a, b, c` on D1, `d` alone on D2; focus on `a`.
    func twoDisplays() -> World {
        var w = base(); w.adopt(d, kind: .tile, on: "D2"); return w
    }

    @Test func moveWindowRightSwapsAndStopsAtEnd() {
        var w = single()
        (w, _) = run(w, .moveWindow(.right)); #expect(w.screens["D1"]!.active.windows == [b, a, c])
        (w, _) = run(w, .moveWindow(.right))
        #expect(w.screens["D1"]!.active.windows == [b, c, a] && w.focus.window == a)
        // At the edge of the only display: a no-op that changes nothing.
        let (out, effects) = CommandRunner.apply(.moveWindow(.right), to: w)
        #expect(out == w && effects.isEmpty)
    }
    /// Under `maximize` only the focused window is painted, and the focus travels with the window
    /// as it moves — so the move was real in the model (the tab row reorders) and invisible on
    /// screen, which reads as "move doesn't work". The verb means "put this beside that", so it
    /// promotes the workspace to `split`, the narrowest layout that can show the pair.
    @Test func moveWindowUnderMaximizePromotesToSplit() {
        var w = base()
        #expect(w.screens["D1"]!.active.layout == .maximize)
        (w, _) = run(w, .moveWindow(.right))
        #expect(w.screens["D1"]!.active.layout == .split)
        #expect(w.screens["D1"]!.active.windows == [b, a, c])
    }

    /// A layout that already shows more than one window is the user's choice and is left alone.
    @Test func moveWindowLeavesOtherLayoutsAlone() {
        var w = base()
        let ws = w.screens["D1"]!.active.id
        (w, _) = run(w, .setWorkspaceLayout(ws, .grid))
        (w, _) = run(w, .moveWindow(.right))
        #expect(w.screens["D1"]!.active.layout == .grid)
    }

    /// A move that cannot happen changes nothing at all — including the layout. Promoting on a
    /// refused move would turn "nudge the leftmost window further left" into a layout change.
    @Test func refusedMoveDoesNotPromoteTheLayout() {
        for w in [single(), twoDisplays()] {           // `a` is leftmost on the leftmost display
            let (out, effects) = CommandRunner.apply(.moveWindow(.left), to: w)
            #expect(out == w && effects.isEmpty)
            #expect(out.screens["D1"]!.active.layout == .maximize)
        }
    }

    // MARK: edge spill (#33) — past the edge of its row, a window moves to the neighbouring display.

    @Test func moveRightPastTheEdgeLandsLeftmostOnTheNextDisplay() {
        var w = twoDisplays()
        (w, _) = run(w, .focusWindowRef(c))           // c is rightmost on D1
        let (out, effects) = run(w, .moveWindow(.right))
        #expect(out.screens["D1"]!.active.windows == [a, b])
        #expect(out.screens["D2"]!.active.windows == [c, d])
        #expect(out.focus == Focus(screen: "D2", window: c))
        #expect(effects == [.focus(c), .relayout])
    }

    @Test func moveLeftPastTheEdgeLandsRightmostOnThePreviousDisplay() {
        var w = twoDisplays()
        (w, _) = run(w, .focusWindowRef(d))           // d is the only tab on D2
        (w, _) = run(w, .moveWindow(.left))
        #expect(w.screens["D1"]!.active.windows == [a, b, c, d])
        #expect(w.focus == Focus(screen: "D1", window: d))
    }

    @Test func theOnlyTabSpillsToo() {
        var w = base()                                // D2 empty
        (w, _) = run(w, .moveWindowToScreen(.next))   // a alone on D2
        (w, _) = run(w, .moveWindow(.left))
        #expect(w.screens["D1"]!.active.windows == [b, c, a])
        #expect(w.focus == Focus(screen: "D1", window: a))
    }

    @Test func outermostDisplayIsANoop() {
        var w = twoDisplays()
        (w, _) = run(w, .focusWindowRef(d))           // D2 is the rightmost display
        let (out, effects) = CommandRunner.apply(.moveWindow(.right), to: w)
        #expect(out == w && effects.isEmpty)
    }

    @Test func spillKeepsTheWindowFloating() {
        var w = twoDisplays()
        (w, _) = run(w, .focusWindowRef(c)); (w, _) = run(w, .toggleFloat)
        (w, _) = run(w, .moveWindow(.right))
        #expect(w.screens["D2"]!.active.floating == [c])
        #expect(w.screens["D1"]!.active.floating.isEmpty)
    }

    /// The maximize→split promotion is for an in-row swap only; a spill changes neither layout.
    @Test func spillDoesNotPromoteTheLayout() {
        var w = twoDisplays()
        (w, _) = run(w, .focusWindowRef(c))
        (w, _) = run(w, .moveWindow(.right))
        #expect(w.screens["D1"]!.active.layout == .maximize)
        #expect(w.screens["D2"]!.active.layout == .maximize)
    }

    // MARK: drag targets — a dragged tab names its window and its destination outright, unlike
    // the keyboard verbs which are relative to whatever is focused.

    @Test func dragToWorkspaceMovesAnyWindowNotJustTheFocusedOne() {
        var w = base()                                    // [a*, b, c] on D1[0]
        let target = w.screens["D1"]!.workspaces[1].id     // the trailing empty
        (w, _) = run(w, .moveWindowRefToWorkspace(c, target))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[a, b], [c], []])
        // Focus follows the dragged window, as the keyboard move does.
        #expect(w.focus.window == c && w.screens["D1"]!.activeIndex == 1)
    }

    /// Dropping on "+" needs no special case: the trailing empty workspace is a workspace, and
    /// normalize() grows a fresh "+" underneath the moment this one stops being empty (I4).
    @Test func dragToTheTrailingEmptyGrowsANewOne() {
        var w = base()
        #expect(w.screens["D1"]!.workspaces.count == 2)
        let plus = w.screens["D1"]!.workspaces.last!.id
        (w, _) = run(w, .moveWindowRefToWorkspace(a, plus))
        #expect(w.screens["D1"]!.workspaces.count == 3)
        #expect(w.screens["D1"]!.workspaces.last!.isEmpty)
    }

    @Test func dragToTheWorkspaceItIsAlreadyInChangesNothing() {
        let w = base()
        let here = w.screens["D1"]!.workspaces[0].id
        let (out, effects) = CommandRunner.apply(.moveWindowRefToWorkspace(a, here), to: w)
        #expect(out == w && effects.isEmpty)
    }

    @Test func dragToAnUnknownWorkspaceIsARefusal() {
        let w = base()
        let (out, effects) = CommandRunner.apply(.moveWindowRefToWorkspace(a, UUID()), to: w)
        #expect(out == w && effects.isEmpty)
    }

    /// A floating window keeps floating when it is dragged somewhere else — the pin travels with
    /// the window, exactly as the keyboard move already guarantees.
    @Test func dragKeepsAWindowFloating() {
        var w = base()
        (w, _) = run(w, .focusWindowRef(b)); (w, _) = run(w, .toggleFloat)
        #expect(w.screens["D1"]!.workspaces[0].floating.contains(b))
        let target = w.screens["D1"]!.workspaces.last!.id
        (w, _) = run(w, .moveWindowRefToWorkspace(b, target))
        #expect(w.screens["D1"]!.workspaces[1].floating.contains(b))
    }

    @Test func dragToReorderInsertsBeforeTheNamedTab() {
        var w = base()                                    // [a, b, c]
        (w, _) = run(w, .moveWindowRefBefore(c, a))
        #expect(w.screens["D1"]!.active.windows == [c, a, b])
        (w, _) = run(w, .moveWindowRefBefore(c, nil))     // nil = past the end
        #expect(w.screens["D1"]!.active.windows == [a, b, c])
    }

    /// Dropping a tab onto itself, or where it already sits, must not shuffle the row.
    @Test func dragToReorderOntoItselfChangesNothing() {
        let w = base()
        for cmd: Command in [.moveWindowRefBefore(a, a), .moveWindowRefBefore(a, b)] {
            let (out, effects) = CommandRunner.apply(cmd, to: w)
            #expect(out == w && effects.isEmpty, "\(cmd) should be a no-op")
        }
    }

    /// Reordering is a row operation, not a focus one: dragging a tab does not steal focus from
    /// the window you were working in.
    @Test func dragToReorderLeavesFocusAlone() {
        var w = base()
        #expect(w.focus.window == a)
        (w, _) = run(w, .moveWindowRefBefore(c, a))
        #expect(w.focus.window == a)
    }

    /// Two windows in different workspaces have no row in common, so there is nothing to reorder.
    @Test func dragToReorderAcrossWorkspacesIsARefusal() {
        var w = base()
        let target = w.screens["D1"]!.workspaces.last!.id
        (w, _) = run(w, .moveWindowRefToWorkspace(c, target))
        let (out, effects) = CommandRunner.apply(.moveWindowRefBefore(c, a), to: w)
        #expect(out == w && effects.isEmpty)
    }

    @Test func moveWindowDownCreatesWorkspaceAndFollows() {
        var w = base()
        (w, _) = run(w, .moveWindowToWorkspace(.down))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[b, c], [a], []])
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == a)
        (w, _) = run(w, .moveWindowToWorkspace(.up))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[b, c, a], []])
    }
    @Test func moveWindowUpFromTopIsNoop() {
        let w = base(); let (w2, e) = run(w, .moveWindowToWorkspace(.up)); #expect(w2 == w && e.isEmpty)
    }
    @Test func cycleLayout() {
        var w = base(); (w, _) = run(w, .cycleLayout); #expect(w.screens["D1"]!.active.layout == .split)
    }
    @Test func closeEmitsCloseWithoutMutating() {
        let w = base(); let (w2, e) = run(w, .closeFocusedWindow); #expect(w2 == w && e == [.close(a)])
    }
    @Test func focusScreenNextWraps() {
        var w = base()
        (w, _) = run(w, .focusScreen(.next)); #expect(w.focus.screen == "D2" && w.focus.window == nil)
        (w, _) = run(w, .focusScreen(.next)); #expect(w.focus.screen == "D1" && w.focus.window == a)
    }
    @Test func moveWindowToScreen() {
        var w = base()
        (w, _) = run(w, .moveWindowToScreen(.next))
        #expect(w.screens["D2"]!.active.windows == [a] && w.focus == Focus(screen: "D2", window: a))
        #expect(w.screens["D1"]!.active.windows == [b, c])
    }
    @Test func toggleFloat() {
        var w = base()
        (w, _) = run(w, .toggleFloat); #expect(w.screens["D1"]!.active.floating == [a])
        (w, _) = run(w, .toggleFloat); #expect(w.screens["D1"]!.active.floating.isEmpty)
    }
    @Test func toggleShellUIFlipsZen() {
        let (w, e) = run(base(), .toggleShellUI)
        #expect(w.zen && e == [.relayout])
        #expect(!run(w, .toggleShellUI).0.zen)
    }
    @Test func commandsOnEmptyWorldDontCrash() {
        let w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        for c: Command in [.focusWindow(.left), .moveWindow(.right), .moveWindowToWorkspace(.down), .closeFocusedWindow, .toggleFloat, .moveWindowToScreen(.next), .focusScreen(.prev)] {
            _ = run(w, c)
        }
    }
}
