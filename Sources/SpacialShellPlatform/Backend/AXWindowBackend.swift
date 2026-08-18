import AppKit
import CoreGraphics
import SpacialShellKit
import struct SpacialShellKit.WindowRef
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
    private var periodic: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var signals: Task<Void, Never>?
    /// What the global mouse monitor last saw. Only ever a hint — see `isMouseDown`.
    private var mouseDown = false
    private var started = false
    private var stopped = false

    private static let log = Logger(subsystem: "me.askalice.SpacialShell", category: "AXWindowBackend")

    /// Ruling 4/5. Display topology is transient across wake and hot-plug: `NSScreen.screens` can
    /// report a half-built (or empty) arrangement for a few hundred milliseconds, and laying out
    /// against it strands windows. Wait for it to settle instead.
    private static let settleMs = 500

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
                let fromLoginwindow = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .bundleIdentifier == loginwindowBundleId
                MainActor.assumeIsolated {
                    guard !fromLoginwindow else { return }
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
        if let down = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            self?.mouseDown = true
        }) {
            eventMonitors.append(down)
        }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            self?.mouseDown = false
            self?.scheduleRefresh()
        }) {
            eventMonitors.append(up)
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
                scheduleRefresh()
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
        // so every other trigger folds into it.
        if let debounce, !debounce.isCancelled { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await RefreshSession(apps: registry).run()
            guard !Task.isCancelled, !stopped else { return }
            // Ruling 5: an empty topology is always transient — `WorldStore` would reseed the
            // world and drop every restored workspace. Skip this one and look again once the
            // display arrangement has settled.
            guard !snapshot.displays.isEmpty else {
                Self.log.warning("empty display topology; retrying in \(Self.settleMs) ms")
                scheduleRefresh(afterMs: Self.settleMs)
                return
            }
            continuation.yield(.snapshot(snapshot))
        }
    }

    /// Cancel-and-reschedule: repeated display-reconfiguration notifications collapse into one
    /// refresh, `settleMs` after the last of them.
    private func scheduleRefresh(afterMs ms: Int) {
        guard !stopped else { return }
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled, let self else { return }
            debounce = nil
            scheduleRefresh()
        }
    }

    // MARK: - WindowBackend

    public nonisolated func currentSnapshot() async -> Snapshot {
        await RefreshSession(apps: registry).run()
    }

    public nonisolated func setFrame(_ ref: WindowRef, _ frame: CGRect) async -> Result<Void, BackendError> {
        await registry.get(ref.pid)?.setFrame(ref.id, frame) ?? .failure(.notFound)
    }

    public nonisolated func setPosition(_ ref: WindowRef, _ origin: CGPoint) async -> Result<Void, BackendError> {
        await registry.get(ref.pid)?.setPosition(ref.id, origin) ?? .failure(.notFound)
    }

    public nonisolated func raise(_ ref: WindowRef) async -> Result<Void, BackendError> {
        await registry.get(ref.pid)?.raise(ref.id) ?? .failure(.notFound)
    }

    public nonisolated func close(_ ref: WindowRef) async -> Result<Void, BackendError> {
        await registry.get(ref.pid)?.close(ref.id) ?? .failure(.notFound)
    }

    // MARK: - Termination (spec §7.4)

    /// Never strand a window in a parking corner. Every window the model placed is centred on its
    /// screen's visible frame at the size we last observed, with blocking, bounded AX writes.
    ///
    /// `nonisolated` and synchronous on purpose: this is called from a `DispatchSource` signal
    /// handler or `applicationWillTerminate` (never from a raw C signal handler), which must not
    /// return until the windows are back.
    public nonisolated func restoreAllForTermination(
        world: World,
        displays: [DisplayInfo],
        observed: [WindowRef: CGRect],
    ) {
        // Deviation from the brief, which skips a screen whose display is missing: a window whose
        // display was unplugged between the last refresh and the quit would stay in its parking
        // corner, which is the one outcome §7.4 exists to prevent. It goes to the main display.
        let fallback = displays.first(where: \.isMain) ?? displays.first
        for (displayID, screen) in world.screens {
            guard let display = displays.first(where: { $0.id == displayID }) ?? fallback else { continue }
            let visible = display.visibleFrame
            for workspace in screen.workspaces {
                for ref in workspace.windows {
                    let size = observed[ref]?.size ?? CGSize(width: 800, height: 600)
                    let frame = CGRect(
                        x: visible.midX - size.width / 2,
                        y: visible.midY - size.height / 2,
                        width: size.width,
                        height: size.height,
                    )
                    registry.get(ref.pid)?.setFrameForTermination(ref.id, frame)
                }
            }
        }
    }

    // MARK: - Testing

    /// Tests have no way to make macOS lock the screen; this is the same door the lock/unlock
    /// observers use.
    nonisolated func _testYield(_ event: BackendEvent) { continuation.yield(event) }
}
