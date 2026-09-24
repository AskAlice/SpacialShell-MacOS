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
    @Test func crowdedColumnParksOverflowAndKeepsItsTabs() {
        // #54: 12 columns in a 980 pt rect would be ~73 pt each. Past the 120×80 floor the row
        // overflows — the windows that don't fit park, and stay in the row (so they keep tabs).
        var w = World.empty(screens: ["D1"], defaultLayout: .column)
        let refs = (1...12).map { WindowRef(id: WindowID($0), pid: 1) }
        for r in refs { w.adopt(r, kind: .tile, on: "D1") }
        let d = Reconciler.desired(world: w, displays: [d1], config: cfg, observed: [:], prePark: [:], parkedNow: [], zeroSliver: [])
        let framed = refs.compactMap { r -> CGRect? in if case .frame(let f) = d[r] { return f } else { return nil } }
        let parked = refs.filter { if case .parked = d[$0] { return true } else { return false } }
        #expect(framed.count == 7)   // (980 + 10) / (120 + 10)
        #expect(parked.count == 5)
        #expect(framed.allSatisfy { $0.width >= LayoutEngine.minSize.width && $0.height >= LayoutEngine.minSize.height })
        #expect(w.screens["D1"]!.active.windows == refs)
        if let f = w.focus.window { if case .frame = d[f] {} else { Issue.record("focused \(f) must stay on screen") } }
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

    func desired(_ w: World? = nil, displays: [DisplayInfo]? = nil,
                 insets: [DisplayID: ShellInsets] = [:],
                 suspended: Set<WindowRef> = []) -> [WindowRef: Placement] {
        Reconciler.desired(world: w ?? world(), displays: displays ?? [d1], config: cfg,
                           observed: obs, prePark: [:], parkedNow: [], zeroSliver: [],
                           insets: insets, suspended: suspended)
    }

    @Test func railLeftInsetShiftsEveryLayoutXAndNarrowsBy48() {
        let left = ShellInsets(top: 0, left: 48, right: 0, bottom: 0)
        for layout in Layout.allCases {
            var w = world(); w.screens["D1"]!.workspaces[0].layout = layout
            guard case .frame(let f) = desired(w, insets: ["D1": left])[a] else {
                Issue.record("\(layout) should frame a"); continue
            }
            #expect(f.origin.x == 58)
            if layout == .maximize { #expect(f == CGRect(x: 58, y: 35, width: 932, height: 654)) }
        }
    }
    @Test func railRightInsetNarrowsOnly() {
        let d = desired(insets: ["D1": ShellInsets(top: 0, left: 0, right: 48, bottom: 0)])
        #expect(d[a] == .frame(CGRect(x: 10, y: 35, width: 932, height: 654)))
    }
    @Test func topInsetShiftsYBy34() {
        let d = desired(insets: ["D1": ShellInsets(top: 34, left: 0, right: 0, bottom: 0)])
        #expect(d[a] == .frame(CGRect(x: 10, y: 69, width: 980, height: 620)))
    }
    @Test func zeroInsetsReproduceM1Frames() {
        let d = desired(insets: ["D1": .zero])
        #expect(d[a] == .frame(CGRect(x: 10, y: 35, width: 980, height: 654)))
        #expect(d[b] == .parked(CGPoint(x: 999, y: 699)))
    }
    @Test func insetsApplyPerDisplayNotGlobally() {
        let d2 = DisplayInfo(id: "D2", frame: CGRect(x: 1000, y: 0, width: 1000, height: 700),
                             visibleFrame: CGRect(x: 1000, y: 25, width: 1000, height: 675), isMain: false)
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D2")
        let d = desired(w, displays: [d1, d2], insets: ["D1": ShellInsets(top: 0, left: 48, right: 0, bottom: 0)])
        #expect(d[a] == .frame(CGRect(x: 58, y: 35, width: 932, height: 654)))
        #expect(d[b] == .frame(CGRect(x: 1010, y: 35, width: 980, height: 654)))
    }
    @Test func insetBeforeGapPinsExactRect() {
        // visible (0,25,1000,675) → left 48 → (48,25,952,675) → gap 10 → (58,35,932,655) → h−1
        // Symmetric insetBy(dx:48) after the gap would yield width 884, not 932.
        let d = desired(insets: ["D1": ShellInsets(top: 0, left: 48, right: 0, bottom: 0)])
        #expect(d[a] == .frame(CGRect(x: 58, y: 35, width: 932, height: 654)))
    }
    @Test func suspendedShortCircuitsToUntouched() {
        let d = desired(suspended: [a])
        #expect(d[a] == .untouched)
        #expect(d[b] == .parked(CGPoint(x: 999, y: 699)))
    }
}
