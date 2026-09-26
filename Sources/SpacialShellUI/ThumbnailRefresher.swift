import AppKit
import SpacialShellKit
import SpacialShellProtocol

/// #142: takes the rail's thumbnails ahead of any hover and keeps them from going stale, so the
/// hover card (#90) draws real pictures in its first frame. The policy — oldest first, `cadence`,
/// one in flight, `perMinute` — is `ThumbnailRefresh` in Kit; this runs it on a timer and captures
/// through `CaptureGate` into `WindowThumbnails`.
///
/// There is no standing timer: one task sleeps until the next window is due, and ends when the
/// policy has nothing to do (no rail windows, the gate not open, the screen locked or asleep). A
/// world change, the screen coming back, or its own capture landing starts it again. The gate not
/// yet open includes every launch until the first user-initiated capture: this never makes it.
@MainActor
final class ThumbnailRefresher {
    static let shared = ThumbnailRefresher()

    private var policy = ThumbnailRefresh()
    private var refs: [WindowID: SpacialShellProtocol.WindowRef] = [:]
    private var order: [WindowID] = []
    private var loop: Task<Void, Never>?
    /// A capture is running; a poke meanwhile is left to the loop, which asks again when it lands.
    private var capturing = false
    private var locked = false, asleep = false

    private init() {
        let ws = NSWorkspace.shared.notificationCenter, dist = DistributedNotificationCenter.default()
        watch(ws, NSWorkspace.screensDidSleepNotification) { $0.asleep = true }
        watch(ws, NSWorkspace.screensDidWakeNotification) { $0.asleep = false }
        watch(dist, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        watch(dist, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
    }

    /// The windows the rail draws icons for; none while the rail is not shown (Zen, `show-panels`).
    func update(world: World, railShown: Bool) {
        let windows = railShown ? ThumbnailRefresh.candidates(in: world) : []
        order = windows.map(\.id)
        refs = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        poke()
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name,
                       _ apply: @escaping @MainActor (ThumbnailRefresher) -> Void) {
        // The shared instance lives as long as the app, so the observers are never removed.
        _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                apply(self)
                self.poke()
            }
        }
    }

    /// Re-decide from scratch: drops a pending wait (never a capture in flight).
    private func poke() {
        guard !capturing else { return }
        loop?.cancel()
        loop = Task(priority: .utility) { [weak self] in await self?.run() }
    }

    private func run() async {
        while !Task.isCancelled {
            let gateOpen = await CaptureGate.shared.admitsPrefetch
            guard !Task.isCancelled else { return }
            let thumbs = WindowThumbnails.shared
            switch policy.next(windows: order, taken: thumbs.taken, gateOpen: gateOpen,
                               screenAwake: !locked && !asleep, now: .now) {
            case .idle:
                loop = nil
                return
            case .wait(let d):
                try? await Task.sleep(for: d)
            case .capture(let id):
                capturing = true
                let taken = ContinuousClock.now
                if let ref = refs[id] {
                    let images = await WindowPreviewCapture.images(for: [ref], longSide: WindowThumbnails.longSide)
                    await thumbs.add(Array(images), taken: taken)
                }
                policy.finished()
                capturing = false
            }
        }
    }
}
