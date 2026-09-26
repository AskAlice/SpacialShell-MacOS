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

/// #141 (G27): turns a stream of `TouchFrame`s into at most one navigation step per swipe.
///
/// The rules, each one a test in `SwipeRecognizerTests`:
/// - **Exact finger count.** Only frames with exactly `fingers` fingers can fire. The centroid
///   where the count first matches is the swipe's start.
/// - **Travel threshold and a dominant axis.** It fires once the centroid has moved `threshold`
///   (normalized) along one axis *and* that axis's travel beats the other's by `dominance`. A
///   diagonal waits: the swipe may still straighten out, and until it does it is not a direction.
/// - **One fire per gesture.** After firing it stays quiet until the count drops below `fingers`
///   (the fingers lift), so a long swipe is one step, never two.
/// - **More fingers spoil it.** Once more than `fingers` are down, nothing fires until the count
///   drops below `fingers` again. Lifting a four-finger Mission Control swipe passes through three
///   fingers, still moving; that must not count as a three-finger swipe.
/// - **Fewer fingers reset it.** A count below `fingers` forgets the start, so the next time the
///   count matches is a fresh swipe.
/// - **An empty frame is only a lift if it stays empty.** Once the fingers move, macOS follows every
///   touch frame with a second, touchless gesture event at the same timestamp. Taken as a lift, it
///   cut every swipe into one-frame pieces, and horizontal swipes (which need the most travel)
///   never fired. An empty frame with a timestamp is held for `liftGrace`: a frame with the fingers
///   still down inside it continues the swipe. Frames without timestamps keep the old rule.
///
/// The result is the direction to *navigate*: the Fn+W/A/S/D key the swipe stands for. By default
/// content follows the fingers, as with natural scrolling: swiping left pushes the current window
/// away to reveal the one on its right (`.right`, Fn+D), and swiping up reveals the workspace below
/// (`.down`, Fn+S). `invert` flips both axes.
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

    public var fingers: Int
    public var invert: Bool
    public var threshold: Double
    public var dominance: Double
    /// When an empty frame arrived that has not yet been confirmed or disproved as a lift.
    private var emptySince: TimeInterval?

    private enum Phase: Equatable, Sendable {
        /// Waiting for exactly `fingers` fingers.
        case idle
        /// The count matched here; watching the centroid move.
        case tracking(x: Double, y: Double)
        /// This gesture has had its step, or had too many fingers. Quiet until the count drops.
        case done
    }
    private var phase = Phase.idle

    public init(fingers: Int = 3, invert: Bool = false,
                threshold: Double = SwipeRecognizer.defaultThreshold,
                dominance: Double = SwipeRecognizer.defaultDominance) {
        self.fingers = fingers; self.invert = invert; self.threshold = threshold; self.dominance = dominance
    }

    /// Feeds one frame; returns a direction the one time a swipe is recognized, and nil otherwise.
    public mutating func feed(_ frame: TouchFrame) -> Direction? {
        if frame.fingers == 0, let t = frame.time {
            // Maybe a lift, maybe macOS's interleaved empty event: decide on the next frame.
            if emptySince == nil { emptySince = t }
            return nil
        }
        if let since = emptySince {
            emptySince = nil
            let lifted = frame.time.map { $0 - since > Self.liftGrace } ?? true
            if lifted { phase = .idle }
        }
        if frame.fingers < fingers { phase = .idle; return nil }
        if frame.fingers > fingers { phase = .done; return nil }
        switch phase {
        case .done:
            return nil
        case .idle:
            phase = .tracking(x: frame.x, y: frame.y)
            return nil
        case .tracking(let x0, let y0):
            let dx = frame.x - x0, dy = frame.y - y0
            let ax = abs(dx), ay = abs(dy)
            let fingerMotion: Direction
            if ax >= threshold, ax > dominance * ay {
                fingerMotion = dx < 0 ? .left : .right
            } else if ay >= threshold, ay > dominance * ax {
                fingerMotion = dy > 0 ? .up : .down   // y grows upward
            } else {
                return nil
            }
            phase = .done
            return invert ? fingerMotion : fingerMotion.opposite
        }
    }

    /// Forget the gesture in progress, as if every finger lifted.
    public mutating func reset() { phase = .idle; emptySince = nil }

    /// The command a navigation direction runs: exactly the one Fn+W/A/S/D runs.
    public static func command(for direction: Direction) -> Command {
        switch direction {
        case .up: .focusWorkspace(.up)
        case .down: .focusWorkspace(.down)
        case .left: .focusWindow(.left)
        case .right: .focusWindow(.right)
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

/// #141: macOS's own trackpad gestures, as its preferences record them. SpacialShell's gesture tap
/// is listen-only: it watches and cannot take an event away, so when macOS also uses three
/// fingers, every swipe does two things at once.
///
/// The values are what System Settings writes into `com.apple.AppleMultitouchTrackpad` (the built-in
/// trackpad) and `com.apple.driver.AppleBluetoothMultitouch.trackpad` (a Magic Trackpad): for the
/// two swipe keys 2 means "three fingers" and 0 means off (a four-finger setting lives in the
/// `…FourFinger…` keys instead); `TrackpadThreeFingerDrag` is 1 when three-finger drag is on.
/// Any non-zero value counts as a conflict: it means macOS is using three fingers for something.
public struct TrackpadSystemGestures: Equatable, Sendable {
    public static let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
    public static let verticalKey = "TrackpadThreeFingerVertSwipeGesture"
    public static let horizontalKey = "TrackpadThreeFingerHorizSwipeGesture"
    public static let dragKey = "TrackpadThreeFingerDrag"
    public static let keys = [verticalKey, horizontalKey, dragKey]

    /// Mission Control and App Exposé on three fingers.
    public var threeFingerVertical: Bool
    /// "Swipe between full-screen apps" on three fingers.
    public var threeFingerHorizontal: Bool
    /// Accessibility's three-finger drag: three fingers move the pointer with the button held.
    public var threeFingerDrag: Bool

    public init(threeFingerVertical: Bool = false, threeFingerHorizontal: Bool = false, threeFingerDrag: Bool = false) {
        self.threeFingerVertical = threeFingerVertical
        self.threeFingerHorizontal = threeFingerHorizontal
        self.threeFingerDrag = threeFingerDrag
    }

    /// One dictionary per domain, key → integer value; a key a domain lacks is off there. A
    /// setting on in either domain is on: which trackpad is in use is not something we can know.
    public init(domains: [[String: Int]]) {
        func on(_ key: String) -> Bool { domains.contains { ($0[key] ?? 0) != 0 } }
        self.init(threeFingerVertical: on(Self.verticalKey), threeFingerHorizontal: on(Self.horizontalKey),
                  threeFingerDrag: on(Self.dragKey))
    }

    /// The Problems entry to list, or nil. Only three-finger swipes are checked: those are the
    /// defaults, and the only fingers macOS's swipe settings offer besides four.
    public func conflict(gestures: Bool, fingers: Int) -> Problem? {
        guard gestures, fingers == 3 else { return nil }
        let swipes = threeFingerVertical || threeFingerHorizontal
        guard swipes || threeFingerDrag else { return nil }
        return .gestureConflict(swipes: swipes, drag: threeFingerDrag)
    }
}
