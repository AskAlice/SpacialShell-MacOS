// Adapted from AeroSpace (MIT) — Sources/AppBundle/tree/MacApp.swift @ c548c7f
// (frame-write ordering also from Sources/AppBundle/tree/MacWindow.swift).
//
// The per-app AX thread, the observer bootstrap, the window registry, the
// size→position→size write order and the blocking termination write all follow MacApp.swift.
// AeroSpace's tree types (`Window`, `MacWindow`, `Workspace`) are replaced by SpacialShell's
// paradigm-neutral `WindowSnapshot`, and the run-session plumbing by an `onEvent` callback.
import AppKit
import CoreGraphics
import SpacialShellKit
import struct SpacialShellKit.WindowRef
import os

// NB: the scoped `import struct SpacialShellKit.WindowRef` is load-bearing — AppKit re-exports
// ApplicationServices, whose Quickdraw header defines a `WindowRef` typedef of its own, and the
// scoped import is what keeps the plain name unambiguous here.

/// Spec §7.6. Raised on the app's own AX thread; the backend coalesces them into refreshes.
enum AXAppEvent: Sendable {
    case windowsChanged
    case focusChanged
    case moved(WindowID, CGRect)
    case resized(WindowID, CGRect)
}

/// Everything SpacialShell does to one running application, funnelled through that
/// application's own `CFRunLoop` thread (spec §7.1). A hung app blocks only its own thread.
///
/// Threading contract:
/// - `axApp`, `windows`, `appSubscriptions` are `ThreadGuardedValue`s — only the app thread
///   may read or write them, enforced at runtime by `AxAppThreadToken`.
/// - `thread` and `pendingFrameJobs` are reachable from any thread and are guarded by
///   `stateLock`. Jobs are always submitted while holding it, so a submission either lands in
///   the run loop before `destroy()`'s stop job or is refused outright.
/// - The static pid registry is guarded by `registryLock`.
final class AXApp: @unchecked Sendable {
    let pid: pid_t
    let bundleID: String?
    let nsApp: NSRunningApplication

    private let timeoutMs: Int
    private let onEvent: @Sendable (AXAppEvent) -> Void

    // Thread-confined state (app thread only).
    private let axApp: ThreadGuardedValue<AXUIElement>
    private let appSubscriptions: ThreadGuardedValue<[AxSubscription]> = .init([])
    private let windows: ThreadGuardedValue<[WindowID: AxWindow]> = .init([:])

    // Cross-thread state.
    private let stateLock = NSLock()
    private var thread: Thread?
    private var pendingFrameJobs: [WindowID: RunLoopJob] = [:]

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [pid_t: AXApp] = [:]

    /// Ruling 1: apps answer `kAXErrorCannotComplete` transiently right after launch.
    private static let maxObserverAttempts = 6
    private static let observerRetryBaseDelay: TimeInterval = 0.2

    private static let log = Logger(subsystem: "me.askalice.SpacialShell", category: "AXApp")

    private init(
        _ nsApp: NSRunningApplication,
        _ axApp: AXUIElement,
        timeoutMs: Int,
        thread: Thread,
        onEvent: @escaping @Sendable (AXAppEvent) -> Void,
    ) {
        self.nsApp = nsApp
        self.pid = nsApp.processIdentifier
        self.bundleID = nsApp.bundleIdentifier
        self.timeoutMs = timeoutMs
        self.onEvent = onEvent
        self.axApp = .init(axApp)
        self.thread = thread
    }

    // MARK: - Lifecycle

