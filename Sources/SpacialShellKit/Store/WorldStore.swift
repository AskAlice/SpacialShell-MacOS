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
    /// The frame the focused window is about to be tiled at (AX top-left coordinates), nil when
    /// focus is floating, hidden, fullscreen or nowhere. Published from `Reconciler.desired`
    /// *before* the AX write lands, so the focus ring arrives with the intent instead of trailing
    /// the window across the screen (M2 T20 / M3a A-list B6).
    private let onFocusedFrame: @Sendable (CGRect?) -> Void

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
    private struct Retired { var frame: CGRect; var fullscreen: Bool }
    private var retired: [WindowRef: Retired] = [:]
    /// The frame each window had in the last *snapshot* — reality, unlike `observed`, which holds the
    /// frame we asked for and which a failed write never delivered. "Changed" is judged against this,
    /// or a retired window would look changed on the very next snapshot and we would fight it forever.
    private var lastSeen: [WindowRef: CGRect] = [:]
    private var failures: [WindowRef: Int] = [:]
    private var lastRaised: WindowRef?
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

    public init(backend: any WindowBackend, config: Config, world: World?, zeroSliverBundleIDs: Set<String>,
                placements: [String: UUID] = [:],
                onFocusedFrame: @escaping @Sendable (CGRect?) -> Void = { _ in },
                onChange: @escaping @Sendable (World) -> Void) {
        self.backend = backend; self.config = config; self.zeroSliverBundleIDs = zeroSliverBundleIDs; self.onChange = onChange
        self.onFocusedFrame = onFocusedFrame
        self.placements = placements
        self.world = world ?? World.seeded(screens: [], config: config)
    }

    public func start() async {
        guard !started else { return }; started = true
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
            observed[r] = f
            if locked { return }
            if let ws = world.workspace(containing: r), !ws.floating.contains(r) { /* tiled: snap back */ } else { return }
        case .focusChanged(let r):
            if locked { return }
            applyNativeFocus(r)
        case .appActivated(let pid):
            if locked { return }
            // Raising a window activates its app, and macOS reports that back as an activation
            // like any other. Acting on it would raise again, and again. Nothing is lost by
            // ignoring it: the app we just raised is the one already on screen.
            if pid == lastRaised?.pid { return }
            surfaceActivatedApp(pid)
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
        var present: Set<WindowRef> = []
        for w in s.windows {
            present.insert(w.ref)
            defer { lastSeen[w.ref] = w.frame }
            observed[w.ref] = w.frame
            bundleIDs[w.ref] = w.bundleID
            // Spec §11 "until it changes": a retired window that has moved, resized or changed
            // fullscreen state is alive and ours again — `ignored` is not a one-way door (#36).
            if world.ignored.contains(w.ref), let was = retired[w.ref],
               !Reconciler.approx(was.frame, w.frame) || was.fullscreen != w.isFullscreen {
                revive(w.ref, frame: w.frame, reason: "changed")
            }
            let known = world.location(of: w.ref) != nil || world.ephemeral.contains(w.ref) || world.ignored.contains(w.ref)
            if !known {
                let kind = config.kindOverride(bundleID: w.bundleID, title: w.title) ?? w.kind
                // The app's remembered workspace, if it still exists — `adopt` falls back to the
                // active workspace when it does not, and never creates one.
                world.adopt(w.ref, kind: kind, on: screenFor(w.frame), parent: w.parent,
                            workspace: w.bundleID.flatMap { placements[$0] })
                Self.log.notice("adopt \(w.ref.id, privacy: .public) pid=\(w.ref.pid) \(w.bundleID ?? "-", privacy: .public) kind=\(kind.rawValue, privacy: .public) fullscreen=\(w.isFullscreen) placed=\(self.world.location(of: w.ref) != nil)")
                if kind == .ephemeral { centerEphemeral(w.ref, size: w.frame.size) }
            }
            let nowHidden = w.isMinimized || hiddenApps.contains(w.ref.pid)
            if nowHidden != world.hidden.contains(w.ref), world.location(of: w.ref) != nil {
                Self.log.notice("hidden \(nowHidden ? "on" : "off", privacy: .public) \(w.ref.id, privacy: .public) \(w.bundleID ?? "-", privacy: .public) minimized=\(w.isMinimized) appHidden=\(hiddenApps.contains(w.ref.pid))")
            }
            world.setHidden(w.ref, nowHidden)
            if w.isFullscreen != world.fullscreen.contains(w.ref), world.location(of: w.ref) != nil {
                Self.log.notice("fullscreen \(w.isFullscreen ? "enter" : "exit", privacy: .public) \(w.ref.id, privacy: .public) \(w.bundleID ?? "-", privacy: .public)")
            }
            world.setFullscreen(w.ref, w.isFullscreen)
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
        let isEcho = r == lastNativeFocus
        lastNativeFocus = r
        Self.log.notice("native focus \(r.id, privacy: .public) \(self.bundleIDs[r] ?? "-", privacy: .public) echo=\(isEcho) placed=\(self.world.location(of: r) != nil) hidden=\(self.world.hidden.contains(r)) ignored=\(self.world.ignored.contains(r)) focusScreen=\(String(self.world.focus.screen.prefix(8)), privacy: .public)")
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
        if world.screens[loc.screen]!.activeIndex != loc.index { world.activate(index: loc.index, on: loc.screen) }
        world.focus = Focus(screen: loc.screen, window: r)
        world.screens[loc.screen]!.workspaces[loc.index].anchor = r
        world.normalize()
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
            let result = await backend.raise(f)
            if gen != generation { return }
            // Spec §11 as amended: a failed raise never retires. Raising fails for transient reasons
            // — the window is in its own fullscreen Space, the app is mid-transition — and counting
            // it left live windows on screen with no tab (#36). Frame writes are the real signal.
            if case .failure(let e) = result {
                Self.log.notice("raise failed \(f.id, privacy: .public) \(String(describing: e), privacy: .public); not counted")
            }
        }
        // T20: the ring follows the *intent* — the frame the reconciler just decided on — rather
        // than chasing the window across the screen after AX delivers it. A focused window with no
        // tiled frame (floating, fullscreen, parked, hidden) has no ring, which is the honest
        // answer: there is nothing at a known place to draw around.
        if let f = world.focus.window, case .frame(let r)? = desired[f] { onFocusedFrame(r) } else { onFocusedFrame(nil) }
        onChange(world)
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
