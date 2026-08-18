import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SpacialShellKit
import os

/// Spec §6.2, §13. A session-level, active `CGEventTap` that consumes bound chords and passes
/// everything else through untouched.
///
/// **Threading.** The tap runs on its own `Thread` with its own `CFRunLoop`, never the main one.
/// An active tap's callback has a hard deadline (~1 s, tunable by the system): if the run loop
/// servicing the tap is busy when a key arrives, macOS posts `kCGEventTapDisabledByTimeout` and
/// silently stops delivering events. The main run loop of a window manager is exactly the run loop
/// that *will* be busy — it drives AX refresh sessions — so the tap gets a thread of its own whose
/// only job is to answer keystrokes. The callback itself is O(µs): one dictionary lookup under an
/// uncontended lock, then `onCommand`.
///
/// **`onCommand` must not block.** It is called on the tap thread, inside the callback's deadline;
/// it is expected to hand the command off (`Task { await store.run(cmd) }`) and return immediately.
///
/// **Re-enable hygiene.** macOS disables the tap for reasons that are not bugs: a callback that
/// overran once, `kCGEventTapDisabledByUserInput`, sleep, fast user switching, the lock screen.
/// Four things put it back: the in-callback re-enable on the two `tapDisabled*` events, the wake /
/// unlock / session-active notifications, and a 5 s health poll that re-enables and — if the port
/// is truly dead — re-creates the tap, behind a circuit breaker so a permanently revoked grant
/// cannot spin.
///
/// **What it never touches** (ruling 3): the Globe/Fn key tapped alone, `Fn`+F1…F20 (the hardware
/// function row and its system actions), and it never *posts* a synthetic event of any kind — the
/// only two outcomes for an event are "pass through unmodified" and "swallow".
///
/// Lifecycle: `init` → `start()` (main actor, once, throwing) → … → `stop()`. `stop()` is terminal.
public final class HotkeyTap: @unchecked Sendable {
    public enum TapError: Error { case creationFailed }

    private static let log = Logger(subsystem: "me.askalice.SpacialShell", category: "hotkeys")

    /// Health poll interval; also how long a tap can stay dead before we notice.
    private static let healthIntervalSeconds: CFTimeInterval = 5
    /// Ruling 2: a wake re-enable that lands before the window server has finished restoring the
    /// session is a no-op, so wait for it to settle.
    private static let wakeDelaySeconds: TimeInterval = 3
    /// Circuit breaker; see `Breaker`.

    /// `kVK_Function` and the Globe key's own keyDown on Apple keyboards (0xB3). Neither is ever
    /// a chord; both pass through so macOS's own Globe behaviour keeps working.
    private static let functionKeyCode = UInt16(kVK_Function)
    private static let globeKeyCode: UInt16 = 0xB3
    /// F1…F20. `Fn`+these is the hardware function row (brightness, volume, Mission Control…);
    /// binding them would break the keyboard, so they are never looked up.
    private static let functionRow: Set<UInt16> = Set(
        [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ].map { UInt16($0) })

    private let onCommand: @Sendable (Command) -> Void
    /// `SPACIAL_LOG_KEYS=1` logs every keyDown's keycode and flags — the instrument for the
    /// empirical checks in `docs/platform-notes.md`.
    private let logKeys: Bool

    /// One lock over everything mutable. Every hold is a handful of instructions and no callout
    /// happens under it, so the callback's lookup is uncontended in practice.
    private let lock = NSLock()
    private var table: [Chord: Command]
    private var tapPort: CFMachPort?
    private var source: CFRunLoopSource?
    private var health: CFRunLoopTimer?
    /// Keeps the tap thread's run loop non-empty for the thread's whole life, independent of the
    /// tap. Without it, a re-creation that fails leaves the run loop with nothing to service,
    /// `CFRunLoopRunInMode` returns `.finished`, the thread exits, `runLoop` goes nil — and every
    /// re-arm path is guarded on that run loop, so the hotkeys would be dead until relaunch.
    private var keepAlive: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var breaker = Breaker()
    private var created = false
    private var started = false
    private var stopping = false
    /// Test seam: makes `createTap()` fail without touching CoreGraphics, so the "what happens
    /// when re-creation fails" path is reachable on a host with no Accessibility grant.
    private var failCreation = false
    /// Test seam: counts re-arm blocks that actually ran on the tap thread.
    private var rearmCount = 0
    /// Signalled by the tap thread on its way out, so `stop()` can be synchronous.
    private let finished = DispatchSemaphore(value: 0)

