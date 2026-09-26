import AppKit
import CoreGraphics
import SpacialShellKit
import struct SpacialShellProtocol.WindowRef
import os

/// The real `WindowBackend` (spec §7.6, §7.7, §7.4 termination): global observers coalesced into
/// refresh sessions, a periodic backstop, and a blocking restore on the way out.
///
/// Isolation: the class is `@MainActor`, because every piece of scheduling state it owns
/// (`refreshTask`, `periodic`, `debounce`, `signals`, `mouseDown`, the observer tokens) is touched
/// from notification callbacks that are already on the main queue. Everything that is *not* the
/// main actor — the `WindowBackend` conformance, the event stream, the registry, the termination
/// restore — is `nonisolated`: AX callbacks arrive on per-app threads, the reconciler calls the
/// write methods from `WorldStore`'s actor, and the termination restore runs on whatever thread
/// the signal source uses. Those paths touch only `let`s of `Sendable` type: the two stream
/// continuations and the (lock-guarded) registry.
///
/// Lifecycle: `init` → `start()` (main actor, once) → … → `stop()`. **`stop()` is terminal**: it
/// removes every observer, cancels every task and *finishes the event stream*, so a consumer's
/// `for await … in events` returns instead of hanging. A backend cannot be restarted after it;
/// `start()` on a stopped backend is a no-op. `restoreAllForTermination` still works afterwards,
/// since it goes straight to the registry.
@MainActor
public final class AXWindowBackend: WindowBackend {
    public nonisolated let events: AsyncStream<BackendEvent>
    private nonisolated let continuation: AsyncStream<BackendEvent>.Continuation

    /// AX threads signal here; `start()`'s consumer turns each signal into a refresh *on the main
    /// actor*, which is the whole hop. `bufferingNewest(1)` is deliberate: a burst of
    /// `kAXWindowCreated`/`kAXFocusedWindowChanged` from one app collapses into one refresh
    /// instead of one cancel-and-restart per notification.
    private nonisolated let refreshSignals: AsyncStream<Void>
    private nonisolated let refreshSignal: AsyncStream<Void>.Continuation

    private nonisolated let registry: AXAppRegistry
    private nonisolated let config: Config

    private var observerTokens: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var eventMonitors: [Any] = []
    private var refreshTask: Task<Void, Never>?
    /// A refresh session is running. The periodic backstop *coalesces* against it instead of
    /// pre-empting it: one sweep is `apps × axTimeoutMs` in the worst case and can outlast
    /// `refreshIntervalMs`, and a tick that cancels-and-restarts would begin again at app #1 every
    /// time, so the apps at the tail of the sweep would never be snapshotted at all.
    private var sessionInFlight = false
    /// Identifies the newest session, so a cancelled one can't clear its successor's flag.
    private var sessionGeneration = 0
    /// When the current run of settle deferrals began — see `Self.maxDeferral`.
    private var deferringSince: ContinuousClock.Instant?
    private var periodic: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var signals: Task<Void, Never>?
    /// What the global mouse monitor last saw. Only ever a hint — see `isMouseDown`.
    private var mouseDown = false
    private var started = false
    private var stopped = false

