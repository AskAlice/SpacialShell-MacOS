import Foundation

/// #170: what a focus or activation report means.
///
/// Every raise the shell makes comes back from macOS twice — as a focus change and as an app
/// activation — and late, after a quick Fn+D or Fn+W may already have moved the model on. Reports
/// also arrive from the human (a click, ⌘Tab, a Dock click) and from apps grabbing focus by
/// themselves. The rules that tell them apart are timing-based but pure, so they live here with the
/// clock injected: the store records its raises (`recordRaise`), its commands' focus moves
/// (`commanded`) and the human's input (`humanInput`), asks what each report is, and follows the
/// `Verdict`. The #28 fullscreen guard's decisions (where an intruder goes, which held-back request
/// is honoured) live here too; the store applies them to the world.
public struct FocusEchoes: Sendable {
    /// Backstop for echoes that never come (raising the app already in front activates nothing):
    /// past this, a report of that window is a human choice again, so #56 keeps surfacing it.
    public static let echoWindow = Duration.seconds(1)
    /// #28: a focus change this soon after a key press or a click is the human's doing and goes
    /// through untouched; later than this, while a fullscreen window is in front, it is a window
    /// grabbing focus by itself. Long enough for ⌘Tab or a Dock click to land as an activation,
    /// short enough that an app waking up a second later is not mistaken for the user.
    public static let humanInputWindow = Duration.seconds(1)

    private let now: @Sendable () -> ContinuousClock.Instant
    /// The shell's own activations (a rename alert, Settings) come from a click on its own panels,
    /// which the global mouse monitor never sees. They are never intrusions.
    private let ownPid: Int32
    /// The window the shell raised last: the same window is not raised twice in a row.
    public private(set) var lastRaised: WindowRef?
    /// Raises whose echoes have not arrived yet, oldest first — one queue per echo stream, since
    /// every raise is reported twice, as a focus change and as an app activation (#69).
    ///
    /// Fast switching raises X then Y before macOS reports X. With only `lastRaised` to go on,
    /// X's late echo read as a human choosing X, surfaced it, and that raise echoed late in turn —
    /// two apps trading focus ~10×/s. So a report matching a queued raise is our own echo; and
    /// since macOS reports raises in order, it also retires every raise queued before it, whose
    /// echo has either landed or never will. A report matching nothing queued is a human.
    private var pendingFocus: [(ref: WindowRef, at: ContinuousClock.Instant)] = []
    private var pendingActivation: [(ref: WindowRef, at: ContinuousClock.Instant)] = []
    /// What the last report said macOS had focused. Focus that has not moved since is an echo,
    /// not news. Same idea as `WindowEchoes`, which does this for frames.
    private var lastNativeFocus: WindowRef?
    /// #84: the window a command just moved focus to, and when. macOS keeps reporting the window
    /// it had until our raise lands.
    private var commandedFocus: (ref: WindowRef, at: ContinuousClock.Instant)?
    private var lastHumanInput: ContinuousClock.Instant?
    /// #28: focus requests held back behind a fullscreen window on a display with nowhere else to
    /// go, oldest first, each with the fullscreen window it was held behind. Handed out by
    /// `drainDeferred` once that window leaves fullscreen.
    private var deferred: [(requester: WindowRef, behind: WindowRef)] = []

    public init(ownPid: Int32 = ProcessInfo.processInfo.processIdentifier,
                now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.ownPid = ownPid; self.now = now
    }

    /// What a report is.
    public enum Verdict: Sendable, Equatable {
        /// The echo of our own raise. News only where the window is already shown (see the store).
        case ownEcho
        /// macOS re-reporting the focus it already had: news about nothing, except where it is
        /// already shown — and a fullscreen window's is always news (#49).
        case repeated
        /// The past: our raise's echo after the model has moved on (#67, #69), or macOS
        /// re-reporting the window it had before a command's raise landed (#84). Ignored.
        case stale
        /// The human moved focus: the model follows.
        case change
        /// #28: a window taking focus by itself while `behind` is fullscreen in front. `behind`
        /// goes back in front; `intercept` says where the requester goes.
        case intrusion(behind: WindowRef)
    }

    // MARK: - recording

    /// The store is about to raise `f`, the model's focus. False when it is the window raised last
    /// (nothing to do); otherwise both of the raise's echoes are expected from now.
    public mutating func recordRaise(of f: WindowRef) -> Bool {
        guard f != lastRaised else { return false }
        lastRaised = f
        pendingFocus.append((f, now()))
        pendingActivation.append((f, now()))
        return true
    }

