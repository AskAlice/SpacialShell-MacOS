// Native fullscreen on/off for runner.py's `fullscreen` step (#38), straight through AX:
//
//   axfullscreen PID on|off
//
// Needs only the Accessibility grant the runner already holds (in the Tart guest,
// tart-guest-agent's). Going through System Events instead needs an Automation grant, which
// tccd will not take from a TCC.db row for tart-guest-agent: it prompts anyway and the step times
// out (-1712).
// ponytail: acts on the app's first AX window; enough while fullscreen scenarios use one window
// per instance.
import ApplicationServices
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let pid = pid_t(args[1]), ["on", "off"].contains(args[2]) else {
    fputs("usage: axfullscreen PID on|off\n", stderr); exit(2)
}
guard AXIsProcessTrusted() else {
    fputs("axfullscreen: this process tree has no Accessibility grant\n", stderr); exit(3)
}
// An app still finishing its launch answers kAXErrorCannotComplete for a moment; retry for ~5 s.
var windows: CFTypeRef?
var err = AXError.cannotComplete
for _ in 0..<20 {
    err = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &windows)
    if err == .success, (windows as? [AXUIElement])?.isEmpty == false { break }
    usleep(250_000)
}
guard let window = (windows as? [AXUIElement])?.first else {
    fputs("axfullscreen: pid \(pid) has no AX window (AXError \(err.rawValue))\n", stderr); exit(4)
}
let set = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString,
                                       (args[2] == "on" ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
guard set == .success else {
    fputs("axfullscreen: setting AXFullScreen failed (AXError \(set.rawValue))\n", stderr); exit(5)
}
