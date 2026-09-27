import Testing
import Foundation
@testable import SpacialShellKit

/// #170: what a focus or activation report means, asked of `FocusEchoes` directly with an injected
/// clock — no store, no backend. The store records its raises, its commands and the human's input
/// here and follows the verdict (#67, #69, #84, and #28's fullscreen guard).
///
/// Mutating calls are bound to a local before `#expect` (see `IntentSetTests`: the macro cannot
/// call a mutating member on its captured receiver).
@Suite struct FocusEchoesTests {
    final class Clock: @unchecked Sendable { var t = ContinuousClock.now }
    let clock = Clock()
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 1)
    let other = WindowRef(id: 4, pid: 9)
    let shell: Int32 = 77

    func echoes() -> FocusEchoes { FocusEchoes(ownPid: shell, now: { [clock] in clock.t }) }
    func later(_ d: Duration) { clock.t = clock.t.advanced(by: d) }

    /// `a`, `b`, `c` and `other` tiled on D1, the model focused on `on`. Which row each is in is
    /// the store's business; the verdicts only ask where the model's focus is.
    func row(focused on: WindowRef) -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        for r in [a, b, c, other] { w.adopt(r, kind: .tile, on: "D1") }
        w.focus = Focus(screen: "D1", window: on)
        return w
    }

    // MARK: - own echo vs human change

    @Test func aReportOfTheWindowWeJustRaisedIsOurEcho() {
        var e = echoes()
        let due = e.recordRaise(of: b)
        #expect(due)
        let v = e.focusReported(b, world: row(focused: b))
        #expect(v == .ownEcho)
    }

    @Test func theSameWindowIsNotRaisedTwice() {
        var e = echoes()
        let first = e.recordRaise(of: b), again = e.recordRaise(of: b), next = e.recordRaise(of: c)
        #expect(first && !again && next)
    }

    @Test func aReportOfAnotherWindowIsTheHuman() {
        var e = echoes()
        _ = e.recordRaise(of: b)
        let v = e.focusReported(c, world: row(focused: b))
        #expect(v == .change)
    }

    /// Past `echoWindow` a raise's echo is not coming (raising the app already in front activates
    /// nothing): a report of that window is a human choice again.
    @Test func anEchoTooLateIsTheHumanAgain() {
        var e = echoes()
        _ = e.recordRaise(of: b)
        later(.seconds(1))
        let v = e.focusReported(b, world: row(focused: b))
        #expect(v == .change)
    }

    /// macOS reports raises in order, so an echo retires every raise queued before it.
    @Test func anEchoRetiresEveryOlderRaise() {
        var e = echoes()
        _ = e.recordRaise(of: b); _ = e.recordRaise(of: c)
        let ofC = e.focusReported(c, world: row(focused: c))
        let ofB = e.focusReported(b, world: row(focused: c))
        #expect(ofC == .ownEcho && ofB == .change)
    }

    /// An unchanged focus is news about nothing (the backstop snapshot re-reports it every refresh).
    @Test func anUnchangedReportIsARepeat() {
        var e = echoes()
        let first = e.focusReported(a, world: row(focused: a))
        let again = e.focusReported(a, world: row(focused: a))
        #expect(first == .change && again == .repeated)
    }

    // MARK: - the historical regressions

    /// #67: Fn+D, Fn+D quickly. The late echo of the first raise must not step focus back a tab;
    /// the second raise's own echo is ours.
    @Test func aLateEchoInsideTheRowIsStale() {
        var e = echoes()
        _ = e.recordRaise(of: b); _ = e.recordRaise(of: c)
        let ofB = e.focusReported(b, world: row(focused: c))
        let ofC = e.focusReported(c, world: row(focused: c))
        #expect(ofB == .stale, "a stale in-row echo would step focus back")
        #expect(ofC == .ownEcho)
    }

    /// #69: fast Fn+W/Fn+S raises `other`, then `a`, before macOS reports `other`. Its late
    /// activation and its late focus report are both ours, not a human going back.
    @Test func aLateEchoOfAnEarlierRaiseIsOurs() {
        var e = echoes()
        _ = e.recordRaise(of: other); _ = e.recordRaise(of: a)
        let activation = e.activationReported(pid: 9, world: row(focused: a))
        let focus = e.focusReported(other, world: row(focused: a))
        #expect(activation == .ownEcho, "a stale activation echo would switch the workspace back")
        #expect(focus == .stale, "a stale focus echo would switch the workspace back")
    }

    /// #69's backstop: long after the raise, activating that app is a human choice again (#56).
    @Test func anActivationLongAfterOurRaiseIsTheHuman() {
        var e = echoes()
        _ = e.recordRaise(of: other); _ = e.recordRaise(of: a)
        later(.seconds(5))
        let v = e.activationReported(pid: 9, world: row(focused: a))
        #expect(v == .change)
        let raisedLast = e.activationReported(pid: 1, world: row(focused: a))
        #expect(raisedLast == .ownEcho, "the app we raised last is on screen already")
    }

    /// #84: right after a command moves focus, macOS re-reports the window it still has before
    /// our raise lands. That is the past; a second later an unchanged report means macOS really
    /// did not move.
    @Test func aStaleUnchangedReportRightAfterACommandIsThePast() {
        var e = echoes()
        let first = e.focusReported(a, world: row(focused: a))
        #expect(first == .change)
        e.commanded(b)
        let soon = e.focusReported(a, world: row(focused: b))
        #expect(soon == .stale, "a stale report would pull focus back a tab")
        later(.seconds(2))
        let long = e.focusReported(a, world: row(focused: b))
        #expect(long == .repeated, "macOS really is on a: the model follows")
    }

    /// #84's rule is about the unchanged report only: a click on another window goes through.
    @Test func aRealChangeRightAfterACommandIsTheHuman() {
        var e = echoes()
        _ = e.focusReported(a, world: row(focused: a))
        e.commanded(b)
        let v = e.focusReported(c, world: row(focused: b))
        #expect(v == .change)
    }

    // MARK: - #28: intrusions while fullscreen is in front

    let video = WindowRef(id: 10, pid: 1), pushy = WindowRef(id: 20, pid: 9)

    /// A fullscreen `video` focused on D1, `pushy` behind it in the same row; D2 (when asked for) empty.
    func fullscreen(twoDisplays: Bool = true) -> World {
        var w = World.empty(screens: twoDisplays ? ["D1", "D2"] : ["D1"], defaultLayout: .maximize)
        w.adopt(video, kind: .tile, on: "D1"); w.adopt(pushy, kind: .tile, on: "D1")
        w.setFullscreen(video, true)
        w.focus = Focus(screen: "D1", window: video)
        return w
    }

    @Test func aWindowTakingFocusBehindFullscreenIsAnIntrusion() {
        var e = echoes()
        let focus = e.focusReported(pushy, world: fullscreen())
        let activation = e.activationReported(pid: 9, world: fullscreen())
        #expect(focus == .intrusion(behind: video) && activation == .intrusion(behind: video))
    }

    @Test func rightAfterHumanInputItIsTheHuman() {
        var e = echoes()
        e.humanInput()
        later(.milliseconds(500))
        let v = e.focusReported(pushy, world: fullscreen())
        #expect(v == .change)
        later(.seconds(2))
        let late = e.activationReported(pid: 9, world: fullscreen())
        #expect(late == .intrusion(behind: video), "long after the input it is an intrusion again")
    }

    @Test func notIntrusions() {
        var e = echoes()
        let own = e.activationReported(pid: 1, world: fullscreen())
        #expect(own == .change, "the fullscreen window's own app activating is no Space switch")
        let shellItself = e.activationReported(pid: shell, world: fullscreen())
        #expect(shellItself == .change, "the shell's own panels are never intrusions")
        let unmanaged = e.focusReported(WindowRef(id: 99, pid: 5), world: fullscreen())
        #expect(unmanaged == .change, "a window the model does not manage is left alone")
        _ = e.recordRaise(of: pushy)
        let ours = e.focusReported(pushy, world: fullscreen())
        #expect(ours == .stale, "our own raise is no intrusion (and, the model being on video, it is history)")
        let noFullscreen = e.focusReported(b, world: row(focused: a))
        #expect(noFullscreen == .change)
    }

    /// With a display free, the requester goes there, into its active row; the fullscreen window
    /// goes back in front, and is raised even if it was the last window we raised.
    @Test func anIntruderMovesToAFreeDisplay() {
        var e = echoes()
        let w = fullscreen()
        _ = e.recordRaise(of: video)
        let i = e.intercept(pushy, behind: video, world: w)
        #expect(i == FocusEchoes.Interception(screen: "D1", requester: .move(display: "D2", workspace: w.screens["D2"]!.active.id)))
        let raiseAgain = e.recordRaise(of: video)
        #expect(raiseAgain)
    }

    /// One display: nowhere to go, so the request waits until fullscreen ends — and is honoured
    /// only if the user is still on the window fullscreen ended in.
    @Test func anIntruderOnOneDisplayIsDeferredUntilFullscreenEnds() {
        var e = echoes()
        var w = fullscreen(twoDisplays: false)
        let i = e.intercept(pushy, behind: video, world: w)
        #expect(i == FocusEchoes.Interception(screen: "D1", requester: .deferred))
        let still = e.drainDeferred(world: w)
        #expect(still == nil, "fullscreen has not ended")
        w.setFullscreen(video, false)
        let next = e.drainDeferred(world: w)
        #expect(next == pushy)
        let once = e.drainDeferred(world: w)
        #expect(once == nil, "handed out once")
    }

    @Test func aDeferredRequestIsDroppedOnceTheUserHasMovedOn() {
        var e = echoes()
        var w = fullscreen(twoDisplays: false)
        _ = e.intercept(pushy, behind: video, world: w)
        w.setFullscreen(video, false)
        w.adopt(a, kind: .tile, on: "D1"); w.focus = Focus(screen: "D1", window: a)   // the user went to `a`
        let v = e.drainDeferred(world: w)
        #expect(v == nil)
        w.focus = Focus(screen: "D1", window: video)
        let gone = e.drainDeferred(world: w)
        #expect(gone == nil, "dropped, not held")
    }

    /// An app with no window the model can show: the fullscreen window still goes back in front.
    @Test func anActivationWithNoWindowStillPutsFullscreenBack() {
        var e = echoes()
        let i = e.intercept(nil, behind: video, world: fullscreen())
        #expect(i == FocusEchoes.Interception(screen: "D1", requester: nil))
        let gone = e.intercept(pushy, behind: WindowRef(id: 99, pid: 5), world: fullscreen())
        #expect(gone == nil, "a fullscreen window the model does not place has no display")
    }

    // MARK: - bookkeeping

    @Test func aVanishedWindowIsForgotten() {
        var e = echoes()
        _ = e.focusReported(a, world: row(focused: a)); _ = e.recordRaise(of: a)
        e.vanished(a)
        let v = e.focusReported(a, world: row(focused: a))
        #expect(v == .ownEcho, "the queued echo is still ours")
        e.vanished(a)
        let again = e.focusReported(a, world: row(focused: a))
        #expect(again == .change, "no longer the last reported focus")
        let raise = e.recordRaise(of: a)
        #expect(raise, "no longer the last raised")
    }

    @Test func aRetiredWindowIsNoLongerTheLastRaised() {
        var e = echoes()
        _ = e.focusReported(a, world: row(focused: a)); _ = e.recordRaise(of: a)
        e.retired(a)
        let raise = e.recordRaise(of: a)
        #expect(raise)
    }
}
