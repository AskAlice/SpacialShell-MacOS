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
    /// #71: "hitting fn+a … didn't focus that tab, but clicking on the tab un-minimized the window".
    /// Fn+A/Fn+D walk the tab row as drawn — minimized windows included — and landing on one
    /// brings it back, exactly as its tab click does (#48).
    @Test func focusStepsOntoAMinimizedTabAndUnhidesIt() {
        var w = base(); w.setHidden(b, true)
        let (after, e) = run(w, .focusWindow(.right))
        #expect(after.focus.window == b)
        #expect(!after.hidden.contains(b))
        #expect(e == [.unhide(b), .focus(b), .relayout])
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
    /// #50: Fn+W onto a row whose windows are all minimized lands on its anchor and brings it
    /// back, instead of focusing nothing and leaving the previous app in front.
    @Test func activatingAnAllHiddenRowUnhidesAndFocusesItsAnchor() {
        var w = base()
        (w, _) = run(w, .focusWorkspace(.down))
        for r in w.screens["D1"]!.workspaces[0].windows { w.setHidden(r, true) }
        let (after, e) = run(w, .focusWorkspace(.up))
        #expect(after.focus.window == a)
        #expect(!after.hidden.contains(a))
        #expect(e.prefix(2) == [.unhide(a), .focus(a)])
    }
    /// Fn+Shift+W from the first row opens a new workspace above every other and carries the
    /// window there; the row it left keeps its other windows, now second.
    @Test func moveWindowUpFromTheTopRowOpensANewTopWorkspace() {
        let w0 = base()
        let before = w0.screens["D1"]!.workspaces[0].id
        let (after, e) = run(w0, .moveWindowToWorkspace(.up))
        let s = after.screens["D1"]!
        #expect(s.workspaces[0].windows == [a] && s.activeIndex == 0 && after.focus.window == a)
        #expect(s.workspaces[1].id == before && s.workspaces[1].windows == [b, c])
        #expect(e == [.focus(a), .relayout])
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

    // MARK: bar drops across rows (#32) — a tab dropped on another row's bar goes to that row.

    /// Dropped on a tab in another display's bar: the window lands in that tab's workspace,
    /// immediately before it. #95: focus does not follow — it falls to the neighbour in the row
    /// the window left, exactly as if it had closed — the same as a rail drop.
    @Test func dragBeforeATabInAnotherRowMovesItThere() {
        var w = twoDisplays()                             // D1 [a*, b, c], D2 [d]
        (w, _) = run(w, .moveWindowRefToWorkspace(a, w.screens["D2"]!.active.id))   // D2 [d, a]
        (w, _) = run(w, .focusWindowRef(b))
        let (out, effects) = run(w, .moveWindowRefBefore(b, a))
        #expect(out.screens["D1"]!.workspaces[0].windows == [c])
        #expect(out.screens["D2"]!.active.windows == [d, b, a])
        #expect(out.focus == Focus(screen: "D1", window: c))
        #expect(out.screens["D2"]!.active.anchor == b)
        #expect(effects == [.focus(c), .relayout])
    }

    @Test func dragBeforeTheFirstTabInAnotherRowLandsFirst() {
        var w = twoDisplays()
        (w, _) = run(w, .moveWindowRefBefore(c, d))
        #expect(w.screens["D1"]!.active.windows == [a, b])
        #expect(w.screens["D2"]!.active.windows == [c, d])
    }

    @Test func dragBeforeATabInAnotherRowKeepsItFloating() {
        var w = twoDisplays()
        (w, _) = run(w, .focusWindowRef(c)); (w, _) = run(w, .toggleFloat)
        (w, _) = run(w, .moveWindowRefBefore(c, d))
        #expect(w.screens["D2"]!.active.floating == [c])
        #expect(w.screens["D1"]!.active.floating.isEmpty)
    }

    /// Other workspaces on the same display are other rows too: no display is special.
    @Test func dragBeforeATabInAnotherWorkspaceMovesItThere() {
        var w = base()
        let target = w.screens["D1"]!.workspaces.last!.id
        (w, _) = run(w, .moveWindowRefToWorkspace(c, target))   // D1 [[a, b], [c], []]
        (w, _) = run(w, .moveWindowRefBefore(a, c))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[b], [a, c], []])
        // #95: the [c] row stays active (the setup's move followed c there); a is not focused.
        #expect(w.focus == Focus(screen: "D1", window: c) && w.screens["D1"]!.activeIndex == 1)
    }

    /// Dropped on the empty end of another display's bar: the bar names its own workspace, and
    /// the window is appended there.
    @Test func dragOntoAnotherBarsEmptySpaceAppendsThere() {
        var w = twoDisplays()
        let bar = ShellUI.state(for: "D2", in: w)!
        (w, _) = run(w, bar.endOfRowDrop(b))
        #expect(w.screens["D1"]!.active.windows == [a, c])
        #expect(w.screens["D2"]!.active.windows == [d, b])
        #expect(w.focus == Focus(screen: "D1", window: a))   // #95: a drop does not follow
    }

    /// The same drop on the window's own bar is the old row-end reorder, focus untouched.
    @Test func dragOntoItsOwnBarsEmptySpaceStillReordersToTheEnd() {
        var w = twoDisplays()
        let bar = ShellUI.state(for: "D1", in: w)!
        #expect(bar.endOfRowDrop(a) == .moveWindowRefBefore(a, nil))
        (w, _) = run(w, bar.endOfRowDrop(a))
        #expect(w.screens["D1"]!.active.windows == [b, c, a])
        #expect(w.screens["D2"]!.active.windows == [d])
        #expect(w.focus.window == a)
    }

    // MARK: drops do not follow (#95) — a dropped tab moves its window; the active row, the focus
    // and the rail highlight stay where the user was.

    func drop(_ w: World, _ ref: WindowRef, to ws: UUID) -> (World, [Effect]) {
        run(w, .moveWindowRefToWorkspace(ref, ws, follow: false))
    }

    /// Same display, unfocused window: only the rows change. The window is its new row's anchor,
    /// and since that row is inactive the reconciler parks it.
    @Test func dropOnAnotherRowOfTheSameDisplayStaysPut() {
        let w = base()                                    // D1 [a*, b, c]
        let (out, effects) = drop(w, b, to: w.screens["D1"]!.workspaces.last!.id)
        #expect(out.screens["D1"]!.workspaces.map(\.windows) == [[a, c], [b], []])
        #expect(out.screens["D1"]!.activeIndex == 0)
        #expect(out.focus == Focus(screen: "D1", window: a))
        #expect(out.screens["D1"]!.workspaces[1].anchor == b)
        #expect(effects == [.relayout])
        let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                             visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875), isMain: true)
        let desired = Reconciler.desired(world: out, displays: [d1], config: LayoutConfig(gap: 8),
                                         observed: [:], prePark: [:], parkedNow: [], zeroSliver: [])
        if case .parked = desired[b] {} else { Issue.record("b should be parked, got \(String(describing: desired[b]))") }
    }

    /// The focused window leaves: focus falls to its neighbour by the close rule — the one before
    /// it, else the one after — and its row stays active.
    @Test func droppingTheFocusedWindowFocusesItsNeighbourLikeAClose() {
        var w = base()                                    // D1 [a*, b, c]
        let plus = w.screens["D1"]!.workspaces.last!.id
        var (out, effects) = drop(w, a, to: plus)         // first → the one after
        #expect(out.focus == Focus(screen: "D1", window: b) && out.screens["D1"]!.activeIndex == 0)
        #expect(out.screens["D1"]!.workspaces[1].windows == [a] && out.screens["D1"]!.workspaces[1].anchor == a)
        #expect(effects == [.focus(b), .relayout])
        (w, _) = run(w, .focusWindowRef(c))
        (out, effects) = drop(w, c, to: plus)             // last → the one before
        #expect(out.focus == Focus(screen: "D1", window: b))
        #expect(effects == [.focus(b), .relayout])
        var closed = w; closed.remove(c)                  // the same rule as a close
        #expect(closed.focus == out.focus)
    }

    /// Across displays: the other display's active row and the focused display both stay as they
    /// were. Dropped onto the other display's inactive "+" row, the window is filed there.
    @Test func dropOnAnotherDisplayStaysPut() {
        let w = twoDisplays()                             // D1 [a*, b, c], D2 [d]
        var (out, effects) = drop(w, a, to: w.screens["D2"]!.active.id)
        #expect(out.screens["D1"]!.active.windows == [b, c] && out.screens["D2"]!.active.windows == [d, a])
        #expect(out.focus == Focus(screen: "D1", window: b))
        #expect(out.screens["D2"]!.active.anchor == a)
        #expect(effects == [.focus(b), .relayout])
        (out, effects) = drop(w, c, to: w.screens["D2"]!.workspaces.last!.id)
        #expect(out.screens["D2"]!.workspaces.map(\.windows) == [[d], [c], []])
        #expect(out.screens["D2"]!.activeIndex == 0 && out.screens["D1"]!.activeIndex == 0)
        #expect(out.focus == Focus(screen: "D1", window: a))
        #expect(effects == [.relayout])
    }

    /// The bar's end-of-row drop sends the non-following form, as the rail does.
    @Test func endOfRowDropDoesNotFollow() {
        let w = twoDisplays()
        #expect(ShellUI.state(for: "D2", in: w)!.endOfRowDrop(b)
                == .moveWindowRefToWorkspace(b, w.screens["D2"]!.active.id, follow: false))
    }

    /// Fn+Shift+S / Fn+Shift+W, the edge spill (#33) and the default form keep following.
    @Test func keyboardMovesStillFollow() {
        var w = base()
        (w, _) = run(w, .moveWindowToWorkspace(.down))
        #expect(w.focus == Focus(screen: "D1", window: a) && w.screens["D1"]!.activeIndex == 1)
        (w, _) = run(w, .moveWindowToWorkspace(.up))
        #expect(w.focus == Focus(screen: "D1", window: a) && w.screens["D1"]!.activeIndex == 0)
        var two = twoDisplays()
        (two, _) = run(two, .focusWindowRef(c)); (two, _) = run(two, .moveWindow(.right))
        #expect(two.focus == Focus(screen: "D2", window: c))
        let w0 = base()
        let (out, _) = run(w0, .moveWindowRefToWorkspace(b, w0.screens["D1"]!.workspaces.last!.id))
        #expect(out.focus == Focus(screen: "D1", window: b) && out.screens["D1"]!.activeIndex == 1)
    }

    // MARK: workspace reorder (#75) — a rail tile dragged to a new place in its display's stack.

    /// D1 [[a], [c], [b*], +]: three rows to shuffle, the last-made one active.
    func stack() -> World {
        var w = base()
        (w, _) = run(w, .moveWindowRefToWorkspace(c, w.screens["D1"]!.workspaces.last!.id))
        (w, _) = run(w, .moveWindowRefToWorkspace(b, w.screens["D1"]!.workspaces.last!.id))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[a], [c], [b], []])
        return w
    }

    @Test func moveWorkspaceUpKeepsTheActiveOneActive() {
        var w = stack()
        let id = w.screens["D1"]!.workspaces[2].id
        let effects: [Effect]
        (w, effects) = run(w, .moveWorkspace(id, toIndex: 0))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[b], [a], [c], []])
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus == Focus(screen: "D1", window: b))
        #expect(effects == [.relayout])
    }

    @Test func moveWorkspaceDownKeepsTheActiveOneActive() {
        var w = stack()
        (w, _) = run(w, .moveWorkspace(w.screens["D1"]!.workspaces[0].id, toIndex: 2))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[c], [b], [a], []])
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == b)
        // Fn+W / Fn+S walk the new order.
        (w, _) = run(w, .focusWorkspace(.down))
        #expect(w.focus.window == a)
    }

    @Test func moveWorkspaceToWhereItIsOrToNowhereChangesNothing() {
        let w = stack()
        let id = w.screens["D1"]!.workspaces[1].id
        for cmd: Command in [.moveWorkspace(id, toIndex: 1), .moveWorkspace(UUID(), toIndex: 0)] {
            let (out, effects) = CommandRunner.apply(cmd, to: w)
            #expect(out == w && effects.isEmpty, "\(cmd) should be a no-op")
        }
    }

    /// An empty pinned row is not reaped by being moved: normalize() keeps pinned rows anywhere.
    @Test func movePinnedWorkspace() {
        var w = base()
        w.screens["D1"]!.workspaces.insert(Workspace(name: "Chat", layout: .maximize, pinned: true), at: 0)
        w.screens["D1"]!.activeIndex = 1
        w.normalize()
        let chat = w.screens["D1"]!.workspaces[0].id
        (w, _) = run(w, .moveWorkspace(chat, toIndex: 1))
        #expect(w.screens["D1"]!.workspaces.map(\.id)[1] == chat)
        #expect(w.screens["D1"]!.workspaces[1].pinned && w.screens["D1"]!.workspaces.count == 3)
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus.window == a)
    }

    /// Past the trailing "+" (or an out-of-range index, clamped): the stranded "+" is reaped and
    /// a fresh one grown underneath, so the result is the same as dropping just before it.
    @Test func moveWorkspacePastTheEndLandsLast() {
        var w = stack()
        (w, _) = run(w, .moveWorkspace(w.screens["D1"]!.workspaces[0].id, toIndex: 99))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[c], [b], [a], []])
        #expect(w.focus.window == b)
    }

    /// The order survives a restart with no persistence change: the state file stores each
    /// screen's workspaces as an array, and `restore` rebuilds them in that order.
    @Test func reorderedStackSurvivesARestart() throws {
        var w = stack()
        (w, _) = run(w, .moveWorkspace(w.screens["D1"]!.workspaces[2].id, toIndex: 0))
        let order = w.screens["D1"]!.workspaces.dropLast().map(\.id)
        let placements = PersistedState.placements(world: w, bundleIDs: [a: "x", b: "y", c: "z"])
        let saved = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(
            PersistedState(world: w, placements: placements)))
        let back = saved.restore(into: World.empty(screens: ["D1", "D2"], defaultLayout: .maximize))
        // Restored rows are held open empty until their apps come back, so none is dropped as "+".
        #expect(Array(back.screens["D1"]!.workspaces.map(\.id).prefix(order.count)) == order)
    }

    /// The rail's drop: land before the tile dropped on, "+" meaning last, within one display.
    @Test func railReorderLandsBeforeTheTargetTile() {
        let w = stack()
        let rail = ShellUI.state(for: "D1", in: w)!
        let ids = rail.rail.map(\.id)
        #expect(rail.railReorder(ids[2], before: ids[0]) == .moveWorkspace(ids[2], toIndex: 0))
        #expect(rail.railReorder(ids[0], before: ids[2]) == .moveWorkspace(ids[0], toIndex: 1))
        #expect(rail.railReorder(ids[0], before: ids[3]) == .moveWorkspace(ids[0], toIndex: 2))   // "+"
        #expect(rail.railReorder(ids[0], before: ids[0]) == nil)
        #expect(rail.railReorder(ids[0], before: ids[1]) == nil)   // already there
        let other = ShellUI.state(for: "D2", in: w)!.rail[0].id
        #expect(rail.railReorder(other, before: ids[0]) == nil)     // another display's tile
    }

    @Test func moveWindowDownCreatesWorkspaceAndFollows() {
        var w = base()
        (w, _) = run(w, .moveWindowToWorkspace(.down))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[b, c], [a], []])
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus.window == a)
        (w, _) = run(w, .moveWindowToWorkspace(.up))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[b, c, a], []])
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
    /// #127: the tab menu floats a window that is not the focused one; focus stays on `a`.
    @Test func toggleFloatRefTargetsTheNamedWindow() {
        var w = base()
        (w, _) = run(w, .toggleFloatRef(c))
        #expect(w.screens["D1"]!.active.floating == [c] && w.focus.window == a)
        (w, _) = run(w, .toggleFloatRef(c)); #expect(w.screens["D1"]!.active.floating.isEmpty)
        #expect(CommandRunner.run(.toggleFloatRef(d), on: w).report == .failed(.unknownWindow(d)))
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

// MARK: move to workspace N (#105)

extension CommandTests {
    /// Fn+Shift+2 from row 1: the window goes to row 2 and focus follows, like Fn+Shift+S.
    @Test func moveToWorkspaceNFollows() {
        let (w, e) = run(base(), .moveWindowToWorkspaceIndex(2))   // D1 [a*, b, c], +
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[b, c], [a], []])
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus == Focus(screen: "D1", window: a))
        #expect(e == [.focus(a), .relayout])
    }
    /// N past the last row targets the trailing empty row, and a new "+" grows below it.
    @Test func moveToWorkspacePastTheEndLandsInTheTrailingRow() {
        let (w, _) = run(base(), .moveWindowToWorkspaceIndex(9))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[b, c], [a], []])
    }
    @Test func moveToTheWorkspaceItIsInChangesNothing() {
        let w = base()
        let (out, e) = run(w, .moveWindowToWorkspaceIndex(1))
        #expect(out == w && e.isEmpty)
        #expect(run(w, .moveWindowToWorkspaceIndex(0)).1.isEmpty)
    }
    @Test func moveToWorkspaceNUpwards() {
        var w = stack()                                          // [[a], [c], [b*], +]
        (w, _) = run(w, .moveWindowToWorkspaceIndex(1))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[a, b], [c], []])
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus.window == b)
    }
}

