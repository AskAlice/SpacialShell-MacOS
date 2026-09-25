import Foundation
import os

public actor WorldStore {
    /// Model membership changes only (adopt, fullscreen, retire, vanish): rare, and the one trail that
    /// answers "where did that window go?" after the fact.
    private static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "store")
    public private(set) var world: World
    private let backend: any WindowBackend
    private var config: Config
    private let zeroSliverBundleIDs: Set<String>
    private let onChange: @Sendable (World) -> Void

    private var displays: [DisplayInfo] = []
    private var observed: [WindowRef: CGRect] = [:]
    private var prePark: [WindowRef: CGRect] = [:]
    /// Spec §7.4 + §11. A window retired to `ignored` after three failed writes *while parked* is
    /// unreachable by the reconciler for good, so nothing would ever unpark it — the one way a
    /// window can be permanently stranded in a corner. Its last known real frame is kept here
    /// purely so the termination restore can put it back.
    private var stranded: [WindowRef: CGRect] = [:]
    private var parked: Set<WindowRef> = []
    private var bundleIDs: [WindowRef: String] = [:]
    /// Where each app's windows belong: bundle id → workspace id. Seeded from the state file at
    /// boot so a relaunch puts windows back, then kept current by every reconcile, so an app that
    /// is quit and reopened mid-session also comes back to where the user last had it.
    private var placements: [String: UUID]
    private var intents = IntentSet()
    /// Spec §11 as amended 2026-09-15: retirement lasts only "until it changes", so a retired
    /// window's last known state is kept to recognise the change that brings it back (#36).
    /// `wentAway`: seen on another Space since retirement — coming back is a change too (#55).
    private struct Retired { var frame: CGRect; var fullscreen: Bool; var wentAway = false }
    private var retired: [WindowRef: Retired] = [:]
    /// The frame each window had in the last *snapshot* — reality, unlike `observed`, which holds the
    /// frame we asked for and which a failed write never delivered. "Changed" is judged against this,
    /// or a retired window would look changed on the very next snapshot and we would fight it forever.
    private var lastSeen: [WindowRef: CGRect] = [:]
    private var failures: [WindowRef: Int] = [:]
    private var lastRaised: WindowRef?
    /// Raises whose echoes have not arrived yet, oldest first — one queue per echo stream, since
    /// every raise is reported twice, as a focus change and as an app activation (#69).
    ///
    /// Fast switching raises X then Y before macOS reports X. With only `lastRaised` to go on,
    /// X's late echo read as a human choosing X, surfaced it, and that raise echoed late in turn —
    /// two apps trading focus ~10×/s. So a report matching a queued raise is our own echo; and
    /// since macOS reports raises in order, it also retires every raise queued before it, whose
    /// echo has either landed or never will. A report matching nothing queued is a human.
    private var pendingFocusEchoes: [(ref: WindowRef, at: ContinuousClock.Instant)] = []
    private var pendingActivationEchoes: [(ref: WindowRef, at: ContinuousClock.Instant)] = []
    /// Backstop for echoes that never come (raising the app already in front activates nothing):
    /// past this, a report of that window is a human choice again, so #56 keeps surfacing it.
    private static let echoWindow = Duration.seconds(1)
    /// #28: a focus change this soon after a key press or a click is the human's doing and goes
    /// through untouched; later than this, while a fullscreen window is in front, it is a window
    /// grabbing focus by itself. Long enough for ⌘Tab or a Dock click to land as an activation,
    /// short enough that an app waking up a second later is not mistaken for the user.
    static let humanInputWindow = Duration.seconds(1)
    private var lastHumanInput: ContinuousClock.Instant?
    /// #28: focus requests held back behind a fullscreen window on a display with nowhere else to
    /// go, oldest first, each with the fullscreen window it was held behind. Drained by
    /// `drainDeferredFocus` once that window leaves fullscreen.
    private var deferredFocus: [(requester: WindowRef, behind: WindowRef)] = []
    /// The shell's own activations (a rename alert, Settings) come from a click on its own panels,
    /// which the global mouse monitor never sees. They are never intrusions.
    private let ownPid = ProcessInfo.processInfo.processIdentifier
    private let now: @Sendable () -> ContinuousClock.Instant
    /// #64: draws each switch as motion; nil (tests, headless) places instantly.
    private let animator: (any SwitchAnimator)?
    /// What each display's tiling showed at the end of the last reconcile — the "before" of the
    /// next switch.
    private var lastShown: [DisplayID: ShownRow] = [:]
    /// What the last snapshot said macOS had focused. Focus that has not moved since is an echo,
    /// not news — see `applyNativeFocus`. Same idea as `intents`, which does this for frames.
    private var lastNativeFocus: WindowRef?
    private var locked = false
    /// Bumped by every `reconcile()`; an in-flight pass abandons itself once a newer pass has started.
    /// Only a *newer reconcile* invalidates a plan — early-return event paths (intent echoes, locked,
    /// floating/unknown moves) must not abort a multi-write plan that is already in flight.
    private var generation = 0
    private var eventTask: Task<Void, Never>?
    private var started = false
    /// See `applySnapshot`: the boot reservations are retired after the first snapshot.
    private var reservationsExpired = false
    /// #13, the crowd rule's "at launch": the first snapshot, plus any app whose windows are first
    /// seen within this long of `start()` — login items and macOS's "reopen windows" trickle in
    /// after the shell is up, and they are exactly the apps that arrive with dozens of windows.
    /// After it, nothing is swept up: an app opened mid-session lands by the ordinary rules.
    static let launchWindow = Duration.seconds(10)
    private var startedAt: ContinuousClock.Instant?
    /// Bundle ids that have shown a window this session. The crowd rule looks only at an app's
    /// first appearance, so later windows of an app are never swept into a workspace of their own.
    private var seenApps: Set<String> = []

    public init(backend: any WindowBackend, config: Config, world: World?, zeroSliverBundleIDs: Set<String>,
                placements: [String: UUID] = [:],
                now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
                animator: (any SwitchAnimator)? = nil,
                onChange: @escaping @Sendable (World) -> Void) {
        self.now = now
        self.animator = animator
        self.backend = backend; self.config = config; self.zeroSliverBundleIDs = zeroSliverBundleIDs; self.onChange = onChange
        self.placements = placements
        self.world = world ?? World.seeded(screens: [], config: config)
    }

    public func start() async {
        guard !started else { return }; started = true
        startedAt = now()
        await apply(.snapshot(await backend.currentSnapshot()))
        // #52: the previous run may have ended without its §7.4 restore — a crash, an OOM kill, a
        // force quit, or (until #30) an ordinary SIGTERM. Whatever it parked is still in a corner,
        // and nothing else will move it: the reconciler leaves floating, ephemeral and ignored
        // windows alone by design. Sweep once, at the only moment we know reality predates us.
        await rescueBeyondReach(reason: "boot")
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await e in self.backend.events { await self.apply(e) }
        }
    }
    public func stop() { eventTask?.cancel() }

    /// Spec §7.4. Everything the termination path needs to put windows back where a human can
    /// reach them: the model, the topology it was laid out against, and the last frames the
    /// backend actually observed (parked windows included — `observed` keeps their real size),
    /// plus the windows that were retired while parked and can no longer be reached any other way.
    ///
    /// `parked` is what the restore actually acts on. §7.4 is about not stranding windows in a
    /// parking corner, and only parked windows are in one — a tiled window is already somewhere
    /// the user can reach, and centring it on the way out just scrambles their screen.
    public func exportForTermination() -> (world: World, displays: [DisplayInfo], observed: [WindowRef: CGRect], stranded: [WindowRef: CGRect], parked: Set<WindowRef>, placements: [String: UUID]) {
        (world, displays, observed, stranded, parked, placements)
    }
    /// The placement memory to persist — see `PersistedState.placements`.
    public func currentPlacements() -> [String: UUID] { placements }
    /// `spacialctl state`, with the side tables the model itself does not carry (#57): which app a
    /// window belongs to, whether the shell has it parked, and the last frame it observed.
    public func wireState() -> WireState {
        WireState(world: world, bundleIDs: bundleIDs, parked: parked, observed: observed)
    }
    public func update(config: Config) async { self.config = config; await reconcile() }

    public func run(_ command: Command) async {
        guard !locked else { return }   // spec §7.7: no writes and no model changes while locked
        let before = world.focus
        let (next, effects) = CommandRunner.apply(command, to: world)
        world = next
        Self.log.notice("command \(String(describing: command), privacy: .public) screen=\(String(before.screen.prefix(8)), privacy: .public)->\(String(self.world.focus.screen.prefix(8)), privacy: .public) focus=\(before.window?.id ?? 0, privacy: .public)->\(self.world.focus.window?.id ?? 0, privacy: .public)")
        for e in effects {
            switch e {
            case .close(let r): _ = await backend.close(r)
            case .exitFullscreen(let r):
                Self.log.notice("exit fullscreen \(r.id, privacy: .public) \(self.bundleIDs[r] ?? "-", privacy: .public) before workspace switch")
                _ = await backend.setFullscreen(r, false)
            // #48: the model already calls it visible, so make that true before the reconciler
            // places it — otherwise the frame lands on a window macOS still has put away.
            case .unhide(let r): _ = await backend.unhide(r)
            case .focus, .relayout: break
            }
        }
        await reconcile()
        if case .rescueWindows = command { await rescueBeyondReach(reason: "command") }
    }

    public func apply(_ event: BackendEvent) async {
        switch event {
        case .snapshot(let s):
            if locked { return }
            applySnapshot(s)
        case .windowMoved(let r, let f), .windowResized(let r, let f):
            if intents.matches(r, frame: f) { observed[r] = f; return }
            let was = observed[r]
            observed[r] = f
            if locked { return }
            if case .windowMoved = event, rehomeDragged(r, to: f, was: was) { break }
            if let ws = world.workspace(containing: r), !ws.floating.contains(r) { /* tiled: snap back */ } else { return }
        case .focusChanged(let r):
            if locked { return }
            applyNativeFocus(r)
        case .appActivated(let pid):
            if locked { return }
            // Raising a window activates its app, and macOS reports that back as an activation
            // like any other. Acting on it would raise again, and again. Nothing is lost by
            // ignoring it: the app we just raised is the one already on screen.
            if consumeEcho(&pendingActivationEchoes, { $0.pid == pid }) || pid == lastRaised?.pid { return }
            // The fullscreen window's own app activating is no Space switch, and the check below
            // already finds it on screen; only another app can pull the user out.
            if let fs = fullscreenInFront, fs.pid != pid, pid != ownPid, !humanRecently {
                interceptFocus(by: candidateWindow(ofPid: pid), behind: fs)
            } else {
                surfaceActivatedApp(pid)
            }
        case .humanInput:
            lastHumanInput = now(); return
        case .screenLocked:
            // Spec §7.7 freeze. Setting the flag only stops the *next* pass from starting; a plan
            // already mid-flight would keep writing frames at a locked screen, and its writes land
            // against whatever the lock screen reports. Bumping the generation is the same signal
            // a newer reconcile sends, and every await in `reconcile()` checks it.
            locked = true; generation += 1; return
        case .screenUnlocked:
            locked = false
            applySnapshot(await backend.currentSnapshot())
        }
        drainDeferredFocus()
        await reconcile()
    }

    // MARK: snapshot → world

    private func applySnapshot(_ s: Snapshot) {
        // An empty display topology is always transient (wake, hot-plug, the lock screen). The
        // backend guards its own snapshots, but a snapshot reaches the store from more than one
        // door, and applying one would reseed the world from nothing: every workspace dropped,
        // every window re-adopted onto a screen that does not exist. Drop it instead.
        guard !s.displays.isEmpty else { return }
        // displays
        let sorted = s.displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        displays = sorted
        let main = sorted.first(where: \.isMain)?.id ?? sorted.first?.id ?? ""
        if world.screens.isEmpty && !sorted.isEmpty {
            world = World.seeded(screens: sorted.map(\.id), config: config)
        } else {
            world.setScreens(sorted.map(\.id), main: main)
        }
        let hiddenApps = Set(s.apps.filter(\.isHidden).map(\.pid))
        let crowds = crowdedApps(s)
        var present: Set<WindowRef> = []
        for w in s.windows {
            present.insert(w.ref)
            defer { lastSeen[w.ref] = w.frame }
            observed[w.ref] = w.frame
            bundleIDs[w.ref] = w.bundleID
            // Spec §11 "until it changes": a retired window that has moved, resized or changed
            // fullscreen state is alive and ours again — `ignored` is not a one-way door (#36). So
            // is one back on the active Space after time away: its frame never changed (#55).
            if !w.onActiveSpace, world.ignored.contains(w.ref) { retired[w.ref]?.wentAway = true }
            if world.ignored.contains(w.ref), let was = retired[w.ref],
               !Reconciler.approx(was.frame, w.frame) || was.fullscreen != w.isFullscreen
                || (was.wentAway && w.onActiveSpace) {
                revive(w.ref, frame: w.frame, reason: "changed")
            }
            let known = world.location(of: w.ref) != nil || world.ephemeral.contains(w.ref) || world.ignored.contains(w.ref)
            if !known {
                let kind = config.kindOverride(bundleID: w.bundleID, title: w.title) ?? w.kind
                // #13's ladder: the app's remembered workspace if it still exists, else a workspace
                // of its own for a crowd arriving at launch, else nil — `adopt`'s ordinary rules.
                // The crowd's new workspace becomes the app's placement, so its other windows
                // follow it there by rung 1.
                let landing = world.landing(remembered: w.bundleID.flatMap { placements[$0] },
                                            crowdOn: w.bundleID.flatMap { crowds[$0] })
                if let b = w.bundleID, let landing { placements[b] = landing }
                world.adopt(w.ref, kind: kind, on: screenFor(w.frame), parent: w.parent, workspace: landing)
                Self.log.notice("adopt \(w.ref.id, privacy: .public) pid=\(w.ref.pid) \(w.bundleID ?? "-", privacy: .public) kind=\(kind.rawValue, privacy: .public) fullscreen=\(w.isFullscreen) placed=\(self.world.location(of: w.ref) != nil)")
                if kind == .ephemeral { centerEphemeral(w.ref, size: w.frame.size) }
            }
            let nowHidden = w.isMinimized || hiddenApps.contains(w.ref.pid)
            rehomeIfMacOSOwnsFrame(w, hidden: nowHidden)
            if nowHidden != world.hidden.contains(w.ref), world.location(of: w.ref) != nil {
                Self.log.notice("hidden \(nowHidden ? "on" : "off", privacy: .public) \(w.ref.id, privacy: .public) \(w.bundleID ?? "-", privacy: .public) minimized=\(w.isMinimized) appHidden=\(hiddenApps.contains(w.ref.pid))")
            }
            world.setHidden(w.ref, nowHidden)
            if w.isFullscreen != world.fullscreen.contains(w.ref), world.location(of: w.ref) != nil {
                Self.log.notice("fullscreen \(w.isFullscreen ? "enter" : "exit", privacy: .public) \(w.ref.id, privacy: .public) \(w.bundleID ?? "-", privacy: .public)")
            }
            world.setFullscreen(w.ref, w.isFullscreen)
            if w.onActiveSpace == world.offSpace.contains(w.ref), world.location(of: w.ref) != nil {
                Self.log.notice("space \(w.onActiveSpace ? "back" : "away", privacy: .public) \(w.ref.id, privacy: .public) \(w.bundleID ?? "-", privacy: .public)")
            }
            world.setOnActiveSpace(w.ref, w.onActiveSpace)
        }
        if !s.loginwindowFrontmost {
            let all = Set(world.screens.values.flatMap { $0.workspaces.flatMap(\.windows) }).union(world.ephemeral).union(world.ignored)
            for gone in all.subtracting(present) {
                Self.log.notice("vanished \(gone.id, privacy: .public) pid=\(gone.pid) \(self.bundleIDs[gone] ?? "-", privacy: .public) wasIgnored=\(self.world.ignored.contains(gone))")
                world.remove(gone); observed[gone] = nil; prePark[gone] = nil; parked.remove(gone); bundleIDs[gone] = nil; intents.forget(gone)
                retired[gone] = nil; lastSeen[gone] = nil
                stranded[gone] = nil
                failures[gone] = nil; if lastRaised == gone { lastRaised = nil }; if lastNativeFocus == gone { lastNativeFocus = nil }
            }
        }
        // Reservations only have to survive the gap between `PersistedState.restore` and the first
        // snapshot: restore holds a workspace open for each remembered placement so its window can
        // land back in it. By here every window that is actually running has been adopted, so a
        // reserved workspace still empty belongs to an app that did not come back — and holding it
        // open any longer leaves a dead row in the middle of the rail forever. One shot: a later
        // snapshot must not re-reap a workspace the user has deliberately emptied and is about to
        // fill, which `normalize()` already protects by never reaping the active row.
        if !reservationsExpired {
            reservationsExpired = true
            world.clearReservations()
        }
        applyNativeFocus(s.focused)
    }

    /// #13 rung 2: bundle id → display, for each app making its first appearance at launch with
    /// more than `crowdThreshold` new tileable windows. The display is the one most of them are on.
    /// ponytail: counts only the windows in the app's first snapshot; an app whose windows arrive
    /// across several snapshots is judged on the first batch. Upgrade path: count per app over the
    /// launch window before adopting.
    private func crowdedApps(_ s: Snapshot) -> [String: DisplayID] {
        defer { seenApps.formUnion(s.windows.compactMap(\.bundleID)) }
        guard !reservationsExpired || startedAt.map({ now() - $0 < Self.launchWindow }) == true else { return [:] }
        var displaysByApp: [String: [DisplayID]] = [:]
        for w in s.windows {
            guard let b = w.bundleID, !seenApps.contains(b), world.location(of: w.ref) == nil,
                  !world.ephemeral.contains(w.ref), !world.ignored.contains(w.ref) else { continue }
            let kind = config.kindOverride(bundleID: b, title: w.title) ?? w.kind
            if kind == .tile || kind == .float { displaysByApp[b, default: []].append(screenFor(w.frame)) }
        }
        return displaysByApp.filter { $0.value.count > config.crowdThreshold }.mapValues { ds in
            world.screenOrder.max { a, b in ds.filter { $0 == a }.count < ds.filter { $0 == b }.count } ?? ds[0]
        }
    }

    /// I6's corollary — *switching to an app always shows a window* (#56, and the cause of #57).
    ///
    /// `focusChanged` only ever names a window. An app whose windows are all parked in an inactive
    /// workspace becomes frontmost with **no focused window**, so the store heard nothing: macOS
    /// named the app in the menu bar, its tab highlighted, and the window stayed off-screen at a
    /// parking corner. Measured live: activating Finder produced no store event at all, and the
    /// model was byte-identical before and after.
    ///
    /// So an activation surfaces a window of that app itself. The workspace's anchor wins where
    /// there is one — it is the window the user last used there — and the reconcile that follows
    /// unparks it.
    /// True when a report is the echo of a queued raise; retires that raise and every older one.
    private func consumeEcho(_ queue: inout [(ref: WindowRef, at: ContinuousClock.Instant)],
                             _ matches: (WindowRef) -> Bool) -> Bool {
        let t = now()
        queue.removeAll { t - $0.at >= Self.echoWindow }
        guard let i = queue.firstIndex(where: { matches($0.ref) }) else { return false }
        queue.removeFirst(i + 1)
        return true
    }

    private func surfaceActivatedApp(_ pid: Int32) {
        // Already showing a window of this app: nothing to surface. The test is per display, not
        // "does this app own the single global focus" — with more than one screen two apps are on
        // screen at once, one per screen, and a focus test answers no for the app on the *other*
        // display. Surfacing it then switches that display's workspace for nothing, and the switch
        // activates the app we just left, which surfaces it right back: the two displays trade
        // workspaces forever.
        if world.screens.values.contains(where: { world.visible(in: $0.active).contains { $0.pid == pid } }) { return }
        guard let target = candidateWindow(ofPid: pid), let loc = world.location(of: target) else { return }
        Self.log.notice("surface \(target.id, privacy: .public) pid=\(pid) \(self.bundleIDs[target] ?? "-", privacy: .public) after app activation")
        world.focus.screen = loc.screen
        if world.screens[loc.screen]?.activeIndex != loc.index { world.activate(index: loc.index, on: loc.screen) }
        world.focus.window = target
        world.screens[loc.screen]!.workspaces[loc.index].anchor = target
        world.normalize()
    }

    /// The window to show for an app: its workspace's anchor if that belongs to the app, else the
    /// first of its windows the model can actually put on screen.
    private func candidateWindow(ofPid pid: Int32) -> WindowRef? {
        let mine = world.screenOrder
            .flatMap { world.screens[$0]!.workspaces.flatMap(\.windows) }
            .filter { $0.pid == pid && !world.hidden.contains($0) }
        guard !mine.isEmpty else { return nil }
        for w in mine {
            guard let loc = world.location(of: w) else { continue }
            if world.screens[loc.screen]!.workspaces[loc.index].anchor == w { return w }
        }
        return mine.first
    }

    private func applyNativeFocus(_ r: WindowRef?) {
        guard let r else { return }
        // The focused-window invariant (#36): a window macOS reports as focused is by definition
        // managed, so a retired one comes back rather than sitting "just under everything".
        if world.ignored.contains(r), retired[r] != nil {
            revive(r, frame: observed[r] ?? retired[r]!.frame, reason: "focused")
        }
        let ownEcho = consumeEcho(&pendingFocusEchoes, { $0 == r })
        let isEcho = ownEcho || r == lastNativeFocus
        lastNativeFocus = r
        Self.log.notice("native focus \(r.id, privacy: .public) \(self.bundleIDs[r] ?? "-", privacy: .public) echo=\(isEcho) placed=\(self.world.location(of: r) != nil) hidden=\(self.world.hidden.contains(r)) ignored=\(self.world.ignored.contains(r)) focusScreen=\(String(self.world.focus.screen.prefix(8)), privacy: .public)")
        // #28. A repeated report of a requester already intercepted is *not* skipped as an echo:
        // it means macOS still has it in front, so the fullscreen window goes back again. Windows
        // the model does not manage (ignored, unknown) are left alone, exactly as below.
        if !ownEcho, let fs = fullscreenInFront, r != fs, r.pid != ownPid, !humanRecently,
           world.ephemeral.contains(r) || world.location(of: r) != nil {
            interceptFocus(by: r, behind: fs)
            return
        }
        // Our own raise of `r` reporting back after the model has already moved on (a quick Fn+D
        // after Fn+A) is history, not news — in *any* row. Only cross-row echoes were dropped
        // below, so a late echo inside the row pulled focus back a tab and the next echo pushed it
        // forward again: fast tab switching stuttered and restarted its slides (#67).
        if ownEcho && world.focus.window != r { return }
        if world.ephemeral.contains(r) { world.focus.window = r; return }
        guard let loc = world.location(of: r), !world.hidden.contains(r) else { return }
        // An unchanged native focus is news about nothing, and must never drag the active
        // workspace back to where it was. Activating an *empty* workspace (the rail's "+", or any
        // empty row) focuses nothing — there is nothing there to focus — so macOS legitimately
        // keeps the previous window focused, and the very click that activated it schedules a
        // refresh via the global mouse-up monitor. Honouring that echo bounced the user straight
        // back out of the workspace they had just opened.
        // …but a *fullscreen* window's echo is news, not noise (#49): macOS re-reports it as focused
        // for as long as its Space is front, and dropping those left the model with no focused
        // window at all, so the next workspace verb ran from a stale belief on a stale screen.
        if isEcho && !world.fullscreen.contains(r) && world.screens[loc.screen]!.activeIndex != loc.index { return }
        focus(r)
    }

    /// Model focus onto `r`: its workspace goes active and `r` becomes its anchor.
    private func focus(_ r: WindowRef) {
        if world.ephemeral.contains(r) { world.focus.window = r; return }
        guard let loc = world.location(of: r), !world.hidden.contains(r) else { return }
        if world.screens[loc.screen]!.activeIndex != loc.index { world.activate(index: loc.index, on: loc.screen) }
        world.focus = Focus(screen: loc.screen, window: r)
        world.screens[loc.screen]!.workspaces[loc.index].anchor = r
        world.normalize()
    }

    // MARK: fullscreen focus protection (#28)

    private var humanRecently: Bool {
        guard let t = lastHumanInput else { return false }
        return now() - t < Self.humanInputWindow
    }

    /// The fullscreen window the user is in, if any — the model's answer to "is this display
    /// showing a fullscreen Space?".
    ///
    /// `AXFullScreen` cannot answer it: a window keeps reporting fullscreen after the user switches
    /// away from its Space. The model's focus can. It follows every native focus report, so the
    /// moment the user goes anywhere else — another Space, window or display — it stops naming the
    /// fullscreen window; while it still does, that window is what macOS last put in front (or
    /// what we just raised back there). So: the focused window, if the model has it fullscreen.
    private var fullscreenInFront: WindowRef? {
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
    private func showsFullscreen(_ d: DisplayID) -> Bool {
        guard let a = world.screens[d]?.active.anchor else { return false }
        return world.fullscreen.contains(a)
    }

    /// `requester` asked for focus with no human behind it while `fs` is in front (#28). Send it to
    /// a display that is not showing a fullscreen Space — into that display's active workspace,
    /// where a new window would land — preferring the display it is already on; with none, hold
    /// the request until `fs` leaves fullscreen. Either way `fs` goes back in front: macOS has no
    /// veto for a window manager, so protection can only be this reactive put-back.
    ///
    /// ponytail: an app that re-activates itself every time it loses focus will trade places with
    /// `fs` for as long as it keeps trying. Upgrade path: give up on a requester after N rounds.
    private func interceptFocus(by requester: WindowRef?, behind fs: WindowRef) {
        guard let fsScreen = world.screenContaining(fs) else { return }
        if let r = requester {
            let free = world.screenOrder.filter { $0 != fsScreen && !showsFullscreen($0) }
            let own = world.screenContaining(r)
            // ponytail: an ephemeral window has no workspace to land in, so it is deferred even
            // when a display is free. Upgrade path: centre it on the free display instead.
            if own != nil, let dest = free.first(where: { $0 == own }) ?? free.first,
               let target = world.screens[dest]?.active.id {
                world = CommandRunner.apply(.moveWindowRefToWorkspace(r, target), to: world).0
                Self.log.notice("fullscreen guard: moved \(r.id, privacy: .public) \(self.bundleIDs[r] ?? "-", privacy: .public) to \(String(dest.prefix(8)), privacy: .public)")
            } else {
                deferredFocus.removeAll { $0.requester == r }
                deferredFocus.append((r, fs))
                Self.log.notice("fullscreen guard: deferred \(r.id, privacy: .public) \(self.bundleIDs[r] ?? "-", privacy: .public) behind \(fs.id, privacy: .public)")
            }
        }
        world.focus = Focus(screen: fsScreen, window: fs)
        world.normalize()
        // Raise it even if it was the last window we raised: macOS has raised the requester since.
        lastRaised = nil
    }

    /// Hands out held-back focus (#28). Requests held behind a window that has left fullscreen, or
    /// gone away, are settled at once: the newest whose window still exists gets the focus — but
    /// only if the user is still on the window fullscreen ended in. One who has already gone
    /// somewhere else has moved on, and the request is dropped; its window keeps its tab.
    private func drainDeferredFocus() {
        let ended = deferredFocus.filter { !world.fullscreen.contains($0.behind) }
        guard !ended.isEmpty else { return }
        deferredFocus.removeAll { !world.fullscreen.contains($0.behind) }
        guard let next = ended.last(where: { world.location(of: $0.requester) != nil || world.ephemeral.contains($0.requester) }),
              world.focus.window == next.behind || world.location(of: next.behind) == nil else { return }
        Self.log.notice("fullscreen guard: fullscreen ended, focusing deferred \(next.requester.id, privacy: .public)")
        focus(next.requester)
    }

    /// #57: a window the user drags onto another display moves there in the model — into that
    /// display's active workspace, focused, exactly as a tab dropped on its rail would — so the tab
    /// follows the window instead of the window being snapped back. Every other disagreement about
    /// which display a window is on (placement memory, an app moving its own window) is left to the
    /// reconciler, which puts the window where its tab is: the model wins.
    ///
    /// "The user dragged it" is judged from what the store has: human input within
    /// `humanInputWindow` (the platform reports mouse-drags as input, so a long drag stays fresh),
    /// a frame whose size did not change (a drag never resizes; macOS clamping one of our own
    /// writes to a minimum size does), and a window that was on screen to be dragged — tiled or
    /// floating in its display's active workspace, not parked, hidden or fullscreen. The display is
    /// the one under the frame's centre.
    /// ponytail: input-within-a-second, not a true drag signal — an app moving its own window just
    /// after a key press would be rehomed too. Upgrade path: a mouse-up event carrying the drag.
    private func rehomeDragged(_ r: WindowRef, to f: CGRect, was: CGRect?) -> Bool {
        guard humanRecently, let was, abs(was.width - f.width) < 1, abs(was.height - f.height) < 1,
              !parked.contains(r), !world.hidden.contains(r), !world.fullscreen.contains(r),
              let loc = world.location(of: r), world.screens[loc.screen]!.activeIndex == loc.index,
              let dest = displays.first(where: { $0.frame.contains(CGPoint(x: f.midX, y: f.midY)) })?.id,
              dest != loc.screen, let target = world.screens[dest]?.active.id else { return false }
        world = CommandRunner.apply(.moveWindowRefToWorkspace(r, target), to: world).0
        Self.log.notice("dragged \(r.id, privacy: .public) \(self.bundleIDs[r] ?? "-", privacy: .public) to \(String(dest.prefix(8)), privacy: .public)")
        return true
    }

    /// Puts a retired window back in the model (spec §11 "until it changes"). The app's remembered
    /// workspace still applies, exactly as at first adoption.
    private func revive(_ r: WindowRef, frame: CGRect, reason: StaticString) {
        guard retired[r] != nil else { return }
        retired[r] = nil
        world.ignored.remove(r)
        failures[r] = nil
        let bundle = bundleIDs[r]
        let kind = config.kindOverride(bundleID: bundle, title: "") ?? .tile
        world.adopt(r, kind: kind, on: screenFor(frame), workspace: bundle.flatMap { placements[$0] })
        Self.log.notice("revive \(r.id, privacy: .public) pid=\(r.pid) \(bundle ?? "-", privacy: .public) \(reason, privacy: .public)")
    }

    /// Which display a window belongs to is decided by whoever owns its frame (#72, #57).
    ///
    /// The shell owns a *tiled* window's frame: the model wins and the reconciler moves the window
    /// to its tab. macOS owns a *fullscreen* window's frame (it picks the display and the Space),
    /// and nothing moves a *floating* window — so for those the display under the frame is the
    /// truth and the model follows it, into that display's active workspace. Otherwise the tab sits
    /// on one display with its window on another, and everything that asks "which display is this
    /// on?" — the fullscreen panel check, the #28 guard, a tab click — answers wrong. Parked and
    /// hidden windows are skipped: a parking corner or a minimized window's frame says nothing —
    /// except a fullscreen one's, which is macOS's word even if we parked it before it went fullscreen.
    private func rehomeIfMacOSOwnsFrame(_ w: WindowSnapshot, hidden: Bool) {
        guard !hidden, let loc = world.location(of: w.ref) else { return }
        let floating = world.screens[loc.screen]!.workspaces[loc.index].floating.contains(w.ref)
        // A fullscreen window's frame is always macOS's word, even one we once parked (a window in
        // an inactive row that went fullscreen); a parked floating window's frame is our corner.
        guard w.isFullscreen || (floating && !parked.contains(w.ref)),
              let d = displayUnder(w.frame), d != loc.screen, world.screens[d] != nil else { return }
        let focused = world.focus.window == w.ref
        world.remove(w.ref)
        world.adopt(w.ref, kind: floating ? .float : .tile, on: d)
        if focused { world.focus = Focus(screen: d, window: w.ref) }
        world.normalize()
        Self.log.notice("rehome \(w.ref.id, privacy: .public) \(w.bundleID ?? "-", privacy: .public) to \(String(d.prefix(8)), privacy: .public): macOS owns its frame (\(w.isFullscreen ? "fullscreen" : "floating", privacy: .public))")
    }

    /// The display holding most of `frame`, or nil when it is on none.
    private func displayUnder(_ frame: CGRect) -> DisplayID? {
        displays.map { d -> (DisplayID, CGFloat) in
            let a = d.frame.intersection(frame); return (d.id, a.isNull ? 0 : a.width * a.height)
        }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }

    private func screenFor(_ frame: CGRect) -> DisplayID {
        var best: (DisplayID, CGFloat)? = nil
        for d in displays {
            let a = d.frame.intersection(frame); let area = a.isNull ? 0 : a.width * a.height
            if best == nil || area > best!.1 { best = (d.id, area) }
        }
        return best?.0 ?? world.focus.screen
    }

    private var pendingCenter: [(WindowRef, CGSize)] = []
    private func centerEphemeral(_ r: WindowRef, size: CGSize) { pendingCenter.append((r, size)) }

    // MARK: reconcile

    private func reconcile() async {
        // Placement memory follows the model: whatever the last command or snapshot did, the
        // windows on screen now define where their apps belong.
        placements.merge(PersistedState.placements(world: world, bundleIDs: bundleIDs)) { _, live in live }
        generation += 1
        let gen = generation
        let zero = Set(bundleIDs.filter { zeroSliverBundleIDs.contains($0.value) }.map(\.key))
        // Zen and `show-panels` decide whether the panels' edges belong to the layout (M2 design
        // §Decisions: `ShellInsets(config:hidden:)` computed purely in Kit; same insets on every
        // screen — each screen carries both panels).
        let shellInsets = ShellInsets(config: config, hidden: world.zen)
        let insets = Dictionary(uniqueKeysWithValues: world.screenOrder.map { ($0, shellInsets) })
        let desired = Reconciler.desired(world: world, displays: displays, config: LayoutConfig(gap: config.gap),
                                         observed: observed, prePark: prePark, parkedNow: parked, zeroSliver: zero,
                                         insets: insets)
        // #64: a switch is motion. The overlay goes up *before* the first write, so the real windows
        // jump to their final frames underneath it; `play` then slides the proxies after them.
        let shownNow = shownRows(desired: desired, insets: insets)
        let transitions = self.transitions(to: shownNow, insets: insets)
        // Recorded *before* the first await: an event that lands while the overlay is being
        // prepared (the echo of this very raise) re-enters and reconciles again, and compared to
        // the old rows it would plan this same switch a second time and cancel the first mid-flight.
        lastShown = shownNow
        var animating = false
        // Once the overlay is up, every way out of this pass plays it — including the early
        // returns when a newer pass supersedes this one mid-write (the echo of our own raise does,
        // routinely). That pass compares against the `lastShown` recorded above, plans no motion,
        // and would never play this one: the pictures sat frozen until the watchdog cut them (#66).
        defer { if animating, let animator { Task { await animator.play() } } }
        if let animator, config.animations {
            if !transitions.isEmpty {
                animating = await animator.prepare(transitions)
                if gen != generation { return }      // superseded: the deferred play still lands it
            }
        }
        // Drained *before* the loop, not after it: every iteration awaits, and a `return` from any
        // of them (superseded mid-write) used to leave the queue full, so the next pass centred the
        // same windows again — dragging an ephemeral window back to the middle of the screen long
        // after it appeared there.
        let toCenter = pendingCenter
        pendingCenter = []
        for (r, size) in toCenter {
            let d = displays.first { $0.id == world.focus.screen } ?? displays.first
            guard let d else { continue }
            let f = Reconciler.centered(size: size, in: d.visibleFrame)
            intents.record(.setFrame(r, f))
            let result = await backend.setFrame(r, f)
            if gen != generation { return }          // superseded mid-write: side tables belong to the newer pass
            observed[r] = f
            note(result, for: r)
        }
        for w in Reconciler.plan(desired: desired, observed: observed, parkedNow: parked) {
            intents.record(w)
            switch w {
            case .setFrame(let r, let f):
                let result = await backend.setFrame(r, f)
                if gen != generation { return }
                observed[r] = f; parked.remove(r); prePark[r] = nil
                note(result, for: r)
            case .setPosition(let r, let o):
                let pre = parked.contains(r) ? nil : observed[r]
                let result = await backend.setPosition(r, o)
                if gen != generation { return }
                if let pre { prePark[r] = pre }
                if let cur = observed[r] { observed[r] = CGRect(origin: o, size: cur.size) }
                parked.insert(r)
                note(result, for: r)
            }
        }
        if let f = world.focus.window, f != lastRaised {
            lastRaised = f
            pendingFocusEchoes.append((f, now()))
            pendingActivationEchoes.append((f, now()))
            let result = await backend.raise(f)
            if gen != generation { return }
            // Spec §11 as amended: a failed raise never retires. Raising fails for transient reasons
            // — the window is in its own fullscreen Space, the app is mid-transition — and counting
            // it left live windows on screen with no tab (#36). Frame writes are the real signal.
            if case .failure(let e) = result {
                Self.log.notice("raise failed \(f.id, privacy: .public) \(String(describing: e), privacy: .public); not counted")
            }
        }
        if animating, let animator { animating = false; await animator.play() }
        onChange(world)
    }

    /// Each display's active row as `desired` is about to show it: the tiled windows that get a
    /// frame, in tab order, and which of them the row is focused on.
    private func shownRows(desired: [WindowRef: Placement], insets: [DisplayID: ShellInsets]) -> [DisplayID: ShownRow] {
        var out: [DisplayID: ShownRow] = [:]
        for sid in world.screenOrder {
            guard let screen = world.screens[sid] else { continue }
            let ws = screen.active
            let row = world.tiled(in: ws)
            var frames: [WindowRef: CGRect] = [:]
            for r in row { if case .frame(let f)? = desired[r] { frames[r] = f } }
            // A floating window is `.frame` when it comes back from parking, `.untouched` while it stays.
            for r in ws.floating where !world.hidden.contains(r) && !world.fullscreen.contains(r) && !world.offSpace.contains(r) {
                switch desired[r] {
                case .frame(let f)?: frames[r] = f
                case .untouched?: if let f = observed[r] { frames[r] = f }
                default: break
                }
            }
            out[sid] = ShownRow(workspace: ws.id, index: screen.activeIndex, order: screen.workspaces.map(\.id),
                                row: row, focused: ws.anchor, frames: frames)
        }
        return out
    }

    private func transitions(to shownNow: [DisplayID: ShownRow], insets: [DisplayID: ShellInsets]) -> [Transition] {
        world.screenOrder.compactMap { sid in
            guard let before = lastShown[sid], let after = shownNow[sid], let screen = world.screens[sid],
                  let display = displays.first(where: { $0.id == sid }) else { return nil }
            let viewport = Reconciler.viewport(screen: screen, display: display, insets: insets[sid, default: .zero])
            let moves = Transition.moves(before: before, after: after, viewport: viewport, gap: config.gap)
            return moves.isEmpty ? nil : Transition(display: sid, viewport: viewport, moves: moves)
        }
    }

    /// Spec §13.3 / M3a A4 (#52). Put back every window that has ended up off every display.
    ///
    /// Only windows the reconciler would *not* move are touched: a window whose desired placement
    /// is `.frame` is about to be laid out anyway, and one whose placement is `.parked` is in a
    /// corner on purpose (its workspace is inactive, and the rail is how the user gets it back).
    /// That leaves exactly the windows nothing else looks after — floating, ephemeral, ignored, and
    /// anything stranded by a run that died before its restore — which is the set that strands.
    private func rescueBeyondReach(reason: StaticString) async {
        guard !locked, !displays.isEmpty else { return }
        let shellInsets = ShellInsets(config: config, hidden: world.zen)
        let insets = Dictionary(uniqueKeysWithValues: world.screenOrder.map { ($0, shellInsets) })
        let desired = Reconciler.desired(world: world, displays: displays, config: LayoutConfig(gap: config.gap),
                                         observed: observed, prePark: prePark, parkedNow: parked,
                                         zeroSliver: [], insets: insets)
        for (ref, frame) in observed.sorted(by: { $0.key.id < $1.key.id }) {
            guard Reconciler.isBeyondReach(frame, displays: displays) else { continue }
            // #55: never write to a window on another Space. ponytail: only placed windows carry the
            // flag, so an ignored or ephemeral one away on another Space can still be rescued.
            guard !world.offSpace.contains(ref) else { continue }
            switch desired[ref] {
            case .frame, .parked: continue          // the reconciler owns this one
            case .untouched, nil: break
            }
            let screen = world.screenContaining(ref) ?? world.focus.screen
            let display = displays.first { $0.id == screen } ?? displays[0]
            let rescued = Reconciler.centered(size: frame.size, in: display.visibleFrame)
            Self.log.notice("rescue \(ref.id, privacy: .public) \(self.bundleIDs[ref] ?? "-", privacy: .public) from \(String(describing: frame.origin), privacy: .public) (\(reason, privacy: .public))")
            intents.record(.setFrame(ref, rescued))
            let result = await backend.setFrame(ref, rescued)
            observed[ref] = rescued
            note(result, for: ref)
        }
    }

    /// Spec §11: three failed *writes* in a row retire the window to `ignored` so we stop fighting
    /// it — until it changes, when `revive` brings it back. Raises never reach here (see `reconcile`).
    private func note(_ result: Result<Void, BackendError>, for r: WindowRef) {
        switch result {
        case .success:
            failures[r] = nil
        case .failure:
            failures[r, default: 0] += 1
            guard failures[r, default: 0] >= 3 else { return }
            failures[r] = nil
            // macOS owns a fullscreen window and the shell writes nothing for it, so a failure
            // there says nothing about manageability (#36).
            guard !world.fullscreen.contains(r) else { return }
            // Remember where it belongs before the side tables that know are cleared.
            if parked.contains(r), let frame = prePark[r] ?? observed[r] { stranded[r] = frame }
            retired[r] = Retired(frame: lastSeen[r] ?? observed[r] ?? .zero, fullscreen: world.fullscreen.contains(r))
            Self.log.notice("retire \(r.id, privacy: .public) pid=\(r.pid) \(self.bundleIDs[r] ?? "-", privacy: .public) after 3 failed writes")
            world.remove(r); world.ignored.insert(r)
            observed[r] = nil; prePark[r] = nil; parked.remove(r); intents.forget(r)
            if lastRaised == r { lastRaised = nil }
        }
    }

    /// Test-only window onto the side tables that must never outlive their window.
    func debugSideTables() -> (parked: Set<WindowRef>, prePark: [WindowRef: CGRect], observed: [WindowRef: CGRect]) {
        (parked, prePark, observed)
    }
}