    /// The re-creation circuit breaker (ruling 2), as a pure state machine so it can be tested
    /// without a tap.
    ///
    /// It counts **consecutive** failures, not failures inside a time window. A window is the
    /// obvious design and it cannot work here: the only thing that drives re-creation is the 5 s
    /// health poll, so any window shorter than 5 s has always pruned every entry by the time the
    /// next attempt arrives and the breaker can never trip.
    struct Breaker: Equatable {
        static let limit = 5
        private(set) var consecutiveFailures = 0
        private(set) var tripped = false

        /// False once the breaker has tripped: stop trying until a wake/unlock resets it.
        var allowsAttempt: Bool { !tripped }

        mutating func recordSuccess() {
            consecutiveFailures = 0
            tripped = false
        }

        /// Returns true when *this* failure is the one that trips the breaker.
        mutating func recordFailure() -> Bool {
            consecutiveFailures += 1
            guard consecutiveFailures >= Self.limit, !tripped else { return false }
            tripped = true
            return true
        }

        /// A wake, unlock or session activation forgives everything: whatever made the tap
        /// unrecreatable (a locked session, a restarting window server) is most likely over.
        mutating func reset() {
            consecutiveFailures = 0
            tripped = false
        }
    }

    public init(table: [Chord: Command], onCommand: @escaping @Sendable (Command) -> Void) {
        self.table = table
        self.onCommand = onCommand
        self.logKeys = ProcessInfo.processInfo.environment["SPACIAL_LOG_KEYS"] == "1"
    }

    public func update(table: [Chord: Command]) {
        lock.lock(); self.table = table; lock.unlock()
    }