// MARK: back-and-forth (#106): Fn+N on the active workspace returns to the previous one.

extension CommandTests {
    @Test func rePressingTheActiveWorkspaceGoesBackAndForth() {
        var w = stack()                                          // [[a], [c], [b*], +], active 2
        (w, _) = run(w, .focusWorkspaceIndex(1))
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus.window == a)
        (w, _) = run(w, .focusWorkspaceIndex(1))                 // re-press: back to row 3
        #expect(w.screens["D1"]!.activeIndex == 2 && w.focus.window == b)
        (w, _) = run(w, .focusWorkspaceIndex(3))                 // re-press again: returns
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus.window == a)
    }
    @Test func aFreshDisplayHasNothingToGoBackTo() {
        let w = base()
        let (out, e) = run(w, .focusWorkspaceIndex(1))
        #expect(out == w && e.isEmpty)
    }
    /// The remembered workspace goes away: the memory goes with it, and the re-press is a no-op.
    @Test func removingThePreviousWorkspaceClearsIt() {
        var w = stack()
        (w, _) = run(w, .focusWorkspaceIndex(1))                 // previous = [b]'s row
        w.remove(b)                                              // that row empties and is reaped
        #expect(w.screens["D1"]!.previous == nil)
        let (out, e) = run(w, .focusWorkspaceIndex(1))
        #expect(out == w && e.isEmpty)
    }
}

