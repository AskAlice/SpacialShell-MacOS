import AppKit
import ApplicationServices

public enum Permissions {
    /// Spec §10. Prompts once, opens the Accessibility pane, then polls each second until the
    /// grant lands. A rebuilt binary keeps the old TCC entry (the code signature changed but the
    /// bundle id didn't), which macOS silently treats as untrusted — so the first retry resets
    /// the app's Accessibility entry once, which makes the checkbox work again.
    public static func waitForAccessibility(bundleID: String) async {
        if AXIsProcessTrusted() { return }
        _ = AXIsProcessTrustedWithOptions([axTrustedCheckOptionPrompt: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        var didReset = false
        while !AXIsProcessTrusted() {
            if !didReset {
                didReset = true
                _ = try? Process.run(URL(filePath: "/usr/bin/tccutil"), arguments: ["reset", "Accessibility", bundleID])
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
