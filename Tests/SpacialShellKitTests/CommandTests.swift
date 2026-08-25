import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct CommandTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1)
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
    @Test func moveWindowRightSwapsAndStopsAtEnd() {
        var w = base()
        (w, _) = run(w, .moveWindow(.right)); #expect(w.screens["D1"]!.active.windows == [b, a, c])
        (w, _) = run(w, .moveWindow(.right)); (w, _) = run(w, .moveWindow(.right))
        #expect(w.screens["D1"]!.active.windows == [b, c, a] && w.focus.window == a)
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
