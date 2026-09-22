// Throwaway probe: can a third party observe Dock bounce (requestUserAttention) and per-app badges?
// Not shipped, not in Package.swift. Build: swiftc -O probe.swift -o probe
//
//   probe dump            AXIsProcessTrusted + every Dock AX item with all attributes
//   probe watch <secs>    AXObserver on Dock (app, lists, items) + 50ms attribute polling diff
//                         + NSWorkspace + distributed notification firehose. One line per event.

import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IOLBF, 0)
func ts() -> String { String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)) }
func log(_ s: String) { print("[\(ts())] \(s)") }

func attr(_ e: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
    var v: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(e, name as CFString, &v)
    return (err, v)
}
func names(_ e: AXUIElement) -> [String] {
    var n: CFArray?
    return AXUIElementCopyAttributeNames(e, &n) == .success ? (n as? [String] ?? []) : []
}
func show(_ v: CFTypeRef?) -> String {
    guard let v else { return "nil" }
    if CFGetTypeID(v) == AXValueGetTypeID() {
        let av = v as! AXValue
        switch AXValueGetType(av) {
        case .cgPoint: var p = CGPoint.zero; AXValueGetValue(av, .cgPoint, &p); return "pt(\(p.x),\(p.y))"
        case .cgSize: var s = CGSize.zero; AXValueGetValue(av, .cgSize, &s); return "size(\(s.width),\(s.height))"
        default: return "\(av)"
        }
    }
    if CFGetTypeID(v) == AXUIElementGetTypeID() { return "<element>" }
    if let a = v as? [Any] { return "[\(a.count) items]" }
    return "\(v)"
}
func snapshot(_ e: AXUIElement) -> [String: String] {
    var d: [String: String] = [:]
    for n in names(e) where n != "AXChildren" && n != "AXParent" && n != "AXTopLevelUIElement" {
        let (err, v) = attr(e, n)
        d[n] = err == .success ? show(v) : "err(\(err.rawValue))"
    }
    return d
}

guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
    fatalError("no Dock process")
}
let dockApp = AXUIElementCreateApplication(dock.processIdentifier)

func dockItems() -> [(list: AXUIElement, item: AXUIElement)] {
    let (_, kids) = attr(dockApp, "AXChildren")
    var out: [(AXUIElement, AXUIElement)] = []
    for l in (kids as? [AXUIElement] ?? []) {
        for i in (attr(l, "AXChildren").1 as? [AXUIElement] ?? []) { out.append((l, i)) }
    }
    return out
}
func label(_ i: AXUIElement) -> String { (attr(i, "AXTitle").1 as? String) ?? "?" }
// Map a dock item back to a running app by bundle URL.
func owner(_ i: AXUIElement) -> String {
    guard let url = attr(i, "AXURL").1 as? URL else { return "-" }
    let app = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
    return app.map { "\($0.bundleIdentifier ?? "?") pid=\($0.processIdentifier)" } ?? "not-running"
}

let args = CommandLine.arguments
log("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)  AXIsProcessTrusted=\(AXIsProcessTrusted())  dock pid=\(dock.processIdentifier)")
let (rootErr, _) = attr(dockApp, "AXRole")
log("Dock AXRole read -> AXError \(rootErr.rawValue)")

