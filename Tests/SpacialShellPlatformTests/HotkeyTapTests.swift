import Testing
import CoreGraphics
@testable import SpacialShellPlatform
@testable import SpacialShellKit

/// The tap's *pure* half — flags → `Chord` — plus the one lifecycle fact that can be pinned
/// without an Accessibility grant. Everything else about a `CGEventTap` (does it see the key
/// before the front app, does macOS keep it enabled across sleep) is only observable on a granted,
/// interactive session; those checks live in `docs/platform-notes.md`.
@Suite struct HotkeyTapTests {
    @Test func mapsFlagsToChord() {
        let c = HotkeyTap.chord(from: [.maskSecondaryFn, .maskShift], keyCode: 13)
        #expect(c == Chord(keyCode: 13, fn: true, control: false, option: false, shift: true, command: false))
        let d = HotkeyTap.chord(from: [.maskControl, .maskAlternate], keyCode: 126)
        #expect(d == Chord(keyCode: 126, fn: false, control: true, option: true, shift: false, command: false))
    }

    /// #31: macOS sets the Fn flag on every arrow keyDown, so a real ⌃⌥← arrives with Fn set and
    /// must still match the `ctrl-alt-left` binding.
    @Test func arrowKeysIgnoreTheHardwareFnFlag() {
        let hw: CGEventFlags = [.maskSecondaryFn, .maskControl, .maskAlternate]
        for (code, name) in [(123, "left"), (124, "right"), (125, "down"), (126, "up")] {
            #expect(HotkeyTap.chord(from: hw, keyCode: UInt16(code)) == KeyBindings.parse("ctrl-alt-\(name)"))
        }
    }

    /// #118: Fn+⇧+arrow reaches the tap as Home/End/PgUp/PgDn with Fn set; unlike a real arrow,
    /// that Fn is kept, so it matches the `fn-shift-left` (= `fn-shift-home`) binding.
    @Test func fnArrowsKeepTheirFnFlag() {
        let hw: CGEventFlags = [.maskSecondaryFn, .maskShift]
        for (code, name) in [(115, "left"), (119, "right"), (116, "up"), (121, "down")] {
            #expect(HotkeyTap.chord(from: hw, keyCode: UInt16(code)) == KeyBindings.parse("fn-shift-\(name)"))
        }
    }

    @Test func ignoresIrrelevantFlags() {
        // caps lock / numeric pad / help must not affect matching
        let c = HotkeyTap.chord(from: [.maskSecondaryFn, .maskAlphaShift, .maskNumericPad], keyCode: 0)
        #expect(c == Chord(keyCode: 0, fn: true, control: false, option: false, shift: false, command: false))
    }

    /// A bound chord's autorepeats used to pass straight through: the first keyDown was consumed
    /// and every repeat after it reached the front app as a bare keystroke, so holding Fn+S typed
    /// a burst of `s` into the editor. Repeats of a bound chord are now swallowed without
    /// re-firing; unbound chords still repeat normally.
    @Test func autorepeatOfABoundChordIsSwallowedWithoutFiring() {
        #expect(HotkeyTap.decision(isRepeat: false, bound: true) == (swallow: true, fire: true))
        #expect(HotkeyTap.decision(isRepeat: true, bound: true) == (swallow: true, fire: false))
        #expect(HotkeyTap.decision(isRepeat: false, bound: false) == (swallow: false, fire: false))
        #expect(HotkeyTap.decision(isRepeat: true, bound: false) == (swallow: false, fire: false))
    }

    /// The test host is not AX-trusted, so `CGEvent.tapCreate` returns NULL and `start()` must
    /// surface that as `TapError.creationFailed` rather than trapping or hanging on the dedicated
    /// tap thread. On a trusted host (someone granted the test runner) the tap really is created,
    /// and then `stop()` must tear the thread down. Either way: no crash, and bounded.
    @Test(.timeLimit(.minutes(1))) @MainActor func tapCanBeConstructedAndStoppedWithoutTrust() async {
        let tap = HotkeyTap(table: [:]) { _ in }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try tap.start()
            tap.stop()      // trusted host: it really started, so it must really stop
        } catch HotkeyTap.TapError.creationFailed {
            tap.stop()      // untrusted host: stop() after a failed start is a no-op
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(start.duration(to: clock.now) < .seconds(2))
    }

    /// The regression that matters most: a *later* creation failure must not kill the tap thread.
    /// If it does, the run loop goes away, every re-arm path (didWake / screenIsUnlocked /
    /// sessionDidBecomeActive) is guarded on it, and the hotkeys are dead until relaunch — with
    /// nothing in the log to say so.
    @Test(.timeLimit(.minutes(1))) func tapThreadSurvivesFailedRecreation() async {
        let tap = HotkeyTap(table: [:]) { _ in }
        defer { tap.stop() }
        tap._testStartWithoutTap()
        #expect(tap._isThreadAlive())

        tap._simulateRecreationFailure()
        #expect(tap._isThreadAlive())                      // the thread outlives the failure
        #expect(tap._breakerState().consecutiveFailures == 1)

        // …and it is still listening: a re-arm posted from "outside" reaches the tap thread.
        let before = tap._rearmCount()
        tap._rearm()
        var reached = false
        for _ in 0..<100 where !reached {
            if tap._rearmCount() > before { reached = true; break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(reached)
        #expect(tap._isThreadAlive())
    }

    /// The old breaker counted re-creations inside a 2 s window while the only caller was a 5 s
    /// poll, so every entry was always pruned and it could never trip.
    @Test func breakerTripsOnConsecutiveFailuresAndForgivesOnReset() {
        var breaker = HotkeyTap.Breaker()
        #expect(breaker.allowsAttempt)
        for _ in 1..<HotkeyTap.Breaker.limit { #expect(breaker.recordFailure() == false) }
        #expect(breaker.consecutiveFailures == HotkeyTap.Breaker.limit - 1)
        #expect(breaker.allowsAttempt)

        #expect(breaker.recordFailure() == true)           // the limit-th failure trips it
        #expect(breaker.tripped)
        #expect(!breaker.allowsAttempt)
        #expect(breaker.recordFailure() == false)          // and only trips once

        breaker.reset()                                    // wake / unlock / session activation
        #expect(breaker.allowsAttempt)
        #expect(breaker.consecutiveFailures == 0)

        // A success anywhere in a run of failures clears the count — the breaker is about
        // *consecutive* failures, not lifetime ones.
        _ = breaker.recordFailure()
        _ = breaker.recordFailure()
        breaker.recordSuccess()
        #expect(breaker.consecutiveFailures == 0)
        #expect(breaker.allowsAttempt)
    }
}