    /// MacApp.swift:46-100. One `AXApp` per pid; the thread is named `AxAppThread <pid>` and
    /// binds `axTaskLocalAppThreadToken` before touching any AX API.
    ///
    /// Unlike AeroSpace's `getOrRegister` this is synchronous: it blocks only until the app
    /// thread has created the application element (no IPC involved), then returns. The observer
    /// bootstrap continues on the app thread and may retry for several seconds without holding
    /// the caller up — reads and writes work meanwhile.
    static func getOrCreate(
        _ app: NSRunningApplication,
        timeoutMs: Int,
        onEvent: @escaping @Sendable (AXAppEvent) -> Void,
    ) -> AXApp? {
        // Ruling 2 / spec §7.1: AX requests to our own pid deadlock, and none of the lock
        // screen's windows are real windows.
        let pid = app.processIdentifier
        if pid == ProcessInfo.processInfo.processIdentifier { return nil }
        if app.bundleIdentifier == loginwindowBundleId { return nil }

        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = registry[pid] { return existing }

        let future = CompletableFuture<AXApp>()
        let thread = Thread {
            $axTaskLocalAppThreadToken.withValue(AxAppThreadToken(pid: pid, idForDebug: app.idForDebug)) {
                let axApp = AXUIElementCreateApplication(pid)
                // Our addition (spec §7.1, ruling 3): AeroSpace has no messaging timeout, so a
                // wedged app strands its thread forever. Timeouts surface as
                // `kAXErrorCannotComplete`, which we map to `BackendError.timeout`.
                _ = AXUIElementSetMessagingTimeout(axApp, Float(timeoutMs) / 1000)
                let instance = AXApp(app, axApp, timeoutMs: timeoutMs, thread: Thread.current, onEvent: onEvent)
                future.complete(instance)
                instance.bootstrapAppObservers(attempt: 0)
                CFRunLoopRun()
                // Destroy AX objects in reverse order of their creation (MacApp.swift:87-91).
                instance.destroyThreadGuardedValues()
            }
        }
        thread.name = "AxAppThread \(app.idForDebug)"
        thread.start()
        let instance = future.blockingGet()
        registry[pid] = instance
        return instance
    }

    /// MacApp.swift:343-359. Stops the run loop; the thread body then destroys the guarded
    /// values. No job may be submitted afterwards.
    func destroy() {
        Self.registryLock.withLock { _ = Self.registry.removeValue(forKey: pid) }
        stateLock.withLock {
            for (_, job) in pendingFrameJobs { job.cancel() }
            pendingFrameJobs = [:]
            let t = thread
            thread = nil // Disallow all future job submissions
            // Queued through the same run loop, so every job submitted before this point still runs.
            _ = t?.runInLoopAsync(job: RunLoopJob(.nonCancellable)) { _ in CFRunLoopStop(CFRunLoopGetCurrent()) }
        }
    }

    private func destroyThreadGuardedValues() {
        appSubscriptions.destroy()
        windows.destroy()
        axApp.destroy()
    }

    // MARK: - Observers (spec §7.6; MacApp.swift:68-72, 375-383)

