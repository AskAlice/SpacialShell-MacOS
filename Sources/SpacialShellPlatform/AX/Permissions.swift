import AppKit
import ApplicationServices
import OSLog
import SpacialShellKit

@MainActor
public enum Permissions {
    /// How long the grant is given to appear before a stale TCC row is suspected out loud — the
    /// grant-wait window's threshold too (#130), so the log and the window agree.
    private static let suspectStaleAfter = GrantWait.suspectStaleAfter

    /// The Privacy & Security › Accessibility pane: the grant-wait window's button (#130).
    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Spec §10. Prompts once, then polls each second until the grant lands, calling `onTick` with
    /// the time waited so far (first with zero) so the grant-wait window can show it (#130).
    ///
    /// #130: it no longer opens the Accessibility pane by itself. The system prompt already offers
    /// that, and so does the grant-wait window, which also says *why* — a pane that opens unasked
    /// over whatever the user was doing explains nothing.
    ///
    /// A rebuilt binary can keep an old TCC row that macOS silently treats as untrusted — the
    /// checkbox is on and the grant does nothing. This used to shell out to
    /// `tccutil reset Accessibility <bundleID>` after `suspectStaleAfter`. It no longer does, for
    /// three reasons, in order of weight:
    ///
    /// 1. **The problem is gone where it mattered.** TCC keys the grant to the *designated
    ///    requirement*, and `Scripts/bundle.sh` now signs with a stable Developer ID whose
    ///    requirement is `certificate leaf[subject.OU] = <TEAMID>` — byte-identical across
    ///    rebuilds and across certificate renewal. The bundled app's grant survives both. The
    ///    stale row was an artefact of ad-hoc signing, whose `cdhash` changed every build.
    /// 2. **The reset was itself a bug.** It deleted the row outright, which removed the app from
    ///    the Accessibility list entirely, with no route back but the "+" button; the re-prompt
    ///    after it was a patch over that. It also revoked grants the user had legitimately given.
    /// 3. **A sandboxed process cannot launch executables at all** (#19), and App Store
    ///    distribution is the goal.
    ///
    /// There is no in-process replacement: clearing a TCC row requires `tccutil` or System
    /// Settings, and no API exposes it. So the honest answer is to *name* the condition once the
    /// evidence for it exists — no grant after `suspectStaleAfter` is what a stale row looks like
    /// — and leave the fix to the user, who can do it in two clicks. `Scripts/README` carries the
    /// same remedy in long form.
    ///
    /// The residual case the reset never fixed anyway: `Scripts/dev.sh` runs a loose binary, which
    /// TCC identifies by *path*, so a moved checkout is a new subject rather than a stale row and
    /// `tccutil reset <bundleID>` was never the cure.
    public static func waitForAccessibility(bundleID: String, onTick: (Duration) -> Void = { _ in }) async {
        if AXIsProcessTrusted() { return }
        let log = Logger(subsystem: bundleID, category: "permissions")
        _ = AXIsProcessTrustedWithOptions([axTrustedCheckOptionPrompt: true] as CFDictionary)
        let clock = ContinuousClock()
        let start = clock.now
        var didWarn = false
        while !AXIsProcessTrusted() {
            onTick(start.duration(to: clock.now))
            if !didWarn, start.duration(to: clock.now) >= suspectStaleAfter {
                didWarn = true
                log.error("""
                    Still untrusted after \(suspectStaleAfter, privacy: .public). If the \
                    Accessibility checkbox for SpacialShell is already ticked, its TCC row is \
                    stale: untick and re-tick it, or select it and press "−", then relaunch. \
                    See Scripts/README.
                    """)
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