// MARK: move all of an app's windows (#98)

extension CommandTests {
    /// Another app's window, pid 2.
    var x: WindowRef { WindowRef(id: 9, pid: 2) }
    /// D1 [[a*, x, b], [c], +], D2 [d]: `a b c d` are one app (pid 1), `x` another.
    func apps() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        for r in [a, x, b] { w.adopt(r, kind: .tile, on: "D1") }
        w.adopt(d, kind: .tile, on: "D2")
        w.adopt(c, kind: .tile, on: "D1", workspace: w.screens["D1"]!.workspaces.last!.id)
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[a, x, b], [c], []] && w.focus.window == a)
        return w
    }
    /// Fn+Shift+Option+S: every window of the app joins the row below, in order, and focus follows.
    @Test func moveAppDownTakesEveryWindowOfTheApp() {
        let (w, e) = run(apps(), .moveAppToWorkspace(.down))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[x], [c, a, b, d], []])
        #expect(w.screens["D2"]!.active.windows.isEmpty)
        #expect(w.screens["D1"]!.activeIndex == 1 && w.focus == Focus(screen: "D1", window: a))
        #expect(e == [.focus(a), .relayout])
    }
    /// From the top row, as Fn+Shift+W does (#78): a new row above everything.
    @Test func moveAppUpFromTheTopOpensANewRow() {
        let (w, _) = run(apps(), .moveAppToWorkspace(.up))
        #expect(w.screens["D1"]!.workspaces.map(\.windows) == [[a, b, c, d], [x], []])
        #expect(w.screens["D1"]!.activeIndex == 0 && w.focus.window == a)
    }
    @Test func moveAppKeepsFloatingWindowsFloating() {
        var w = apps(); w.setFloating(b, true)
        (w, _) = run(w, .moveAppToWorkspace(.down))
        #expect(w.screens["D1"]!.workspaces[1].floating == [b])
    }
    /// Option held on a drop (#95's non-following move): the app moves, nothing else does. Focus
    /// was on one of its windows, so it falls to a window that stays — never to one that left.
    @Test func optionDropMovesTheAppWithoutFollowing() {
        let w = apps()
        let plus = w.screens["D1"]!.workspaces.last!.id
        let (out, e) = run(w, .moveAppRefToWorkspace(b, plus))
        #expect(out.screens["D1"]!.workspaces.map(\.windows) == [[x], [a, b, c, d], []])
        #expect(out.screens["D1"]!.activeIndex == 0 && out.focus == Focus(screen: "D1", window: x))
        #expect(e == [.focus(x), .relayout])
    }
    /// Option on a tab-bar drop names the bar's own workspace, like its end-of-row drop.
    @Test func optionDropOnABarMovesTheAppThere() {
        let w = twoDisplays()
        #expect(ShellUI.state(for: "D2", in: w)!.appDrop(b) == .moveAppRefToWorkspace(b, w.screens["D2"]!.active.id))
    }
    @Test func moveAppWithNothingToMoveChangesNothing() {
        let w = single()
        let (out, e) = run(w, .moveAppRefToWorkspace(a, w.screens["D1"]!.active.id))
        #expect(out == w && e.isEmpty)
        #expect(run(World.empty(screens: ["D1"], defaultLayout: .maximize), .moveAppToWorkspace(.down)).1.isEmpty)
    }
}
