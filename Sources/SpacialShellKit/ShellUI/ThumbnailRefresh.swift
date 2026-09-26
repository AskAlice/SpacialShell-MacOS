import Foundation

/// #142: which rail window's thumbnail to take next in the background, so a hover draws a real
/// picture in its first frame. Pure policy — the timer, the capture and the pixels live in the UI
/// layer's `ThumbnailRefresher`, which asks `next` and reports `finished`.
///
/// - **Oldest first:** a window with no thumbnail is the oldest of all, so preload and refresh are
///   one rule. Age counts from the newer of the last picture (from any source: a switch, a hover,
///   this) and the last background attempt, so a window that will not capture waits its turn
///   instead of being retried every step.
/// - **Due** once `cadence` old; nothing due means wait until something is.
/// - **Budget:** one capture in flight, at most `perMinute` started in any 60 s.
/// - **Never** while the capture gate does not admit prefetch (#92: not before the first capture has
///   succeeded, and not after a decline), nor while the screen is locked or the display asleep.
public struct ThumbnailRefresh: Sendable {
    /// How old a rail window's thumbnail may get before the background takes it again.
    public static var cadence: Duration { .seconds(30) }
    /// Captures started in any minute. About 10 windows kept at `cadence`; more are refreshed less
    /// often, oldest first. A cold rail of 20 windows warms up in a minute.
    public static var perMinute: Int { 20 }

    public enum Decision: Equatable, Sendable {
        /// Take this window now, then call `finished`.
        case capture(WindowID)
        /// Nothing may start before this long; ask again then.
        case wait(Duration)
        /// Nothing to do until something changes (the windows, the gate, the screen, or a capture
        /// landing): the caller stops its timer.
        case idle
    }

    private var inFlight = false
    private var started: [ContinuousClock.Instant] = []
    private var attempted: [WindowID: ContinuousClock.Instant] = [:]

    public init() {}

    /// `windows` are the rail's, in rail order (the tie-break); `taken` is each one's thumbnail time.
    public mutating func next(windows: [WindowID], taken: (WindowID) -> ContinuousClock.Instant?,
                              gateOpen: Bool, screenAwake: Bool,
                              now: ContinuousClock.Instant) -> Decision {
        let live = Set(windows)
        attempted = attempted.filter { live.contains($0.key) }
        started.removeAll { now - $0 >= .seconds(60) }
        guard gateOpen, screenAwake, !inFlight, !windows.isEmpty else { return .idle }

        // Oldest first, the first in rail order on a tie; nil (never taken, never tried) is oldest.
        let ages = windows.map { id in (id: id, at: [taken(id), attempted[id]].compactMap { $0 }.max()) }
        guard let pick = ages.min(by: { a, b in
            guard let x = a.at else { return b.at != nil }
            return b.at.map { x < $0 } ?? false
        }) else { return .idle }
        if let at = pick.at, now - at < Self.cadence { return .wait(Self.cadence - (now - at)) }
        if started.count >= Self.perMinute, let first = started.first {
            return .wait(.seconds(60) - (now - first))
        }
        inFlight = true
        started.append(now)
        attempted[pick.id] = now
        return .capture(pick.id)
    }

    /// The capture `next` asked for has ended, whether or not it produced a picture.
    public mutating func finished() { inFlight = false }

    /// The windows a rail tile represents and a background capture can usefully take: every window
    /// in every workspace row. Parked windows (an inactive workspace's, in a corner sliver) are
    /// included — the window server still lists them on screen, and `desktopIndependentWindow`
    /// captures their full content. Minimized, app-hidden, off-Space and fullscreen windows are
    /// not: none is in the on-screen listing a capture resolves through. Nor is a placeholder
    /// (#128), which has no window at all.
    public static func candidates(in world: World) -> [WindowRef] {
        let skip = world.hidden.union(world.offSpace).union(world.fullscreen)
        return world.screens.keys.sorted().flatMap { display in
            world.screens[display]!.workspaces.flatMap(\.windows).filter { !skip.contains($0) && !$0.isPlaceholder }
        }
    }
}
