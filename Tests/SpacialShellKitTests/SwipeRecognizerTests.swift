import Testing
import Foundation
@testable import SpacialShellKit

/// #141 (G27), #160: trackpad swipes. Pure: frames in, at most one swipe out per gesture, and
/// `SwipeBindings` for what each runs — three fingers Fn+W/A/S/D, four the layout.
@Suite struct SwipeRecognizerTests {
    /// Every swipe the recognizer returned while the centroid of `fingers` fingers moved from
    /// (0.5, 0.5) by (dx, dy) in `steps` even frames, then the fingers lifted.
    private func swipes(_ r: inout SwipeRecognizer, dx: Double, dy: Double, fingers: Int = 3,
                        from start: (Double, Double) = (0.5, 0.5), steps: Int = 10) -> [Swipe] {
        var out: [Swipe] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            if let s = r.feed(TouchFrame(fingers: fingers, x: start.0 + dx * t, y: start.1 + dy * t)) { out.append(s) }
        }
        if let s = r.feed(.lifted) { out.append(s) }
        return out
    }

    /// The same, as the directions the fingers moved.
    private func swipe(_ r: inout SwipeRecognizer, dx: Double, dy: Double, fingers: Int = 3,
                       from start: (Double, Double) = (0.5, 0.5), steps: Int = 10) -> [Direction] {
        swipes(&r, dx: dx, dy: dy, fingers: fingers, from: start, steps: steps).map(\.direction)
    }

    // MARK: directions

    /// The recognizer reports the way the fingers moved. normalizedPosition's y grows upward.
    @Test func swipesReportTheWayTheFingersMoved() {
        var r = SwipeRecognizer()
        #expect(swipes(&r, dx: -0.3, dy: 0) == [Swipe(fingers: 3, direction: .left)])
        #expect(swipe(&r, dx: 0.3, dy: 0) == [.right])
        #expect(swipe(&r, dx: 0, dy: 0.3) == [.up])
        #expect(swipe(&r, dx: 0, dy: -0.3) == [.down])
    }

    /// Like macOS's own swipes: horizontally content follows the fingers (swiping left reveals the
    /// window on the right, Fn+D); vertically the swipe points (swiping up goes to the workspace
    /// above, Fn+W, as on the rail). Found live: natural vertical felt inverted.
    @Test func naturalDirectionsFollowTheContent() {
        let b = SwipeBindings()
        #expect(b.command(for: Swipe(fingers: 3, direction: .left)) == .focusWindow(.right))
        #expect(b.command(for: Swipe(fingers: 3, direction: .right)) == .focusWindow(.left))
        #expect(b.command(for: Swipe(fingers: 3, direction: .up)) == .focusWorkspace(.up))
        #expect(b.command(for: Swipe(fingers: 3, direction: .down)) == .focusWorkspace(.down))
    }

    @Test func invertFlipsBothAxes() {
        let b = SwipeBindings(invert: true)
        #expect(b.command(for: Swipe(fingers: 3, direction: .left)) == .focusWindow(.left))
        #expect(b.command(for: Swipe(fingers: 3, direction: .right)) == .focusWindow(.right))
        #expect(b.command(for: Swipe(fingers: 3, direction: .up)) == .focusWorkspace(.down))
        #expect(b.command(for: Swipe(fingers: 3, direction: .down)) == .focusWorkspace(.up))
    }

    /// Exactly the commands Fn+W/A/S/D run.
    @Test func directionsRunTheWASDCommands() {
        #expect(SwipeBindings.navigation(.up) == .focusWorkspace(.up))
        #expect(SwipeBindings.navigation(.down) == .focusWorkspace(.down))
        #expect(SwipeBindings.navigation(.left) == .focusWindow(.left))
        #expect(SwipeBindings.navigation(.right) == .focusWindow(.right))
        let fn = KeyBindings.table(for: Config())
        for (key, direction) in [("w", Direction.up), ("s", .down), ("a", .left), ("d", .right)] {
            let chord = KeyBindings.parse("fn-\(key)")
            #expect(chord.flatMap { fn[$0] } == SwipeBindings.navigation(direction))
        }
    }

    // MARK: threshold and axis

    @Test func belowTheThresholdIsNothing() {
        var r = SwipeRecognizer()
        #expect(swipe(&r, dx: -(SwipeRecognizer.defaultThreshold - 0.01), dy: 0).isEmpty)
        #expect(swipe(&r, dx: 0, dy: 0.1).isEmpty)
        // …and just past it fires.
        #expect(swipe(&r, dx: -(SwipeRecognizer.defaultThreshold + 0.01), dy: 0) == [.left])
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
        #expect(swipe(&r, dx: -0.3, dy: 0.15) == [.left])   // 2×
        #expect(swipe(&r, dx: 0.1, dy: 0.3) == [.up])       // 3×
    }

    /// A swipe that starts diagonal and straightens out fires once it has.
    @Test func aDiagonalThatStraightensFires() {
        var r = SwipeRecognizer()
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.35, y: 0.65)) == nil)   // 45°, both past threshold
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.1, y: 0.7)) == Swipe(fingers: 3, direction: .left))  // 0.4 vs 0.2
    }

    // MARK: finger count

    @Test func twoAndFourFingersAreIgnored() {
        var r = SwipeRecognizer()
        #expect(swipe(&r, dx: -0.4, dy: 0, fingers: 2).isEmpty)
        #expect(swipe(&r, dx: 0, dy: 0.4, fingers: 4).isEmpty)
        #expect(swipe(&r, dx: -0.4, dy: 0, fingers: 1).isEmpty)
    }

    @Test func theCountIsConfigurable() {
        var r = SwipeRecognizer(fingers: [4])
        #expect(swipe(&r, dx: -0.4, dy: 0, fingers: 3).isEmpty)
        #expect(swipes(&r, dx: -0.4, dy: 0, fingers: 4) == [Swipe(fingers: 4, direction: .left)])
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
        #expect(swipe(&r, dx: 0, dy: 0.3) == [.up])                      // the next real swipe works
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
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.20, y: 0.5)) == Swipe(fingers: 3, direction: .left))
    }

    // MARK: one fire per gesture

    @Test func oneSwipeIsOneStep() {
        var r = SwipeRecognizer()
        #expect(swipe(&r, dx: -0.9, dy: 0, from: (0.95, 0.5), steps: 60) == [.left])
        // Reversing, or turning a corner, without lifting is still the same gesture.
        var fired: [Direction] = []
        for x in stride(from: 0.9, through: 0.1, by: -0.05) {
            if let s = r.feed(TouchFrame(fingers: 3, x: x, y: 0.5)) { fired.append(s.direction) }
        }
        for x in stride(from: 0.1, through: 0.9, by: 0.05) {
            if let s = r.feed(TouchFrame(fingers: 3, x: x, y: 0.5)) { fired.append(s.direction) }
        }
        for y in stride(from: 0.5, through: 0.9, by: 0.05) {
            if let s = r.feed(TouchFrame(fingers: 3, x: 0.9, y: y)) { fired.append(s.direction) }
        }
        #expect(fired == [.left])
        #expect(r.feed(.lifted) == nil)
        // Lifting re-arms: the next swipe is its own step.
        #expect(swipe(&r, dx: -0.3, dy: 0) == [.left])
    }

    @Test func resetForgetsTheGesture() {
        var r = SwipeRecognizer()
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.2, y: 0.5)) == Swipe(fingers: 3, direction: .left))
        r.reset()
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.2, y: 0.5)) == nil)   // a new start
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.5)) == Swipe(fingers: 3, direction: .right))
    }

    // MARK: frames

    @Test func aFrameIsTheCentroid() {
        let f = TouchFrame(positions: [(x: 0.2, y: 0.1), (x: 0.4, y: 0.3), (x: 0.6, y: 0.8)])
        #expect(f.fingers == 3)
        #expect(abs(f.x - 0.4) < 1e-9 && abs(f.y - 0.4) < 1e-9)
        #expect(TouchFrame(positions: []) == .lifted)
    }

    // MARK: four fingers (#160)

    /// Up cycles the layout and down cycles it back; right widens the focused tile and left
    /// narrows it, so the edge follows the fingers. The hotkeys' own commands.
    @Test func fourFingerDirectionsRunTheLayoutCommands() {
        let b = SwipeBindings()
        #expect(b.command(for: Swipe(fingers: 4, direction: .up)) == .cycleLayout)
        #expect(b.command(for: Swipe(fingers: 4, direction: .down)) == .cycleLayoutReverse)
        #expect(b.command(for: Swipe(fingers: 4, direction: .right)) == .resizeWindow(.width, grow: true))
        #expect(b.command(for: Swipe(fingers: 4, direction: .left)) == .resizeWindow(.width, grow: false))
        #expect(SwipeBindings(invert: true).command(for: Swipe(fingers: 4, direction: .up)) == .cycleLayout,
                "invert is navigation's: nothing scrolls here")
        let fn = KeyBindings.table(for: Config())
        for (chord, motion) in [("fn-space", Direction.up), ("fn-shift-space", .down), ("fn-ctrl-d", .right), ("fn-ctrl-a", .left)] {
            #expect(KeyBindings.parse(chord).flatMap { fn[$0] } == SwipeBindings.layout(motion), "\(chord)")
        }
        // End to end: frames in, command out.
        var r = SwipeRecognizer(fingers: b.fingerCounts)
        #expect(swipes(&r, dx: 0, dy: 0.3, fingers: 4).compactMap(b.command(for:)) == [.cycleLayout])
        #expect(swipes(&r, dx: 0.3, dy: 0, fingers: 4).compactMap(b.command(for:)) == [.resizeWindow(.width, grow: true)])
        #expect(swipes(&r, dx: -0.3, dy: 0, fingers: 3).compactMap(b.command(for:)) == [.focusWindow(.right)])
    }

    @Test func layoutSwipesTakeFourFingersUnlessNavigationDoes() {
        #expect(SwipeBindings().fingerCounts == [3, 4] && SwipeBindings().layoutFingers == 4)
        #expect(SwipeBindings(layout: false).fingerCounts == [3] && SwipeBindings(layout: false).layoutFingers == nil)
        let nav4 = SwipeBindings(navigationFingers: 4)
        #expect(nav4.fingerCounts == [4] && nav4.layoutFingers == nil)
        #expect(nav4.command(for: Swipe(fingers: 4, direction: .up)) == .focusWorkspace(.up), "four fingers navigate")
        #expect(SwipeBindings(navigationFingers: 5).fingerCounts == [4, 5])
        #expect(SwipeBindings().command(for: Swipe(fingers: 5, direction: .up)) == nil)
        var cfg = Config(); cfg.gestureFingers = 3; cfg.gestureInvert = true; cfg.gestureLayout = false
        #expect(SwipeBindings(config: cfg) == SwipeBindings(navigationFingers: 3, invert: true, layout: false))
    }

    /// Both counts at once, and each gesture is only ever its own count.
    @Test func threeAndFourFingersDoNotCrossFire() {
        var r = SwipeRecognizer(fingers: [3, 4])
        #expect(swipes(&r, dx: -0.3, dy: 0, fingers: 3) == [Swipe(fingers: 3, direction: .left)])
        #expect(swipes(&r, dx: -0.3, dy: 0, fingers: 4) == [Swipe(fingers: 4, direction: .left)])
        #expect(swipes(&r, dx: 0, dy: 0.3, fingers: 4) == [Swipe(fingers: 4, direction: .up)])
        #expect(swipes(&r, dx: 0, dy: 0.3, fingers: 3) == [Swipe(fingers: 3, direction: .up)])
        #expect(swipes(&r, dx: 0, dy: 0.4, fingers: 5).isEmpty, "more fingers than any swipe takes")
        #expect(swipes(&r, dx: 0, dy: 0.4, fingers: 2).isEmpty)
    }

    /// Fingers land one by one: three on the way to four is not a three-finger swipe, and the
    /// four-finger swipe is measured from where the fourth landed.
    @Test func landingThroughThreeIsAFourFingerSwipe() {
        var r = SwipeRecognizer(fingers: [3, 4])
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.58)) == nil)   // under the threshold on three
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.6)) == nil)    // the fourth lands: a fresh start
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.7)) == nil)    // 0.2 from the first landing, 0.1 from here
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.75)) == Swipe(fingers: 4, direction: .up))
        #expect(r.feed(.lifted) == nil)
    }

    /// Lifting from four through three, still moving, never fires a three — whether or not the
    /// four-finger swipe fired first.
    @Test func liftingFromFourThroughThreeDoesNotFireAThree() {
        var r = SwipeRecognizer(fingers: [3, 4])
        // Fired as four, then the rest keep going on three.
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.7)) == Swipe(fingers: 4, direction: .up))
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.75)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.2, y: 0.75)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.2, y: 0.3)) == nil)
        #expect(r.feed(.lifted) == nil)
        // Never fired as four (too short), then three travel far.
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.55, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.6, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.9, y: 0.5)) == nil)
        #expect(r.feed(.lifted) == nil)
        // A three that fired does not fire again when a fourth finger lands.
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.2, y: 0.5)) == Swipe(fingers: 3, direction: .left))
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.2, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.2, y: 0.9)) == nil)
        #expect(r.feed(.lifted) == nil)
        // …and after all that, both counts still work.
        #expect(swipes(&r, dx: 0, dy: -0.3, fingers: 3) == [Swipe(fingers: 3, direction: .down)])
        #expect(swipes(&r, dx: 0, dy: -0.3, fingers: 4) == [Swipe(fingers: 4, direction: .down)])
    }

    /// Five fingers spoils the gesture for four and three alike until the fingers lift.
    @Test func fiveFingersSpoilFourAndThree() {
        var r = SwipeRecognizer(fingers: [3, 4])
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 5, x: 0.5, y: 0.5)) == nil)
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.6)) == nil)
        #expect(r.feed(TouchFrame(fingers: 4, x: 0.5, y: 0.9)) == nil)
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.1, y: 0.9)) == nil)
        #expect(r.feed(.lifted) == nil)
    }

    // MARK: macOS's own gestures (#141's Problems entry)

    @Test func systemThreeFingerSwipesConflict() {
        let domains: [[String: Int]] = [
            [TrackpadSystemGestures.verticalKey: 2, TrackpadSystemGestures.horizontalKey: 0],
            [TrackpadSystemGestures.horizontalKey: 2],
        ]
        let system = TrackpadSystemGestures(domains: domains)
        #expect(system == TrackpadSystemGestures(threeFingerVertical: true, threeFingerHorizontal: true))
        let problem = system.conflict(gestures: true, fingers: 3, layout: false)
        #expect(problem?.key == Problem.Key.gestureConflict && problem?.severity == .warning)
        #expect(problem?.message.contains("to four fingers") == true)
        #expect(problem?.message.contains("More Gestures") == true)
        #expect(problem?.message.contains("three-finger drag") == false)
        // With layout swipes on, four fingers are taken: the advice is off, not four.
        let taken = system.conflict(gestures: true, fingers: 3, layout: true)?.message ?? ""
        #expect(taken.contains("turn off Mission Control") && taken.contains("not four fingers") && !taken.contains("to four fingers"))
    }

    @Test func noConflictWhenOffOrOnOtherFingers() {
        let on = TrackpadSystemGestures(threeFingerVertical: true, threeFingerHorizontal: true, threeFingerDrag: true)
        #expect(on.conflict(gestures: false, fingers: 3, layout: true) == nil)
        #expect(on.conflict(gestures: true, fingers: 4, layout: true) == nil)
        let off = TrackpadSystemGestures(domains: [[TrackpadSystemGestures.verticalKey: 0], [:]])
        #expect(off == TrackpadSystemGestures())
        #expect(off.conflict(gestures: true, fingers: 3, layout: true) == nil)
    }

    /// The fix the three-finger warning asks for, as System Settings writes it (recorded on the
    /// user's Mac, 2026-09-26): three-finger swipes 0, full-screen apps on four (2), in both
    /// domains. It clears the three-finger warning, and with layout swipes on it is the four-finger
    /// conflict #160 warns about.
    @Test func systemGesturesMovedToFourFingersClearTheWarning() {
        let fixed: [String: Int] = [
            TrackpadSystemGestures.verticalKey: 0, TrackpadSystemGestures.horizontalKey: 0,
            TrackpadSystemGestures.fourFingerHorizontalKey: 2, TrackpadSystemGestures.fourFingerVerticalKey: 0,
            TrackpadSystemGestures.dragKey: 0,
        ]
        let system = TrackpadSystemGestures(domains: [fixed, fixed])
        #expect(system.conflict(gestures: true, fingers: 3, layout: false) == nil)
        let message = system.conflict(gestures: true, fingers: 3, layout: true)?.message ?? ""
        #expect(message.contains("macOS also uses four fingers"))
        #expect(message.contains("\"Swipe between full-screen applications\"") && message.contains("More Gestures"))
        #expect(!message.contains("Mission Control"), "four-finger vertical is off")
    }

    @Test func threeFingerDragConflictsToo() {
        let drag = TrackpadSystemGestures(domains: [[TrackpadSystemGestures.dragKey: 1]])
        let message = drag.conflict(gestures: true, fingers: 3, layout: false)?.message ?? ""
        #expect(message.contains("three-finger drag") && !message.contains("More Gestures"))
    }

    /// #160: the four-finger keys, read from either domain; 2 means on.
    @Test func systemFourFingerSwipesConflictWithLayoutSwipes() {
        let system = TrackpadSystemGestures(domains: [
            [TrackpadSystemGestures.fourFingerVerticalKey: 2],
            [TrackpadSystemGestures.fourFingerHorizontalKey: 2],
        ])
        #expect(system == TrackpadSystemGestures(fourFingerVertical: true, fourFingerHorizontal: true))
        let problem = system.conflict(gestures: true, fingers: 3, layout: true)
        #expect(problem?.key == Problem.Key.gestureConflict && problem?.severity == .warning)
        let message = problem?.message ?? ""
        #expect(message.contains("four fingers") && !message.contains("three"))
        #expect(message.contains("\"Swipe between full-screen applications\" and Mission Control and App Exposé"))
        #expect(message.contains("Trackpad → More Gestures") && message.contains("gesture-layout = false"))
        // Clears with layout swipes off, swipes off, or the settings off.
        #expect(system.conflict(gestures: true, fingers: 3, layout: false) == nil)
        #expect(system.conflict(gestures: false, fingers: 3, layout: true) == nil)
        let off = TrackpadSystemGestures(domains: [[TrackpadSystemGestures.fourFingerVerticalKey: 0,
                                                    TrackpadSystemGestures.fourFingerHorizontalKey: 0], [:]])
        #expect(off.conflict(gestures: true, fingers: 3, layout: true) == nil)
        // Navigation on four fingers conflicts too, without the gesture-layout hint (layout is off there).
        let nav4 = system.conflict(gestures: true, fingers: 4, layout: true)?.message ?? ""
        #expect(nav4.contains("four fingers") && !nav4.contains("gesture-layout"))
        // Layout on four beside navigation on five.
        #expect(system.conflict(gestures: true, fingers: 5, layout: true) != nil)
        #expect(system.conflict(gestures: true, fingers: 5, layout: false) == nil)
    }

    /// Both at once: one entry naming both finger counts.
    @Test func threeAndFourFingerConflictsShareOneEntry() {
        let both = TrackpadSystemGestures(threeFingerVertical: true, fourFingerHorizontal: true)
        let message = both.conflict(gestures: true, fingers: 3, layout: true)?.message ?? ""
        #expect(message.contains("macOS also uses three and four fingers"))
        #expect(message.contains("Mission Control") && message.contains("\"Swipe between full-screen applications\""))
    }

    // MARK: config

    @Test func gestureKeysDefaultParseAndRoundTrip() throws {
        let d = try Config.parse(toml: "")
        #expect(d.gestures && d.gestureFingers == 3 && !d.gestureInvert && d.gestureLayout)
        let c = try Config.parse(toml: "gestures = false\ngesture-fingers = 4\ngesture-invert = true\ngesture-layout = false\n")
        #expect(!c.gestures && c.gestureFingers == 4 && c.gestureInvert && !c.gestureLayout)
        #expect(c.render().contains("gesture-layout = false"))
        let back = try Config.parse(toml: c.render())
        #expect(!back.gestures && back.gestureFingers == 4 && back.gestureInvert && !back.gestureLayout)
        #expect(try Config.parse(toml: Config().render()).gestureLayout)
        #expect(Config.unknownKeys(toml: c.render()).isEmpty)
        #expect(Config.unknownKeys(toml: "gestures = true\ngesture-fingers = 3\ngesture-invert = false\ngesture-layout = true\n").isEmpty)
        #expect(Config.unknownKeys(toml: "gesture-finger = 3\n") == ["gesture-finger"])
        #expect(Config.unknownKeys(toml: "gesture-layouts = true\n") == ["gesture-layouts"])
    }

    /// Two fingers is scrolling; clamped rather than refused, like `panel-opacity`.
    @Test func gestureFingersIsClamped() throws {
        #expect(try Config.parse(toml: "gesture-fingers = 2").gestureFingers == 3)
        #expect(try Config.parse(toml: "gesture-fingers = 9").gestureFingers == 5)
    }

    @Test func theSettingsWindowOverridesGestures() throws {
        var file = Config(); file.gestures = true; file.gestureInvert = false; file.gestureLayout = true
        var gui = SettingsOverrides(); gui.gestures = false; gui.gestureInvert = true; gui.gestureLayout = false
        let out = Settings.effective(config: file, overrides: gui)
        #expect(!out.gestures && out.gestureInvert && !out.gestureLayout)
        let plain = Settings.effective(config: file, overrides: SettingsOverrides())
        #expect(plain.gestures && plain.gestureLayout)
        let back = try JSONDecoder().decode(SettingsOverrides.self, from: JSONEncoder().encode(gui))
        #expect(back.gestureLayout == false)
    }

    // MARK: macOS's interleaved empty frames (found live, 2026-09-26)

    /// Once the fingers move, macOS follows every touch frame with a touchless gesture event at the
    /// same timestamp. This is the start of a real right-to-left log capture that never fired:
    /// three fingers travel x 0.380 → 0.751, each frame paired with an empty one.
    static let capturedXs = [0.380, 0.383, 0.393, 0.405, 0.416, 0.432, 0.450, 0.477, 0.503, 0.531, 0.564, 0.592,
                             0.623, 0.653, 0.679, 0.700, 0.726, 0.751]

    @Test func interleavedEmptyFramesDoNotSplitASwipe() {
        var r = SwipeRecognizer()
        var out: [Swipe] = []
        for (i, x) in Self.capturedXs.enumerated() {
            let t = 100 + Double(i) * 0.006
            if let s = r.feed(TouchFrame(fingers: 3, x: x, y: 0.645, time: t)) { out.append(s) }
            if let s = r.feed(TouchFrame(fingers: 0, x: 0, y: 0, time: t)) { out.append(s) }
        }
        #expect(out == [Swipe(fingers: 3, direction: .right)])
        // …and it runs Fn+A: the content follows, so the window on the left.
        #expect(out.compactMap(SwipeBindings().command(for:)) == [.focusWindow(.left)])
    }

    /// #160: the same capture on four fingers, with both counts listened for, is one four-finger
    /// swipe. Lifting afterwards through three, with the empties still interleaved, adds nothing.
    @Test func interleavedEmptyFramesDoNotSplitAFourFingerSwipe() {
        var r = SwipeRecognizer(fingers: SwipeBindings().fingerCounts)
        var out: [Swipe] = []
        var t = 100.0
        func feed(_ fingers: Int, _ x: Double) {
            t += 0.006
            if let s = r.feed(TouchFrame(fingers: fingers, x: x, y: 0.645, time: t)) { out.append(s) }
            if let s = r.feed(TouchFrame(fingers: 0, x: 0, y: 0, time: t)) { out.append(s) }
        }
        feed(3, 0.378)   // the fingers land one by one
        for x in Self.capturedXs { feed(4, x) }
        for x in stride(from: 0.76, through: 0.95, by: 0.02) { feed(3, x) }   // one lifts; the rest keep going
        #expect(out == [Swipe(fingers: 4, direction: .right)])
        #expect(out.compactMap(SwipeBindings().command(for:)) == [.resizeWindow(.width, grow: true)])
        // A real lift, then a fresh four-finger swipe fires again.
        t += 0.4
        for x in Self.capturedXs.reversed() { feed(4, x) }
        #expect(out.map(\.direction) == [.right, .left])
    }

    /// A real lift (nothing for longer than the grace) still ends the gesture, so the next swipe
    /// is a fresh one and fires again.
    @Test func aRealLiftStillSeparatesSwipes() {
        var r = SwipeRecognizer()
        var out: [Direction] = []
        func stroke(from t0: Double) {
            for i in 0...10 {
                let t = t0 + Double(i) * 0.008
                if let s = r.feed(TouchFrame(fingers: 3, x: 0.3 + 0.04 * Double(i), y: 0.5, time: t)) { out.append(s.direction) }
                if let s = r.feed(TouchFrame(fingers: 0, x: 0, y: 0, time: t)) { out.append(s.direction) }
            }
        }
        stroke(from: 10)
        stroke(from: 10.5)   // fingers were off the trackpad for ~400 ms in between
        #expect(out == [.right, .right])
    }

    /// Fingers still down after an empty frame's grace ran out start a new gesture from where
    /// they are, rather than measuring from the old start.
    @Test func aLongGapRestartsTheSwipe() {
        var r = SwipeRecognizer()
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.2, y: 0.5, time: 1)) == nil)
        #expect(r.feed(TouchFrame(fingers: 0, x: 0, y: 0, time: 1)) == nil)
        // 200 ms later, far to the right: a new gesture starts here, so no fire yet.
        #expect(r.feed(TouchFrame(fingers: 3, x: 0.6, y: 0.5, time: 1.2)) == nil)
    }
}