    /// Pure: the five modifiers the model knows about, and nothing else. Caps lock, the numeric-pad
    /// flag and the help flag ride along on ordinary keystrokes and must never affect matching.
    static func chord(from flags: CGEventFlags, keyCode: UInt16) -> Chord {
        Chord(
            keyCode: keyCode,
            fn: flags.contains(.maskSecondaryFn),
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift),
            command: flags.contains(.maskCommand))
    }

    // MARK: - Lifecycle

    /// Spawns the tap thread and waits (briefly) for it to report whether `CGEvent.tapCreate`
    /// succeeded — it fails when the process is not trusted for Accessibility / Input Monitoring,
    /// and the caller needs to know that synchronously to tell the user.
    @MainActor public func start() throws {
        lock.lock()
        if started || stopping { lock.unlock(); return }
        started = true
        lock.unlock()

        // tapCreate is a synchronous kernel call; a second is three orders of magnitude of slack.
        let reported = spawnThread(exitIfCreationFails: true)
        lock.lock()
        let ok = reported && created
        if !ok { stopping = true }
        lock.unlock()
        guard ok else {
            Self.log.error("CGEvent.tapCreate failed — the process is not trusted to observe keys")
            throw TapError.creationFailed
        }
        installObservers()
        Self.log.info("hotkey tap active on its own run loop")
    }

    /// Terminal. Removes the observers, tears the tap down on its own thread and waits for that
    /// thread to exit, so a caller that stops the tap can rely on no further commands arriving.
    public func stop() {
        removeObservers()
        lock.lock()
        let alreadyStopping = stopping
        stopping = true
        let runLoop = self.runLoop
        lock.unlock()
        guard let runLoop, !alreadyStopping else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            teardownOnTapThread()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
        if finished.wait(timeout: .now() + 1) != .success {
            Self.log.error("hotkey tap thread did not exit within 1 s")
        }
    }

    // MARK: - The tap thread

    /// Returns whether the thread reported back inside the timeout.
    private func spawnThread(exitIfCreationFails: Bool) -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in threadMain(ready: ready, exitIfCreationFails: exitIfCreationFails) }
        thread.name = "me.askalice.SpacialShell.hotkeys"
        thread.qualityOfService = .userInteractive
        lock.lock(); self.thread = thread; lock.unlock()
        thread.start()
        return ready.wait(timeout: .now() + 1) == .success
    }

    private func threadMain(ready: DispatchSemaphore, exitIfCreationFails: Bool) {
        let runLoop = CFRunLoopGetCurrent()!
        lock.lock(); self.runLoop = runLoop; lock.unlock()

        let ok = createTap()
        lock.lock(); created = ok; lock.unlock()
        ready.signal()

        // A creation failure *at start* is reported to the caller, which throws — nothing should
        // linger. A creation failure *later* is a different thing entirely: the thread has to stay
        // up so the health poll and the wake/unlock re-arms can keep trying.
        if ok || !exitIfCreationFails {
            installKeepAlive(on: runLoop)
            installHealthTimer(on: runLoop)
            while true {
                lock.lock(); let stopping = self.stopping; lock.unlock()
                if stopping { break }
                // A bounded run keeps the thread responsive to `stopping`. `.finished` should be
                // impossible while the keep-alive source is installed; if it ever happens, put the
                // source back rather than exiting — exiting is what stranded the re-arm paths.
                if CFRunLoopRunInMode(.defaultMode, 60, false) == .finished {
                    Self.log.error("hotkey run loop emptied unexpectedly; re-installing the keep-alive source")
                    installKeepAlive(on: runLoop)
                }
            }
        }

        teardownOnTapThread()
        lock.lock(); self.runLoop = nil; self.thread = nil; lock.unlock()
        finished.signal()
    }

    /// A version-0 source that is never signalled. Its only job is to be there, so the run loop
    /// always has something to service and `CFRunLoopRunInMode` blocks instead of returning
    /// `.finished`. Tap thread only.
    private func installKeepAlive(on runLoop: CFRunLoop) {
        var context = CFRunLoopSourceContext()
        context.perform = { _ in }
        guard let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) else {
            Self.log.error("could not create the hotkey run loop's keep-alive source")
            return
        }
        CFRunLoopAddSource(runLoop, source, .commonModes)
        lock.lock()
        let previous = keepAlive
        keepAlive = source
        lock.unlock()
        if let previous { CFRunLoopSourceInvalidate(previous) }
    }

    /// Tap thread only.
    private func createTap() -> Bool {
        lock.lock(); let failCreation = self.failCreation; lock.unlock()
        if failCreation { return false }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hotkeyTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        lock.lock(); self.tapPort = port; self.source = source; lock.unlock()
        return true
    }

    private func installHealthTimer(on runLoop: CFRunLoop) {
        let timer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + Self.healthIntervalSeconds,
            Self.healthIntervalSeconds, 0, 0,
        ) { [weak self] _ in self?.healthCheck() }
        CFRunLoopAddTimer(runLoop, timer, .commonModes)
        lock.lock(); health = timer; lock.unlock()
    }

    /// Drops the port and its run loop source **and nothing else** — the health timer and the
    /// keep-alive source must outlive a re-creation, or the first successful re-creation would be
    /// the last one the poll ever notices. Tap thread only; idempotent.
    private func teardownTapOnly() {
        lock.lock()
        let port = tapPort, source = self.source
        tapPort = nil; self.source = nil
        lock.unlock()
        if let source { CFRunLoopSourceInvalidate(source) }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
    }

    /// The terminal teardown: the tap, plus the two things that keep the thread's run loop alive.
    /// Tap thread only; idempotent.
    private func teardownOnTapThread() {
        teardownTapOnly()
        lock.lock()
        let health = self.health, keepAlive = self.keepAlive
        self.health = nil; self.keepAlive = nil
        lock.unlock()
        if let health { CFRunLoopTimerInvalidate(health) }
        if let keepAlive { CFRunLoopSourceInvalidate(keepAlive) }
    }

    /// Drops the current port and makes a new one — the only cure when the port itself is dead
    /// (revoked and re-granted trust, a window-server restart). Tap thread only.
    private func recreateTap() {
        lock.lock(); let allowed = breaker.allowsAttempt; lock.unlock()
        guard allowed else { return }

        teardownTapOnly()
        let ok = createTap()

        lock.lock()
        var tripped = false
        if ok { breaker.recordSuccess() } else { tripped = breaker.recordFailure() }
        lock.unlock()

        if ok {
            Self.log.info("event tap re-created")
            return
        }
        Self.log.error("event tap re-creation failed — Accessibility may have been revoked")
        if tripped {
            Self.log.error(
                "event tap could not be re-created \(Breaker.limit)× in a row; giving up until the next wake or unlock")
        }
    }

    /// The 5 s poll (ruling 2). Cheap when healthy: one `tapIsEnabled` call.
    private func healthCheck() {
        lock.lock()
        let port = tapPort
        let allowed = breaker.allowsAttempt
        let stopping = self.stopping
        lock.unlock()
        guard !stopping else { return }

        if let port {
            if CGEvent.tapIsEnabled(tap: port) { return }
            Self.log.warning("event tap found disabled by the health poll; re-enabling")
            CGEvent.tapEnable(tap: port, enable: true)
            if CGEvent.tapIsEnabled(tap: port) { return }
        }
        guard allowed else { return }
        recreateTap()
    }

    // MARK: - Wake / unlock / session change

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didWakeNotification, after: Self.wakeDelaySeconds, reason: "wake")
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, after: 0, reason: "session activation")
        observe(
            DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"),
            after: 0, reason: "screen unlock")
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, after: TimeInterval, reason: String) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.rearm(after: after, reason: reason)
        }
        lock.lock(); observers.append((center, token)); lock.unlock()
    }

    private func removeObservers() {
        lock.lock()
        let observers = self.observers
        self.observers = []
        lock.unlock()
        for (center, token) in observers { center.removeObserver(token) }
    }

    /// A wake or unlock is also the moment to forgive the circuit breaker: whatever made the tap
    /// unrecreatable (a locked session, a restarting window server) is most likely over.
    private func rearm(after delay: TimeInterval, reason: String) {
        perform(after: delay) { [weak self] in
            guard let self else { return }
            lock.lock()
            let stopping = self.stopping
            breaker.reset()
            rearmCount += 1
            lock.unlock()
            guard !stopping else { return }
            Self.log.info("re-arming hotkey tap after \(reason, privacy: .public)")
            healthCheck()
        }
    }

    /// Runs `body` on the tap thread's run loop. `CFRunLoop` is thread-safe for exactly this.
    private func perform(after delay: TimeInterval, _ body: @escaping @Sendable () -> Void) {
        lock.lock()
        let runLoop = self.runLoop
        let stopping = self.stopping
        lock.unlock()
        guard let runLoop, !stopping else { return }
        if delay <= 0 {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, body)
        } else {
            let timer = CFRunLoopTimerCreateWithHandler(
                kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0,
            ) { _ in body() }
            CFRunLoopAddTimer(runLoop, timer, .commonModes)
        }
        CFRunLoopWakeUp(runLoop)
    }

    // MARK: - The callback

    /// Called on the tap thread inside macOS's deadline. Everything here is O(µs) and nothing
    /// blocks, awaits or allocates beyond a dictionary lookup.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            lock.lock(); let port = tapPort; lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            Self.log.warning(
                "event tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public); re-enabled")
            return passThrough

        case .keyDown:
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if logKeys {
                Self.log.info(
                    "keyDown code=\(code) flags=0x\(String(flags.rawValue, radix: 16), privacy: .public) repeat=\(isRepeat)")
            }
            // Ruling 3: never the Globe key itself, never Fn+F1…F20.
            if code == Self.globeKeyCode || code == Self.functionKeyCode { return passThrough }
            let chord = Self.chord(from: flags, keyCode: code)
            if chord.fn && Self.functionRow.contains(code) { return passThrough }
            // Autorepeat passes through untouched: holding Fn+S must not fire the command 30×/s,
            // and swallowing the repeats would make a held key feel broken in the front app.
            if isRepeat { return passThrough }

            lock.lock(); let command = table[chord]; lock.unlock()
            guard let command else { return passThrough }
            if IsSecureEventInputEnabled() {
                Self.log.warning("secure input is active; hotkeys may be unreliable")
            }
            onCommand(command)
            return nil                                       // consume: the front app never sees it

        default:
            return passThrough
        }
    }

    // MARK: - Test seams

    /// Starts the tap thread with **no tap**: `createTap()` is forced to fail. That is the only
    /// way to ask the lifecycle question that matters here — "does the thread survive a creation
    /// failure?" — on a machine with no Accessibility grant, where a real tap cannot exist.
    func _testStartWithoutTap() {
        lock.lock()
        guard !started, !stopping else { lock.unlock(); return }
        started = true
        failCreation = true
        lock.unlock()
        _ = spawnThread(exitIfCreationFails: false)
    }

    /// True while the tap thread's run loop is live and reachable.
    func _isThreadAlive() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return runLoop != nil
    }

    /// Runs the re-creation path (with creation failing) *on the tap thread*, and returns once it
    /// has finished — so a test can assert about the state it left behind.
    func _simulateRecreationFailure() {
        let done = DispatchSemaphore(value: 0)
        perform(after: 0) { [weak self] in
            self?.recreateTap()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    /// A wake-style re-arm. Asynchronous by nature (it hops to the tap thread), so the counter is
    /// what proves it was not swallowed.
    func _rearm() { rearm(after: 0, reason: "test") }

    func _rearmCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return rearmCount
    }

    func _breakerState() -> Breaker {
        lock.lock(); defer { lock.unlock() }
        return breaker
    }
}

/// A `@convention(c)` trampoline; captures nothing, so it converts to `CGEventTapCallBack`.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?,
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HotkeyTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