    /// App-level notifications. Ruling 1: retry `kAXErrorCannotComplete` with exponential
    /// backoff (200 ms × 2ⁿ, ≤ 6 tries) on the app thread — apps that have just launched
    /// refuse observers for a moment (the yabai/Amethyst lesson).
    private func bootstrapAppObservers(attempt: Int) {
        let handlers: HandlerToNotifKeyMapping = [
            (axNotificationHandler, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]),
        ]
        let job = RunLoopJob(.nonCancellable)
        let result = (try? AxSubscription.bulkSubscribe(nsApp, axApp.threadGuarded, job, handlers))
            ?? .failed(.failure)
        switch result {
            case .subscribed(let subscriptions):
                appSubscriptions.threadGuarded = subscriptions
            case .failed(let err):
                guard err == .cannotComplete, attempt + 1 < Self.maxObserverAttempts else {
                    Self.log.warning("\(self.nsApp.idForDebug, privacy: .public): app observers unavailable (AXError \(err.rawValue))")
                    return
                }
                let delay = Self.observerRetryBaseDelay * pow(2, Double(attempt))
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [self] in
                    submitAsync { _ in self.bootstrapAppObservers(attempt: attempt + 1) }
                }
        }
    }

    /// MacApp.swift:375-383 (`AxWindow.new`). Subscribed the first time a window is seen.
    private func subscribeWindow(_ ax: AXUIElement, _ job: RunLoopJob) -> [AxSubscription] {
        let handlers: HandlerToNotifKeyMapping = [
            (axNotificationHandler, [
                kAXUIElementDestroyedNotification,
                kAXWindowMiniaturizedNotification,
                kAXWindowDeminiaturizedNotification,
                kAXMovedNotification,
                kAXResizedNotification,
            ]),
        ]
        switch (try? AxSubscription.bulkSubscribe(nsApp, ax, job, handlers)) ?? .failed(.failure) {
            case .subscribed(let subscriptions): return subscriptions
            // No backoff loop here: a window whose observers were refused keeps its element and
            // is retried on the next `snapshotWindows()`, which the backend runs every 2 s.
            case .failed: return []
        }
    }

    /// Runs on the app thread, inside the run loop, with the thread token bound.
    fileprivate func handle(notif: String, element: AXUIElement) {
        switch notif {
            case kAXWindowCreatedNotification, kAXUIElementDestroyedNotification,
                 kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
                onEvent(.windowsChanged)
            case kAXFocusedWindowChangedNotification:
                onEvent(.focusChanged)
            case kAXMovedNotification, kAXResizedNotification:
                // movedObs/resizedObs fall back to a full refresh when the id doesn't resolve.
                guard let id = element.containingWindowId(),
                      let origin = element.get(Ax.topLeftCornerAttr),
                      let size = element.get(Ax.sizeAttr)
                else {
                    onEvent(.windowsChanged)
                    return
                }
                let rect = CGRect(origin: origin, size: size)
                onEvent(notif == kAXMovedNotification ? .moved(id, rect) : .resized(id, rect))
            default: break
        }
    }

    fileprivate static func dispatch(element: AXUIElement, notif: String) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        guard let app = registryLock.withLock({ registry[pid] }) else { return }
        app.handle(notif: notif, element: element)
    }

    // MARK: - Reads

    /// Spec §7.2. Enumerate → classify → frame/title/parent/native state.
    /// Ruling 5: three phases — app thread, one `MainActor` hop for the `CGWindowList` level
    /// cache, app thread again.
    func snapshotWindows() async -> [WindowSnapshot] {
        guard let thread = currentThread() else { return [] }
        guard let refreshed = try? await thread.runInLoop(.cancellable, { [self] job in try refreshWindows(job) })
        else { return [] }
        // MacApp.swift:297-299: a dead window's queued frame write is pointless.
        stateLock.withLock {
            for id in refreshed.dead { pendingFrameJobs.removeValue(forKey: id)?.cancel() }
        }
        let ids = refreshed.alive
        let levels: [WindowID: MacOsWindowLevel] = await MainActor.run {
            var levels: [WindowID: MacOsWindowLevel] = [:]
            for id in ids {
                if let level = getWindowLevel(for: id) { levels[id] = level }
            }
            return levels
        }
        return (try? await thread.runInLoop(.cancellable, { [self] job in try buildSnapshots(ids, levels, job) })) ?? []
    }

    /// MacApp.swift:259-298 (`refreshAndGetAliveWindowIds`), minus the lock-screen gate — the
    /// backend owns "is loginwindow frontmost?" (spec §7.7) — and minus the mouse-down gate,
    /// which needs the backend's global mouse monitor (spec §7.6).
    private func refreshWindows(_ job: RunLoopJob) throws -> (alive: [WindowID], dead: [WindowID]) {
        var alive = windows.threadGuarded
        var dead: [WindowID] = []
        for (id, window) in alive {
            try job.checkCancellation()
            if window.ax.containingWindowId() == nil {
                dead.append(id)
                alive.removeValue(forKey: id)
            }
        }
        for (id, ax) in axApp.threadGuarded.get(Ax.windowsAttr) ?? [] {
            try job.checkCancellation()
            registerWindow(id: id, ax: ax, in: &alive, job)
        }
        windows.threadGuarded = alive
        return (Array(alive.keys), dead)
    }

    /// MacApp.swift:399-414 (`getOrRegisterAxWindow`). Deviation: AeroSpace drops a window
    /// whose observers could not be attached; we keep it (reads and writes only need the
    /// element) and retry the subscription on the next refresh.
    private func registerWindow(id: WindowID, ax: AXUIElement, in map: inout [WindowID: AxWindow], _ job: RunLoopJob) {
        if let existing = map[id] {
            if existing.subscriptions.isEmpty { existing.subscriptions = subscribeWindow(existing.ax, job) }
            return
        }
        map[id] = AxWindow(id: id, ax: ax, subscriptions: subscribeWindow(ax, job))
    }

    private func buildSnapshots(
        _ ids: [WindowID],
        _ levels: [WindowID: MacOsWindowLevel],
        _ job: RunLoopJob,
    ) throws -> [WindowSnapshot] {
        let axApp = self.axApp.threadGuarded
        let policy = nsApp.activationPolicy
        var result: [WindowSnapshot] = []
        for id in ids {
            try job.checkCancellation()
            guard let window = windows.threadGuarded[id] else { continue }
            let ax = window.ax
            // An unreadable rect doesn't hide the window (AeroSpace keeps it in the tree too);
            // the reconciler will simply see a mismatch and write the desired frame.
            let origin = ax.get(Ax.topLeftCornerAttr) ?? .zero
            let size = ax.get(Ax.sizeAttr) ?? .zero
            result.append(WindowSnapshot(
                ref: WindowRef(id: id, pid: pid),
                frame: CGRect(origin: origin, size: size),
                title: ax.get(Ax.titleAttr) ?? "",
                bundleID: bundleID,
                kind: WindowClassifier.kind(
                    axWindow: ax,
                    axApp: axApp,
                    bundleID: bundleID,
                    activationPolicy: policy,
                    windowLevel: levels[id],
                ),
                parent: parentRef(of: ax, ownId: id),
                isMinimized: ax.get(Ax.minimizedAttr) ?? false,
                isFullscreen: ax.get(Ax.isFullscreenAttr) ?? false,
            ))
        }
        return result
    }

    /// Spec §7.2 / ruling 5. `AXParent` of a plain window is the application element, whose
    /// `containingWindowId()` is nil; for a sheet or attached dialog it is the owner window.
    private func parentRef(of ax: AXUIElement, ownId: WindowID) -> WindowRef? {
        guard let parent = ax.get(Ax.parentAttr),
              let parentId = parent.containingWindowId(),
              parentId != ownId
        else { return nil }
        return WindowRef(id: parentId, pid: pid)
    }

    /// MacApp.swift:114-124. Registers the focused window on the way, so a write can address it
    /// before the first `snapshotWindows()`.
    func focusedWindowRef() async -> WindowRef? {
        guard let thread = currentThread() else { return nil }
        let id = try? await thread.runInLoop(.cancellable) { [self] job -> WindowID? in
            guard let focused = axApp.threadGuarded.get(Ax.focusedWindowAttr) else { return nil }
            var map = windows.threadGuarded
            registerWindow(id: focused.windowId, ax: focused.ax.cast, in: &map, job)
            windows.threadGuarded = map
            return focused.windowId
        }
        return (id ?? nil).map { WindowRef(id: $0, pid: pid) }
    }

    // MARK: - Writes (spec §7.4; MacApp.swift:411-436)

    /// size → position → size, wrapped in `AXEnhancedUserInterface = false`.
    func setFrame(_ id: WindowID, _ frame: CGRect) async -> Result<Void, BackendError> {
        await frameWrite(id) { window, axApp, job in
            try disableAnimations(app: axApp, job) {
                try writeFrame(window, frame.origin, frame.size, job)
            }
        }
    }

    /// Position only — parking and unparking preserve the size (spec §7.4).
    func setPosition(_ id: WindowID, _ origin: CGPoint) async -> Result<Void, BackendError> {
        await frameWrite(id) { window, axApp, job in
            try disableAnimations(app: axApp, job) {
                try writeFrame(window, origin, nil, job)
            }
        }
    }

    /// MacApp.swift:186-195 (`setAxFrameForTermination`). Blocking and non-cancellable: called
    /// from the termination handler, which must not return before windows are unparked.
    func setFrameForTermination(_ id: WindowID, _ frame: CGRect) {
        let job = RunLoopJob(.nonCancellable)
        let semaphore = DispatchSemaphore(value: 0)
        let submitted = stateLock.withLock { () -> Bool in
            pendingFrameJobs.removeValue(forKey: id)?.cancel()
            guard let thread else { return false }
            thread.runInLoopAsync(job: job, autoCheckCancelled: false) { [self] job in
                if let window = windows.threadGuarded[id] {
                    _ = try? disableAnimations(app: axApp.threadGuarded, job) {
                        try writeFrame(window.ax, frame.origin, frame.size, job)
                    }
                }
                semaphore.signal()
            }
            return true
        }
        guard submitted else { return }
        // AeroSpace waits forever; we bound the wait by the messaging-timeout budget so that
        // quitting can never hang on a wedged app.
        _ = semaphore.wait(timeout: .now() + .milliseconds(max(2000, timeoutMs * 4)))
    }

    /// Ruling 4: a newer write for the same window cancels the queued older one
    /// (AeroSpace's `setFrameJobs`, MacApp.swift:150-156).
    private func frameWrite(
        _ id: WindowID,
        _ body: @escaping @Sendable (AXUIElement, AXUIElement, RunLoopJob) throws -> Result<Void, BackendError>,
    ) async -> Result<Void, BackendError> {
        let job = RunLoopJob(.cancellable)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Result<Void, BackendError>, Never>) in
                let submitted = stateLock.withLock { () -> Bool in
                    pendingFrameJobs.removeValue(forKey: id)?.cancel()
                    guard let thread else { return false }
                    pendingFrameJobs[id] = job
                    // Submitted under the lock: either this lands in the run loop before
                    // `destroy()`'s stop job, or `thread` is already nil and we refuse.
                    thread.runInLoopAsync(job: job, autoCheckCancelled: false) { [self] job in
                        // Superseded (or the awaiting task was cancelled). Reported as success
                        // on purpose: a newer write for the same window is already queued, and
                        // WorldStore retires a window after three *failed* writes (spec §11).
                        if job.isCancelled { cont.resume(returning: .success(())); return }
                        guard let window = windows.threadGuarded[id] else {
                            cont.resume(returning: .failure(.notFound))
                            return
                        }
                        cont.resume(returning: (try? body(window.ax, axApp.threadGuarded, job)) ?? .success(()))
                    }
                    return true
                }
                if !submitted { cont.resume(returning: .failure(.notFound)) }
            }
        } onCancel: {
            job.cancel()
        }
    }

    // MARK: - Focus and close (spec §7.5)

    /// MacApp.swift:130-148 (`nativeFocus`). AeroSpace's fast path (skip AX when the app is
    /// already focused) depends on tree state we don't have, so we always do the AX work.
    func raise(_ id: WindowID) async -> Result<Void, BackendError> {
        guard let thread = currentThread() else { return .failure(.notFound) }
        let result = try? await thread.runInLoop(.cancellable) { [self] job -> Result<Void, BackendError> in
            guard let window = windows.threadGuarded[id] else { return .failure(.notFound) }
            // Raise first so the window is already on top by the time we activate the app.
            var err = window.ax.setChecked(Ax.isMainAttr, true)
            try job.checkCancellation()
            let raiseErr = AXUIElementPerformAction(window.ax, kAXRaiseAction as CFString)
            if err == .success { err = raiseErr }
            return err.asBackendResult
        }
        guard let result else { return .failure(.timeout) }
        if case .success = result {
            // `.activateIgnoringOtherApps` is deprecated (and inert) since macOS 14; the
            // AXRaise above already put the right window on top.
            await MainActor.run { _ = nsApp.activate() }
        }
        return result
    }

    /// MacApp.swift:102-110 (`closeAndUnregisterAxWindow`): press the close button and forget
    /// the window so no queued write outlives it.
    func close(_ id: WindowID) async -> Result<Void, BackendError> {
        guard let thread = currentThread() else { return .failure(.notFound) }
        stateLock.withLock { pendingFrameJobs.removeValue(forKey: id)?.cancel() }
        let result = try? await thread.runInLoop(.cancellable) { [self] job -> Result<Void, BackendError> in
            guard let window = windows.threadGuarded[id] else { return .failure(.notFound) }
            guard let closeButton = window.ax.get(Ax.closeButtonAttr) else { return .failure(.notFound) }
            try job.checkCancellation()
            let err = AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString)
            if err == .success { windows.threadGuarded.removeValue(forKey: id) }
            return err.asBackendResult
        }
        return result ?? .failure(.timeout)
    }

    // MARK: - Plumbing

    private func currentThread() -> Thread? { stateLock.withLock { thread } }

    private func submitAsync(_ body: @escaping @Sendable (RunLoopJob) -> ()) {
        stateLock.withLock {
            _ = thread?.runInLoopAsync(job: RunLoopJob(.nonCancellable), autoCheckCancelled: false, body)
        }
    }
}

