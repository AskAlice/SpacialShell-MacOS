// Adapted from AeroSpace (MIT) — Sources/AppBundle/util/NSRunningApplicationEx.swift @ c548c7f
import AppKit

extension NSRunningApplication {
    var idForDebug: String {
        "PID: \(processIdentifier) ID: \(bundleIdentifier ?? executableURL?.description ?? "")"
    }
}
