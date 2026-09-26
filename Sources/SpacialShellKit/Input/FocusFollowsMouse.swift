import CoreGraphics
import Foundation

/// #135 (G28): what the pointer can focus, as the last reconcile framed it. The store builds one
/// on every publish and hands it to the platform's pointer watcher, which hit-tests every mouse
/// move against it on the main thread, never touching the store's actor.
///
/// Only **tiled windows in an active row** are targets. Everything drawn over them is a cover the
/// pointer can pass through, or rest on, without moving focus: floating windows, ephemeral
/// visitors, and the rail and tab bar strips, which stay covers while the rail auto-hides, since
/// that edge is where the pointer goes to reveal it.
///
/// A tile that a floating or ephemeral window overlaps is not a target anywhere, not even on its
/// uncovered part: macOS has no public way to focus a window without raising it, and raising the
/// tile would bury the window on top of it. A display showing a native-fullscreen Space offers
/// nothing: its tiles are behind the Space.
/// All frames are global, top-left origin: the space of AX frames and `CGEvent.location`.
public struct PointerTargets: Equatable, Sendable {
    public var tiles: [WindowRef: CGRect]
    public var covers: [CGRect]
    /// The model's focused window, when these were built.
    public var focused: WindowRef?

    public static let empty = PointerTargets(tiles: [:], covers: [], focused: nil)

    public init(tiles: [WindowRef: CGRect], covers: [CGRect], focused: WindowRef?) {
        self.tiles = tiles; self.covers = covers; self.focused = focused
    }

    /// - Parameters:
    ///   - shown: each display's active row as the last reconcile framed it (`ShownRow.frames`
    ///     carries its tiled and floating windows).
    ///   - observed: frames for the ephemeral windows, which no row carries.
    public init(world: World, shown: [DisplayID: ShownRow], observed: [WindowRef: CGRect],
                displays: [DisplayInfo], config: Config) {
        var tiles: [WindowRef: CGRect] = [:]
        var windows: [CGRect] = []   // floating and ephemeral: the covers a raise would bury
        for d in world.screenOrder where !world.showsFullscreenSpace(d) {
            guard let row = shown[d] else { continue }
            let tiled = Set(row.row)
            for (r, f) in row.frames.sorted(by: { $0.key.id < $1.key.id }) {
                if tiled.contains(r) { tiles[r] = f } else { windows.append(f) }
            }
        }
        for r in world.ephemeral.sorted(by: { $0.id < $1.id }) where !world.hidden.contains(r) {
            if let f = observed[r] { windows.append(f) }
        }
        tiles = tiles.filter { _, f in !windows.contains { $0.intersects(f) } }
        var covers = windows
        if config.showPanels, !world.zen {
            for d in displays where world.screens[d.id] != nil {
                covers.append(contentsOf: Self.panelStrips(d.visibleFrame, config: config))
            }
        }
        self.init(tiles: tiles, covers: covers, focused: world.focus.window)
    }

    /// The rail's column and the tab bar's row on one display: where `ShellInsets` would inset a
    /// tiling rect, whether or not the rail currently takes that width.
    static func panelStrips(_ vf: CGRect, config: Config) -> [CGRect] {
        let w = CGFloat(config.panelWidth), h = CGFloat(config.panelHeight)
        let railX = config.railSide == .left ? vf.minX : vf.maxX - w
        return [CGRect(x: railX, y: vf.minY, width: w, height: vf.height),
                CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: h)]
    }

    /// The tile under `p`, or nil over a cover, a gap, a parked sliver, or nothing managed.
    public func window(at p: CGPoint) -> WindowRef? {
        guard !covers.contains(where: { $0.contains(p) }) else { return nil }
        return tiles.first { $0.value.contains(p) }?.key
    }
}

/// #135 (G28): focus follows the mouse, with a dwell — a pure function of pointer moves, a clock
/// and the model's focus. The platform feeds `moved` from a listen-only tap, drives `tick` with a
/// timer while `deadline` is set, and runs the window `tick` returns through the store as
/// `.focusWindowRef`, exactly like a click on its tab.
///
/// The rules, each one a way the pointer must *not* steal focus:
/// - Only movement arms a dwell. A pointer at rest while a key, a swipe or a command moves focus
///   (or a pointer warp, #107, puts it somewhere) changes nothing.
/// - The pointer has to *rest*: stay within `restRadius` of one spot, over the same tile, for
///   `delay`. Sweeping across a window on the way to another one never focuses it.
/// - Focus moving by any other route during the dwell (a key, a click, a warp's command) abandons
///   it: the user has already chosen.
/// - A key press or mouse button cancels it (`cancel`).
public struct FocusFollowsMouse: Equatable, Sendable {
    public static let defaultDelayMs = 150
    /// 50 ms is about one sweep's worth of moves; past 2 s it is no longer "following".
    public static let delayRangeMs = 50...2000
    /// A hand resting on a mouse still twitches by a point or two; a trackpad settles to zero.
    public static let restRadius: CGFloat = 6

    public struct Pending: Equatable, Sendable {
        public var target: WindowRef
        /// Where the pointer came to rest; moving further than `restRadius` from it starts again.
        public var anchor: CGPoint
        public var due: TimeInterval
        /// Focus when the dwell began; if it has moved since, the dwell is abandoned.
        public var focusedAtStart: WindowRef?
    }

    public var delay: TimeInterval
    public private(set) var pending: Pending?

    public init(delayMs: Int = FocusFollowsMouse.defaultDelayMs) {
        delay = TimeInterval(Self.clamp(delayMs)) / 1000
    }

    public static func clamp(_ ms: Int) -> Int { min(delayRangeMs.upperBound, max(delayRangeMs.lowerBound, ms)) }

    /// When `tick` next needs calling, or nil when nothing is pending.
    public var deadline: TimeInterval? { pending?.due }

    /// A mouse move to `p`, over `target` (`PointerTargets.window(at:)`).
    public mutating func moved(to p: CGPoint, over target: WindowRef?, focused: WindowRef?, now: TimeInterval) {
        guard let target, target != focused else { pending = nil; return }
        if let pd = pending, pd.target == target, hypot(p.x - pd.anchor.x, p.y - pd.anchor.y) <= Self.restRadius {
            return   // still resting: the clock keeps running
        }
        pending = Pending(target: target, anchor: p, due: now + delay, focusedAtStart: focused)
    }

    /// The clock. Returns the window to focus when a dwell completes: the pointer is still over its
    /// target (`over`, hit-tested now, since the layout may have moved under a resting pointer),
    /// and focus has not moved since the dwell began.
    public mutating func tick(now: TimeInterval, over: WindowRef?, focused: WindowRef?) -> WindowRef? {
        guard let pd = pending, now >= pd.due else { return nil }
        pending = nil
        guard over == pd.target, focused == pd.focusedAtStart, pd.target != focused else { return nil }
        return pd.target
    }

    /// A key press, a mouse button, the feature switched off.
    public mutating func cancel() { pending = nil }

    /// The last check, against the window server's own stacking (`CGWindowListCopyWindowInfo`,
    /// front to back): the frontmost window under the pointer must be an ordinary (layer 0) window
    /// of the target's app. Anything else in front — a menu, a popover, a Notification Center
    /// banner, the shell's own panels or hover cards, a window the model does not manage — means
    /// the pointer is not really on the tile, and focus stays.
    public static func accepts(_ target: WindowRef, frontmost: (pid: Int32, layer: Int)?) -> Bool {
        guard let frontmost else { return false }
        return frontmost.layer == 0 && frontmost.pid == target.pid
    }
}