/// MacApp.swift:361-383. Element plus its observers; the observers live exactly as long as it does.
private final class AxWindow {
    let id: WindowID
    let ax: AXUIElement
    var subscriptions: [AxSubscription] // keep subscriptions in memory

    init(id: WindowID, ax: AXUIElement, subscriptions: [AxSubscription]) {
        self.id = id
        self.ax = ax
        self.subscriptions = subscriptions
    }
}

/// One C callback for every notification: `AXObserverAddNotification` takes no context, so the
/// app is recovered from the element's pid (AeroSpace routes through its MainActor tree instead).
private func axNotificationHandler(
    _ obs: AXObserver,
    _ element: AXUIElement,
    _ notif: CFString,
    _ data: UnsafeMutableRawPointer?,
) {
    AXApp.dispatch(element: element, notif: notif as String)
}

let loginwindowBundleId = "com.apple.loginwindow"

extension AXUIElement {
    /// AeroSpace's `set` collapses the `AXError` into a `Bool`; `BackendError.ax` needs the code.
    fileprivate func setChecked<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> AXError {
        guard let value = attr.setter(value) else { return .failure }
        return AXUIElementSetAttributeValue(self, attr.key as CFString, value)
    }
}

extension AXError {
    /// Ruling 3: a messaging timeout surfaces as `kAXErrorCannotComplete`.
    fileprivate var asBackendResult: Result<Void, BackendError> {
        switch self {
            case .success: .success(())
            case .cannotComplete: .failure(.timeout)
            default: .failure(.ax(rawValue))
        }
    }
}

