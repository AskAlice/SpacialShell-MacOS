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

    /// **I6 — "no invisible windows"** (M3a roadmap, task A1). The model alone cannot state it:
    /// reachability is geometric, so the invariant is asserted where geometry is decided, against
    /// `Reconciler.desired` over randomly-built worlds.
    ///
    /// What it pins, in the roadmap's words — *every window that is neither minimized, hidden by
    /// its app, nor on an inactive workspace is visible on screen*, and Alice's corollary,
    /// *switching to an app always shows a window*:
    ///
    /// 1. the focused window of an active workspace always gets a real frame (every layout paints
    ///    the focused slot — maximize paints only that one);
    /// 2. a non-empty active workspace always shows at least one window, so no workspace is a row
    ///    of tabs with nothing on screen;
    /// 3. no frame lands outside the display it belongs to;
    /// 4. nothing tiled in an active workspace is silently `.untouched` — only hidden, fullscreen
    ///    (macOS owns the frame) and floating windows may be left alone.
    /// 5. every frame is at least `LayoutEngine.minSize` — a crowded row parks its overflow
    ///    (the tab bar reaches it) instead of framing slivers (#54).
    ///
    /// Deliberately *not* re-deriving the layout rects here: that would re-test `LayoutEngine`'s
    /// arithmetic (`layoutsNeverOverlap` already does) instead of the property users feel.
    @Test(arguments: 0..<200)
    func i6NoInvisibleWindows(seed: Int) {
        var rng = TestRNG(seed: UInt64(seed) &+ 6_000)
        let displays = [
            DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                        visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1030), isMain: true),
            DisplayInfo(id: "D2", frame: CGRect(x: 1920, y: 0, width: 1280, height: 800),
                        visibleFrame: CGRect(x: 1920, y: 25, width: 1280, height: 750), isMain: false),
        ]
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        var next: WindowID = 1
        var live: [WindowRef] = []

        for step in 0..<40 {
            switch randomOp(&rng, world: w, live: live) {
            case .adopt(let k, let s):
                let r = WindowRef(id: next, pid: 1); next += 1; live.append(r)
                w.adopt(r, kind: k, on: s)
            case .remove:
                if let r = live.randomElement(using: &rng) { w.remove(r); live.removeAll { $0 == r } }
            case .hide: if let r = live.randomElement(using: &rng) { w.setHidden(r, true) }
            case .unhide: if let r = live.randomElement(using: &rng) { w.setHidden(r, false) }
            case .cmd(let c): w = CommandRunner.apply(c, to: w).0
            case .screens: break   // the display list is fixed here; `desired` needs it to match
            }
            // A fullscreen window every so often: macOS owns its frame, and the reconciler must
            // leave it alone without that counting as an invisible window.
            if Int.random(in: 0..<6, using: &rng) == 0, let r = live.randomElement(using: &rng) {
                w.setFullscreen(r, !w.fullscreen.contains(r))
            }

            let desired = Reconciler.desired(world: w, displays: displays, config: LayoutConfig(gap: 8),
                                             observed: [:], prePark: [:], parkedNow: [], zeroSliver: [])
            let byId = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })

            for sid in w.screenOrder {
                guard let display = byId[sid] else { continue }
                let ws = w.screens[sid]!.active
                let tiled = w.tiled(in: ws)
                var framed: [WindowRef] = []

                for win in tiled {
                    switch desired[win] {
                    case .frame(let f):
                        framed.append(win)
                        // 3. inside its own display — a frame on a neighbour's screen, or off every
                        //    screen, is exactly the "visible but unreachable" state I6 forbids.
                        #expect(display.visibleFrame.intersects(f),
                                "seed \(seed) step \(step): \(win) framed at \(f), outside \(sid)")
                        // 5. a frame the user can actually use (#54): intersecting the display is
                        //    not enough — a 0×h or 40 pt sliver is on screen and useless.
                        #expect(f.width >= LayoutEngine.minSize.width && f.height >= LayoutEngine.minSize.height,
                                "seed \(seed) step \(step): \(win) framed at \(f), below the \(LayoutEngine.minSize) floor")
                    case .parked:
                        continue   // 2 covers whether parking was legitimate for this layout
                    case .untouched:
                        // 4. the only tiled windows the reconciler may skip.
                        #expect(w.hidden.contains(win) || w.fullscreen.contains(win),
                                "seed \(seed) step \(step): \(win) untouched but neither hidden nor fullscreen")
                    case nil:
                        #expect(Bool(false), "seed \(seed) step \(step): \(win) has no placement at all")
                    }
                }

                // 1 + 2. Anything reachable in this row means something must be on screen, and the
                // focused window in particular. Fullscreen windows count as shown: macOS is
                // painting them full-display, which is the most visible a window gets.
                let shouldShow = tiled.filter { !w.hidden.contains($0) && !w.fullscreen.contains($0) }
                if !shouldShow.isEmpty {
                    let fullscreenHere = tiled.contains { w.fullscreen.contains($0) }
                    #expect(!framed.isEmpty || fullscreenHere,
                            "seed \(seed) step \(step): \(sid) row has \(shouldShow.count) window(s) and none on screen")
                }
                if let f = w.focus.window, sid == w.focus.screen, tiled.contains(f),
                   !w.hidden.contains(f), !w.fullscreen.contains(f) {
                    #expect(framed.contains(f),
                            "seed \(seed) step \(step): focused \(f) is not on screen (layout \(ws.layout))")
                }
            }

            let v = w.invariantViolations()
            #expect(v.isEmpty, "seed \(seed) step \(step): \(v)")
            if !v.isEmpty { return }
        }
    }

    @Test(arguments: 0..<50)
    func layoutsNeverOverlap(seed: Int) {
        var rng = TestRNG(seed: UInt64(seed) &+ 99)
        let rect = CGRect(x: 0, y: 0, width: Double.random(in: 300...4000, using: &rng), height: Double.random(in: 200...3000, using: &rng))
        for l in Layout.allCases {
            let n = Int.random(in: 1...40, using: &rng)
            let fs = LayoutEngine.frames(l, count: n, focused: Int.random(in: 0..<n, using: &rng), in: rect, gap: Double.random(in: 0...20, using: &rng)).compactMap { $0 }
            for i in fs.indices { for j in fs.indices where j > i {
                let x = fs[i].intersection(fs[j])
                #expect(x.isNull || x.width < 0.01 || x.height < 0.01, "\(l) n=\(n) overlap \(fs[i]) \(fs[j])")
            } }
            // The rect here is always ≥ 300×200, so the floor is always reachable (#54).
            #expect(fs.allSatisfy { $0.width >= LayoutEngine.minSize.width && $0.height >= LayoutEngine.minSize.height },
                    "\(l) n=\(n) in \(rect.size): frame below the floor")
        }
    }
}
