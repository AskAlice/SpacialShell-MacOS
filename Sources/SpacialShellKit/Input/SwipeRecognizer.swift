import Foundation

/// #141 (G27): one trackpad sample, reduced to what swipe recognition needs — how many fingers are
/// down and where their centroid is. Coordinates are `NSTouch.normalizedPosition`'s: 0…1 on each
/// axis, origin at the **lower left** of the trackpad, so y grows upward. Each axis is normalized
/// on its own, so 0.1 across is a longer physical distance than 0.1 up on a wide trackpad.
public struct TouchFrame: Equatable, Sendable {
    public var fingers: Int
    public var x: Double
    public var y: Double
    /// The event's timestamp in seconds, when known. It lets the recognizer tell a real lift from
    /// the empty frame macOS interleaves with every moving frame (see `SwipeRecognizer.liftGrace`).
    public var time: TimeInterval?

    public init(fingers: Int, x: Double, y: Double, time: TimeInterval? = nil) {
        self.fingers = fingers; self.x = x; self.y = y; self.time = time
    }

    /// The centroid of these positions; `fingers` is their count. No positions is `lifted`.
    public init(positions: [(x: Double, y: Double)], time: TimeInterval? = nil) {
        guard !positions.isEmpty else { self = .lifted; self.time = time; return }
        let n = Double(positions.count)
        self.init(fingers: positions.count,
                  x: positions.reduce(0) { $0 + $1.x } / n,
                  y: positions.reduce(0) { $0 + $1.y } / n,
                  time: time)
    }

    /// Every finger is off the trackpad.
    public static let lifted = TouchFrame(fingers: 0, x: 0, y: 0)
}

/// #160: one recognized swipe — how many fingers made it, and the way they moved (`.up` is up the
/// trackpad). What it runs is `SwipeBindings`' business.
public struct Swipe: Equatable, Sendable {
    public var fingers: Int
    public var direction: Direction

    public init(fingers: Int, direction: Direction) { self.fingers = fingers; self.direction = direction }
}

/// #141 (G27), #160: turns a stream of `TouchFrame`s into at most one `Swipe` per gesture. It
/// recognizes several finger counts at once: three to navigate, four for the layout.
///
/// The rules, each one a test in `SwipeRecognizerTests`:
/// - **Exact finger count.** Only a count in `fingers` can fire, and only at the gesture's peak
///   (below). The centroid where that count is reached is the swipe's start.
/// - **Travel threshold and a dominant axis.** It fires once the centroid has moved `threshold`
///   (normalized) along one axis *and* that axis's travel beats the other's by `dominance`. A
///   diagonal waits: the swipe may still straighten out, and until it does it is not a direction.
/// - **One fire per gesture.** After firing it stays quiet until the count drops below the fewest
///   of `fingers` (the fingers lift), so a long swipe is one step, never two, and a swipe that
///   fired on three fingers does not fire again when a fourth lands.
/// - **More fingers spoil it.** A gesture's *peak* is the most fingers it has had down at once, and
///   only the peak can fire. Fewer is a gesture being lifted: lifting a four-finger swipe passes
///   through three fingers, still moving, and that is never a three-finger swipe. A count no swipe
///   takes (five, say) spoils the gesture until the fingers lift. A finger landing raises the peak
///   and starts the swipe afresh at the new count: fingers rarely land together.
/// - **Fewer fingers reset it.** A count below the fewest of `fingers` forgets the gesture, so the
///   next time a count matches is a fresh swipe.
/// - **An empty frame is only a lift if it stays empty.** Once the fingers move, macOS follows every
///   touch frame with a second, touchless gesture event at the same timestamp. Taken as a lift, it
///   cut every swipe into one-frame pieces, and horizontal swipes (which need the most travel)
///   never fired. An empty frame with a timestamp is held for `liftGrace`: a frame with the fingers
///   still down inside it continues the swipe. Frames without timestamps keep the old rule.
///
/// The result is the way the fingers moved. `SwipeBindings` turns it into a command, and is where
/// navigation's natural-scrolling direction is applied.
public struct SwipeRecognizer: Equatable, Sendable {
    /// About 1.8 cm across a 15 cm trackpad and 1.2 cm up a 10 cm one. Well past the drift of fingers
    /// landing and settling (a few hundredths), and short enough that the step happens during the
    /// swipe rather than at its end, so it feels like the swipe did it.
    public static let defaultThreshold = 0.12
    /// The dominant axis must beat the other by half again: about 34° either side of the axis.
    public static let defaultDominance = 1.5

    /// How long an empty frame waits to become a lift. The interleaved empties land within a
    /// millisecond of the next real frame, which arrives every ~4–10 ms while fingers move.
    public static let liftGrace: TimeInterval = 0.05

    /// The finger counts a swipe can have. Empty recognizes nothing.
    public var fingers: Set<Int>
    public var threshold: Double
    public var dominance: Double
    /// When an empty frame arrived that has not yet been confirmed or disproved as a lift.
    private var emptySince: TimeInterval?
    /// The most fingers down at once since the gesture began.
    private var peak = 0

