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

    @Test func ignoresIrrelevantFlags() {
        // caps lock / numeric pad / help must not affect matching
        let c = HotkeyTap.chord(from: [.maskSecondaryFn, .maskAlphaShift, .maskNumericPad], keyCode: 0)
        #expect(c == Chord(keyCode: 0, fn: true, control: false, option: false, shift: false, command: false))
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
}
