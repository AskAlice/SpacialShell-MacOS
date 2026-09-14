// Test app: from the background, request attention and/or set a Dock badge. No windows, no alerts.
// Args: <delaySecs> <critical|informational|badge|none> [badgeText] [holdSecs]
import AppKit
let a = CommandLine.arguments
let delay = Double(a.count > 1 ? a[1] : "3") ?? 3
let mode = a.count > 2 ? a[2] : "critical"
let badge = a.count > 3 ? a[3] : ""
let hold = Double(a.count > 4 ? a[4] : "10") ?? 10
let app = NSApplication.shared
app.setActivationPolicy(.regular)
func out(_ s: String) { FileHandle.standardError.write("bouncer: \(s)\n".data(using: .utf8)!) }
DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
    out("isActive=\(app.isActive) pid=\(ProcessInfo.processInfo.processIdentifier)")
    if !badge.isEmpty { app.dockTile.badgeLabel = badge; out("badgeLabel=\(badge)") }
    switch mode {
    case "critical": out("requestUserAttention(.criticalRequest) -> \(app.requestUserAttention(.criticalRequest))")
    case "informational": out("requestUserAttention(.informationalRequest) -> \(app.requestUserAttention(.informationalRequest))")
    default: break
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
        if !badge.isEmpty { app.dockTile.badgeLabel = nil; out("badge cleared") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { out("exit"); exit(0) }
    }
}
app.run()
