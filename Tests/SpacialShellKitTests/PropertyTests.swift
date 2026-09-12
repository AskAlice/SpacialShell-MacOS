import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct PropertyTests {
    enum Op { case adopt(WindowKind, DisplayID), remove, hide, unhide, cmd(Command), screens([DisplayID]) }

    func randomOp(_ rng: inout TestRNG, world: World, live: [WindowRef]) -> Op {
        let screens = world.screenOrder
        var cmds: [Command] = [.focusWindow(.left), .focusWindow(.right), .focusWorkspace(.up), .focusWorkspace(.down),
            .focusWorkspaceIndex(Int.random(in: 1...4, using: &rng)), .moveWindow(.left), .moveWindow(.right),
            .moveWindowToWorkspace(.up), .moveWindowToWorkspace(.down), .cycleLayout, .focusScreen(.next),
            .focusScreen(.prev), .moveWindowToScreen(.next), .moveWindowToScreen(.prev), .toggleFloat]
        // The drag verbs name a window and a destination outright, so they can only be built
        // against a live world — including the destinations a real drag can never produce
        // (a dead window, another screen's workspace), which is exactly what should be fuzzed.
        if let r = live.randomElement(using: &rng) {
            let workspaces = screens.flatMap { world.screens[$0]!.workspaces.map(\.id) }
            if let ws = workspaces.randomElement(using: &rng) { cmds.append(.moveWindowRefToWorkspace(r, ws)) }
            cmds.append(.moveWindowRefBefore(r, Bool.random(using: &rng) ? live.randomElement(using: &rng) : nil))
        }
        switch Int.random(in: 0..<10, using: &rng) {
        case 0...2: return .adopt([.tile, .tile, .tile, .float, .ephemeral, .ignore].randomElement(using: &rng)!, screens.randomElement(using: &rng)!)
        case 3: return .remove
        case 4: return .hide
        case 5: return .unhide
        case 6: return .screens(Bool.random(using: &rng) ? ["D1"] : ["D1", "D2", "D3"])
        default: return .cmd(cmds.randomElement(using: &rng)!)
        }
    }

    @Test(arguments: 0..<200)
    func randomSequencesPreserveInvariants(seed: Int) {
        var rng = TestRNG(seed: UInt64(seed))
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        var next: WindowID = 1
        var live: [WindowRef] = []
        for step in 0..<60 {
            let op = randomOp(&rng, world: w, live: live)
            switch op {
            case .adopt(let k, let s):
                let r = WindowRef(id: next, pid: 1); next += 1; live.append(r)
                w.adopt(r, kind: k, on: s, parent: Bool.random(using: &rng) ? live.randomElement(using: &rng) : nil)
            case .remove:
                if let r = live.randomElement(using: &rng) { w.remove(r); live.removeAll { $0 == r } }
            case .hide: if let r = live.randomElement(using: &rng) { w.setHidden(r, true) }
            case .unhide: if let r = live.randomElement(using: &rng) { w.setHidden(r, false) }
            case .cmd(let c): w = CommandRunner.apply(c, to: w).0
            case .screens(let s): w.setScreens(s, main: "D1")
            }
            let v = w.invariantViolations()
            #expect(v.isEmpty, "seed \(seed) step \(step) op \(op): \(v)")
            if !v.isEmpty { return }
        }
    }

    @Test(arguments: 0..<50)
    func layoutsNeverOverlap(seed: Int) {
        var rng = TestRNG(seed: UInt64(seed) &+ 99)
        let rect = CGRect(x: 0, y: 0, width: Double.random(in: 300...4000, using: &rng), height: Double.random(in: 200...3000, using: &rng))
        for l in Layout.allCases {
            let n = Int.random(in: 1...12, using: &rng)
            let fs = LayoutEngine.frames(l, count: n, focused: Int.random(in: 0..<n, using: &rng), in: rect, gap: Double.random(in: 0...20, using: &rng)).compactMap { $0 }
            for i in fs.indices { for j in fs.indices where j > i {
                let x = fs[i].intersection(fs[j])
                #expect(x.isNull || x.width < 0.01 || x.height < 0.01, "\(l) n=\(n) overlap \(fs[i]) \(fs[j])")
            } }
        }
    }
}
