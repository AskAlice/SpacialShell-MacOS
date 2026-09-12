import AppKit
import ApplicationServices
import OSLog

public enum Permissions {
    /// How long the grant is given to appear before a stale TCC row is suspected out loud.
    /// Long enough that a user who is walking to System Settings, unlocking the padlock and
    /// ticking the box is never nagged; short enough that a developer staring at a checkbox
    /// that refuses to stick does not sit there for a minute.
    private static let suspectStaleAfter = Duration.seconds(20)

    /// Spec §10. Prompts once, opens the Accessibility pane, then polls each second until the
    /// grant lands.
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
    public static func waitForAccessibility(bundleID: String) async {
        if AXIsProcessTrusted() { return }
        let log = Logger(subsystem: bundleID, category: "permissions")
        _ = AXIsProcessTrustedWithOptions([axTrustedCheckOptionPrompt: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        let clock = ContinuousClock()
        let start = clock.now
        var didWarn = false
        while !AXIsProcessTrusted() {
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
