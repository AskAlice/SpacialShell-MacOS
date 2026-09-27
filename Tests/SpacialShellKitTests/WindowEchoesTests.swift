import Testing
import Foundation
@testable import SpacialShellKit

/// #169: what a window's move or resize report means, asked of `WindowEchoes` directly — no store,
/// no backend. The store records its writes here and acts on the verdict; these are the rules it
/// used to sequence inline (#125, #164, #165, #108, #57).
@Suite struct WindowEchoesTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let d2 = DisplayInfo(id: "D2", frame: CGRect(x: 1000, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 1000, y: 25, width: 1000, height: 675), isMain: false)
    let a = WindowRef(id: 1, pid: 1), f = WindowRef(id: 2, pid: 1), s = WindowRef(id: 3, pid: 1)
    let tile = CGRect(x: 8, y: 33, width: 984, height: 658)
    let small = CGRect(x: 8, y: 33, width: 400, height: 300)

    /// `a` tiled on D1, `f` floating there; D2 empty. Made once: its workspace ids are random.
    let world: World
    init() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(WindowRef(id: 1, pid: 1), kind: .tile, on: "D1"); w.adopt(WindowRef(id: 2, pid: 1), kind: .float, on: "D1")
        world = w
    }
    func moved(was: CGRect? = nil, _ tweak: (inout WindowEchoes.Context) -> Void = { _ in }) -> WindowEchoes.Context {
        var c = WindowEchoes.Context(event: .moved, was: was, world: world, displays: [d1, d2])
        tweak(&c)
        return c
    }
    func resized(was: CGRect? = nil) -> WindowEchoes.Context {
        WindowEchoes.Context(event: .resized, was: was, world: world, displays: [d1, d2])
    }

    // MARK: - own echo vs foreign move

    @Test func theEchoOfOurOwnWriteIsOurs() {
        var e = WindowEchoes()
        e.record(.setFrame(a, tile))
        let v1 = e.interpret(a, frame: tile, resized())
        #expect(v1 == .init(action: .ownEcho))
        let v2 = e.interpret(a, frame: tile, resized())
        #expect(v2.action == .snapBack, "consumed: the same frame again is news")
    }

    @Test func aParkingEchoClampedByTheTitleBarIsOurs() {
        var e = WindowEchoes()
        e.record(.setPosition(a, CGPoint(x: 999, y: 699)))
        let v3 = e.interpret(a, frame: CGRect(x: 999, y: 668, width: 400, height: 300), moved())
        #expect(v3.action == .ownEcho)
    }

    @Test func aForeignMoveOfATileSnapsBackAndOfAFloatingWindowIsLeft() {
        var e = WindowEchoes()
        let v4 = e.interpret(a, frame: CGRect(x: 300, y: 300, width: 984, height: 658), moved())
        #expect(v4.action == .snapBack)
        let v5 = e.interpret(f, frame: CGRect(x: 300, y: 300, width: 400, height: 300), moved())
        #expect(v5.action == .leave)
        let v6 = e.interpret(WindowRef(id: 99, pid: 9), frame: small, moved())
        #expect(v6.action == .leave, "not ours at all")
    }

    @Test func lockedOrABorderInTheHandHoldsEverything() {
        var e = WindowEchoes()
        let v7 = e.interpret(a, frame: small, moved { $0.locked = true })
        #expect(v7.action == .hold)
        let v8 = e.interpret(a, frame: small, moved { $0.grabbing = true })
        #expect(v8.action == .hold)
        e.record(.setFrame(a, tile))
        let v9 = e.interpret(a, frame: tile, moved { $0.locked = true })
        #expect(v9.action == .ownEcho, "our own echo is ours even locked")
    }

    // MARK: - #164: a refusal is suspected, then confirmed

    /// The first smaller echo of our own write is only a suspicion; the tile is asked for again.
    @Test func aFirstSmallerEchoIsOnlyASuspicion() {
        var e = WindowEchoes()
        e.record(.setFrame(a, tile))
        let v = e.interpret(a, frame: small, resized())
        #expect(v == .init(learned: [.refusalSuspected(Refusal(asked: tile, size: small.size))], action: .snapBack))
        #expect(e.refused[a] == nil)
    }

    /// The same size back a second time confirms it: the reconciler centres it from now on.
    @Test func aSecondSameSizeEchoConfirmsIt() {
        var e = WindowEchoes()
        e.record(.setFrame(a, tile)); _ = e.interpret(a, frame: small, resized())
        e.record(.setFrame(a, tile))
        let v = e.interpret(a, frame: small.insetBy(dx: 0.5, dy: 0.5), resized())
        #expect(v.learned == [.refusalConfirmed(Refusal(asked: tile, size: small.insetBy(dx: 0.5, dy: 0.5).size))])
        #expect(e.refused[a]?.size == small.insetBy(dx: 0.5, dy: 0.5).size)
        // The centred write that follows echoes back as ours.
        let centred = e.refused[a]!.fitted(in: tile)!
        e.record(.setFrame(a, centred))
        let v10 = e.interpret(a, frame: centred, moved())
        #expect(v10.action == .ownEcho)
    }

    /// A browser mid-resize reports one smaller frame, then takes the tile: nothing is learned,
    /// and the granted echo clears the suspicion.
    @Test func aTransientSmallerEchoLearnsNothing() {
        var e = WindowEchoes()
        e.record(.setFrame(a, tile)); _ = e.interpret(a, frame: CGRect(x: 8, y: 33, width: 700, height: 500), resized())
        e.record(.setFrame(a, tile))
        let v11 = e.interpret(a, frame: tile, resized())
        #expect(v11 == .init(action: .ownEcho))
        // A later smaller echo is a first suspicion again, not a confirmation.
        e.record(.setFrame(a, tile))
        let v12 = e.interpret(a, frame: CGRect(x: 8, y: 33, width: 700, height: 500), resized())
        #expect(v12.learned.first == .refusalSuspected(Refusal(asked: tile, size: CGSize(width: 700, height: 500))))
        #expect(e.refused[a] == nil)
    }

    /// Two different smaller sizes are two suspicions, never a confirmation.
    @Test func twoDifferentSizesConfirmNothing() {
        var e = WindowEchoes()
        e.record(.setFrame(a, tile)); _ = e.interpret(a, frame: small, resized())
        e.record(.setFrame(a, tile))
        let v = e.interpret(a, frame: CGRect(x: 8, y: 33, width: 600, height: 300), resized())
        #expect(v.learned == [.refusalSuspected(Refusal(asked: tile, size: CGSize(width: 600, height: 300)))])
        #expect(e.refused[a] == nil)
    }

    /// Learned, then it grows (the user or the app resized it): forgotten, and snapped back to the
    /// whole tile rather than the old size.
    @Test func aRefusedWindowThatGrowsIsForgotten() {
        var e = confirmed(small)
        let v = e.interpret(a, frame: CGRect(x: 100, y: 100, width: 900, height: 600), resized())
        #expect(v == .init(learned: [.refusalForgotten], action: .snapBack))
        #expect(e.refused[a] == nil)
    }

    /// Its own size again is not growth: the record holds.
    @Test func aRefusedWindowAtItsRefusedSizeKeepsTheRecord() {
        var e = confirmed(small)
        let v13 = e.interpret(a, frame: small.offsetBy(dx: 50, dy: 0), moved())
        #expect(v13.learned.isEmpty)
        #expect(e.refused[a] != nil)
    }

    /// #164: bigger than the tile (an app minimum) is a refusal too, and shrinking toward the tile forgets it.
    @Test func aWindowBiggerThanItsTileIsARefusalAndShrinkingForgetsIt() {
        let big = CGRect(x: 8, y: 33, width: 1200, height: 658)
        var e = confirmed(big)
        #expect(e.refused[a] == Refusal(asked: tile, size: big.size))
        let v14 = e.interpret(a, frame: tile, resized())
        #expect(v14.learned == [.refusalForgotten])
    }

    /// `a` confirmed as refusing the tile at `got`'s size.
    func confirmed(_ got: CGRect) -> WindowEchoes {
        var e = WindowEchoes()
        for _ in 0..<2 { e.record(.setFrame(a, tile)); _ = e.interpret(a, frame: got, resized()) }
        return e
    }

    // MARK: - #165: a sheet that will not move

    let from = CGRect(x: 900, y: 55, width: 400, height: 200)
    let to = CGRect(x: 300, y: 262, width: 400, height: 200)

    /// The echo of a first placement still shows the sheet where it was: bound to its owner's title
    /// bar. Learned, and the owner moves instead.
    @Test func aPlacementThatDidNotTakeIsAnUnmovableSheet() {
        var e = WindowEchoes()
        e.record(.setFrame(s, to)); e.probe(s, from: from, to: to)
        let v15 = e.interpret(s, frame: from, moved())
        #expect(v15 == .init(learned: [.sheetUnmovable], action: .moveOwner))
        #expect(e.unmovable == [s])
    }

    @Test func aPlacementThatTookIsNothingToLearn() {
        var e = WindowEchoes()
        e.record(.setFrame(s, to)); e.probe(s, from: from, to: to)
        let v16 = e.interpret(s, frame: to, moved())
        #expect(v16 == .init(action: .ownEcho))
        #expect(e.unmovable.isEmpty)
        let v17 = e.settle(s, seenAt: from)
        #expect(v17 == false, "the probe is spent")
    }

    /// Somewhere else entirely: the user or the app moved it. Not a sheet.
    @Test func aPlacementEchoElsewhereIsNotASheet() {
        var e = WindowEchoes()
        e.probe(s, from: from, to: to)
        let v18 = e.interpret(s, frame: CGRect(x: 50, y: 400, width: 400, height: 200), moved())
        #expect(v18.learned.isEmpty)
        #expect(e.unmovable.isEmpty)
    }

    /// A snapshot settles a probe too, and a placement that goes nowhere is no probe.
    @Test func aSnapshotSettlesAProbe() {
        var e = WindowEchoes()
        e.probe(s, from: from, to: to)
        let v19 = e.settle(s, seenAt: from.offsetBy(dx: 1, dy: -2))
        #expect(v19)
        #expect(e.unmovable == [s])
        var none = WindowEchoes()
        none.probe(s, from: to, to: to); none.probe(a, from: nil, to: to)
        let v20 = none.settle(s, seenAt: to)
        let v21 = none.settle(a, seenAt: from)
        #expect(!v20 && !v21)
    }

    // MARK: - #108 / #57: the hand

    /// A tile moving under a held button, pressed on the window, same size: a drag starts, holding
    /// the window where the button went down; later moves continue it.
    @Test func aTileMovedUnderTheButtonIsADrag() {
        var e = WindowEchoes()
        let was = CGRect(x: 8, y: 33, width: 984, height: 658)
        let v = e.interpret(a, frame: was.offsetBy(dx: 40, dy: 10), moved(was: was) {
            $0.pointerDown = CGPoint(x: 100, y: 40); $0.isTile = true
        })
        #expect(v.action == .drag(start: CGVector(dx: 92, dy: 7)))
        let v22 = e.interpret(a, frame: was.offsetBy(dx: 80, dy: 10), moved(was: was) { $0.dragging = a })
        #expect(v22.action == .drag(start: nil))
    }

    @Test func notADrag() {
        var e = WindowEchoes()
        let was = CGRect(x: 8, y: 33, width: 984, height: 658)
        let press = CGPoint(x: 100, y: 40)
        let v23 = e.interpret(a, frame: was.offsetBy(dx: 40, dy: 0), moved(was: was) { $0.isTile = true })
        #expect(v23.action == .snapBack, "no button held")
        let v24 = e.interpret(a, frame: was.offsetBy(dx: 40, dy: 0), moved(was: was) { $0.pointerDown = CGPoint(x: -50, y: 0); $0.isTile = true })
        #expect(v24.action == .snapBack, "pressed off the window")
        let v25 = e.interpret(a, frame: CGRect(x: 48, y: 33, width: 944, height: 658), moved(was: was) { $0.pointerDown = press; $0.isTile = true })
        #expect(v25.action == .snapBack, "resized from its left edge")
        let v26 = e.interpret(a, frame: was.offsetBy(dx: 40, dy: 0), moved(was: was) { $0.pointerDown = press })
        #expect(v26.action == .snapBack, "not a tile a drop can land on")
        let v27 = e.interpret(a, frame: was.offsetBy(dx: 40, dy: 0), moved(was: was) { $0.dragging = f })
        #expect(v27.action == .snapBack, "another window is in the hand")
        let v28 = e.interpret(a, frame: was.offsetBy(dx: 40, dy: 0), WindowEchoes.Context(event: .resized, was: was, pointerDown: press, isTile: true,
                                                                          world: world, displays: [d1]))
        #expect(v28.action == .snapBack, "a resize report is never a drag")
    }

    /// #57: right after human input, a same-size tile whose centre is now on another display was
    /// dragged there: its tab follows, into that display's active row.
    @Test func aTileDraggedOntoAnotherDisplayIsRehomed() {
        var e = WindowEchoes()
        let was = CGRect(x: 8, y: 33, width: 984, height: 658)
        let there = was.offsetBy(dx: 900, dy: 0)
        let target = world.screens["D2"]!.active.id
        let v29 = e.interpret(a, frame: there, moved(was: was) { $0.humanRecently = true })
        #expect(v29.action == .rehome(display: "D2", workspace: target))
        let v30 = e.interpret(a, frame: there, moved(was: was))
        #expect(v30.action == .snapBack, "no human behind it: the model wins")
        let v31 = e.interpret(a, frame: there, moved(was: was) { $0.humanRecently = true; $0.parked = [a] })
        #expect(v31.action == .snapBack, "a parked window was not on screen to be dragged")
        let v32 = e.interpret(f, frame: CGRect(x: 1200, y: 100, width: 400, height: 300),
                            moved(was: CGRect(x: 200, y: 100, width: 400, height: 300)) { $0.humanRecently = true })
        #expect(v32.action == .rehome(display: "D2", workspace: target), "a floating window is rehomed too")
    }

    // MARK: - bookkeeping

    @Test func forgettingAWindowForgetsEverything() {
        var e = confirmed(small)
        e.record(.setFrame(a, tile)); e.probe(a, from: from, to: to)
        _ = e.settle(a, seenAt: from)
        e.forget(a)
        #expect(e.refused.isEmpty && e.unmovable.isEmpty)
        let v33 = e.interpret(a, frame: tile, resized())
        #expect(v33.action == .snapBack, "no intent left")
    }
}