    private enum Phase: Equatable, Sendable {
        /// Waiting for the peak to be a count in `fingers`.
        case idle
        /// The count matched here; watching the centroid move.
        case tracking(x: Double, y: Double)
        /// This gesture has had its step. Quiet until the fingers lift.
        case done
    }
    private var phase = Phase.idle

    public init(fingers: Set<Int> = [3],
                threshold: Double = SwipeRecognizer.defaultThreshold,
                dominance: Double = SwipeRecognizer.defaultDominance) {
        self.fingers = fingers; self.threshold = threshold; self.dominance = dominance
    }

    /// Feeds one frame; returns a swipe the one time a gesture is recognized, and nil otherwise.
    public mutating func feed(_ frame: TouchFrame) -> Swipe? {
        if frame.fingers == 0, let t = frame.time {
            // Maybe a lift, maybe macOS's interleaved empty event: decide on the next frame.
            if emptySince == nil { emptySince = t }
            return nil
        }
        if let since = emptySince {
            emptySince = nil
            let lifted = frame.time.map { $0 - since > Self.liftGrace } ?? true
            if lifted { forget() }
        }
        let n = frame.fingers
        guard let fewest = fingers.min(), n >= fewest else { forget(); return nil }
        if n > peak {
            // A finger landed: the swipe starts again at the new count, unless it already fired.
            peak = n
            if phase != .done { phase = .idle }
        }
        guard n == peak, fingers.contains(n) else {
            // Lifting from the peak, or more fingers than any swipe takes: nothing fires.
            if phase != .done { phase = .idle }
            return nil
        }
        switch phase {
        case .done:
            return nil
        case .idle:
            phase = .tracking(x: frame.x, y: frame.y)
            return nil
        case .tracking(let x0, let y0):
            let dx = frame.x - x0, dy = frame.y - y0
            let ax = abs(dx), ay = abs(dy)
            let motion: Direction
            if ax >= threshold, ax > dominance * ay {
                motion = dx < 0 ? .left : .right
            } else if ay >= threshold, ay > dominance * ax {
                motion = dy > 0 ? .up : .down   // y grows upward
            } else {
                return nil
            }
            phase = .done
            return Swipe(fingers: n, direction: motion)
        }
    }

    /// Forget the gesture in progress, as if every finger lifted.
    public mutating func reset() { forget(); emptySince = nil }

    private mutating func forget() { phase = .idle; peak = 0 }
}

/// #141, #160: which swipe runs which command. Pure, so the whole mapping is tested in Kit; the
/// platform only feeds frames and routes the command, through the same `route` as a hotkey's.
///
/// - **Navigation** (`gesture-fingers`, three by default) mirrors Fn+W/A/S/D, the way macOS's own
///   swipes go. Horizontally content follows the fingers, like switching full-screen apps: swiping
///   left pushes the current window away to reveal the one on its right (Fn+D). Vertically the
///   swipe points, like Mission Control's swipe up and like the rail: swiping up goes to the
///   workspace above (Fn+W). (Found live: natural vertical felt inverted.) `invert` flips both.
/// - **Layout** (four fingers, `gesture-layout`): up runs `cycle-layout` and down
///   `cycle-layout-reverse`; right runs `grow-width` and left `shrink-width`, so the focused tile's
///   edge follows the fingers. `invert` does not apply: nothing scrolls. When navigation already
///   uses four fingers it keeps them, and layout swipes are off.
public struct SwipeBindings: Equatable, Sendable {
    /// The fingers layout swipes take.
    public static let layoutFingerCount = 4

    public var navigationFingers: Int
    public var invert: Bool
    public var layout: Bool

    public init(navigationFingers: Int = 3, invert: Bool = false, layout: Bool = true) {
        self.navigationFingers = navigationFingers; self.invert = invert; self.layout = layout
    }

    public init(config: Config) {
        self.init(navigationFingers: config.gestureFingers, invert: config.gestureInvert, layout: config.gestureLayout)
    }

    /// Four, while layout swipes are on and navigation does not already use four fingers.
    public var layoutFingers: Int? {
        layout && navigationFingers != Self.layoutFingerCount ? Self.layoutFingerCount : nil
    }

    /// The counts the recognizer listens for.
    public var fingerCounts: Set<Int> {
        var out: Set<Int> = [navigationFingers]
        if let l = layoutFingers { out.insert(l) }
        return out
    }

    /// The command a swipe runs, or nil for a finger count nothing is bound to.
    public func command(for swipe: Swipe) -> Command? {
        if swipe.fingers == navigationFingers {
            let d = swipe.direction
            let natural = d == .left || d == .right ? d.opposite : d
            return Self.navigation(invert ? natural.opposite : natural)
        }
        if swipe.fingers == layoutFingers { return Self.layout(swipe.direction) }
        return nil
    }

