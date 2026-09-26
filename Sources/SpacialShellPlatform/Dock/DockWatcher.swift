import AppKit
import ApplicationServices
import SpacialShellKit
import os

/// #126 (G35): the Dock's badges and bounces, polled over AX into `DockSample`s. Public AX API on
/// an undocumented tree — the attention study (`docs/superpowers/specs/2026-09-14-attention-signals-
/// feasibility.md`) measured it: app items (`AXApplicationDockItem`) carry the badge in
/// `AXStatusLabel` and lift their `AXPosition` while bouncing, and none of it is pushed (every
/// item refuses `AXValueChanged`), so it has to be read. What a sample *means* is Kit's
/// `AttentionTracker`; this only reads.
///
/// **Cost.** One poll is one `kAXChildren` read on the Dock's list plus one
/// `AXUIElementCopyMultipleAttributeValues` per item — a single round trip each, not five. Polls run
/// every `interval` on a utility queue, never the main thread; the Dock's messaging timeout is
/// capped so a wedged Dock cannot stall the queue for long. Mean and worst poll times are logged
/// once a minute (`log stream --predicate 'category == "dock"' --level debug`).
public final class DockWatcher: @unchecked Sendable {
    /// A bounce is ~1 s of lift every ~2 s, so a poll every half second lands inside every one of
    /// them. Twice as often bought nothing but twice the cost (measured in `DockReaderTests`).
    public static let interval: TimeInterval = 0.5
    private static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "dock")

    private let queue = DispatchQueue(label: "sh.emu.SpacialShell.dock", qos: .utility)
    private let onSample: @Sendable (DockSample) -> Void
    // Everything below is confined to `queue`.
    private var timer: (any DispatchSourceTimer)?
    private var reader = DockReader()
    private var polls = 0
    private var total = Duration.zero
    private var worst = Duration.zero

    public init(onSample: @escaping @Sendable (DockSample) -> Void) {
        self.onSample = onSample
    }

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(50))
            t.setEventHandler { [weak self] in self?.poll() }
            t.resume()
            timer = t
        }
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel(); timer = nil
            reader = DockReader()
        }
    }

    private func poll() {
        let clock = ContinuousClock()
        var sample: DockSample?
        let took = clock.measure { sample = reader.read() }
        polls += 1; total += took; worst = max(worst, took)
        if polls % Int(60 / Self.interval) == 0 {
            let (n, mean, peak) = (polls, (total / polls).formatted(.units(allowed: [.microseconds])),
                                   worst.formatted(.units(allowed: [.microseconds])))
            Self.log.debug("dock poll: \(n) polls, mean \(mean, privacy: .public), worst \(peak, privacy: .public)")
            worst = .zero
        }
        if let sample { onSample(sample) }
    }
}

/// One read of the Dock's AX tree. Keeps the Dock's list element between reads and finds it again
/// when the Dock restarts. Not thread-safe: `DockWatcher` confines it to its queue.
public struct DockReader {
    private static let dockBundleID = "com.apple.dock"
    private static let attributeNames = ["AXSubrole", kAXPositionAttribute, kAXSizeAttribute, "AXStatusLabel", "AXURL"]
    private let attributes = DockReader.attributeNames as CFArray
    private var list: AXUIElement?
    /// The running-app map and the Dock's edge change rarely and cost more to read than the Dock
    /// itself, so they are re-read every `refreshEvery` reads (4 s at the watcher's pace): an app
    /// launched since is matched a few seconds late, and it is still launching then anyway.
    private static let refreshEvery = 8
    private var reads = 0
    private var pids: [String: [Int32]] = [:]
    private var edge = DockEdge.bottom

    public init() {}

    /// Nil when there is no Dock to read (not running, or no Accessibility grant).
    public mutating func read() -> DockSample? {
        guard let items = children() else { return nil }
        if reads % Self.refreshEvery == 0 { pids = Self.runningPids(); edge = Self.edge() }
        reads += 1
        var out: [DockItemSample] = []
        for item in items {
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
                  let values = raw as? [AnyObject], values.count == 5,
                  values[0] as? String == "AXApplicationDockItem",
                  let origin = Self.point(values[1]), let size = Self.size(values[2]) else { continue }
            let url = CFGetTypeID(values[4]) == CFURLGetTypeID() ? (values[4] as! URL) : nil
            out.append(DockItemSample(pids: url.map { pids[$0.standardizedFileURL.path] ?? [] } ?? [],
                                      frame: CGRect(origin: origin, size: size),
                                      badge: values[3] as? String))
        }
        return DockSample(edge: edge, items: out)
    }

    /// The Dock list's items, finding the list again if the cached one has gone.
    private mutating func children() -> [AXUIElement]? {
        for attempt in 0..<2 {
            if list == nil || attempt == 1 { list = Self.findList() }
            guard let list else { return nil }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &value) == .success,
               let items = value as? [AXUIElement] { return items }
        }
        return nil
    }

    private static func findList() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID).first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        return children.first { child in
            var role: CFTypeRef?
            return AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success
                && role as? String == kAXListRole
        }
    }

    /// Bundle path → pids of its running, finished-launching instances. A launch bounce is the
    /// Dock saying "starting", not "look at me", so a launching app has no pids here.
    private static func runningPids() -> [String: [Int32]] {
        var out: [String: [Int32]] = [:]
        for app in NSWorkspace.shared.runningApplications where app.isFinishedLaunching {
            guard let url = app.bundleURL else { continue }
            out[url.standardizedFileURL.path, default: []].append(app.processIdentifier)
        }
        return out
    }

    private static func edge() -> DockEdge {
        let raw = CFPreferencesCopyAppValue("orientation" as CFString, dockBundleID as CFString) as? String
        return raw.flatMap(DockEdge.init(rawValue:)) ?? .bottom
    }

    private static func point(_ v: AnyObject) -> CGPoint? {
        guard CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func size(_ v: AnyObject) -> CGSize? {
        guard CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
}