    /// #179: the store raised `p` for a peek, without activating its app or focusing it. A raise
    /// in the app's own window order can still make `p` that app's focused window, and macOS then
    /// reports it, possibly after the peek has ended: queued like any raise, so that report is our
    /// own echo of a window the model has not focused — `.stale`, never a human choosing `p`. Only
    /// the focus stream: nothing is activated, so no activation echo is due. `lastRaised` is left
    /// alone; the peek is not the model's focus.
    public mutating func peekRaised(_ p: WindowRef) { pendingFocus.append((p, now())) }

    /// #179: the peek is over. The model's focus is raised again on the next pass, even if it was
    /// the window raised last: the peek raise may have taken its app's focus, and it went over it.
    public mutating func peekEnded() { lastRaised = nil }

    /// #84: a command just moved the model's focus to `f`.
    public mutating func commanded(_ f: WindowRef) { commandedFocus = (f, now()) }

    /// A key press, a click, or a swipe: the human is at the keyboard or the mouse.
    public mutating func humanInput() { lastHumanInput = now() }

    /// #28: human input arrived within `humanInputWindow`.
    public var humanRecently: Bool {
        guard let t = lastHumanInput else { return false }
        return now() - t < Self.humanInputWindow
    }

    // MARK: - classifying

    /// macOS reports `r` as the focused window. `world` is the model as it stands.
    public mutating func focusReported(_ r: WindowRef, world: World) -> Verdict {
        let ownEcho = Self.consume(&pendingFocus, now: now()) { $0 == r }
        let unchanged = r == lastNativeFocus
        lastNativeFocus = r
        // #84: right after a command moved focus, macOS re-reports the window it *had* (unchanged)
        // until our raise lands. That is the past, not the user: honouring it pulled focus back a
        // tab ~50 ms after Fn+D and restarted the slide. A *change* (the user clicked something)
        // still goes through, and so does an unchanged report once the echo window has passed —
        // then macOS really did not move, and the model follows it.
        if unchanged, let c = commandedFocus, c.ref != r, world.focus.window == c.ref,
           now() - c.at < Self.echoWindow { return .stale }
        // #28. A repeated report of a requester already intercepted is *not* skipped as an echo:
        // it means macOS still has it in front, so the fullscreen window goes back again. Windows
        // the model does not manage (ignored, unknown) are left alone.
        if !ownEcho, let fs = Self.fullscreenInFront(world), r != fs, r.pid != ownPid, !humanRecently,
           world.ephemeral.contains(r) || world.location(of: r) != nil {
            return .intrusion(behind: fs)
        }
        // Our own raise of `r` reporting back after the model has already moved on (a quick Fn+D
        // after Fn+A) is history, not news — in *any* row. Only cross-row echoes used to be
        // dropped, so a late echo inside the row pulled focus back a tab and the next echo pushed
        // it forward again: fast tab switching stuttered and restarted its slides (#67).
        if ownEcho && world.focus.window != r { return .stale }
        return ownEcho ? .ownEcho : unchanged ? .repeated : .change
    }

    /// macOS reports app `pid` activated. Raising a window activates its app, and macOS reports
    /// that back like any other activation; acting on it would raise again, and again. Nothing is
    /// lost by ignoring it: the app we just raised is the one already on screen.
    public mutating func activationReported(pid: Int32, world: World) -> Verdict {
        if Self.consume(&pendingActivation, now: now(), { $0.pid == pid }) || pid == lastRaised?.pid { return .ownEcho }
        // The fullscreen window's own app activating is no Space switch, and the store's check
        // already finds it on screen; only another app can pull the user out.
        if let fs = Self.fullscreenInFront(world), fs.pid != pid, pid != ownPid, !humanRecently { return .intrusion(behind: fs) }
        return .change
    }

    // MARK: - the fullscreen guard (#28)

    /// Where an intercepted request goes.
    public struct Interception: Sendable, Equatable {
        public enum Requester: Sendable, Equatable {
            /// Into `workspace`, the active row of `display`, a display not showing a fullscreen Space.
            case move(display: DisplayID, workspace: UUID)
            /// Held until the fullscreen window leaves fullscreen (`drainDeferred`).
            case deferred
        }
        /// The fullscreen window's display: the model's focus goes back there, on it.
        public var screen: DisplayID
        /// nil when there is no requester to place (an app with no window the model can show).
        public var requester: Requester?
        public init(screen: DisplayID, requester: Requester?) { self.screen = screen; self.requester = requester }
    }