/// MacApp.swift:421-429. Set size, then position, then size again — the order matters
/// (AeroSpace #143, #335). The first error is reported; the remaining writes are still attempted.
private func writeFrame(
    _ window: AXUIElement,
    _ topLeft: CGPoint?,
    _ size: CGSize?,
    _ job: RunLoopJob,
) throws -> Result<Void, BackendError> {
    var err = AXError.success
    func record(_ e: AXError) { if err == .success { err = e } }
    if let size { record(window.setChecked(Ax.sizeAttr, size)) }
    try job.checkCancellation()
    guard let topLeft else { return err.asBackendResult }
    record(window.setChecked(Ax.topLeftCornerAttr, topLeft))
    try job.checkCancellation()
    if let size { record(window.setChecked(Ax.sizeAttr, size)) }
    return err.asBackendResult
}

/// MacApp.swift:431-445. Some undocumented magic, restored afterwards.
/// References: yabai 3fe4c77, Rectangle #285.
private func disableAnimations<T>(app: AXUIElement, _ job: RunLoopJob, _ body: () throws -> T) throws -> T {
    let wasEnabled = app.get(Ax.enhancedUserInterfaceAttr) == true
    if wasEnabled {
        app.set(Ax.enhancedUserInterfaceAttr, false)
    }
    defer {
        if wasEnabled {
            app.set(Ax.enhancedUserInterfaceAttr, true)
        }
    }
    try job.checkCancellation()
    return try body()
}
