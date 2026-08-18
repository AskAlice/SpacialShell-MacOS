import AppKit
import ApplicationServices

public enum Permissions {
    /// How long the grant is given to appear before the stale-TCC-entry theory is entertained.
    /// Long enough that a user who is walking to System Settings, unlocking the padlock and
    /// ticking the box is never interrupted; short enough that a developer staring at a checkbox
    /// that refuses to stick does not sit there for a minute.
    private static let resetAfter = Duration.seconds(20)

    /// Spec §10. Prompts once, opens the Accessibility pane, then polls each second until the
    /// grant lands.
    ///
    /// A *rebuilt* binary keeps its old TCC entry (the code signature changed but the bundle id
    /// did not), which macOS silently treats as untrusted — the checkbox is on and the grant does
    /// nothing, and only `tccutil reset` clears it. But that reset also revokes a grant the user
    /// has already given, so it must never run on a first launch: doing it up front made the very
    /// first grant disappear the moment it was made, on exactly the launch where the user is
    /// least equipped to understand why. So the reset waits for the evidence for it — no grant
    /// after `resetAfter`, which is what a stale row looks like — and then runs at most once.
    public static func waitForAccessibility(bundleID: String) async {
        if AXIsProcessTrusted() { return }
        _ = AXIsProcessTrustedWithOptions([axTrustedCheckOptionPrompt: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        let clock = ContinuousClock()
        let start = clock.now
        var didReset = false
        while !AXIsProcessTrusted() {
            if !didReset, start.duration(to: clock.now) >= resetAfter {
                didReset = true
                _ = try? Process.run(URL(filePath: "/usr/bin/tccutil"), arguments: ["reset", "Accessibility", bundleID])
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
