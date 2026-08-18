import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ReconcilerTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1)
    let cfg = LayoutConfig(gap: 10)

    func world() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        return w
    }
    let obs: [WindowRef: CGRect] = [WindowRef(id: 1, pid: 1): CGRect(x: 0, y: 0, width: 300, height: 200), WindowRef(id: 2, pid: 1): CGRect(x: 0, y: 0, width: 400, height: 300)]

    @Test func maximizeFramesFocusedAndParksTheOther() {
        let d = Reconciler.desired(world: world(), displays: [d1], config: cfg, observed: obs, prePark: [:], parkedNow: [], zeroSliver: [])
        // rect = visibleFrame inset by gap, height −1
        #expect(d[a] == .frame(CGRect(x: 10, y: 35, width: 980, height: 654)))
        #expect(d[b] == .parked(CGPoint(x: 999, y: 699)))     // bottom-right sliver of visibleFrame (maxX 1000, maxY 700)
    }
    @Test func inactiveWorkspaceWindowsAreParked() {
        var w = world(); w = CommandRunner.apply(.moveWindowToWorkspace(.down), to: w).0   // a → ws1 (active), b stays ws0
        let d = Reconciler.desired(world: w, displays: [d1], config: cfg, observed: obs, prePark: [:], parkedNow: [], zeroSliver: [])
        #expect(d[b] == .parked(CGPoint(x: 999, y: 699)))
        if case .frame = d[a]! {} else { Issue.record("a should be framed") }
    }
    @Test func floatingVisibleIsUntouchedAndParkedRestoresPrePark() {
        var w = world(); w.setFloating(b, true)
        let d = Reconciler.desired(world: w, displays: [d1], config: cfg, observed: obs, prePark: [:], parkedNow: [], zeroSliver: [])
        #expect(d[b] == .untouched)
        let d2 = Reconciler.desired(world: w, displays: [d1], config: cfg, observed: obs, prePark: [b: CGRect(x: 50, y: 60, width: 400, height: 300)], parkedNow: [b], zeroSliver: [])
        #expect(d2[b] == .frame(CGRect(x: 50, y: 60, width: 400, height: 300)))
    }
    @Test func hiddenAndEphemeralAreUntouchedIgnoredAbsent() {
        var w = world(); w.setHidden(b, true); w.adopt(c, kind: .ephemeral, on: "D1")
        let d = Reconciler.desired(world: w, displays: [d1], config: cfg, observed: obs, prePark: [:], parkedNow: [], zeroSliver: [])
        #expect(d[b] == .untouched && d[c] == .untouched)
    }
    @Test func zeroSliverAppliesToZoom() {
        let d = Reconciler.desired(world: world(), displays: [d1], config: cfg, observed: obs, prePark: [:], parkedNow: [], zeroSliver: [b])
        #expect(d[b] == .parked(CGPoint(x: 1000, y: 700)))
    }
    @Test func planWritesOnlyDeltasUnparkBeforePark() {
        let desired: [WindowRef: Placement] = [a: .frame(CGRect(x: 10, y: 35, width: 980, height: 654)), b: .parked(CGPoint(x: 999, y: 699)), c: .untouched]
        let observed: [WindowRef: CGRect] = [a: CGRect(x: 0, y: 0, width: 300, height: 200), b: CGRect(x: 0, y: 0, width: 400, height: 300), c: .zero]
        let plan = Reconciler.plan(desired: desired, observed: observed, parkedNow: [])
        #expect(plan == [.setFrame(a, CGRect(x: 10, y: 35, width: 980, height: 654)), .setPosition(b, CGPoint(x: 999, y: 699))])
        let again = Reconciler.plan(desired: desired, observed: [a: CGRect(x: 10, y: 35, width: 980, height: 654), b: CGRect(x: 999, y: 699, width: 400, height: 300)], parkedNow: [b])
        #expect(again.isEmpty)
    }
    @Test func planToleratesHalfPointDrift() {
        let plan = Reconciler.plan(desired: [a: .frame(CGRect(x: 10, y: 35, width: 980, height: 654))], observed: [a: CGRect(x: 10.4, y: 35, width: 979.6, height: 654)], parkedNow: [])
        #expect(plan.isEmpty)
    }
    @Test func planTolerantOfTitleBarClampOnParkedY() {
        let desired: [WindowRef: Placement] = [b: .parked(CGPoint(x: 999, y: 699))]
        let observed: [WindowRef: CGRect] = [b: CGRect(x: 999, y: 668, width: 400, height: 300)]
        let planParked = Reconciler.plan(desired: desired, observed: observed, parkedNow: [b])
        #expect(planParked.isEmpty)
        let planUnparked = Reconciler.plan(desired: desired, observed: observed, parkedNow: [])
        #expect(planUnparked == [.setPosition(b, CGPoint(x: 999, y: 699))])
    }
}