switch args.dropFirst().first ?? "dump" {
case "dump":
    var lastList: AXUIElement?
    for (l, i) in dockItems() {
        if lastList == nil || !CFEqual(lastList, l) { log("LIST \(snapshot(l))"); lastList = l }
        let s = snapshot(i)
        log("ITEM \(label(i)) owner=\(owner(i))")
        for k in s.keys.sorted() { print("    \(k) = \(s[k]!)") }
        var an: CFArray?
        if AXUIElementCopyActionNames(i, &an) == .success { print("    actions = \(an as? [String] ?? [])") }
    }

case "watch":
    let secs = Double(args.count > 2 ? args[2] : "20") ?? 20
    let cb: AXObserverCallback = { _, el, note, _ in
        log("AXNOTE \(note) on \(label(el)) role=\(show(attr(el, "AXRole").1)) status=\(show(attr(el, "AXStatusLabel").1))")
    }
    var obs: AXObserver?
    log("AXObserverCreate -> \(AXObserverCreate(dock.processIdentifier, cb, &obs).rawValue)")
    let notes = [kAXValueChangedNotification, kAXTitleChangedNotification, kAXUIElementDestroyedNotification,
                 kAXCreatedNotification, kAXLayoutChangedNotification, kAXSelectedChildrenChangedNotification,
                 kAXElementBusyChangedNotification, kAXMovedNotification, kAXResizedNotification,
                 kAXAnnouncementRequestedNotification, kAXFocusedUIElementChangedNotification]
    var addResults: [String: [Int32: Int]] = [:]
    func observe(_ e: AXUIElement) {
        for n in notes { let r = AXObserverAddNotification(obs!, e, n as CFString, nil).rawValue; addResults[n, default: [:]][r, default: 0] += 1 }
    }
    observe(dockApp)
    var seenLists: [AXUIElement] = []
    for (l, i) in dockItems() {
        if !seenLists.contains(where: { CFEqual($0, l) }) { seenLists.append(l); observe(l) }
        observe(i)
    }
    log("AXObserverAddNotification result codes (code:count) per notification: \(addResults)")
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs!), .defaultMode)

    // Poll every item's full attribute set and print diffs.
    // Key by subrole|title|occurrence: titles collide (an app and its minimized window share one).
    // Geometry churns whenever the Dock relays out, so geometry diffs print only for the test app.
    let geometry: Set<String> = ["AXFrame", "AXPosition", "AXSize"]
    func keyed() -> [(String, AXUIElement)] {
        var seen: [String: Int] = [:]
        return dockItems().map { (_, i) in
            let base = "\(show(attr(i, "AXSubrole").1))|\(label(i))"
            seen[base, default: 0] += 1
            return ("\(base)#\(seen[base]!)", i)
        }
    }
    var prev: [String: [String: String]] = [:]
    for (k, i) in keyed() { prev[k] = snapshot(i) }
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
        for (k, i) in keyed() {
            let s = snapshot(i)
            if let p = prev[k] {
                for key in Set(p.keys).union(s.keys) where p[key] != s[key]
                    && (!geometry.contains(key) || k.contains("AttentionBouncer")) {
                    log("DIFF \(k) owner=\(owner(i)) \(key): \(p[key] ?? "absent") -> \(s[key] ?? "absent")")
                }
            } else { log("NEWITEM \(k) owner=\(owner(i)) \(s)") }
            prev[k] = s
        }
    }
    NSWorkspace.shared.notificationCenter.addObserver(forName: nil, object: nil, queue: .main) { n in
        log("NSWORKSPACE \(n.name.rawValue) \(n.userInfo?[NSWorkspace.applicationUserInfoKey].map { "\($0)" } ?? "")")
    }
    DistributedNotificationCenter.default().addObserver(forName: nil, object: nil, queue: .main) { n in
        log("DISTRIBUTED \(n.name.rawValue) object=\(n.object ?? "nil")")
    }
    // Controls: prove the two firehoses deliver at all in this process.
    for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
        NSWorkspace.shared.notificationCenter.addObserver(forName: n, object: nil, queue: .main) { n in
            log("NSWORKSPACE(named) \(n.name.rawValue) \(n.userInfo?[NSWorkspace.applicationUserInfoKey].map { "\($0)" } ?? "")")
        }
    }
    let control = Notification.Name("me.askalice.attention-probe.control")
    DistributedNotificationCenter.default().addObserver(forName: control, object: nil, queue: .main) { _ in log("DISTRIBUTED(named) control received") }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        DistributedNotificationCenter.default().postNotificationName(control, object: nil, userInfo: nil, deliverImmediately: true)
        log("posted distributed control")
    }
    log("watching \(secs)s")
    DispatchQueue.main.asyncAfter(deadline: .now() + secs) { log("done"); exit(0) }
    CFRunLoopRun()

default:
    print("usage: probe dump | probe watch <secs>")
}
