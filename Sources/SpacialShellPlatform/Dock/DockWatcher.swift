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
/// **Cost.** A full read is one `kAXChildren` read on the Dock's list plus one
/// `AXUIElementCopyMultipleAttributeValues` per item — a single round trip each, not five. #212: it
/// runs only every `DockReader.refreshEvery` polls; the polls between ask only `DockPoll.live`'s
/// items — the running apps', the only ones whose badge or bounce can mark a tile, and one anchor.
/// The running-app map is re-read when an app launches or quits, with a slow backstop. Polls run every `interval` on a utility queue, never the main
/// thread; the Dock's messaging timeout is capped so a wedged Dock cannot stall the queue for long.
/// Mean and worst poll times are logged once a minute (`log stream --predicate 'category == "dock"'
/// --level debug`).
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
    /// #212: launches and quits, which are what change the running-app map.
    private var observers: [NSObjectProtocol] = []
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
            let center = NSWorkspace.shared.notificationCenter
            observers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map {
                center.addObserver(forName: $0, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async { self?.reader.appsChanged() }
                }
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel(); timer = nil
            observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
            observers = []
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
    /// #212: what a poll between full reads asks a running app's item — no subrole, no URL.
    private let liveAttributes = [kAXPositionAttribute, kAXSizeAttribute, "AXStatusLabel"] as CFArray
    private var list: AXUIElement?
    /// The Dock's app items as of the last full read: their elements, bundle paths, and frames and
    /// badges as last read. A full read every `refreshEvery` reads (4 s at the watcher's pace)
    /// picks up an item added or moved since; the reads between ask only running apps' items.
    static let refreshEvery = 8
    private struct Item { let element: AXUIElement; let path: String?; var frame: CGRect; var badge: String? }
    private var items: [Item] = []
    private var reads = 0
    private var pids: [String: [Int32]] = [:]
    /// #212: set by a launch or quit (`appsChanged`), and to start with. The map is re-read then,
    /// and otherwise only every `pidsBackstop` reads: listing every running app was ~13% of the
    /// shell's idle CPU every 4 s. The backstop catches an app the notification arrived for before
    /// it reported `isFinishedLaunching`.
    private var appsDirty = true
    static let pidsBackstop = 120
    /// #210: each app's bundle path, by pid. `bundleURL` is a LaunchServices round trip per app,
    /// and a process's bundle never changes, so only pids not seen before are asked.
    private var paths: [Int32: String] = [:]
    private var edge = DockEdge.bottom

    public init() {}

    /// An app launched or quit: the running-app map and the Dock's items (a launched app's tile
    /// appears, a quit one's goes) are both read again on the next read.
    public mutating func appsChanged() { appsDirty = true; items = [] }

    /// Nil when there is no Dock to read (not running, or no Accessibility grant).
    public mutating func read() -> DockSample? {
        if appsDirty || reads % Self.pidsBackstop == 0 { pids = runningPids(); appsDirty = false }
        let full = items.isEmpty || reads % Self.refreshEvery == 0
        reads += 1
        let read: [Int]
        if full {
            edge = Self.edge()
            guard readAll() else { return nil }
            read = Array(items.indices)
        } else if let live = readLive() {
            read = live
        } else {
            // An item went away under us (the Dock restarted, or an app quit): a full read now.
            guard readAll() else { return nil }
            read = Array(items.indices)
        }
        // Only frames read in this poll: a lift is measured against the others (see `DockPoll`).
        return DockSample(edge: edge, items: read.map { items[$0] }.map {
            DockItemSample(pids: $0.path.map { pids[$0] ?? [] } ?? [], frame: $0.frame, badge: $0.badge)
        })
    }

    /// Every app item, with everything a sample needs.
    private mutating func readAll() -> Bool {
        guard let children = children() else { items = []; return false }
        var out: [Item] = []
        for item in children {
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
                  let values = raw as? [AnyObject], values.count == 5,
                  values[0] as? String == "AXApplicationDockItem",
                  let origin = Self.point(values[1]), let size = Self.size(values[2]) else { continue }
            let url = CFGetTypeID(values[4]) == CFURLGetTypeID() ? (values[4] as! URL) : nil
            out.append(Item(element: item, path: url?.standardizedFileURL.path,
                            frame: CGRect(origin: origin, size: size), badge: values[3] as? String))
        }
        items = out
        return true
    }

    /// Only `DockPoll.live`'s items; the indices read, or nil when one of them no longer answers.
    private mutating func readLive() -> [Int]? {
        let live = DockPoll.live(items.map(\.path), running: pids)
        for i in live {
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(items[i].element, liveAttributes, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
                  let values = raw as? [AnyObject], values.count == 3,
                  let origin = Self.point(values[0]), let size = Self.size(values[1]) else { return nil }
            items[i].frame = CGRect(origin: origin, size: size)
            items[i].badge = values[2] as? String
        }
        return live
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
    private mutating func runningPids() -> [String: [Int32]] {
        var out: [String: [Int32]] = [:], seen: [Int32: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.isFinishedLaunching {
            let pid = app.processIdentifier
            guard let path = paths[pid] ?? app.bundleURL?.standardizedFileURL.path else { continue }
            seen[pid] = path
            out[path, default: []].append(pid)
        }
        paths = seen   // the exited are forgotten
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
