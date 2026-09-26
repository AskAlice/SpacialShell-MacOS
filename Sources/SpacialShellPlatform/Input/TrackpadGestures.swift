import AppKit
import CoreGraphics
import SpacialShellKit
import os

/// #141 (G27): trackpad swipes, watched with public API only — a **listen-only** `CGEvent` tap for
/// `NSEvent.EventType.gesture` events, each turned back into an `NSEvent` for its
/// `allTouches()` (`NSTouch.normalizedPosition`, `phase`). The private MultitouchSupport framework
/// is off the table (project rule: no private API).
///
/// **Why a tap and not `NSEvent.addGlobalMonitorForEvents(matching: .gesture)`.** The global
/// monitor was the plan, and measured on macOS 26.5 it receives *no* gesture events at all: over
/// 4 minutes of trackpad use, 0, while a listen-only tap in the same process received a frame
/// every ~30 ms whenever a finger touched (`docs/platform-notes.md`, check 10). A session-level tap
/// also sees the events aimed at this app (the rail, the tab bar), which a global monitor never does.
///
/// **It only watches.** Listen-only: the tap cannot modify or consume an event, so macOS's own
/// three-finger gestures still fire alongside ours; `checkSystemGestures` reads the trackpad
/// preferences and lists a Problem when they overlap.
///
/// **Threading.** The tap's source is on the main run loop and every method runs on the main
/// thread. A listen-only tap does not hold the event stream while it waits, so a busy main thread
/// only delays recognition, never the trackpad. Per event: one `NSEvent(cgEvent:)`, a handful of
/// touches, a few arithmetic operations (`SwipeRecognizer`). `onSwipe` must only hand the command
/// off, as `HotkeyTap.onCommand` does.
///
/// `SPACIAL_LOG_GESTURES=1` logs every frame (finger count, centroid) and every recognized swipe —
/// the instrument for the checks in `docs/platform-notes.md`.
@MainActor
public final class TrackpadGestures {
    private static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "gestures")
    /// Where the trackpad settings are changed; leaving it is when a fix may have happened.
    private nonisolated static let systemSettingsBundleID = "com.apple.systempreferences"

    private let onSwipe: @Sendable (Direction) -> Void
    private let problems: ProblemCenter
    private let logFrames: Bool
    private var recognizer = SwipeRecognizer()
    private var enabled = false
    private var tapPort: CFMachPort?
    private var source: CFRunLoopSource?
    private var observers: [any NSObjectProtocol] = []
    private var lastFingers = 0

    public init(problems: ProblemCenter = .shared, onSwipe: @escaping @Sendable (Direction) -> Void) {
        self.problems = problems
        self.onSwipe = onSwipe
        self.logFrames = ProcessInfo.processInfo.environment["SPACIAL_LOG_GESTURES"] == "1"
    }

    /// Boot and every config change. Installs or removes the tap as `enabled` says, and re-checks
    /// macOS's own gestures (the finger count decides whether they conflict).
    public func update(enabled: Bool, fingers: Int, invert: Bool) {
        if fingers != recognizer.fingers || invert != recognizer.invert {
            recognizer.fingers = fingers
            recognizer.invert = invert
            recognizer.reset()
        }
        if enabled != self.enabled {
            self.enabled = enabled
            if enabled { install() } else { uninstall() }
        }
        checkSystemGestures()
    }

    /// Terminal: the tap goes and so does the Problem, which only means something while swipes are on.
    public func stop() {
        enabled = false
        uninstall()
        problems.clear(Problem.Key.gestureConflict)
    }

    // MARK: - The tap

    private func install() {
        let mask: CGEventMask = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: trackpadTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            // Same trust as the hotkey tap: if that one works, this one does.
            Self.log.error("the trackpad gesture tap could not be created; swipes are off")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tapPort = port
        self.source = source

        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.systemSettingsBundleID else { return }
                MainActor.assumeIsolated { self?.checkSystemGestures() }
            },
            // Sleep can disable a tap; a disabled listen-only tap is otherwise silent forever.
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reenable() }
            },
            workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reenable() }
            },
        ]
        Self.log.info("trackpad swipes on: \(self.recognizer.fingers) fingers, invert=\(self.recognizer.invert)")
    }

    private func uninstall() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tapPort = nil
        source = nil
        recognizer.reset()
        lastFingers = 0
    }

    fileprivate func reenable() {
        guard let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) else { return }
        Self.log.notice("re-enabling the trackpad gesture tap")
        CGEvent.tapEnable(tap: tapPort, enable: true)
        recognizer.reset()
    }

    fileprivate func handle(_ frame: TouchFrame) {
        guard enabled else { return }
        if logFrames, frame.fingers != 0 || lastFingers != 0 {
            Self.log.info("gesture frame fingers=\(frame.fingers) centroid=(\(frame.x, format: .fixed(precision: 3)), \(frame.y, format: .fixed(precision: 3)))")
        }
        lastFingers = frame.fingers
        guard let direction = recognizer.feed(frame) else { return }
        if logFrames { Self.log.info("swipe recognized: \(String(describing: direction), privacy: .public)") }
        onSwipe(direction)
    }

    /// The fingers on the trackpad now: touches that have not ended or been cancelled, and are not
    /// resting (a thumb parked on a Magic Trackpad's edge is not part of the swipe).
    public nonisolated static func frame(_ touches: Set<NSTouch>, time: TimeInterval? = nil) -> TouchFrame {
        let down = touches.filter { NSTouch.Phase.touching.contains($0.phase) && !$0.isResting }
        return TouchFrame(positions: down.map { (x: Double($0.normalizedPosition.x), y: Double($0.normalizedPosition.y)) },
                          time: time)
    }

    // MARK: - macOS's own gestures

    /// Lists or clears the conflict Problem. Cheap (two preference domains, three keys each), so it
    /// runs on every config change and whenever System Settings is left.
    public func checkSystemGestures() {
        let system = Self.readSystemGestures()
        if let problem = system.conflict(gestures: enabled, fingers: recognizer.fingers) {
            problems.report(problem)
        } else {
            problems.clear(Problem.Key.gestureConflict)
        }
    }

    /// Read straight from the trackpad drivers' preference domains. Synchronized first: this
    /// process's copy of another app's domain is otherwise cached from the first read. Unsandboxed,
    /// as the app ships; a sandboxed build would read its own container and see nothing.
    public nonisolated static func readSystemGestures() -> TrackpadSystemGestures {
        TrackpadSystemGestures(domains: TrackpadSystemGestures.domains.map { domain in
            let id = domain as CFString
            CFPreferencesAppSynchronize(id)
            var values: [String: Int] = [:]
            for key in TrackpadSystemGestures.keys {
                if let n = CFPreferencesCopyAppValue(key as CFString, id) as? NSNumber { values[key] = n.intValue }
            }
            return values
        })
    }
}

/// A C callback: it cannot capture, so `TrackpadGestures` rides in `userInfo`. The source is on the
/// main run loop, so this runs on the main thread. Listen-only: the event is returned untouched and
/// the return value is ignored anyway.
private func trackpadTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?,
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let gestures = Unmanaged<TrackpadGestures>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { gestures.reenable() }
    default:
        guard let ns = NSEvent(cgEvent: event), ns.type == .gesture else { break }
        let frame = TrackpadGestures.frame(ns.allTouches(), time: ns.timestamp)
        MainActor.assumeIsolated { gestures.handle(frame) }
    }
    return Unmanaged.passUnretained(event)
}