    /// The command a navigation direction runs: exactly the one Fn+W/A/S/D runs.
    public static func navigation(_ direction: Direction) -> Command {
        switch direction {
        case .up: .focusWorkspace(.up)
        case .down: .focusWorkspace(.down)
        case .left: .focusWindow(.left)
        case .right: .focusWindow(.right)
        }
    }

    /// The command a four-finger swipe runs, by the way the fingers moved: exactly the ones
    /// Fn+Space, Fn+⇧Space, Fn+⌃D and Fn+⌃A run.
    public static func layout(_ motion: Direction) -> Command {
        switch motion {
        case .up: .cycleLayout
        case .down: .cycleLayoutReverse
        case .right: .resizeWindow(.width, grow: true)
        case .left: .resizeWindow(.width, grow: false)
        }
    }
}

extension Direction {
    var opposite: Direction {
        switch self {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }
    }
}

/// #141, #160: macOS's own trackpad gestures, as its preferences record them. SpacialShell's
/// gesture tap is listen-only: it watches and cannot take an event away, so when macOS uses the
/// same number of fingers, every swipe does two things at once.
///
/// The values are what System Settings writes into `com.apple.AppleMultitouchTrackpad` (the built-in
/// trackpad) and `com.apple.driver.AppleBluetoothMultitouch.trackpad` (a Magic Trackpad). For the
/// three-finger swipe keys 2 means "three fingers" and 0 means off, and any non-zero value counts:
/// it means macOS is using three fingers for something. The four-finger keys hold the same setting
/// on four fingers, and 2 means on. `TrackpadThreeFingerDrag` is 1 when three-finger drag is on.
public struct TrackpadSystemGestures: Equatable, Sendable {
    public static let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
    public static let verticalKey = "TrackpadThreeFingerVertSwipeGesture"
    public static let horizontalKey = "TrackpadThreeFingerHorizSwipeGesture"
    public static let dragKey = "TrackpadThreeFingerDrag"
    /// #160: Mission Control and App Exposé on four fingers.
    public static let fourFingerVerticalKey = "TrackpadFourFingerVertSwipeGesture"
    /// #160: "Swipe between full-screen applications" on four fingers.
    public static let fourFingerHorizontalKey = "TrackpadFourFingerHorizSwipeGesture"
    public static let keys = [verticalKey, horizontalKey, dragKey, fourFingerVerticalKey, fourFingerHorizontalKey]

    /// Mission Control and App Exposé on three fingers.
    public var threeFingerVertical: Bool
    /// "Swipe between full-screen apps" on three fingers.
    public var threeFingerHorizontal: Bool
    /// Accessibility's three-finger drag: three fingers move the pointer with the button held.
    public var threeFingerDrag: Bool
    /// Mission Control and App Exposé on four fingers.
    public var fourFingerVertical: Bool
    /// "Swipe between full-screen applications" on four fingers.
    public var fourFingerHorizontal: Bool

    public init(threeFingerVertical: Bool = false, threeFingerHorizontal: Bool = false, threeFingerDrag: Bool = false,
                fourFingerVertical: Bool = false, fourFingerHorizontal: Bool = false) {
        self.threeFingerVertical = threeFingerVertical
        self.threeFingerHorizontal = threeFingerHorizontal
        self.threeFingerDrag = threeFingerDrag
        self.fourFingerVertical = fourFingerVertical
        self.fourFingerHorizontal = fourFingerHorizontal
    }

    /// One dictionary per domain, key → integer value; a key a domain lacks is off there. A
    /// setting on in either domain is on: which trackpad is in use is not something we can know.
    public init(domains: [[String: Int]]) {
        func on(_ key: String) -> Bool { domains.contains { ($0[key] ?? 0) != 0 } }
        func two(_ key: String) -> Bool { domains.contains { $0[key] == 2 } }
        self.init(threeFingerVertical: on(Self.verticalKey), threeFingerHorizontal: on(Self.horizontalKey),
                  threeFingerDrag: on(Self.dragKey),
                  fourFingerVertical: two(Self.fourFingerVerticalKey), fourFingerHorizontal: two(Self.fourFingerHorizontalKey))
    }

    /// The Problems entry to list, or nil. Only the finger counts SpacialShell listens for are
    /// checked (`SwipeBindings.fingerCounts`): three-finger swipes and drag against three, the
    /// four-finger swipes against four. Five fingers is nothing macOS's swipe settings offer.
    public func conflict(gestures: Bool, fingers: Int, layout: Bool) -> Problem? {
        guard gestures else { return nil }
        let bindings = SwipeBindings(navigationFingers: fingers, layout: layout)
        let three = bindings.fingerCounts.contains(3), four = bindings.fingerCounts.contains(4)
        let swipes = three && (threeFingerVertical || threeFingerHorizontal)
        let drag = three && threeFingerDrag
        let fourH = four && fourFingerHorizontal, fourV = four && fourFingerVertical
        guard swipes || drag || fourH || fourV else { return nil }
        return .gestureConflict(swipes: swipes, drag: drag, fourFingerHorizontal: fourH, fourFingerVertical: fourV,
                                layoutSwipes: bindings.layoutFingers != nil)
    }
}
