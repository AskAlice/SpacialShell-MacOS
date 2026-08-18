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
/// - `thread`, `pendingFrameJobs`, `pendingResumes` and `lastSnapshots` are reachable from any
///   thread and are guarded by `stateLock`. Every job is *submitted while holding `stateLock`*
///   together with the registration of its continuation, so a caller either gets its job queued
///   on a live run loop or is answered immediately — and `tearDown()` answers whatever is still
///   outstanding when the loop exits. No caller can be left awaiting a dropped perform.
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

    // Cross-thread state, guarded by `stateLock`.
    private let stateLock = NSLock()
    private var thread: Thread?
    private var pendingFrameJobs: [WindowID: RunLoopJob] = [:]
    private var pendingResumes: [UInt64: @Sendable () -> Void] = [:]
    private var nextResumeToken: UInt64 = 0
    /// Last conclusive observation. Returned whenever a refresh can't conclude anything, so that
    /// "the app didn't answer" never masquerades as "the app has no windows" (see `snapshotWindows`).
    private var lastSnapshots: [WindowSnapshot] = []

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
                // AeroSpace runs the loop only `if isGood`, i.e. only when the observers attached
                // (MacApp.swift:73, 85-92) — their observer source is what keeps the loop alive.
                // We must serve reads and writes for observer-less apps too, so we own a source of
                // our own: without it `CFRunLoopRun()` returns immediately (kCFRunLoopRunFinished)
                // and every later `perform(onThread:)` would be silently dropped.
                let keepAlive = addRunLoopKeepAliveSource()
                instance.bootstrapAppObservers(attempt: 0)
                CFRunLoopRun()
                if let keepAlive { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), keepAlive, .commonModes) }
                // Answers every outstanding caller and destroys the AX objects in reverse order of
                // their creation (MacApp.swift:87-91).
                instance.tearDown()
            }
        }
        thread.name = "AxAppThread \(app.idForDebug)"
        thread.start()
        let instance = future.blockingGet()
        registry[pid] = instance
        return instance
    }

    // MARK: - Registry (spec §7.6)

    /// The pid → `AXApp` map is the one `getOrCreate` dedupes against and `dispatch` routes
    /// notifications through; `destroy()` and `tearDown()` both remove from it. The backend reads
    /// it through `AXAppRegistry` rather than keeping a second map, which would go on vouching for
    /// apps whose run loop has already exited.
    static func registered(_ pid: pid_t) -> AXApp? { registryLock.withLock { registry[pid] } }

    static func allRegistered() -> [AXApp] { registryLock.withLock { Array(registry.values) } }

    /// Spec §7.6 gc. `destroy()` takes `registryLock` itself, so the dead set is collected first
    /// and the lock released before anything is destroyed.
    static func reapTerminated(alive: Set<pid_t>) {
        let dead = registryLock.withLock { registry.filter { !alive.contains($0.key) }.map(\.value) }
        for app in dead { app.destroy() }
    }

    /// MacApp.swift:343-359. Stops the run loop; `tearDown()` on the app thread finishes the job.
    /// No job may be submitted afterwards.
    func destroy() {
        Self.registryLock.withLock { if Self.registry[pid] === self { Self.registry[pid] = nil } }
        stateLock.withLock {
            for (_, job) in pendingFrameJobs { job.cancel() }
            pendingFrameJobs = [:]
            lastSnapshots = [] // Deliberately dropped: this app is no longer ours to vouch for.
            let t = thread
            thread = nil // Disallow all future job submissions
            // Queued through the same run loop, so every job submitted before this point still runs.
            _ = t?.runInLoopAsync(job: RunLoopJob(.nonCancellable)) { _ in CFRunLoopStop(CFRunLoopGetCurrent()) }
        }
    }

    /// Runs on the app thread once `CFRunLoopRun()` has returned — whether that was `destroy()`'s
    /// stop job or an unexpected exit. Anything still awaiting an answer gets its fallback rather
    /// than waiting forever on a run loop that will never run again.
    private func tearDown() {
        Self.registryLock.withLock { if Self.registry[pid] === self { Self.registry[pid] = nil } }
        let resumes = stateLock.withLock { () -> [@Sendable () -> Void] in
            thread = nil
            for (_, job) in pendingFrameJobs { job.cancel() }
            pendingFrameJobs = [:]
            lastSnapshots = [] // The app is unmanageable now; don't keep vouching for its windows.
            let outstanding = Array(pendingResumes.values)
            pendingResumes = [:]
            return outstanding
        }
        for resume in resumes { resume() }
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
    /// Ruling 5: app thread, one batched `MainActor` hop for the `CGWindowList` level cache (only
    /// for ids whose level isn't cached yet), app thread again.
    ///
    /// An empty result means "this app really has no windows". Whenever the app didn't answer, or
    /// the refresh was cancelled, or the thread is gone, the last conclusive observation is
    /// returned instead — `WorldStore.apply` removes every window missing from a snapshot, so an
    /// inconclusive read must never look like a mass close.
    func snapshotWindows() async -> [WindowSnapshot] {
        let refresh = await runOnAppThread(fallback: { RefreshResult.inconclusive }) { [self] job in
            refreshWindows(job)
        }
        // MacApp.swift:297-299: a dead window's queued frame write is pointless.
        if !refresh.dead.isEmpty {
            stateLock.withLock {
                for id in refresh.dead { pendingFrameJobs.removeValue(forKey: id)?.cancel() }
            }
        }
        guard refresh.conclusive else { return cachedSnapshots() }
        var levels: [WindowID: MacOsWindowLevel] = [:]
        if !refresh.needLevels.isEmpty {
            let ids = refresh.needLevels
            levels = await MainActor.run {
                var levels: [WindowID: MacOsWindowLevel] = [:]
                for id in ids {
                    if let level = getWindowLevel(for: id) { levels[id] = level }
                }
                return levels
            }
        }
        let ids = refresh.ids
        let fresh = levels
        let built = await runOnAppThread(fallback: { nil as [WindowSnapshot]? }) { [self] job in
            buildSnapshots(ids, fresh, job)
        }
        guard let built else { return cachedSnapshots() }
        stateLock.withLock { lastSnapshots = built }
        return built
    }

    private struct RefreshResult: Sendable {
        var ids: [WindowID]
        var dead: [WindowID]
        /// False when the app didn't answer (timeout, `kAXErrorAPIDisabled`) or we were cancelled.
        var conclusive: Bool
        var needLevels: [WindowID]

        static let inconclusive = RefreshResult(ids: [], dead: [], conclusive: false, needLevels: [])
    }

    /// MacApp.swift:259-298 (`refreshAndGetAliveWindowIds`), minus the lock-screen gate — the
    /// backend owns "is loginwindow frontmost?" (spec §7.7) — and minus the mouse-down gate,
    /// which needs the backend's global mouse monitor (spec §7.6).
    ///
    /// AeroSpace can partition alive/dead unconditionally because it sets no messaging timeout,
    /// so a read only fails when the window is really gone. With a timeout (ruling 3) a
    /// beachballing app fails *every* read, so the enumeration is the gate: it must succeed
    /// before any window may be declared dead.
    private func refreshWindows(_ job: RunLoopJob) -> RefreshResult {
        let previous = windows.threadGuarded
        if job.isCancelled { return .inconclusive }
        // `get` returns nil only when the AX request itself failed; an app with no windows
        // answers with an empty array.
        guard let enumerated = axApp.threadGuarded.get(Ax.windowsAttr) else { return .inconclusive }
        let enumeratedIds = Set(enumerated.map(\.windowId))
        var alive = previous
        var dead: [WindowID] = []
        // Only probe windows the app did *not* enumerate: `kAXWindowsAttribute` omits windows on
        // other native macOS Spaces (spec §7.2), which are alive and must keep their ids.
        for (id, window) in previous where !enumeratedIds.contains(id) {
            if job.isCancelled { return .inconclusive }
            if window.ax.containingWindowId() == nil {
                dead.append(id)
                alive.removeValue(forKey: id)
            }
        }
        for (id, ax) in enumerated {
            if job.isCancelled { return .inconclusive }
            registerWindow(id: id, ax: ax, in: &alive, job)
        }
        windows.threadGuarded = alive
        return RefreshResult(
            ids: Array(alive.keys),
            dead: dead,
            conclusive: true,
            needLevels: alive.compactMap { $0.value.windowLevel == nil ? $0.key : nil },
        )
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

    /// Returns nil if cancelled part-way, so a half-built list can't be mistaken for the truth.
    private func buildSnapshots(
        _ ids: [WindowID],
        _ freshLevels: [WindowID: MacOsWindowLevel],
        _ job: RunLoopJob,
    ) -> [WindowSnapshot]? {
        let axApp = self.axApp.threadGuarded
        let policy = nsApp.activationPolicy
        var result: [WindowSnapshot] = []
        for id in ids {
            if job.isCancelled { return nil }
            guard let window = windows.threadGuarded[id] else { continue }
            let ax = window.ax
            if let level = freshLevels[id] { window.windowLevel = level }
            // A window that stopped answering must not be re-classified from nil reads — every
            // heuristic in §7.3 degrades to "dialog" — so keep the last good observation.
            guard let origin = ax.get(Ax.topLeftCornerAttr), let size = ax.get(Ax.sizeAttr) else {
                if let last = window.lastSnapshot { result.append(last) }
                continue
            }
            let snapshot = WindowSnapshot(
                ref: WindowRef(id: id, pid: pid),
                frame: CGRect(origin: origin, size: size),
                title: ax.get(Ax.titleAttr) ?? "",
                bundleID: bundleID,
                kind: WindowClassifier.kind(
                    axWindow: ax,
                    axApp: axApp,
                    bundleID: bundleID,
                    activationPolicy: policy,
                    windowLevel: window.windowLevel,
                ),
                parent: parentRef(of: ax, ownId: id),
                isMinimized: ax.get(Ax.minimizedAttr) ?? false,
                isFullscreen: ax.get(Ax.isFullscreenAttr) ?? false,
            )
            window.lastSnapshot = snapshot
            result.append(snapshot)
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
        let id = await runOnAppThread(fallback: { nil as WindowID? }) { [self] job -> WindowID? in
            if job.isCancelled { return nil }
            guard let focused = axApp.threadGuarded.get(Ax.focusedWindowAttr) else { return nil }
            var map = windows.threadGuarded
            registerWindow(id: focused.windowId, ax: focused.ax.cast, in: &map, job)
            windows.threadGuarded = map
            return focused.windowId
        }
        return id.map { WindowRef(id: $0, pid: pid) }
    }

    private func cachedSnapshots() -> [WindowSnapshot] { stateLock.withLock { lastSnapshots } }

    // MARK: - Writes (spec §7.4; MacApp.swift:411-436)

    /// size → position → size, wrapped in `AXEnhancedUserInterface = false`.
    func setFrame(_ id: WindowID, _ frame: CGRect) async -> Result<Void, BackendError> {
        await frameWrite(id) { window, axApp, job in
            disableAnimations(app: axApp) { writeFrame(window, frame.origin, frame.size, job) }
        }
    }

    /// Position only — parking and unparking preserve the size (spec §7.4).
    func setPosition(_ id: WindowID, _ origin: CGPoint) async -> Result<Void, BackendError> {
        await frameWrite(id) { window, axApp, job in
            disableAnimations(app: axApp) { writeFrame(window, origin, nil, job) }
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
                    _ = disableAnimations(app: axApp.threadGuarded) {
                        writeFrame(window.ax, frame.origin, frame.size, job)
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
        _ body: @escaping @Sendable (AXUIElement, AXUIElement, RunLoopJob) -> Result<Void, BackendError>,
    ) async -> Result<Void, BackendError> {
        await runOnAppThread(dedupKey: id, fallback: { Result<Void, BackendError>.failure(.notFound) }) { [self] job in
            // Superseded (or the awaiting task was cancelled) *before the first AX call*. Reported
            // as success on purpose: nothing was written, a newer write for the same window is
            // already queued, and WorldStore retires a window after three failed writes (§11).
            // A write cancelled after it started still reports what AX actually said, so a wedged
            // app does accumulate real failures.
            if job.isCancelled { return .success(()) }
            guard let window = windows.threadGuarded[id] else { return .failure(.notFound) }
            return body(window.ax, axApp.threadGuarded, job)
        }
    }

    // MARK: - Focus and close (spec §7.5)

    /// MacApp.swift:130-148 (`nativeFocus`). AeroSpace's fast path (skip AX when the app is
    /// already focused) depends on tree state we don't have, so we always do the AX work.
    func raise(_ id: WindowID) async -> Result<Void, BackendError> {
        let outcome: (found: Bool, result: Result<Void, BackendError>) = await runOnAppThread(
            fallback: { (false, .failure(.notFound)) },
        ) { [self] job in
            guard let window = windows.threadGuarded[id] else { return (false, .failure(.notFound)) }
            // A superseded raise must not steal focus.
            if job.isCancelled { return (false, .failure(.timeout)) }
            // `AXMain` is best-effort and its result is deliberately ignored, exactly as in
            // MacApp.swift:143-145: sheets and attached dialogs — our `.float` windows — answer
            // `kAXErrorAttributeUnsupported`, and that must not read as "the raise failed".
            _ = window.ax.setChecked(Ax.isMainAttr, true)
            // Raise first so the window is already on top by the time we activate the app.
            return (true, AXUIElementPerformAction(window.ax, kAXRaiseAction as CFString).asBackendResult)
        }
        if outcome.found {
            // AeroSpace activates whenever it found the window, whatever the AX calls returned.
            // `.activateIgnoringOtherApps` is deprecated (and inert) since macOS 14.
            await MainActor.run { _ = nsApp.activate() }
        }
        return outcome.result
    }

    /// MacApp.swift:102-110 (`closeAndUnregisterAxWindow`): press the close button and forget
    /// the window so no queued write outlives it.
    func close(_ id: WindowID) async -> Result<Void, BackendError> {
        stateLock.withLock { pendingFrameJobs.removeValue(forKey: id)?.cancel() }
        return await runOnAppThread(fallback: { Result<Void, BackendError>.failure(.notFound) }) { [self] job in
            if job.isCancelled { return .failure(.timeout) }
            guard let window = windows.threadGuarded[id] else { return .failure(.notFound) }
            guard let closeButton = window.ax.get(Ax.closeButtonAttr) else { return .failure(.notFound) }
            let err = AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString)
            if err == .success { windows.threadGuarded.removeValue(forKey: id) }
            return err.asBackendResult
        }
    }

    // MARK: - Plumbing

    /// The single submission path onto the app thread. The continuation is registered *and* the
    /// job submitted under one `stateLock` acquisition, so exactly one of three things happens:
    /// the body runs and answers; `tearDown()` answers with `fallback` because the run loop is
    /// gone; or there is no thread at all and we answer with `fallback` right away.
    private func runOnAppThread<T: Sendable>(
        _ cm: CancellationMode = .cancellable,
        dedupKey: WindowID? = nil,
        fallback: @escaping @Sendable () -> T,
        _ body: @escaping @Sendable (RunLoopJob) -> T,
    ) async -> T {
        let job = RunLoopJob(cm)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
                stateLock.lock()
                guard let thread else {
                    stateLock.unlock()
                    cont.resume(returning: fallback())
                    return
                }
                let token = nextResumeToken
                nextResumeToken &+= 1
                pendingResumes[token] = { cont.resume(returning: fallback()) }
                if let dedupKey {
                    pendingFrameJobs.removeValue(forKey: dedupKey)?.cancel()
                    pendingFrameJobs[dedupKey] = job
                }
                thread.runInLoopAsync(job: job, autoCheckCancelled: false) { [self] job in
                    let claimed = stateLock.withLock { () -> Bool in
                        if let dedupKey, pendingFrameJobs[dedupKey] === job { pendingFrameJobs[dedupKey] = nil }
                        return pendingResumes.removeValue(forKey: token) != nil
                    }
                    guard claimed else { return } // tearDown() already answered this caller
                    cont.resume(returning: body(job))
                }
                stateLock.unlock()
            }
        } onCancel: {
            job.cancel()
        }
    }

    private func submitAsync(_ body: @escaping @Sendable (RunLoopJob) -> ()) {
        stateLock.withLock {
            _ = thread?.runInLoopAsync(job: RunLoopJob(.nonCancellable), autoCheckCancelled: false, body)
        }
    }
}

/// MacApp.swift:361-383. Element plus its observers; the observers live exactly as long as it
/// does. `windowLevel` and `lastSnapshot` are per-window caches that die with the window.
private final class AxWindow {
    let id: WindowID
    let ax: AXUIElement
    var subscriptions: [AxSubscription] // keep subscriptions in memory
    /// `CGWindowList` level, resolved once (the lookup is a `@MainActor` hop over the whole
    /// window list). A window's level does not change while the window lives.
    var windowLevel: MacOsWindowLevel?
    /// Last snapshot built from readable attributes, reused when the app stops answering.
    var lastSnapshot: WindowSnapshot?

    init(id: WindowID, ax: AXUIElement, subscriptions: [AxSubscription]) {
        self.id = id
        self.ax = ax
        self.subscriptions = subscriptions
    }
}

/// A version-0 source that is never signalled: it exists only so `CFRunLoopRun()` has something to
/// wait on and blocks instead of returning `kCFRunLoopRunFinished` on an observer-less app.
private func addRunLoopKeepAliveSource() -> CFRunLoopSource? {
    var context = CFRunLoopSourceContext()
    guard let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) else { return nil }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    return source
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
/// (AeroSpace #143, #335). Cancellation stops further writes but never rewrites the outcome: the
/// first `AXError` is reported so a wedged app's partial writes count as the failures they are.
private func writeFrame(
    _ window: AXUIElement,
    _ topLeft: CGPoint?,
    _ size: CGSize?,
    _ job: RunLoopJob,
) -> Result<Void, BackendError> {
    var err = AXError.success
    func record(_ e: AXError) { if err == .success { err = e } }
    if let size { record(window.setChecked(Ax.sizeAttr, size)) }
    guard !job.isCancelled, let topLeft else { return err.asBackendResult }
    record(window.setChecked(Ax.topLeftCornerAttr, topLeft))
    guard !job.isCancelled else { return err.asBackendResult }
    if let size { record(window.setChecked(Ax.sizeAttr, size)) }
    return err.asBackendResult
}

/// MacApp.swift:431-445. Some undocumented magic, restored afterwards.
/// References: yabai 3fe4c77, Rectangle #285.
private func disableAnimations<T>(app: AXUIElement, _ body: () -> T) -> T {
    let wasEnabled = app.get(Ax.enhancedUserInterfaceAttr) == true
    if wasEnabled {
        app.set(Ax.enhancedUserInterfaceAttr, false)
    }
    defer {
        if wasEnabled {
            app.set(Ax.enhancedUserInterfaceAttr, true)
        }
    }
    return body()
}
