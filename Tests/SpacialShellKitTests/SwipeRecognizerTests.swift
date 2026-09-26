import Testing
import Foundation
@testable import SpacialShellKit

/// #141 (G27): trackpad swipes as Fn+W/A/S/D. Pure: frames in, at most one direction out.
@Suite struct SwipeRecognizerTests {
    /// Every direction the recognizer returned while the centroid of `fingers` fingers moved from
    /// (0.5, 0.5) by (dx, dy) in `steps` even frames, then the fingers lifted.
    private func swipe(_ r: inout SwipeRecognizer, dx: Double, dy: Double, fingers: Int = 3,
                       from start: (Double, Double) = (0.5, 0.5), steps: Int = 10) -> [Direction] {
        var out: [Direction] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            if let d = r.feed(TouchFrame(fingers: fingers, x: start.0 + dx * t, y: start.1 + dy * t)) { out.append(d) }
        }
        if let d = r.feed(.lifted) { out.append(d) }
        return out
    }

    // MARK: directions

    /// Natural: content follows the fingers. Swiping left reveals the window on the right (Fn+D);
    /// swiping up reveals the workspace below (Fn+S). normalizedPosition's y grows upward.
    @Test func naturalDirectionsFollowTheContent() {
        var r = SwipeRecognizer()
        #expect(swipe(&r, dx: -0.3, dy: 0) == [.right])
        #expect(swipe(&r, dx: 0.3, dy: 0) == [.left])
        #expect(swipe(&r, dx: 0, dy: 0.3) == [.down])
        #expect(swipe(&r, dx: 0, dy: -0.3) == [.up])
    }

    @Test func invertPointsTheWayTheKeysDo() {
        var r = SwipeRecognizer(invert: true)
        #expect(swipe(&r, dx: -0.3, dy: 0) == [.left])
        #expect(swipe(&r, dx: 0.3, dy: 0) == [.right])
        #expect(swipe(&r, dx: 0, dy: 0.3) == [.up])
        #expect(swipe(&r, dx: 0, dy: -0.3) == [.down])
    }

    /// Exactly the commands Fn+W/A/S/D run.
    @Test func directionsRunTheWASDCommands() {
        #expect(SwipeRecognizer.command(for: .up) == .focusWorkspace(.up))
        #expect(SwipeRecognizer.command(for: .down) == .focusWorkspace(.down))
        #expect(SwipeRecognizer.command(for: .left) == .focusWindow(.left))
        #expect(SwipeRecognizer.command(for: .right) == .focusWindow(.right))
        let fn = KeyBindings.table(for: Config())
        for (key, direction) in [("w", Direction.up), ("s", .down), ("a", .left), ("d", .right)] {
            let chord = KeyBindings.parse("fn-\(key)")
            #expect(chord.flatMap { fn[$0] } == SwipeRecognizer.command(for: direction))
        }
    }

    // MARK: threshold and axis

    @Test func belowTheThresholdIsNothing() {
        var r = SwipeRecognizer()
        #expect(swipe(&r, dx: -(SwipeRecognizer.defaultThreshold - 0.01), dy: 0).isEmpty)
        #expect(swipe(&r, dx: 0, dy: 0.1).isEmpty)
        // …and just past it fires.
        #expect(swipe(&r, dx: -(SwipeRecognizer.defaultThreshold + 0.01), dy: 0) == [.right])
    }

    /// A 45° swipe is neither: it waits, and lifting ends it without a step.
    @Test func aDiagonalIsAmbiguous() {
        var r = SwipeRecognizer()
        #expect(swipe(&r, dx: 0.3, dy: 0.3).isEmpty)
        #expect(swipe(&r, dx: -0.3, dy: 0.25).isEmpty)   // 1.2×, under the 1.5× dominance
    }

    /// Off-axis by less than the dominance ratio still counts.
    @Test func aSlightlyCrookedSwipeCounts() {
        var r = SwipeRecognizer()
        #expect(swipe(&r, dx: -0.3, dy: 0.15) == [.right])   // 2×
        #expect(swipe(&r, dx: 0.1, dy: 0.3) == [.down])      // 3×
    }

    /// A swipe that starts diagonal and straightens out fires once it has.
    @Test func aDiagonalThatStraightensFires() {
        var r = SwipeRecognizer()
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.35, y: 0.65)) == nil)   // 45°, both past threshold
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.1, y: 0.7)) == .right)  // 0.4 vs 0.2
    }

    // MARK: finger count

    @Test func twoAndFourFingersAreIgnored() {
        var r = SwipeRecognizer()
        #expect(swipe(&r, dx: -0.4, dy: 0, fingers: 2).isEmpty)
        #expect(swipe(&r, dx: 0, dy: 0.4, fingers: 4).isEmpty)
        #expect(swipe(&r, dx: -0.4, dy: 0, fingers: 1).isEmpty)
    }

    @Test func theCountIsConfigurable() {
        var r = SwipeRecognizer(fingers: 4)
        #expect(swipe(&r, dx: -0.4, dy: 0, fingers: 3).isEmpty)
        #expect(swipe(&r, dx: -0.4, dy: 0, fingers: 4) == [.right])
    }

    /// Lifting a four-finger (Mission Control) swipe passes through three fingers still moving;
    /// that is not a three-finger swipe.
    @Test func liftingFromFourThroughThreeDoesNotFire() {
        var r = SwipeRecognizer()
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.5)) == nil)   // landing: 3 on the way to 4
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.8)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.85)) == nil)  // one lifts, the rest still moving
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 1.0)) == nil)
        #expect(r.feed(.lifted) == nil)
        #expect(swipe(&r, dx: 0, dy: 0.3) == [.down])                    // the next real swipe works
    }

    /// Dropping below the count forgets where the swipe started: the travel is counted from where
    /// the count matched again, not from the first landing.
    @Test func fewerFingersResetTheStart() {
        var r = SwipeRecognizer()
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.42, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 2, x: 0.40, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.38, y: 0.5)) == nil)  // a fresh start here
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.30, y: 0.5)) == nil)  // 0.08 from it: not yet, though 0.2 from the first
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.20, y: 0.5)) == .right)
    }

    // MARK: one fire per gesture

    @Test func oneSwipeIsOneStep() {
        var r = SwipeRecognizer()
        #expect(swipe(&r, dx: -0.9, dy: 0, from: (0.95, 0.5), steps: 60) == [.right])
        // Reversing, or turning a corner, without lifting is still the same gesture.
        var fired: [Direction] = []
        for x in stride(from: 0.9, through: 0.1, by: -0.05) {
            if let d = r.feed(TouchFrame(fingers: 3, x: x, y: 0.5)) { fired.append(d) }
        }
        for x in stride(from: 0.1, through: 0.9, by: 0.05) {
            if let d = r.feed(TouchFrame(fingers: 3, x: x, y: 0.5)) { fired.append(d) }
        }
        for y in stride(from: 0.5, through: 0.9, by: 0.05) {
            if let d = r.feed(TouchFrame(fingers: 3, x: 0.9, y: y)) { fired.append(d) }
        }
        #expect(fired == [.right])
        #expect(r.feed(.lifted) == nil)
        // Lifting re-arms: the next swipe is its own step.
        #expect(swipe(&r, dx: -0.3, dy: 0) == [.right])
    }

    @Test func resetForgetsTheGesture() {
        var r = SwipeRecognizer()
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.2, y: 0.5)) == .right)
        r.reset()
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.2, y: 0.5)) == nil)   // a new start
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.5)) == .left)
    }

    // MARK: frames

    @Test func aFrameIsTheCentroid() {
        let f = TouchFrame(positions: [(x: 0.2, y: 0.1), (x: 0.4, y: 0.3), (x: 0.6, y: 0.8)])
        #expect(f.fingers == 3)
        #expect(abs(f.x - 0.4) < 1e-9 && abs(f.y - 0.4) < 1e-9)
        #expect(TouchFrame(positions: []) == .lifted)
    }

    // MARK: macOS's own gestures (#141's Problems entry)

    @Test func systemThreeFingerSwipesConflict() {
        let domains: [[String: Int]] = [
            [TrackpadSystemGestures.verticalKey: 2, TrackpadSystemGestures.horizontalKey: 0],
            [TrackpadSystemGestures.horizontalKey: 2],
        ]
        let system = TrackpadSystemGestures(domains: domains)
        #expect(system == TrackpadSystemGestures(threeFingerVertical: true, threeFingerHorizontal: true))
        let problem = system.conflict(gestures: true, fingers: 3)
        #expect(problem?.key == Problem.Key.gestureConflict && problem?.severity == .warning)
        #expect(problem?.message.contains("four fingers") == true)
        #expect(problem?.message.contains("More Gestures") == true)
        #expect(problem?.message.contains("three-finger drag") == false)
    }

    @Test func noConflictWhenOffOrOnOtherFingers() {
        let on = TrackpadSystemGestures(threeFingerVertical: true, threeFingerHorizontal: true, threeFingerDrag: true)
        #expect(on.conflict(gestures: false, fingers: 3) == nil)
        #expect(on.conflict(gestures: true, fingers: 4) == nil)
        let off = TrackpadSystemGestures(domains: [[TrackpadSystemGestures.verticalKey: 0], [:]])
        #expect(off == TrackpadSystemGestures())
        #expect(off.conflict(gestures: true, fingers: 3) == nil)
    }

    /// The fix the warning asks for, as System Settings writes it (recorded on the user's Mac,
    /// 2026-09-26): three-finger swipes 0, full-screen apps on four (2), in both domains.
    @Test func systemGesturesMovedToFourFingersClearTheWarning() {
        let fixed: [String: Int] = [
            TrackpadSystemGestures.verticalKey: 0, TrackpadSystemGestures.horizontalKey: 0,
            "TrackpadFourFingerHorizSwipeGesture": 2, "TrackpadFourFingerVertSwipeGesture": 0,
            TrackpadSystemGestures.dragKey: 0,
        ]
        #expect(TrackpadSystemGestures(domains: [fixed, fixed]).conflict(gestures: true, fingers: 3) == nil)
    }

    @Test func threeFingerDragConflictsToo() {
        let drag = TrackpadSystemGestures(domains: [[TrackpadSystemGestures.dragKey: 1]])
        let message = drag.conflict(gestures: true, fingers: 3)?.message ?? ""
        #expect(message.contains("three-finger drag") && !message.contains("More Gestures"))
    }

    // MARK: config

    @Test func gestureKeysDefaultParseAndRoundTrip() throws {
        let d = try Config.parse(toml: "")
        #expect(d.gestures && d.gestureFingers == 3 && !d.gestureInvert)
        let c = try Config.parse(toml: "gestures = false\ngesture-fingers = 4\ngesture-invert = true\n")
        #expect(!c.gestures && c.gestureFingers == 4 && c.gestureInvert)
        let back = try Config.parse(toml: c.render())
        #expect(!back.gestures && back.gestureFingers == 4 && back.gestureInvert)
        #expect(Config.unknownKeys(toml: c.render()).isEmpty)
        #expect(Config.unknownKeys(toml: "gestures = true\ngesture-fingers = 3\ngesture-invert = false\n").isEmpty)
        #expect(Config.unknownKeys(toml: "gesture-finger = 3\n") == ["gesture-finger"])
    }

    /// Two fingers is scrolling; clamped rather than refused, like `panel-opacity`.
    @Test func gestureFingersIsClamped() throws {
        #expect(try Config.parse(toml: "gesture-fingers = 2").gestureFingers == 3)
        #expect(try Config.parse(toml: "gesture-fingers = 9").gestureFingers == 5)
    }

    @Test func theSettingsWindowOverridesGestures() {
        var file = Config(); file.gestures = true; file.gestureInvert = false
        var gui = SettingsOverrides(); gui.gestures = false; gui.gestureInvert = true
        let out = Settings.effective(config: file, overrides: gui)
        #expect(!out.gestures && out.gestureInvert)
        #expect(Settings.effective(config: file, overrides: SettingsOverrides()).gestures)
    }
}