    private nonisolated static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "AXWindowBackend")

    /// Ruling 4/5. Display topology is transient across wake and hot-plug: `NSScreen.screens` can
    /// report a half-built (or empty) arrangement for a few hundred milliseconds, and laying out
    /// against it strands windows. Wait for it to settle instead.
    private nonisolated static let settleMs = 500

    /// A display arrangement that never settles (a flapping adapter) must not defer refreshes
    /// forever: after this long, one refresh is forced through.
    private static let maxDeferral = Duration.seconds(5)

    /// How many `settleMs` waits `currentSnapshot()` gives an empty topology before giving up on
    /// it — 6 × 500 ms = 3 s, generous enough for a wake or a hot-plug, short enough that a boot
    /// with a genuinely dark screen still finishes starting up.
    private nonisolated static let emptyTopologyRetries = 6

    /// The last non-empty topology this backend saw, on either the push or the pull path. C1:
    /// `WorldStore.start()` and `.screenUnlocked` *pull* a snapshot, and an empty `displays` there
    /// reseeds the world from nothing — every workspace dropped. A stale-but-real arrangement is
    /// always the better answer. Lock-guarded rather than main-actor isolated because
    /// `currentSnapshot()` is `nonisolated`: it is called from `WorldStore`'s actor.
    private nonisolated let lastGoodDisplays = LastGoodDisplays()

    public init(config: Config) {
        self.config = config
        let (events, continuation) = AsyncStream.makeStream(of: BackendEvent.self, bufferingPolicy: .bufferingNewest(64))
        self.events = events
        self.continuation = continuation
        let (refreshSignals, refreshSignal) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        self.refreshSignals = refreshSignals
        self.refreshSignal = refreshSignal
        // Set once, here: the AX threads' only route back into the backend. Both continuations are
        // immutable `Sendable` values, so the closure races with nothing.
        self.registry = AXAppRegistry(timeoutMs: config.axTimeoutMs) { pid, event in
            switch event {
                case .windowsChanged, .focusChanged:
                    refreshSignal.yield(())
                case .moved(let id, let rect):
                    continuation.yield(.windowMoved(WindowRef(id: id, pid: pid), rect))
                case .resized(let id, let rect):
                    continuation.yield(.windowResized(WindowRef(id: id, pid: pid), rect))
            }
        }
    }

    /// #28: whoever sees a human press a key or a mouse button reports it here — the global
    /// mouse monitor above, and `HotkeyTap` via `AppRuntime`. It rides the event stream, so the
    /// store sees it before the activation it causes. Safe from any thread (the tap calls it from
    /// its own, inside the tap's deadline): one uncontended lock and a yield.
    ///
    /// Throttled, because the stream buffers only the newest 64 events: key repeat during a long
    /// reconcile would otherwise push out the events that matter. Coarsening the stamp by this
    /// much is nothing against the store's 1 s input window.
    public nonisolated func noteHumanInput() {
        let now = ContinuousClock.now
        let due = lastHumanInput.withLock { last -> Bool in
            if let last, now - last < Self.humanInputThrottle { return false }
            last = now; return true
        }
        if due { continuation.yield(.humanInput) }
    }
    private nonisolated let lastHumanInput = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: nil)
    private nonisolated static let humanInputThrottle = Duration.milliseconds(100)

    // MARK: - Lifecycle

    /// Spec §7.6 global observers plus the periodic backstop. Called once, from the main thread;
    /// everything registered here is undone by `stop()`.
    public func start() {
        guard !started, !stopped else { return }
        started = true

        let workspaceNames: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in workspaceNames {
            observe(workspaceCenter, name) { [weak self] note in
                // Spec §7.7 defence 3: loginwindow's launch/activate churn is the lock screen
                // arriving, not the user doing anything.
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let fromLoginwindow = app?.bundleIdentifier == loginwindowBundleId
                // An activation is news in its own right, ahead of the debounced sweep (#56): the
                // sweep reports the *focused window*, and an app whose windows are all parked has
                // none, so waiting for it means never hearing that the user switched app at all.
                let activatedPid = name == NSWorkspace.didActivateApplicationNotification
                    ? app?.processIdentifier : nil
                MainActor.assumeIsolated {
                    guard !fromLoginwindow else { return }
                    if let pid = activatedPid { self?.resolveActivation(pid) }
                    self?.scheduleRefresh()
                }
            }
        }

        // Ruling 4: debounced, because a hot-plug or a wake reports several arrangements in a row.
        // `NSApplication.didChangeScreenParameters` is enough for M1; a
        // `CGDisplayRegisterReconfigurationCallback` would only tell us the same thing earlier and
        // less usefully (it fires *before* the arrangement settles), so it is deliberately not used.
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh(afterMs: Self.settleMs) }
        }

        // Spec §7.7: freeze between these two. They must reach `WorldStore` even while a refresh
        // is in flight, so they go straight to the stream.
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [continuation] _ in
            continuation.yield(.screenLocked)
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [continuation] _ in
            continuation.yield(.screenUnlocked)
        }

        // Spec §7.6: `kAXUIElementDestroyed` is unreliable (a close-button click on an unfocused
        // window raises nothing), so every mouse-up refreshes; and new windows are not adopted
        // while the button is down, because a tab being dragged out is briefly its own window
        // (AeroSpace #1001).
        // #108: both also report where, so the store can tell a title-bar drag and its drop. The
        // up is yielded before the refresh it schedules, so the drop lands before the sweep does.
        if let down = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            self?.mouseDown = true
            self?.noteHumanInput()
            self?.continuation.yield(.pointerDown(Self.pointer()))
        }) {
            eventMonitors.append(down)
        }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            self?.mouseDown = false
            self?.continuation.yield(.pointerUp(Self.pointer()))
            self?.scheduleRefresh()
        }) {
            eventMonitors.append(up)
        }
        // #28: every other way a hand leaves fullscreen — a Dock right-click menu, a scroll, a
        // trackpad swipe between Spaces — is human input too, or the guard would put the user
        // straight back into the fullscreen Space they just swiped out of. A left-button drag keeps
        // the input fresh for as long as it lasts, which is how the store tells a window the user
        // is dragging to another display from one that got there by itself (#57).
        // ponytail: whether a three-finger Space swipe reaches a global monitor is unverified;
        // if leaving fullscreen by swipe snaps back, that is the gap.
        if let other = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .rightMouseDown, .otherMouseDown, .scrollWheel, .swipe, .gesture, .beginGesture, .magnify],
            handler: { [weak self] _ in self?.noteHumanInput() }) {
            eventMonitors.append(other)
        }

        signals = Task { @MainActor [weak self, refreshSignals] in
            for await _ in refreshSignals {
                guard let self else { return }
                scheduleRefresh()
            }
        }

        periodic = Task { @MainActor [weak self, intervalMs = config.refreshIntervalMs] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(intervalMs))
                guard !Task.isCancelled, let self else { return }
                scheduleRefreshIfIdle()
            }
        }
    }

    /// Undoes `start()`. Terminal: the event stream is finished, so every consumer's `for await`
    /// ends rather than hanging on a backend that will never speak again.
    public func stop() {
        guard !stopped else { return }
        stopped = true
        for (center, token) in observerTokens { center.removeObserver(token) }
        observerTokens = []
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        eventMonitors = []
        refreshTask?.cancel(); refreshTask = nil
        periodic?.cancel(); periodic = nil
        debounce?.cancel(); debounce = nil
        signals?.cancel(); signals = nil
        refreshSignal.finish()
        continuation.finish()
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ body: @escaping @Sendable (Notification) -> Void,
    ) {
        observerTokens.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: body)))
    }

    /// M3a A7 (#56): ⌘Tab and the Dock land within one reconcile, not after the debounced sweep.
    /// The activated app's focused window is read on the spot and reported as `focusChanged`
    /// *ahead of* `appActivated`, so the store lands on the window macOS actually brought forward
    /// (via `applyNativeFocus`: the echo queues and the #28 fullscreen guard apply as ever), and the
    /// activation that follows finds that app on screen and changes nothing. An app with no focused
    /// window (all parked or minimized) reports only the activation, which surfaces one.
    ///
    /// Deliberately outside `scheduleRefresh`'s mouse-down gate: that gate stops a full sweep
    /// adopting a tab mid-drag-out, and this reads one attribute of one app, adopting nothing. The
    /// sweep this notification also schedules stays gated.
    ///
    /// Chained, so reports leave in the order macOS activated the apps: the store's echo queues
    /// retire every raise older than the one matched (#69), and a reordered pair would read our
    /// own earlier raise as a human switching back. A hung app delays the activations behind it
    /// by at most one `axTimeoutMs`.
    private func resolveActivation(_ pid: pid_t) {
        let previous = activationChain
        activationChain = Task { @MainActor [weak self, registry, continuation] in
            await previous?.value
            guard let self, !stopped else { return }
            // Not for an activation our own raise caused: it can land before macOS has made the
            // raised window the app's focused one, and reading focus then reports the app's
            // *previous* window as the user's choice — the #69 switch-back loop. Those activations
            // report as before, and the store matches them against its echo queue.
            let ours = ownRaises.withLock { t in t[pid].map { ContinuousClock.now - $0 < .seconds(1) } ?? false }
            if !ours, let ref = await registry.get(pid)?.focusedWindowRef() {
                continuation.yield(.focusChanged(ref))
            }
            continuation.yield(.appActivated(pid: pid))
        }
    }
    private var activationChain: Task<Void, Never>?

    /// The mouse, top-left global like every frame the store sees.
    private static func pointer() -> CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
    }

    // MARK: - Refresh sessions (spec §7.6)

    /// The global monitor never sees mouse events delivered to our own process, so a drag that
    /// ends over SpacialShell's own UI would leave `mouseDown` stuck true and freeze every refresh
    /// for good. The live button state is the authority; the flag only records what we saw.
    private var isMouseDown: Bool { mouseDown && NSEvent.pressedMouseButtons & 0x1 != 0 }

    /// Cancel any in-flight session and start a new one; the newest snapshot wins.
    private func scheduleRefresh() {
        guard !stopped else { return }
        // Deferred rather than dropped: the mouse-up monitor refreshes, and the periodic backstop
        // catches the drag that ended somewhere we couldn't see it.
        if isMouseDown { return }
        // A settle timer is pending (ruling 4/5: the topology is mid-hot-plug, or was empty a
        // moment ago). It will refresh in at most `settleMs`, against an arrangement that has
        // stopped moving — refreshing *now* is exactly the transient layout it exists to avoid,
        // so every other trigger folds into it, up to `maxDeferral`.
        if let debounce, !debounce.isCancelled {
            let deferredFor = deferringSince?.duration(to: .now) ?? .zero
            guard deferredFor >= Self.maxDeferral else { return }
            Self.log.warning("display topology unsettled for \(deferredFor.components.seconds) s; refreshing anyway")
            debounce.cancel()
            self.debounce = nil
        }
        deferringSince = nil
        refreshTask?.cancel()
        sessionGeneration &+= 1
        let generation = sessionGeneration
        sessionInFlight = true
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == sessionGeneration { sessionInFlight = false; refreshTask = nil } }
            // Ruling 5: an empty topology is always transient — `WorldStore` would reseed the
            // world and drop every restored workspace. Checked *before* the sweep too, so a
            // mid-hot-plug tick costs nothing instead of an `apps × axTimeoutMs` walk whose result
            // is discarded.
            guard !DisplayTopology.current().isEmpty else {
                retryAfterEmptyTopology()
                return
            }
            let snapshot = await RefreshSession(apps: registry).run()
            guard !Task.isCancelled, !stopped else { return }
            guard !snapshot.displays.isEmpty else {
                retryAfterEmptyTopology()
                return
            }
            lastGoodDisplays.record(snapshot.displays)
            continuation.yield(.snapshot(snapshot))
        }
    }

    private func retryAfterEmptyTopology() {
        Self.log.warning("empty display topology; retrying in \(Self.settleMs) ms")
        scheduleRefresh(afterMs: Self.settleMs)
    }

    /// The periodic backstop's entry point: never pre-empts a sweep that is still walking the app
    /// list, so every app gets its turn even when one of them is hung.
    private func scheduleRefreshIfIdle() {
        guard !sessionInFlight else { return }
        scheduleRefresh()
    }

    /// Cancel-and-reschedule: repeated display-reconfiguration notifications collapse into one
    /// refresh, `settleMs` after the last of them.
    private func scheduleRefresh(afterMs ms: Int) {
        guard !stopped else { return }
        if deferringSince == nil { deferringSince = .now }
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled, let self else { return }
            debounce = nil
            scheduleRefresh()
        }
    }

    // MARK: - WindowBackend

    /// C1. The *pull* counterpart of `scheduleRefresh`'s empty-topology guard, and the more
    /// dangerous of the two: `WorldStore.start()` (boot) and `.screenUnlocked` call this directly,
    /// and both are exactly when macOS is most likely to report no screens at all. There is no
    /// "try again later" here — whatever this returns is what the world is rebuilt from — so it
    /// waits for the arrangement to settle, and failing that answers with the last real one it
    /// saw. Only a backend that has never seen a display returns an empty topology, and the store
    /// drops that snapshot rather than acting on it.
    ///
    /// The cheap `DisplayTopology.current()` call is what gets retried, not the sweep: one sweep
    /// costs `apps × axTimeoutMs` and its result would be thrown away anyway.
    public nonisolated func currentSnapshot() async -> Snapshot {
        for _ in 0..<Self.emptyTopologyRetries {
            guard await MainActor.run(body: { DisplayTopology.current().isEmpty }) else { break }
            try? await Task.sleep(for: .milliseconds(Self.settleMs))
        }
        let snapshot = await RefreshSession(apps: registry).run()
        guard snapshot.displays.isEmpty else {
            lastGoodDisplays.record(snapshot.displays)
            return snapshot
        }
        let lastGood = lastGoodDisplays.value
        guard !lastGood.isEmpty else {
            Self.log.error("display topology still empty after \(Self.emptyTopologyRetries) retries and none ever seen; returning an empty snapshot")
            return snapshot
        }
        Self.log.warning("display topology still empty after \(Self.emptyTopologyRetries) retries; using the last known arrangement of \(lastGood.count) display(s)")
        var patched = snapshot
        patched.displays = lastGood
        return patched
    }

    public nonisolated func setFrame(_ ref: WindowRef, _ frame: CGRect) async -> Result<Void, BackendError> {
        await registry.get(ref.pid)?.setFrame(ref.id, frame) ?? .failure(.notFound)
    }

    public nonisolated func setPosition(_ ref: WindowRef, _ origin: CGPoint) async -> Result<Void, BackendError> {
        await registry.get(ref.pid)?.setPosition(ref.id, origin) ?? .failure(.notFound)
    }

    public nonisolated func raise(_ ref: WindowRef) async -> Result<Void, BackendError> {
        ownRaises.withLock { $0[ref.pid] = ContinuousClock.now }
        return await registry.get(ref.pid)?.raise(ref.id) ?? .failure(.notFound)
    }
    /// When the shell last raised a window of each pid — see `resolveActivation`.
    private nonisolated let ownRaises = OSAllocatedUnfairLock<[pid_t: ContinuousClock.Instant]>(initialState: [:])

    public nonisolated func close(_ ref: WindowRef) async -> Result<Void, BackendError> {
        await registry.get(ref.pid)?.close(ref.id) ?? .failure(.notFound)
    }

    public nonisolated func setFullscreen(_ ref: WindowRef, _ on: Bool) async -> Result<Void, BackendError> {
        await registry.get(ref.pid)?.setFullscreen(ref.id, on) ?? .failure(.notFound)
    }

    public nonisolated func unhide(_ ref: WindowRef) async -> Result<Void, BackendError> {
        await registry.get(ref.pid)?.unhide(ref.id) ?? .failure(.notFound)
    }

    /// #107. A fresh null-source event reads the current pointer in global top-left coordinates —
    /// the same space as AX frames and `DisplayInfo`.
    public nonisolated func pointerLocation() async -> CGPoint? { CGEvent(source: nil)?.location }

    /// #107. `CGWarpMouseCursorPosition` does not post a mouse event, and afterwards macOS ignores
    /// physical mouse movement for a moment (the local-events suppression interval); re-associating
    /// the mouse with the cursor ends that, so the pointer never feels stuck after a warp.
    public nonisolated func warpPointer(to point: CGPoint) async {
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - Termination (spec §7.4)

    /// Never strand a window in a parking corner. Every window in `parked` is centred on its
    /// screen's `visibleFrame` at the size we last observed (fallback 800×600), with blocking,
    /// bounded AX writes — plus every window in `stranded`, which was retired to `ignored` while
    /// parked and can no longer be reached any other way (best-effort, on the main display).
    ///
    /// Only *parked* windows move. A tiled window is already where the user put it, and centring
    /// it on the way out would pile every window on every workspace into the middle of one screen
    /// — a mess of the quitting window manager's own making, and nothing §7.4 asked for.
    ///
    /// `nonisolated` and synchronous on purpose: this is called from a `DispatchSource` signal
    /// handler or `applicationWillTerminate` (never from a raw C signal handler), which must not
    /// return until the windows are back.
    ///
    /// `deadline` is a **total** wall-clock budget. Each `setFrameForTermination` waits up to
    /// `max(2000, axTimeoutMs × 4)` ms on its own, so a handful of hung apps would otherwise blow
    /// through macOS's termination grace period and every window after the stall would stay
    /// parked anyway — with the budget, the ones we can still reach get moved first.
    public nonisolated func restoreAllForTermination(
        world: World,
        displays: [DisplayInfo],
        observed: [WindowRef: CGRect],
        stranded: [WindowRef: CGRect] = [:],
        parked: Set<WindowRef> = [],
        deadline: Duration = .seconds(8),
    ) {
        let clock = ContinuousClock()
        let start = clock.now
        var restored = 0
        var skipped = 0

        func place(_ ref: WindowRef, size: CGSize, on display: DisplayInfo) {
            guard start.duration(to: clock.now) < deadline else { skipped += 1; return }
            let visible = display.visibleFrame
            let frame = CGRect(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2,
                width: size.width,
                height: size.height,
            )
            // An app that is no longer registered has no window left to strand.
            guard let app = registry.get(ref.pid) else { return }
            app.setFrameForTermination(ref.id, frame)
            restored += 1
        }

        // Deviation from the brief, which skips a screen whose display is missing: a window whose
        // display was unplugged between the last refresh and the quit would stay in its parking
        // corner, which is the one outcome §7.4 exists to prevent. It goes to the main display.
        let fallback = displays.first(where: \.isMain) ?? displays.first
        for (displayID, screen) in world.screens {
            guard let display = displays.first(where: { $0.id == displayID }) ?? fallback else { continue }
            for workspace in screen.workspaces {
                for ref in workspace.windows where parked.contains(ref) {
                    place(ref, size: observed[ref]?.size ?? CGSize(width: 800, height: 600), on: display)
                }
            }
        }
        // Retired-while-parked windows are in no workspace any more, so the walk above cannot see
        // them; their recorded frame is the last one from before they were parked.
        if let fallback {
            for (ref, frame) in stranded {
                place(ref, size: frame.size, on: fallback)
            }
        }
        if skipped > 0 {
            Self.log.error("termination restore ran out of budget: \(restored) restored, \(skipped) left parked")
        }
    }

    // MARK: - Testing

    /// Tests have no way to make macOS lock the screen; this is the same door the lock/unlock
    /// observers use.
    nonisolated func _testYield(_ event: BackendEvent) { continuation.yield(event) }
}

/// The backend's memory of the last real display arrangement (C1). Its own type because
/// `currentSnapshot()` is `nonisolated` and may run on any thread, so the storage needs a lock
/// rather than the class's main-actor isolation.
private final class LastGoodDisplays: @unchecked Sendable {
    private let lock = NSLock()
    private var displays: [DisplayInfo] = []

    var value: [DisplayInfo] { lock.lock(); defer { lock.unlock() }; return displays }

    func record(_ new: [DisplayInfo]) {
        guard !new.isEmpty else { return }
        lock.lock(); displays = new; lock.unlock()
    }
}