    /// `requester` asked for focus with no human behind it while `fs` is in front. Send it to a
    /// display that is not showing a fullscreen Space — into that display's active workspace,
    /// where a new window would land — preferring the display it is already on; with none, hold
    /// the request until `fs` leaves fullscreen. Either way `fs` goes back in front, raised even
    /// if it was the last window raised: macOS has raised the requester since. macOS has no veto
    /// for a window manager, so protection can only be this reactive put-back. Nil when `fs` is on
    /// no display the model knows: nothing to do.
    ///
    /// ponytail: an app that re-activates itself every time it loses focus will trade places with
    /// `fs` for as long as it keeps trying. Upgrade path: give up on a requester after N rounds.
    public mutating func intercept(_ requester: WindowRef?, behind fs: WindowRef, world: World) -> Interception? {
        guard let fsScreen = world.screenContaining(fs) else { return nil }
        var placed: Interception.Requester?
        if let r = requester {
            let free = world.screenOrder.filter { $0 != fsScreen && !Self.showsFullscreen($0, world) }
            let own = world.screenContaining(r)
            // ponytail: an ephemeral window has no workspace to land in, so it is deferred even
            // when a display is free. Upgrade path: centre it on the free display instead.
            if own != nil, let dest = free.first(where: { $0 == own }) ?? free.first,
               let target = world.screens[dest]?.active.id {
                placed = .move(display: dest, workspace: target)
            } else {
                deferred.removeAll { $0.requester == r }
                deferred.append((r, fs))
                placed = .deferred
            }
        }
        lastRaised = nil
        return Interception(screen: fsScreen, requester: placed)
    }

    /// Hands out held-back focus. Requests held behind a window that has left fullscreen, or gone
    /// away, are settled at once: the newest whose window still exists gets the focus — but only if
    /// the user is still on the window fullscreen ended in. One who has already gone somewhere else
    /// has moved on, and the request is dropped; its window keeps its tab. Returns the window to focus.
    public mutating func drainDeferred(world: World) -> WindowRef? {
        let ended = deferred.filter { !world.fullscreen.contains($0.behind) }
        guard !ended.isEmpty else { return nil }
        deferred.removeAll { !world.fullscreen.contains($0.behind) }
        guard let next = ended.last(where: { world.location(of: $0.requester) != nil || world.ephemeral.contains($0.requester) }),
              world.focus.window == next.behind || world.location(of: next.behind) == nil else { return nil }
        return next.requester
    }

    // MARK: - bookkeeping

    /// `r` is gone: it is neither the window raised last nor the focus macOS last reported.
    public mutating func vanished(_ r: WindowRef) {
        if lastRaised == r { lastRaised = nil }
        if lastNativeFocus == r { lastNativeFocus = nil }
    }

    /// `r` was retired to `ignored`: raise it again if it comes back.
    public mutating func retired(_ r: WindowRef) { if lastRaised == r { lastRaised = nil } }

    // MARK: - rules

    /// True when a report is the echo of a queued raise; retires that raise and every older one.
    private static func consume(_ queue: inout [(ref: WindowRef, at: ContinuousClock.Instant)], now t: ContinuousClock.Instant,
                                _ matches: (WindowRef) -> Bool) -> Bool {
        queue.removeAll { t - $0.at >= echoWindow }
        guard let i = queue.firstIndex(where: { matches($0.ref) }) else { return false }
        queue.removeFirst(i + 1)
        return true
    }

    /// The fullscreen window the user is in, if any — the model's answer to "is this display
    /// showing a fullscreen Space?".
    ///
    /// `AXFullScreen` cannot answer it: a window keeps reporting fullscreen after the user switches
    /// away from its Space. The model's focus can. It follows every native focus report, so the
    /// moment the user goes anywhere else — another Space, window or display — it stops naming the
    /// fullscreen window; while it still does, that window is what macOS last put in front (or
    /// what we just raised back there). So: the focused window, if the model has it fullscreen.
    static func fullscreenInFront(_ world: World) -> WindowRef? {
        guard let f = world.focus.window, world.fullscreen.contains(f) else { return nil }
        return f
    }

    /// Whether a display the user is *not* on is showing a fullscreen Space. macOS reports one
    /// focused window, not one per display, so that display's own focus stands in: its active
    /// workspace's anchor, the window last focused there.
    ///
    /// ponytail: a stale anchor (the user swiped that display off its fullscreen Space and focused
    /// nothing there since) reads as covered. That errs towards deferring rather than moving — the
    /// safe side. Upgrade path: per-display current-Space ids from the platform.
    static func showsFullscreen(_ d: DisplayID, _ world: World) -> Bool {
        guard let a = world.screens[d]?.active.anchor else { return false }
        return world.fullscreen.contains(a)
    }
}
