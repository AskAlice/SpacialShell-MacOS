// Adapted from AeroSpace (MIT) — Sources/AppBundle/util/NsApplicationEx.swift @ c548c7f
import AppKit

extension NSApplication.ActivationPolicy {
    var prettyDescription: String {
        switch self {
            case .accessory: "accessory"
            case .prohibited: " prohibited"
            case .regular: "regular"
            @unknown default: "unknown \(self.rawValue)"
        }
    }
}
