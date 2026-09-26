import Foundation
import CoreGraphics

// #126 (G35): which apps are asking for attention, read off the Dock.
//
// macOS has no public way to ask. The attention study (2026-09-14) measured the two AX symptoms
// that do work: an app Dock item's `AXStatusLabel` is its badge, and while an attention request is
// pending the item's `AXPosition` lifts off the Dock's edge once per ~2 s (the bounce). The
// platform polls those (`DockWatcher`) into plain `DockSample`s; everything else is here.

/// The screen edge the Dock sits on (`com.apple.dock` `orientation`). A bounce lifts an item away
/// from that edge, so it says which coordinate to watch.
public enum DockEdge: String, Sendable, Equatable { case bottom, left, right }

/// One application item in the Dock, as one poll saw it.
public struct DockItemSample: Equatable, Sendable {
    /// Every running, finished-launching instance of the item's app (matched on the bundle URL);
    /// empty for an app that is not running or still launching (a launch bounce is not a request).
    public var pids: [Int32]
    /// AX coordinates: top-left origin, y down.
    public var frame: CGRect
    /// The badge text (`"3"`, `"•"`), or nil for none. Opaque: only "present" and "changed" matter.
    public var badge: String?
    public init(pids: [Int32], frame: CGRect, badge: String? = nil) {
        self.pids = pids; self.frame = frame; self.badge = badge
    }
}

public struct DockSample: Equatable, Sendable {
    public var edge: DockEdge
    public var items: [DockItemSample]
    public init(edge: DockEdge, items: [DockItemSample]) { self.edge = edge; self.items = items }
}

/// Turns polled Dock samples, plus which app has focus, into the set of apps wanting attention.
///
/// - **Bounce**: an item lifted at least `minLift` off the Dock's edge was bouncing. Measured
///   against the other items, not a remembered rest position: every item rests on the same edge,
///   and magnification grows icons *from* that edge, so a hovered Dock does not read as a bounce.
///   One lift holds the mark for `bounceHold` (a bounce comes every ~2 s), so the mark does not
///   flicker between bounces and goes soon after the Dock stops.
/// - **Badge**: a badge the user has not seen. Focusing the app sees it; a new value (a count going
///   up) is news again. A badge that goes away takes its mark with it.
/// - Focusing any window of the app clears both, and the focused app is never marked: you are
///   looking at it. Lifts for `settle` after that are the bounce landing, not a new request.
public struct AttentionTracker: Equatable, Sendable {
    /// The measured lift was ~52 pt; anything past a few points is not layout jitter.
    public static let minLift: CGFloat = 6
    /// A bounce every ~2 s, seen by a poll every 0.5 s: lifts can be seen up to ~2.5 s apart.
    public static let bounceHold: TimeInterval = 3
    public static let settle: TimeInterval = 1

    private var lastLift: [Int32: TimeInterval] = [:]
    private var badges: [Int32: String] = [:]
    /// The badge each app showed when the user last had it focused.
    private var seen: [Int32: String] = [:]
    private var focused: Int32?
    private var focusedAt: [Int32: TimeInterval] = [:]

    public init() {}

    /// How far each item stands off the Dock's edge, in `sample.items` order.
    public static func lifts(_ sample: DockSample) -> [CGFloat] {
        let frames = sample.items.map(\.frame)
        guard !frames.isEmpty else { return [] }
        switch sample.edge {
        case .bottom:
            let base = frames.map(\.maxY).max()!
            return frames.map { base - $0.maxY }
        case .left:
            let base = frames.map(\.minX).min()!
            return frames.map { $0.minX - base }
        case .right:
            let base = frames.map(\.maxX).max()!
            return frames.map { base - $0.maxX }
        }
    }

    public mutating func feed(_ sample: DockSample, now: TimeInterval) {
        for (item, lift) in zip(sample.items, Self.lifts(sample)) where lift >= Self.minLift {
            for pid in item.pids where pid != focused && now - (focusedAt[pid] ?? -.infinity) >= Self.settle {
                lastLift[pid] = now
            }
        }
        var next: [Int32: String] = [:]
        for item in sample.items { if let b = item.badge { for pid in item.pids { next[pid] = b } } }
        for pid in seen.keys where next[pid] == nil { seen[pid] = nil }
        badges = next
        if let focused, let b = badges[focused] { seen[focused] = b }
    }

    /// The app of the focused window (nil: nothing focused, or not a window we know).
    public mutating func focus(_ pid: Int32?, now: TimeInterval) {
        guard pid != focused else { return }
        focused = pid
        guard let pid else { return }
        lastLift[pid] = nil
        seen[pid] = badges[pid]
        focusedAt[pid] = now
    }

    public func wanting(now: TimeInterval) -> Set<Int32> {
        var out: Set<Int32> = []
        for (pid, at) in lastLift where now - at <= Self.bounceHold { out.insert(pid) }
        for (pid, b) in badges where seen[pid] != b { out.insert(pid) }
        if let focused { out.remove(focused) }
        return out
    }
}
