import CoreGraphics
import Foundation

/// #135 (G28): what the pointer can focus, as the last reconcile framed it. The store builds one
/// on every publish and hands it to the platform's pointer watcher, which hit-tests every mouse
/// move against it on the main thread, never touching the store's actor.
///
/// Targets are the **tiled and floating windows in an active row**, in stacking order, front to
/// back: the topmost window under the pointer is the one it is on. A floating window over a tile
/// is the target there, and the tile stays a target everywhere it shows. Focusing a floating
/// window raises it (macOS has no public way to focus without raising); the 2026-09-26 decision
/// on #135 accepts that.
///
/// Covers the pointer can pass through, or rest on, without moving focus: ephemeral visitors
/// (they come and go) and the rail and tab bar strips, which stay covers while the rail
/// auto-hides, since that edge is where the pointer goes to reveal it. A window an ephemeral one
/// overlaps is not a target anywhere, not even on its uncovered part: raising it would bury the
/// visitor. It still hides whatever is stacked under it. A display showing a native-fullscreen
/// Space offers nothing: its rows are behind the Space.
///
/// All frames are global, top-left origin: the space of AX frames and `CGEvent.location`.
public struct PointerTargets: Equatable, Sendable {
    public struct Target: Equatable, Sendable {
        public var window: WindowRef
        public var frame: CGRect
        /// False for a window an ephemeral one overlaps: it hides what is under it, and takes nothing.
        public var focusable: Bool
        public init(window: WindowRef, frame: CGRect, focusable: Bool = true) {
            self.window = window; self.frame = frame; self.focusable = focusable
        }
    }

    /// Front to back.
    public var windows: [Target]
    public var covers: [CGRect]
    /// The model's focused window, when these were built.
    public var focused: WindowRef?

    public static let empty = PointerTargets(windows: [], covers: [], focused: nil)

    public init(windows: [Target], covers: [CGRect], focused: WindowRef?) {
        self.windows = windows; self.covers = covers; self.focused = focused
    }

    /// - Parameters:
    ///   - shown: each display's active row as the last reconcile framed it (`ShownRow.frames`
    ///     carries its tiled and floating windows).
    ///   - observed: frames for the ephemeral windows, which no row carries.
    ///   - stacking: the store's picture of the window server's stacking, front to back
    ///     (`restack`). Windows it does not name go under the ones it does, floating over tiled,
    ///     newer over older.
    public init(world: World, shown: [DisplayID: ShownRow], observed: [WindowRef: CGRect],
                displays: [DisplayInfo], config: Config, stacking: [WindowRef] = []) {
        var framed: [(ref: WindowRef, frame: CGRect, floating: Bool)] = []
        for d in world.screenOrder where !world.showsFullscreenSpace(d) {
            guard let row = shown[d] else { continue }
            let tiled = Set(row.row)
            for (r, f) in row.frames { framed.append((r, f, !tiled.contains(r))) }
        }
        let rank = Dictionary(stacking.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        framed.sort { x, y in
            switch (rank[x.ref], rank[y.ref]) {
            case let (i?, j?): return i < j
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return x.floating != y.floating ? x.floating : x.ref.id > y.ref.id
            }
        }
        var visitors: [CGRect] = []
        for r in world.ephemeral.sorted(by: { $0.id < $1.id }) where !world.hidden.contains(r) {
            if let f = observed[r] { visitors.append(f) }
        }
        let windows = framed.map { w in
            Target(window: w.ref, frame: w.frame, focusable: !visitors.contains { $0.intersects(w.frame) })
        }
        var covers = visitors
        if config.showPanels, !world.zen {
            for d in displays where world.screens[d.id] != nil {
                covers.append(contentsOf: Self.panelStrips(d.visibleFrame, config: config))
            }
        }
        self.init(windows: windows, covers: covers, focused: world.focus.window)
    }

    /// The store's running picture of the window server's stacking, front to back. macOS raises a
    /// window when it is focused, and the reconcile raises the model's focus, so the most recently
    /// focused windows are on top: `focused` goes to the front, and windows the world no longer
    /// holds drop out.
    public static func restack(_ stacking: [WindowRef], focused: WindowRef?, world: World) -> [WindowRef] {
        var live = world.ephemeral
        for s in world.screens.values { for ws in s.workspaces { live.formUnion(ws.windows) } }
        var out = stacking.filter { live.contains($0) && $0 != focused }
        if let focused, live.contains(focused) { out.insert(focused, at: 0) }
        return out
    }

    /// The rail's column and the tab bar's row on one display: where `ShellInsets` would inset a
    /// tiling rect, whether or not the rail currently takes that width.
    static func panelStrips(_ vf: CGRect, config: Config) -> [CGRect] {
        let w = CGFloat(config.panelWidth), h = CGFloat(config.panelHeight)
        let railX = config.railSide == .left ? vf.minX : vf.maxX - w
        return [CGRect(x: railX, y: vf.minY, width: w, height: vf.height),
                CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: h)]
    }

    /// The topmost window under `p`, or nil over a cover, a gap, a parked sliver, nothing managed,
    /// or a window that cannot take focus.
    public func window(at p: CGPoint) -> WindowRef? {
        guard !covers.contains(where: { $0.contains(p) }),
              let top = windows.first(where: { $0.frame.contains(p) }), top.focusable else { return nil }
        return top.window
    }

    /// Where `r` is a target, if it is one.
    public func frame(of r: WindowRef) -> CGRect? { windows.first { $0.window == r }?.frame }
}

/// #135 (G28): focus follows the mouse, with a dwell — a pure function of pointer moves, a clock
/// and the model's focus. The platform feeds `moved` from a listen-only tap, drives `tick` with a
/// timer while `deadline` is set, and runs the window `tick` returns through the store as
/// `.focusWindowRef`, exactly like a click on its tab.
///
/// The rules, each one a way the pointer must *not* steal focus:
/// - Only movement arms a dwell. A pointer at rest while a key, a swipe or a command moves focus
///   (or a pointer warp, #107, puts it somewhere) changes nothing.
/// - The pointer has to *rest*: stay within `restRadius` of one spot, over the same window, for
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
    /// the pointer is not really on the target, and focus stays.
    public static func accepts(_ target: WindowRef, frontmost: (pid: Int32, layer: Int)?) -> Bool {
        guard let frontmost else { return false }
        return frontmost.layer == 0 && frontmost.pid == target.pid
    }
}
