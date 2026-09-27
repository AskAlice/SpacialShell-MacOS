import AppKit
import CoreGraphics
import SpacialShellKit
import struct SpacialShellProtocol.WindowRef
import os

/// #135 (G28): focus follows the mouse, opt-in. Public API only, the same way as the trackpad
/// swipes (#141): a **listen-only** `CGEvent` tap for mouse moves and button presses, on the main
/// run loop. It cannot delay, change or consume an event; installed only while
/// `focus-follows-mouse` is on.
///
/// Everything that decides is pure and in Kit: `PointerTargets` hit-tests a move against what the
/// store last framed, `FocusFollowsMouse` runs the dwell. This class only feeds them, keeps one
/// timer alive while a dwell is pending, and makes the last check against the window server's
/// stacking (`FocusFollowsMouse.accepts`) before handing the window to `onFocus`, which runs
/// `.focusWindowRef` through the store like a click on a tab.
///
/// Per move: one `CGEvent.location` and a hit-test over a handful of rects. Per completed dwell:
/// one `CGWindowListCopyWindowInfo`.
///
/// macOS has no public way to focus a window without raising it, so the focused window comes to
/// the front. Tiles never overlap each other, so for a tile that is invisible; a floating window
/// hovered from under a tile comes up over it, which #135's 2026-09-26 decision accepts.
/// `PointerTargets` hit-tests in the store's stacking order, so the topmost window wins.
///
/// `SPACIAL_LOG_FOCUS_FOLLOWS_MOUSE=1` logs every completed dwell and whether it was accepted.
@MainActor
public final class PointerFocus {
    private static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "focus-follows-mouse")

    private let onFocus: @Sendable (WindowRef) -> Void
    private let logDwells: Bool
    private var dwell = FocusFollowsMouse()
    private var targets = PointerTargets.empty
    private var enabled = false
    private var lastPoint: CGPoint?
    private var timer: Timer?
    private var tapPort: CFMachPort?
    private var source: CFRunLoopSource?
    private var observers: [any NSObjectProtocol] = []

    public init(onFocus: @escaping @Sendable (WindowRef) -> Void) {
        self.onFocus = onFocus
        self.logDwells = ProcessInfo.processInfo.environment["SPACIAL_LOG_FOCUS_FOLLOWS_MOUSE"] == "1"
    }

    /// Boot and every config change.
    public func update(enabled: Bool, delayMs: Int) {
        dwell.delay = TimeInterval(FocusFollowsMouse.clamp(delayMs)) / 1000
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        if enabled { install() } else { uninstall() }
    }

    /// Every store publish whose targets changed.
    public func update(targets: PointerTargets) { self.targets = targets }

    /// A key press: whatever the pointer was about to do, the keyboard has the floor.
    public func cancel() {
        dwell.cancel()
        stopTimer()
    }

    public func stop() {
        enabled = false
        uninstall()
    }

    // MARK: - The tap

    private func install() {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: pointerFocusTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Self.log.error("the pointer tap could not be created; focus-follows-mouse is off")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tapPort = port
        self.source = source
        // Sleep can disable a tap; a disabled listen-only tap is otherwise silent forever.
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reenable() }
            }
        }
        Self.log.info("focus-follows-mouse on: \(Int(self.dwell.delay * 1000)) ms dwell")
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
        cancel()
        lastPoint = nil
    }

    fileprivate func reenable() {
        guard let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) else { return }
        Self.log.notice("re-enabling the pointer tap")
        CGEvent.tapEnable(tap: tapPort, enable: true)
        cancel()
    }

    fileprivate func moved(to p: CGPoint) {
        guard enabled else { return }
        lastPoint = p
        dwell.moved(to: p, over: targets.window(at: p), focused: targets.focused, now: Self.now)
        if dwell.deadline == nil { stopTimer() } else if timer == nil { schedule() }
    }

    // MARK: - The clock

    /// One timer at most. A dwell that restarts only pushes its deadline later, so the timer that
    /// is already set fires early, finds nothing due, and sets itself again for what is left.
    private func schedule() {
        guard let due = dwell.deadline else { return }
        let t = Timer(timeInterval: max(0, due - Self.now), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func fire() {
        timer = nil
        guard enabled, let p = lastPoint else { return }
        let target = dwell.tick(now: Self.now, over: targets.window(at: p), focused: targets.focused)
        guard let target else {
            if dwell.deadline != nil { schedule() }
            return
        }
        let front = Self.frontmost(at: p)
        let ok = FocusFollowsMouse.accepts(target, frontmost: front)
        if logDwells {
            Self.log.info("dwell on \(target.id) pid=\(target.pid) frontmost=\(front.map { "\($0.pid)/\($0.layer)" } ?? "none", privacy: .public) accepted=\(ok)")
        }
        if ok { onFocus(target) }
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// The frontmost visible on-screen window under `p`: `CGWindowListCopyWindowInfo` lists front
    /// to back. Bounds are global top-left, like `CGEvent.location`. Fully transparent windows are
    /// skipped (some apps keep an invisible overlay on screen). Owner, layer and alpha need no
    /// Screen Recording grant; only titles do, and this reads none.
    private static func frontmost(at p: CGPoint) -> (pid: Int32, layer: Int)? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        for d in raw {
            guard let pid = d[kCGWindowOwnerPID as String] as? pid_t,
                  let b = d[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary), rect.contains(p)
            else { continue }
            if let alpha = d[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            return (pid, d[kCGWindowLayer as String] as? Int ?? 0)
        }
        return nil
    }
}

/// #172: the runtime's watcher lifecycle. `apply` installs or removes the tap, so `start` has
/// nothing left to do. The pointer targets come from the store's own feed (`update(targets:)`),
/// not from the world.
extension PointerFocus: Watcher {
    public func apply(_ config: Config) {
        update(enabled: config.focusFollowsMouse, delayMs: config.focusFollowsMouseDelayMs)
    }

    public func start() {}
}

/// A C callback: it cannot capture, so `PointerFocus` rides in `userInfo`. The source is on the
/// main run loop, so this runs on the main thread. Listen-only: the event goes back untouched.
private func pointerFocusTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?,
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let focus = Unmanaged<PointerFocus>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { focus.reenable() }
    case .mouseMoved:
        let p = event.location
        MainActor.assumeIsolated { focus.moved(to: p) }
    default:
        // A button: the click decides focus itself, and a drag starting now is not a hover.
        MainActor.assumeIsolated { focus.cancel() }
    }
    return Unmanaged.passUnretained(event)
}
