import Testing
import Foundation
@testable import SpacialShellKit

/// #134 (M3c): a sheet (or an attached dialog — a floating window whose AX parent is a window in
/// its own row) belongs to its owner's tile: no tab of its own, it moves with the owner, and
/// closing it hands focus back to the owner.
@Suite struct SheetTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 2), s = WindowRef(id: 3, pid: 1)

    /// `a` and `b` tiled as columns, `s` a sheet on `a`, focus on the sheet (macOS focuses it).
    func world() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .column)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        w.adopt(s, kind: .float, on: "D1", parent: a)
        w.focus.window = s; w.normalize()
        return w
    }
    func ws(_ w: World) -> Workspace { w.screens["D1"]!.active }

    @Test func theSheetIsAttachedAndHasNoTab() throws {
        let w = world()
        #expect(ws(w).windows == [a, s, b], "it still joins its owner's row, after the owner")
        #expect(w.owner(of: s) == a && w.owner(of: a) == nil && w.owner(of: b) == nil)
        #expect(w.tabs(in: ws(w)) == [a, b])
        let ui = try #require(ShellUI.state(for: "D1", in: w))
        #expect(ui.tabs.map(\.ref) == [a, b])
        #expect(ui.tabs.first { $0.ref == a }?.isFocused == true, "the owner's tab lights while its sheet has focus")
    }

    /// A floating window with no owner in its row is a window of its own and keeps its tab.
    @Test func aFloatingWindowWithoutAnOwnerKeepsItsTab() {
        var w = world()
        w.adopt(WindowRef(id: 9, pid: 9), kind: .float, on: "D1")
        #expect(w.tabs(in: ws(w)).contains(WindowRef(id: 9, pid: 9)))
    }

    /// The layout's focused index is the owner's, so focusing a sheet never flips the page.
    @Test func focusingTheSheetAnchorsTheOwner() {
        let w = CommandRunner.apply(.focusWindowRef(s), to: world(), in: .test()).0
        #expect(w.focus.window == s && ws(w).anchor == a)
    }

    @Test func theKeysWalkTheTabsNotTheSheet() {
        var w = CommandRunner.apply(.focusWindow(.right), to: world(), in: .test()).0
        #expect(w.focus.window == b, "from the sheet, right is the owner's right")
        w = CommandRunner.apply(.focusWindow(.left), to: w, in: .test()).0
        #expect(w.focus.window == a)
        #expect(CommandRunner.apply(.focusTab(2), to: world(), in: .test()).0.focus.window == b)
    }

    @Test func closingTheSheetReturnsFocusToTheOwner() {
        var w = world()
        // Even when the row no longer has the sheet next to its owner.
        w.screens["D1"]!.workspaces[w.screens["D1"]!.activeIndex].windows = [a, b, s]
        w.remove(s)
        #expect(w.focus.window == a)
    }

    @Test func movingTheSheetMovesItsOwnerAndMovingTheOwnerTakesTheSheet() {
        let fromSheet = CommandRunner.apply(.moveWindowToWorkspace(.down), to: world(), in: .test()).0
        #expect(ws(fromSheet).windows == [a, s] && ws(fromSheet).floating == [s])
        #expect(fromSheet.screens["D1"]!.workspaces[0].windows == [b])
        #expect(fromSheet.owner(of: s) == a)
        var w = world(); w.focus.window = a; w.normalize()
        let fromOwner = CommandRunner.apply(.moveWindowToWorkspace(.down), to: w, in: .test()).0
        #expect(ws(fromOwner).windows == [a, s] && fromOwner.focus.window == a)
    }

    // MARK: - geometry: the sheet keeps its place on the owner

    func desired(_ w: World, observed: [WindowRef: CGRect], parkedNow: Set<WindowRef> = [],
                 prePark: [WindowRef: CGRect] = [:]) -> [WindowRef: Placement] {
        Reconciler.desired(world: w, displays: [d1], config: LayoutConfig(gap: 10), observed: observed,
                           prePark: prePark, parkedNow: parkedNow, zeroSliver: [])
    }

    @Test func theSheetMovesWithItsOwnersTile() throws {
        let w = world()
        let before = desired(w, observed: [:])
        guard case .frame(let tileA)? = before[a] else { Issue.record("a framed"); return }
        let sheet = CGRect(x: tileA.minX + 40, y: tileA.minY + 28, width: 300, height: 180)
        // In place: the sheet is where it is, so nothing is written for it.
        let same = desired(w, observed: [a: tileA, s: sheet])
        #expect(same[s] == .frame(sheet))
        #expect(Reconciler.plan(desired: same, observed: [a: tileA, s: sheet], parkedNow: []).allSatisfy {
            if case .setFrame(let r, _) = $0 { r != s } else { true }
        })
        // Maximize on a: a new tile, and the sheet goes with it, same offset, same size.
        var m = w; m.screens["D1"]!.workspaces[m.screens["D1"]!.activeIndex].layout = .maximize
        let after = desired(m, observed: [a: tileA, s: sheet])
        guard case .frame(let bigA)? = after[a] else { Issue.record("a framed"); return }
        #expect(after[s] == .frame(CGRect(x: bigA.minX + 40, y: bigA.minY + 28, width: 300, height: 180)))
    }

    @Test func theSheetParksWithItsOwner() {
        let tileA = CGRect(x: 10, y: 35, width: 485, height: 654)
        let sheet = CGRect(x: 50, y: 63, width: 300, height: 180)
        let w = CommandRunner.apply(.focusWorkspace(.down), to: world(), in: .test()).0   // a's row is now inactive
        let d = desired(w, observed: [a: tileA, s: sheet])
        guard case .parked(let pa)? = d[a], case .parked(let ps)? = d[s] else { Issue.record("both parked"); return }
        #expect(ps == CGPoint(x: pa.x + 40, y: pa.y + 28))
        // Back again: the offset comes from where they were before parking, not from the corner
        // macOS clamped them into.
        let back = CommandRunner.apply(.focusWorkspace(.up), to: w, in: .test()).0
        let corner = CGRect(x: 999, y: 660, width: 485, height: 654)
        let r = desired(back, observed: [a: corner, s: CGRect(x: 999, y: 660, width: 300, height: 180)],
                        parkedNow: [a, s], prePark: [a: tileA, s: sheet])
        guard case .frame(let fa)? = r[a] else { Issue.record("a framed"); return }
        #expect(r[s] == .frame(CGRect(x: fa.minX + 40, y: fa.minY + 28, width: 300, height: 180)))
    }

    /// A floating owner is the user's to place; its sheet is left alone with it.
    @Test func aFloatingOwnersSheetIsUntouched() {
        var w = world(); w.setFloating(a, true)
        let d = desired(w, observed: [a: CGRect(x: 100, y: 100, width: 500, height: 400), s: CGRect(x: 140, y: 128, width: 300, height: 180)])
        #expect(d[a] == .untouched && d[s] == .untouched)
    }
}
