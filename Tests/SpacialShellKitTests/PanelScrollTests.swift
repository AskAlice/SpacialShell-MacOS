import Testing
import Foundation
@testable import SpacialShellKit

/// #121: scrolling the rail, the tab bar and the layout switcher.
@Suite struct PanelScrollTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 2), c = WindowRef(id: 3, pid: 3), d = WindowRef(id: 4, pid: 4)

    /// D1: [a, b] active, [c], "+"; D2: [d]. Focus on a.
    func world() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        for (r, s) in [(a, "D1"), (b, "D1"), (c, "D1"), (d, "D2")] { w.adopt(r, kind: .tile, on: DisplayID(s)) }
        w = CommandRunner.apply(.moveWindowRefToWorkspace(c, w.screens["D1"]!.workspaces[1].id, follow: false), to: w, in: .test()).0
        w.focus = Focus(screen: "D1", window: a)
        return w
    }

    @Test func railStepsToTheNeighbourAndStopsAtTheEnds() {
        let s = ShellUI.testState(for: "D1", in: world())!
        #expect(s.rail.count == 3 && s.rail[0].isActive)
        #expect(s.railScroll(1) == .focusWorkspaceID(s.rail[1].id))
        #expect(s.railScroll(-1) == nil)                       // top: no wrap, like Fn+W
        #expect(s.railScroll(0) == nil)
    }

    /// The target is by id, from this display's state: scrolling D2's rail switches D2 even while
    /// D1 has focus — `.focusWorkspace(.down)` would have moved D1.
    @Test func unfocusedDisplayScrollsItself() {
        let s = ShellUI.testState(for: "D2", in: world())!
        #expect(!s.isFocusedScreen)
        #expect(s.railScroll(1) == .focusWorkspaceID(s.rail[1].id))
    }

    @Test func tabsStepAndWrapLikeTheKeys() {
        let s = ShellUI.testState(for: "D1", in: world())!
        #expect(s.tabs.map(\.ref) == [a, b])
        #expect(s.tabScroll(1) == .focusWindowRef(b))
        #expect(s.tabScroll(-1) == .focusWindowRef(b))          // wraps, like Fn+A
        // A bar with no focused tab starts from its ends.
        let other = ShellUI.testState(for: "D2", in: world())!
        #expect(other.tabScroll(1) == .focusWindowRef(d) && other.tabScroll(-1) == .focusWindowRef(d))
        // A single focused tab has nowhere to go.
        var w = world(); w.focus = Focus(screen: "D2", window: d)
        #expect(ShellUI.testState(for: "D2", in: w)!.tabScroll(1) == nil)
    }

    @Test func layoutCyclesTheSwitcherAndWraps() {
        let s = ShellUI.testState(for: "D1", in: world())!
        let set = s.switcher.map(\.id), ws = s.rail[0].id
        #expect(set.first == s.shownLayout && set.count > 1)
        #expect(s.layoutScroll(1) == .setWorkspaceLayout(ws, set[1]))
        #expect(s.layoutScroll(-1) == .setWorkspaceLayout(ws, set.last!))
    }

    // MARK: ScrollStepper — one step per notch, one per gesture

    @Test func everyWheelNotchSteps() {
        var s = ScrollStepper()
        #expect(s.feed(dx: 0, dy: 1, phase: .none) == -1)      // rolled away: back (up)
        #expect(s.feed(dx: 0, dy: -3, phase: .none) == 1)
        #expect(s.feed(dx: 2, dy: 0, phase: .none) == nil)     // shift-wheel: sideways, passes
    }

    @Test func aTrackpadGestureStepsOnceAndSwallowsItsMomentum() {
        var s = ScrollStepper()
        #expect(s.feed(dx: 0, dy: 0, phase: .began) == nil)   // nothing to decide yet
        #expect(s.feed(dx: 0, dy: -5, phase: .changed) == 0)   // under the threshold: swallowed
        #expect(s.feed(dx: 0, dy: -9, phase: .changed) == 1)   // over it: one step
        #expect(s.feed(dx: 0, dy: -40, phase: .changed) == 0)  // the same gesture never steps again
        #expect(s.feed(dx: 0, dy: 0, phase: .ended) == 0)
        #expect(s.feed(dx: 0, dy: -30, phase: .momentum) == 0) // the coast is swallowed, not a step
        // The next gesture steps again.
        #expect(s.feed(dx: 0, dy: 0, phase: .began) == nil)
        #expect(s.feed(dx: 0, dy: 20, phase: .changed) == -1)
    }

    /// The tab bar's overflow scroll (#14): a sideways gesture passes through whole, momentum too,
    /// even where a later event in it leans vertical.
    @Test func aSidewaysGesturePassesThroughWhole() {
        var s = ScrollStepper()
        #expect(s.feed(dx: 0, dy: 0, phase: .began) == nil)
        #expect(s.feed(dx: -8, dy: 1, phase: .changed) == nil)
        #expect(s.feed(dx: -1, dy: 30, phase: .changed) == nil)
        #expect(s.feed(dx: 0, dy: 0, phase: .ended) == nil)
        #expect(s.feed(dx: -20, dy: 0, phase: .momentum) == nil)
    }
}
