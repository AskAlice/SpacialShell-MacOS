import Foundation
import OpenTelemetryApi
import os
import SpacialShellProtocol

public actor WorldStore {
    /// Model membership changes only (adopt, fullscreen, retire, vanish): rare, and the one trail that
    /// answers "where did that window go?" after the fact.
    private static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "store")
    public private(set) var world: World
    private let backend: any WindowBackend
    private var config: Config { didSet { layouts = LayoutCatalogue(config: config) } }
    /// #9: the layout ids' meaning, rebuilt whenever the config is — the one place every
    /// `Reconciler.desired` call and `commandEnvironment` here gets it from.
    private var layouts: LayoutCatalogue
    /// Unresolved layout ids already logged: once per id, not once per reconcile (design §8).
    private var loggedUnresolved: Set<LayoutID> = []
    private let zeroSliverBundleIDs: Set<String>
    /// M2 design "Store→UI/IPC feed": the world and its `ShellSnapshot`, in the same instant.
    /// Deduped — an unchanged world with an equivalent snapshot is not published again, so the 2 s
    /// backstop and a title that did not really change wake nobody (#110).
    private let onChange: @Sendable (World, ShellSnapshot) -> Void
    private var lastPublished: (world: World, snapshot: ShellSnapshot)?
    private var publishGeneration: UInt64 = 0

    private var displays: [DisplayInfo] = []
    /// #171: what every command run here reads besides the world, from the config, layouts and
    /// displays as they stand. Computed, so it cannot fall behind any of them; the one place a
    /// `CommandRunner.run` call here gets its environment from.
    private var commandEnvironment: CommandEnvironment {
        CommandEnvironment(config: config, layouts: layouts, displays: displays)
    }
    /// #174: what the store knows of each window beyond the model, one record per window, so a
    /// vanished window is forgotten in one place (`forget`) and a retired one in one other (`retire`).
    private var records = WindowRecords()
    /// #169: our writes, and what their echoes taught us — refusals (#125, #164) and unmovable
    /// sheets (#165). Every move or resize report is read here first.
    private var echoes = WindowEchoes()
    /// #110: `appName` by pid, replaced wholesale by each refresh's app list.
    private var appNames: [Int32: String] = [:]
    /// Where each app's windows belong: bundle id → workspace id. Seeded from the state file at
    /// boot so a relaunch puts windows back, then kept current by every reconcile, so an app that
    /// is quit and reopened mid-session also comes back to where the user last had it.
    private var placements: [String: UUID]
    /// #98: apps the user moved as a whole (Fn+Shift+Option+W/S, Option+drop). Their placement is
    /// an explicit choice, so it beats category routing (#74) for their new windows from then on.
    /// ponytail: nothing clears it yet; "reset placement" is meant to, and does not exist yet.
    private var movedApps: Set<String>
    /// #170: our raises, our commands' focus moves and the human's input, and what each focus or
    /// activation report means against them (#67, #69, #84, #28). Shares the store's clock.
    private var focusEchoes: FocusEchoes
    private let now: @Sendable () -> ContinuousClock.Instant
    /// #64: draws each switch as motion; nil (tests, headless) places instantly.
    private let animator: (any SwitchAnimator)?
    /// What each display's tiling showed at the end of the last reconcile — the "before" of the
    /// next switch.
    private var lastShown: [DisplayID: ShownRow] = [:]
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
    /// #148: nil means the global provider — a no-op until the app registers the SDK. Tests pass
    /// their own, so they never race each other over the global.
    private let tracerProvider: (any TracerProvider)?
    private var tracer: any Tracer { Telemetry.tracer(tracerProvider) }

    /// #108: where the left button is held down, from its `pointerDown` to its `pointerUp`.
    private var pointerDown: CGPoint?
    /// #108: the tiled window being dragged by its title bar, where on it the hand holds it, and
    /// the tile it would land on. The reconciler leaves it where the hand has it until the drop.
    private struct Drag { let ref: WindowRef; let grab: CGVector; var target: WindowRef? }
    private var drag: Drag?
    /// Every tile a drop can land on, as the last reconcile framed it (`DropTarget.tiles`). Not in
    /// `WindowRecord` (#174): rebuilt whole by every pass, so a vanished window is gone from the next.
    private var tiles: [WindowRef: CGRect] = [:]
    /// #108: the drop target's frame (top-left global) for the indicator panel; nil hides it.
    private let onDropTarget: @Sendable (CGRect?) -> Void

    /// #113: every shared edge between two tiles in an active row, as the last reconcile framed
    /// them — what a press can grab and what hovering highlights.
    private struct BorderRef { let display: DisplayID; let workspace: UUID; let key: String; let border: Resize.Border }
    private var borders: [BorderRef] = []
    /// #113: the border in the hand, from the press on it to the release — #162: or the focused
    /// tile's side edge under four fingers, from the axis lock to the lift. `latest` is where the
    /// hand has it now; `applied` where the row was last laid out for — moves arrive far faster
    /// than frames can be written, so a pump lays out only the newest (`pumpGrab`).
    private struct Grab {
        /// The line in the hand: which workspace, which page of it, which line on which axis.
        let workspace: UUID, key: String, axis: ResizeAxis, line: Int
        /// #162: where the line was when four fingers took it; nil for the pointer.
        let swipeStart: Double?
        /// #162: whether that line is the focused tile's trailing edge (right grows it) or its
        /// leading one (right shrinks it, so the travel is flipped: right always grows the tile).
        var swipeTrailing = true
        var latest: GrabTarget
        var applied: GrabTarget?
        /// Where the highlight is looked for along the line: the pointer, or the focused tile.
        var anchor: CGPoint?
        var bySwipe: Bool { swipeStart != nil }
    }
    /// Where the hand has the line: a pointer position, or (#162) a unit position on the axis.
    private enum GrabTarget: Equatable { case pointer(CGPoint), unit(Double) }
    private var grab: Grab?
    private var pump: Task<Void, Never>?
    private var hovered: CGRect?
    /// #113: the hovered or grabbed border's highlight (top-left global); nil hides it.
    private let onBorder: @Sendable (CGRect?) -> Void
    /// #135: what the pointer can focus, for focus-follows-mouse; sent on publish when it changed.
    private let onPointerTargets: @Sendable (PointerTargets) -> Void
    private var lastTargets: PointerTargets?
    /// #135: which window is over which, front to back, as far as the model can tell: the order
    /// focus landed on them (`PointerTargets.restack`). Kept on every publish, which drops windows
    /// the model no longer has; an order across windows, not a fact of one, so not in `WindowRecord`.
    private var stacking: [WindowRef] = []

    public init(backend: any WindowBackend, config: Config, world: World?, zeroSliverBundleIDs: Set<String>,
                placements: [String: UUID] = [:], movedApps: Set<String> = [],
                now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
                animator: (any SwitchAnimator)? = nil,
                tracerProvider: (any TracerProvider)? = nil,
                onDropTarget: @escaping @Sendable (CGRect?) -> Void = { _ in },
                onBorder: @escaping @Sendable (CGRect?) -> Void = { _ in },
                onPointerTargets: @escaping @Sendable (PointerTargets) -> Void = { _ in },
                onChange: @escaping @Sendable (World, ShellSnapshot) -> Void) {
        self.onDropTarget = onDropTarget
        self.onBorder = onBorder
        self.onPointerTargets = onPointerTargets
        self.now = now
        self.focusEchoes = FocusEchoes(now: now)
        self.tracerProvider = tracerProvider
        self.animator = animator
        self.layouts = LayoutCatalogue(config: config)
        self.backend = backend; self.config = config; self.zeroSliverBundleIDs = zeroSliverBundleIDs; self.onChange = onChange
        self.placements = placements
        self.movedApps = movedApps
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
    public func exportForTermination() -> (world: World, displays: [DisplayInfo], observed: [WindowRef: CGRect], stranded: [WindowRef: CGRect], parked: Set<WindowRef>, placements: [String: UUID], movedApps: Set<String>, bundleIDs: [WindowRef: String], titles: [WindowRef: String]) {
        (world, displays, records.observed, records.stranded, records.parked, placements, movedApps, records.bundleIDs, records.titles)
    }
    /// The placement memory to persist — see `PersistedState.placements`.
    public func currentPlacements() -> [String: UUID] { placements }
    /// #128: each live window's app and title — what `PersistedState` saves of a window so it can
    /// come back as a placeholder in its slot.
    public func currentWindowTables() -> (bundleIDs: [WindowRef: String], titles: [WindowRef: String]) { (records.bundleIDs, records.titles) }
    /// See `PersistedState.movedApps`.
    public func currentMovedApps() -> Set<String> { movedApps }
    /// `spacialctl state`, with the side tables the model itself does not carry (#57): which app a
    /// window belongs to, whether the shell has it parked, and the last frame it observed.
    public func wireState() -> WireState {
        WireState(world: world, bundleIDs: records.bundleIDs, parked: records.parked, observed: records.observed, layouts: layouts,
                  problems: ProblemCenter.shared.current)
    }
    public func update(config: Config) async { self.config = config; await reconcile() }

    /// #135: the pull side of `onPointerTargets`, for a watcher that starts after the first publish.
    public func pointerTargets() -> PointerTargets { lastTargets ?? .empty }

    /// The pull side of the feed: what the last publish would say now.
    public func shellSnapshot() -> ShellSnapshot { makeSnapshot(generation: publishGeneration) }

    private func makeSnapshot(generation: UInt64) -> ShellSnapshot {
        ShellSnapshot(world: world, generation: generation, displays: displays, config: config, layouts: layouts,
                      titles: records.titles, appNames: appNames, bundleIDs: records.bundleIDs, locked: locked)
    }

    private func publish() {
        // #135: frames can change with the world unchanged (a resize drag), so this has its own dedupe.
        stacking = PointerTargets.restack(stacking, focused: world.focus.window, world: world)
        let targets = PointerTargets(world: world, shown: lastShown, observed: records.observed, displays: displays, config: config,
                                     stacking: stacking)
        if targets != lastTargets { lastTargets = targets; onPointerTargets(targets) }
        let snapshot = makeSnapshot(generation: publishGeneration + 1)
        if let last = lastPublished, last.world == world, last.snapshot.isEquivalent(to: snapshot) { return }
        publishGeneration += 1
        lastPublished = (world, snapshot)
        onChange(world, snapshot)
    }

    /// A span that is a root when `parent` is nil — never a child of whatever happens to be active.
    private func startSpan(_ name: String, parent: (any Span)?) -> any Span {
        let b = tracer.spanBuilder(spanName: name)
        if let parent { b.setParent(parent) } else { b.setNoParent() }
        return b.startSpan()
    }

    /// #109: hotkeys ignore the report; `spacialctl run` prints it and exits 1 on a failure.
    @discardableResult
    public func run(_ command: Command) async -> CommandReport {
        guard !locked else { return .failed(.locked) }   // spec §7.7: no writes and no model changes while locked
        var command = command
        // #108, material-shell's M3: while a window is in the hand, Fn+W/S carries it to the row
        // above/below instead of leaving it behind.
        if let d = drag, case .focusWorkspace(let dir) = command, let loc = world.location(of: d.ref) {
            let rows = world.screens[loc.screen]!.workspaces
            let i = loc.index + (dir == .down ? 1 : -1)
            guard rows.indices.contains(i) else { return .noop("no workspace that way") }
            command = .moveWindowRefToWorkspace(d.ref, rows[i].id)
        }
        // #113: a resize key is measured against the real tiling rect, so it edits the page the
        // #54 floor actually shows; `CommandRunner` alone only knows the model's page.
        if case .resizeWindow(let axis, let grow) = command, let rect = tilingRect(world.focus.screen) {
            guard let (id, page, i) = world.resizePage(layouts: layouts, in: rect, gap: config.gap) else { return .noop("nothing to resize") }
            let (next, moved) = Resize.step(page, world.screens[world.focus.screen]?.active.portions[page.key],
                                            index: i, axis: axis, grow: grow)
            guard moved else { return .noop(Resize.stuck(page, index: i, axis: axis)) }
            command = .setPortions(id, key: page.key, next)
        }
        let issued = now()
        // #148: the root of a command's trace. The case name is the low-cardinality key; the detail
        // carries only ids and enum values — `Command` has no string payloads.
        let span = startSpan("command", parent: nil)
        defer { span.end() }
        let detail = String(describing: command)
        span.setAttribute(key: "command", value: String(detail.prefix { $0 != "(" }))
        span.setAttribute(key: "command.detail", value: detail)
        let before = world.focus
        let outcome = CommandRunner.run(command, on: world, in: commandEnvironment)
        // M2 ruling: a failed command changes nothing, so there is nothing to reconcile.
        if case .failed(let e) = outcome.report {
            Self.log.notice("command \(String(describing: command), privacy: .public) failed: \(e.description, privacy: .public)")
            return outcome.report
        }
        let (next, effects) = (outcome.world, outcome.effects)
        // #98: a whole-app move is an explicit placement for that app (see `movedApps`).
        let movedPid: Int32? = switch command {
        case .moveAppToWorkspace: before.window?.pid
        case .moveAppRefToWorkspace(let r, _): r.pid
        default: nil
        }
        if let movedPid, next != world, let bundle = records.bundleIDs.first(where: { $0.key.pid == movedPid })?.value {
            movedApps.insert(bundle)
        }
        world = next
        if let f = world.focus.window, f != before.window { focusEchoes.commanded(f) }
        Self.log.notice("command \(String(describing: command), privacy: .public) screen=\(String(before.screen.prefix(8)), privacy: .public)->\(String(self.world.focus.screen.prefix(8)), privacy: .public) focus=\(before.window?.id ?? 0, privacy: .public)->\(self.world.focus.window?.id ?? 0, privacy: .public)")
        for e in effects {
            switch e {
            case .close(let r): _ = await backend.close(r)
            case .exitFullscreen(let r):
                Self.log.notice("exit fullscreen \(r.id, privacy: .public) \(self.records[r].bundleID ?? "-", privacy: .public) before workspace switch")
                _ = await backend.setFullscreen(r, false)
            // #48: the model already calls it visible, so make that true before the reconciler
            // places it — otherwise the frame lands on a window macOS still has put away.
            case .unhide(let r): _ = await backend.unhide(r)
            case .launch(let bundle):
                Self.log.notice("launch \(bundle, privacy: .public) for a placeholder")
                _ = await backend.launch(bundleID: bundle)
            case .focus, .relayout: break
            }
        }
        await reconcile(parent: span, since: issued)
        // #107: after the reconcile, so the focused window's frame is the one it now has.
        if config.pointerWarp, world.focus.screen != before.screen,
           let p = PointerWarp.target(after: command, from: before.screen, world: world, frames: records.observed,
                                      displays: displays, pointer: await backend.pointerLocation()) {
            await backend.warpPointer(to: p)
        }
        switch command {
        case .rescueWindows, .recoverWindow: await rescueBeyondReach(reason: "command")   // #73: the tray's "off every display"
        default: break
        }
        return outcome.report
    }

    public func apply(_ event: BackendEvent) async {
        // #148: a snapshot is traced with the reconcile it causes as its child; every other event's
        // reconcile is a root of its own.
        var eventSpan: (any Span)?
        defer { eventSpan?.end() }
        switch event {
        case .snapshot(let s):
            if locked { return }
            // The backend sweeps only with the button up, so a drag still open here lost its
            // mouse-up (released over the shell's own panels, which the global monitor never
            // sees). It lands nowhere: the reconcile below snaps the window home. (A four-finger
            // drag has no button; it ends at its lift.)
            pointerDown = nil; endDrag(); if grab?.bySwipe == false { dropGrab() }
            eventSpan = tracedSnapshot(s)
        case .pointerDown(let p):
            pointerDown = p; focusEchoes.humanInput()
            if grab?.bySwipe == true { return }   // four fingers have the edge; the button waits
            // #113: a press on a shared edge grabs it, instead of anything else a press can start.
            if !locked, let b = borders.first(where: { $0.border.contains(p) }) {
                grab = Grab(workspace: b.workspace, key: b.key, axis: b.border.axis, line: b.border.line,
                            swipeStart: nil, latest: .pointer(p), applied: nil, anchor: p)
                show(b.border.indicator)
            } else { show(nil) }
            return
        case .pointerMoved(let p):
            if locked { return }
            if let g = grab {
                guard !g.bySwipe else { return }
                grab?.latest = .pointer(p); grab?.anchor = p
                if pump == nil { pump = Task { await self.pumpGrab() } }
            } else { show(pointerDown == nil ? borders.first { $0.border.contains(p) }?.border.indicator : nil) }
            return
        case .pointerUp(let p):
            pointerDown = nil
            if let g = grab, !g.bySwipe {
                // The release lands where it was let go: after the pump in flight, one more pass.
                grab?.latest = .pointer(p); grab?.anchor = p
                await settleGrab()
                show(borders.first { $0.border.contains(p) }?.border.indicator)
                return
            }
            guard let d = drag else { return }
            endDrag()
            if locked { return }
            if let command = drop(d.ref, at: p) { await run(command); return }
        case .windowMoved(let r, let f), .windowResized(let r, let f):
            // #169: `WindowEchoes` says what the report is; the store only acts on it.
            let was = records[r].observed
            let kind: WindowEchoes.Context.Event = if case .windowMoved = event { .moved } else { .resized }
            let verdict = echoes.interpret(r, frame: f, WindowEchoes.Context(
                event: kind, was: was, locked: locked, grabbing: grab != nil, pointerDown: pointerDown,
                dragging: drag?.ref, isTile: tiles[r] != nil, humanRecently: focusEchoes.humanRecently,
                world: world, displays: displays, parked: records.parked))
            records[r].observed = f
            if verdict.learned.contains(.sheetUnmovable) { logUnmovable(r) }
            switch verdict.action {
            case .ownEcho, .hold, .leave: return
            case .drag(let start):
                // #108: suspended until the mouse-up; each move re-aims the drop indicator.
                if let start {
                    drag = Drag(ref: r, grab: start)
                    Self.log.notice("drag \(r.id, privacy: .public) \(self.records[r].bundleID ?? "-", privacy: .public)")
                }
                guard let d = drag else { return }
                aim(DropTarget.tile(at: CGPoint(x: f.minX + d.grab.dx, y: f.minY + d.grab.dy), dragging: r, in: tiles))
                return
            case .rehome(let dest, let target):
                world = CommandRunner.run(.moveWindowRefToWorkspace(r, target), on: world, in: commandEnvironment).world
                Self.log.notice("dragged \(r.id, privacy: .public) \(self.records[r].bundleID ?? "-", privacy: .public) to \(String(dest.prefix(8)), privacy: .public)")
            case .moveOwner, .snapBack: break   // the reconcile below moves the owner, or puts it back
            }
        case .focusChanged(let r):
            if locked { return }
            applyNativeFocus(r)
        case .appActivated(let pid):
            if locked { return }
            // #170: our own raise's activation is ignored (`FocusEchoes.activationReported`).
            switch focusEchoes.activationReported(pid: pid, world: world) {
            case .intrusion(let fs): interceptFocus(by: candidateWindow(ofPid: pid), behind: fs)
            case .change: surfaceActivatedApp(pid)
            case .ownEcho, .repeated, .stale: return
            }
        case .humanInput:
            focusEchoes.humanInput(); return
        case .windowTitleChanged(let r, let title):
            // Not spatial: no sweep, no reconcile, no span. Only a window a refresh has already
            // seen, and only a real change reaches `publish`'s dedupe.
            guard let was = records[r].title, was != title else { return }
            records[r].title = title
            if !locked { publish() }
            return
        case .screenLocked:
            // Spec §7.7 freeze. Setting the flag only stops the *next* pass from starting; a plan
            // already mid-flight would keep writing frames at a locked screen, and its writes land
            // against whatever the lock screen reports. Bumping the generation is the same signal
            // a newer reconcile sends, and every await in `reconcile()` checks it.
            locked = true; generation += 1; pointerDown = nil; endDrag(); dropGrab(); publish(); return
        case .screenUnlocked:
            locked = false
            eventSpan = tracedSnapshot(await backend.currentSnapshot())
        }
        drainDeferredFocus()
        await reconcile(parent: eventSpan)
    }

    private func tracedSnapshot(_ s: Snapshot) -> any Span {
        let span = startSpan("snapshot", parent: nil)
        let (adopted, vanished) = applySnapshot(s)
        span.setAttribute(key: "windows", value: s.windows.count)
        span.setAttribute(key: "displays", value: s.displays.count)
        span.setAttribute(key: "adopted", value: adopted)
        span.setAttribute(key: "vanished", value: vanished)
        return span
    }

    // MARK: snapshot → world

    /// Returns how many windows it adopted and how many vanished, for the trace.
    private func applySnapshot(_ s: Snapshot) -> (adopted: Int, vanished: Int) {
        // An empty display topology is always transient (wake, hot-plug, the lock screen). The
        // backend guards its own snapshots, but a snapshot reaches the store from more than one
        // door, and applying one would reseed the world from nothing: every workspace dropped,
        // every window re-adopted onto a screen that does not exist. Drop it instead.
        guard !s.displays.isEmpty else { return (0, 0) }
        var adopted = 0, vanished = 0
        // displays
        let sorted = s.displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        let displaysChanged = !displays.isEmpty && displays != sorted
        displays = sorted
        let main = sorted.first(where: \.isMain)?.id ?? sorted.first?.id ?? ""
        if world.screens.isEmpty && !sorted.isEmpty {
            world = World.seeded(screens: sorted.map(\.id), config: config)
        } else {
            world.setScreens(sorted.map(\.id), main: main)
        }
        let hiddenApps = Set(s.apps.filter(\.isHidden).map(\.pid))
        let crowds = crowdedApps(s)
        let systemCategories = Dictionary(s.apps.map { ($0.pid, $0.systemCategory) }, uniquingKeysWith: { a, _ in a })
        appNames = Dictionary(s.apps.compactMap { a in a.name.map { (a.pid, $0) } }, uniquingKeysWith: { a, _ in a })
        let fills = placeholderFills(s)
        var present: Set<WindowRef> = []
        for w in s.windows {
            present.insert(w.ref)
            defer { records[w.ref].lastSeen = w.frame }
            if echoes.settle(w.ref, seenAt: w.frame) { logUnmovable(w.ref) }
            records[w.ref].observed = w.frame
            records[w.ref].bundleID = w.bundleID
            records[w.ref].title = w.title
            // Spec §11 "until it changes": a retired window that has moved, resized or changed
            // fullscreen state is alive and ours again — `ignored` is not a one-way door (#36). So
            // is one back on the active Space after time away: its frame never changed (#55).
            if !w.onActiveSpace, world.ignored.contains(w.ref) { records[w.ref].retired?.wentAway = true }
            if world.ignored.contains(w.ref), let was = records[w.ref].retired,
               !Reconciler.approx(was.frame, w.frame) || was.fullscreen != w.isFullscreen
                || (was.wentAway && w.onActiveSpace) {
                revive(w.ref, frame: w.frame, reason: "changed")
            }
            let known = world.location(of: w.ref) != nil || world.ephemeral.contains(w.ref) || world.ignored.contains(w.ref)
            if !known, let p = fills[w.ref], let loc = world.location(of: p) {
                // #128: it is the window a placeholder was waiting for — it takes that slot, ahead
                // of every rung of the ladder below. Its row becomes the app's placement, as any
                // landing does.
                let kind = config.kindOverride(bundleID: w.bundleID, title: w.title, standard: w.isStandard) ?? w.kind
                if let b = w.bundleID { placements[b] = world.screens[loc.screen]!.workspaces[loc.index].id }
                world.fill(p, with: w.ref, kind: kind)
                adopted += 1
                Self.log.notice("adopt \(w.ref.id, privacy: .public) pid=\(w.ref.pid) \(w.bundleID ?? "-", privacy: .public) kind=\(kind.rawValue, privacy: .public) into placeholder \(p.id, privacy: .public)")
            } else if !known {
                let kind = config.kindOverride(bundleID: w.bundleID, title: w.title, standard: w.isStandard) ?? w.kind
                // #13's ladder, with #74's category routing: its category's row on the display it
                // is on (app type beats memory), else the app's remembered workspace if it still
                // exists, else a workspace of its own for a crowd arriving at launch, else a row of
                // its own, else nil — `adopt`'s ordinary rules. Whichever row it gets becomes the
                // app's placement, so the other windows of an app outside the order follow it. Only a window `adopt` will file on its own is routed: an
                // ephemeral, ignored or child window would leave its new row empty.
                // #98: an app the user moved as a whole goes where they put it, not by category.
                let routable = w.bundleID.map { !movedApps.contains($0) } == true && w.parent == nil && (kind == .tile || kind == .float)
                let landing = world.landing(remembered: w.bundleID.flatMap { placements[$0] },
                                            crowdOn: w.bundleID.flatMap { crowds[$0] },
                                            routeOn: routable ? screenFor(w.frame) : nil,
                                            category: AppCategories.category(bundleID: w.bundleID,
                                                                             systemCategory: systemCategories[w.ref.pid] ?? nil,
                                                                             overrides: config.appCategories),
                                            order: config.categoryOrder, maxWorkspaces: config.maxWorkspaces)
                if let b = w.bundleID, let landing { placements[b] = landing }
                let popup = popupRequest(for: w, kind: kind)   // before `adopt`, which may move focus to it
                world.adopt(w.ref, kind: kind, on: screenFor(w.frame), parent: w.parent, workspace: landing)
                adopted += 1
                Self.log.notice("adopt \(w.ref.id, privacy: .public) pid=\(w.ref.pid) \(w.bundleID ?? "-", privacy: .public) kind=\(kind.rawValue, privacy: .public) fullscreen=\(w.isFullscreen) placed=\(self.world.location(of: w.ref) != nil)")
                if let popup { records[w.ref].pendingPopup = popup; records[w.ref].isPopup = true }
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
            // #128: placeholders are never in a snapshot — they have no window — so they are not
            // candidates for vanishing; only closing one (or a match) removes it.
            let all = Set(world.screens.values.flatMap { $0.workspaces.flatMap(\.windows) }.filter { !$0.isPlaceholder })
                .union(world.ephemeral).union(world.ignored)
            for gone in all.subtracting(present) {
                vanished += 1
                Self.log.notice("vanished \(gone.id, privacy: .public) pid=\(gone.pid) \(self.records[gone].bundleID ?? "-", privacy: .public) wasIgnored=\(self.world.ignored.contains(gone))")
                // #129: a pinned window leaves a placeholder in its slot instead of its tab going.
                if let b = records[gone].bundleID, world.leavePlaceholder(for: gone, bundleID: b, title: records[gone].title ?? "") != nil {
                    Self.log.notice("pinned \(gone.id, privacy: .public) \(b, privacy: .public) closed: placeholder left in its slot")
                } else { world.remove(gone) }
                forget(gone)
            }
            if vanished > 0 { publishWriteProblems() }
        }
        // #165: a display came, went or changed size: every popup is clamped back inside its
        // display once. A popup still waiting for its first placement keeps that instead.
        if displaysChanged {
            for r in records.popups where records[r].pendingPopup == nil { records[r].pendingPopup = PopupRequest(.clamp) }
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
        return (adopted, vanished)
    }

    /// #128: which placeholder each window this snapshot shows for the first time fills. Only a
    /// window `adopt` would file on its own is a candidate — tileable, no parent, with a bundle id:
    /// a dialog belongs with its owner and a popup in no row, so neither may take a slot.
    private func placeholderFills(_ s: Snapshot) -> [WindowRef: WindowRef] {
        guard !world.placeholders.isEmpty else { return [:] }
        let arrivals: [PlaceholderMatch.Arrival] = s.windows.compactMap { w in
            guard let b = w.bundleID, w.parent == nil, world.location(of: w.ref) == nil,
                  !world.ephemeral.contains(w.ref), !world.ignored.contains(w.ref) else { return nil }
            let kind = config.kindOverride(bundleID: b, title: w.title, standard: w.isStandard) ?? w.kind
            return kind == .tile || kind == .float ? PlaceholderMatch.Arrival(ref: w.ref, bundleID: b, title: w.title) : nil
        }
        return PlaceholderMatch.match(arrivals, in: world)
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
            let kind = config.kindOverride(bundleID: b, title: w.title, standard: w.isStandard) ?? w.kind
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
    private func surfaceActivatedApp(_ pid: Int32) {
        // Already showing a window of this app: nothing to surface. The test is per display, not
        // "does this app own the single global focus" — with more than one screen two apps are on
        // screen at once, one per screen, and a focus test answers no for the app on the *other*
        // display. Surfacing it then switches that display's workspace for nothing, and the switch
        // activates the app we just left, which surfaces it right back: the two displays trade
        // workspaces forever.
        if world.screens.values.contains(where: { world.visible(in: $0.active).contains { $0.pid == pid } }) { return }
        guard let target = candidateWindow(ofPid: pid), let loc = world.location(of: target) else { return }
        Self.log.notice("surface \(target.id, privacy: .public) pid=\(pid) \(self.records[target].bundleID ?? "-", privacy: .public) after app activation")
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
        if world.ignored.contains(r), let was = records[r].retired {
            revive(r, frame: records[r].observed ?? was.frame, reason: "focused")
        }
        // #170: our own raise's echo, a repeat, the past (#67, #69, #84), the user, or an intrusion (#28).
        let verdict = focusEchoes.focusReported(r, world: world)
        // #68: the backstop snapshot re-reports an unchanged focus every refresh; at .notice that
        // pushed every interesting line out of a `log show --last 5m` window. Changes stay loud.
        if verdict == .repeated {
            Self.log.debug("native focus \(r.id, privacy: .public) unchanged")
        } else { Self.log.notice("native focus \(r.id, privacy: .public) \(self.records[r].bundleID ?? "-", privacy: .public) verdict=\(String(describing: verdict), privacy: .public) placed=\(self.world.location(of: r) != nil) hidden=\(self.world.hidden.contains(r)) ignored=\(self.world.ignored.contains(r)) focusScreen=\(String(self.world.focus.screen.prefix(8)), privacy: .public)") }
        let isEcho: Bool
        switch verdict {
        case .stale: return
        case .intrusion(let fs): interceptFocus(by: r, behind: fs); return
        case .ownEcho, .repeated: isEcho = true
        case .change: isEcho = false
        }
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

    /// `requester` asked for focus with no human behind it while `fs` is in front: it goes where
    /// `FocusEchoes.intercept` decides (another display's active row, or held until fullscreen
    /// ends), and `fs` goes back in front.
    private func interceptFocus(by requester: WindowRef?, behind fs: WindowRef) {
        guard let i = focusEchoes.intercept(requester, behind: fs, world: world) else { return }
        if let r = requester {
            switch i.requester {
            case .move(let dest, let target)?:
                world = CommandRunner.run(.moveWindowRefToWorkspace(r, target), on: world, in: commandEnvironment).world
                Self.log.notice("fullscreen guard: moved \(r.id, privacy: .public) \(self.records[r].bundleID ?? "-", privacy: .public) to \(String(dest.prefix(8)), privacy: .public)")
            case .deferred?:
                Self.log.notice("fullscreen guard: deferred \(r.id, privacy: .public) \(self.records[r].bundleID ?? "-", privacy: .public) behind \(fs.id, privacy: .public)")
            case nil: break
            }
        }
        world.focus = Focus(screen: i.screen, window: fs)
        world.normalize()
    }

    /// Hands out held-back focus (#28) once the window it was held behind has left fullscreen
    /// (`FocusEchoes.drainDeferred`).
    private func drainDeferredFocus() {
        guard let next = focusEchoes.drainDeferred(world: world) else { return }
        Self.log.notice("fullscreen guard: fullscreen ended, focusing deferred \(next.id, privacy: .public)")
        focus(next)
    }

    /// Points the drop indicator at `target` (nil hides it), telling the panel only on a change.
    private func aim(_ target: WindowRef?) {
        guard drag != nil, drag?.target != target else { return }
        drag?.target = target
        onDropTarget(target.flatMap { tiles[$0] })
    }

    private func endDrag() {
        guard drag != nil else { return }
        aim(nil)
        drag = nil
    }

    /// #108: what releasing `r` at `p` does. Over another tile, `dropWindow` (a swap in its own
    /// row; that tile's slot in another). Over no tile on another display, #57's rehome into that
    /// display's active row, at the drop instead of mid-drag. Anywhere else, nothing: the
    /// reconcile that follows snaps it back to its tile.
    private func drop(_ r: WindowRef, at p: CGPoint) -> Command? {
        if let t = DropTarget.tile(at: p, dragging: r, in: tiles) { return .dropWindow(r, onto: t) }
        guard let loc = world.location(of: r),
              let dest = displays.first(where: { $0.frame.contains(p) })?.id, dest != loc.screen,
              let target = world.screens[dest]?.active.id else { return nil }
        return .moveWindowRefToWorkspace(r, target)
    }

    /// #113: lays the grabbed border's row out for the newest pointer position, then the next, until
    /// it has caught up.
    private func pumpGrab() async {
        while let g = grab, g.latest != g.applied {
            grab?.applied = g.latest
            let t0 = ContinuousClock.now
            let moved = moveGrab(to: g.latest)
            if moved { await reconcile() }
            // #162: how live a drag can look is how long one step takes; logged for tuning.
            if g.bySwipe { Self.log.debug("swipe edge step: moved=\(moved, privacy: .public) took \((ContinuousClock.now - t0).formatted(.units(allowed: [.milliseconds])), privacy: .public)") }
        }
        pump = nil
    }

    /// #113: the grabbed line to the pointer (#162: or to where four fingers have it), snapped and
    /// clamped, as a `setPortions` — false when nothing changed or the row no longer shows the page
    /// the line belongs to.
    private func moveGrab(to target: GrabTarget) -> Bool {
        guard let g = grab, let loc = world.location(ofWorkspace: g.workspace), let rect = tilingRect(loc.screen) else { return false }
        let ws = world.screens[loc.screen]!.workspaces[loc.index], row = world.tiled(in: ws)
        let focused = ws.anchor.flatMap { row.firstIndex(of: $0) } ?? 0
        guard let page = LayoutEngine.page(layouts.resolve(ws.layout).def, count: row.count, focused: focused, in: rect, gap: config.gap,
                                           split: ws.split(in: row)),
              page.key == g.key else { return false }
        let u = switch target {
        case .pointer(let p): Resize.unit(g.axis == .width ? p.x : p.y, axis: g.axis, in: rect, gap: config.gap)
        case .unit(let u): u
        }
        let next = Resize.drag(page, ws.portions[g.key], axis: g.axis, line: g.line, to: u)
        let o = CommandRunner.run(.setPortions(g.workspace, key: g.key, next), on: world, in: commandEnvironment)
        guard !o.effects.isEmpty else { return false }
        world = o.world
        return true
    }

    /// The release, a mouse-up's or (#162) a lift's: the line lands where it was let go — after
    /// the pump in flight, one more pass for `latest` — and leaves the hand.
    private func settleGrab() async {
        await pump?.value
        await pumpGrab()
        grab = nil
    }

    // MARK: four-finger edge drag (#162)

    /// #162: a four-finger horizontal drag moves the focused tile's side edge the way a mouse
    /// drags a border (#113) — the same grab, the same pump, the same `setPortions`, snaps and
    /// floor: `began` takes the edge the resize keys move (measured against the real tiling rect,
    /// like them), each `moved` puts it `Resize.swiped` from where it was, and `ended` (a real
    /// lift) settles it there, once. The platform recognizes; this is the only door to the model.
    ///
    /// In maximize, and wherever the focused tile has no edge sideways, `began` is a no-op with the
    /// resize keys' reason, and the moves and the lift that follow find nothing in the hand.
    @discardableResult
    public func swipeEdge(_ drag: SwipeDrag) async -> CommandReport {
        switch drag.phase {
        case .began:
            guard !locked else { return .failed(.locked) }
            if let g = grab {
                // A lost lift (the tap re-armed, the config changed): the old drag lands first.
                guard g.bySwipe else { return .noop("a border is already in the hand") }
                await settleGrab()
            }
            guard let rect = tilingRect(world.focus.screen),
                  let (id, page, i) = world.resizePage(layouts: layouts, in: rect, gap: config.gap)
            else { return .noop("nothing to resize") }
            guard let (line, trailing) = Resize.swipeLine(page, index: i) else { return .noop(Resize.stuck(page, index: i, axis: .width)) }
            let start = page.positions(world.screens[world.focus.screen]?.active.portions[page.key], .width)[line]
            let anchor = world.focus.window.flatMap { tiles[$0] }.map { CGPoint(x: $0.midX, y: $0.midY) }
            grab = Grab(workspace: id, key: page.key, axis: .width, line: line, swipeStart: start,
                        swipeTrailing: trailing,
                        latest: .unit(Resize.swiped(from: start, travel: drag.travel, trailing: trailing)),
                        applied: nil, anchor: anchor)
            Self.log.notice("swipe edge \(line, privacy: .public) of \(page.key, privacy: .public) from \(start, privacy: .public)")
            focusEchoes.humanInput()
            if pump == nil { pump = Task { await self.pumpGrab() } }
            return .done
        case .moved:
            guard let g = grab, let start = g.swipeStart else { return .noop("no edge in the hand") }
            grab?.latest = .unit(Resize.swiped(from: start, travel: drag.travel, trailing: g.swipeTrailing))
            focusEchoes.humanInput()
            if pump == nil { pump = Task { await self.pumpGrab() } }
            return .done
        case .ended:
            guard let g = grab, let start = g.swipeStart else { return .noop("no edge in the hand") }
            grab?.latest = .unit(Resize.swiped(from: start, travel: drag.travel, trailing: g.swipeTrailing))
            await settleGrab()
            show(nil)
            Self.log.notice("swipe edge settled: \(String(describing: self.world.screens[self.world.focus.screen]?.active.portions[g.key]), privacy: .public)")
            return .done
        }
    }

    /// A lost mouse-up (released over the shell's own panels) or a lock: the border is let go where
    /// it last was.
    private func dropGrab() {
        guard grab != nil else { return }
        grab = nil; show(nil)
    }

    /// Points the border highlight at `rect` (nil hides it), telling the panel only on a change.
    private func show(_ rect: CGRect?) {
        guard rect != hovered else { return }
        hovered = rect
        onBorder(rect)
    }

    /// The rect `display`'s active row is tiled in, as the reconciler computes it.
    private func tilingRect(_ display: DisplayID) -> CGRect? {
        guard let screen = world.screens[display], let d = displays.first(where: { $0.id == display }) else { return nil }
        return Reconciler.tilingRect(screen: screen, display: d, insets: ShellInsets(config: config, hidden: world.zen), screenGap: config.outerGap)
    }

    /// #113: every draggable border the reconcile is about to frame, per display's active row.
    private func findBorders(_ desired: [WindowRef: Placement]) -> [BorderRef] {
        var out: [BorderRef] = []
        for sid in world.screenOrder {
            guard let screen = world.screens[sid], let rect = tilingRect(sid) else { continue }
            let ws = screen.active, row = world.tiled(in: ws)
            let focused = ws.anchor.flatMap { row.firstIndex(of: $0) } ?? 0
            guard let page = LayoutEngine.page(layouts.resolve(ws.layout).def, count: row.count, focused: focused, in: rect, gap: config.gap,
                                               split: ws.split(in: row))
            else { continue }
            let frames: [CGRect?] = row.map { if case .frame(let f)? = desired[$0] { f } else { nil } }
            out += Resize.borders(page, frames: frames).map { BorderRef(display: sid, workspace: ws.id, key: page.key, border: $0) }
        }
        return out
    }

    /// Puts a retired window back in the model (spec §11 "until it changes"). The app's remembered
    /// workspace still applies, exactly as at first adoption.
    private func revive(_ r: WindowRef, frame: CGRect, reason: StaticString) {
        guard records[r].retired != nil else { return }
        records[r].retired = nil
        world.ignored.remove(r)
        records[r].failures = 0
        let bundle = records[r].bundleID
        let kind = config.kindOverride(bundleID: bundle, title: "") ?? .tile
        world.adopt(r, kind: kind, on: screenFor(frame), workspace: bundle.flatMap { placements[$0] })
        Self.log.notice("revive \(r.id, privacy: .public) pid=\(r.pid) \(bundle ?? "-", privacy: .public) \(reason, privacy: .public)")
        publishWriteProblems()
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
        guard w.isFullscreen || (floating && !records[w.ref].parked),
              let d = displayUnder(w.frame), d != loc.screen, world.screens[d] != nil else { return }
        let focused = world.focus.window == w.ref
        world.remove(w.ref)
        world.adopt(w.ref, kind: floating ? .float : .tile, on: d)
        if focused { world.focus = Focus(screen: d, window: w.ref) }
        world.normalize()
        Self.log.notice("rehome \(w.ref.id, privacy: .public) \(w.bundleID ?? "-", privacy: .public) to \(String(d.prefix(8)), privacy: .public): macOS owns its frame (\(w.isFullscreen ? "fullscreen" : "floating", privacy: .public))")
    }

    /// The display holding most of `frame`, or nil when it is on none.
    private func displayUnder(_ frame: CGRect) -> DisplayID? { Reconciler.mostlyOn(frame, displays) }

    private func screenFor(_ frame: CGRect) -> DisplayID {
        var best: (DisplayID, CGFloat)? = nil
        for d in displays {
            let a = d.frame.intersection(frame); let area = a.isNull ? 0 : a.width * a.height
            if best == nil || area > best!.1 { best = (d.id, area) }
        }
        return best?.0 ?? world.focus.screen
    }

    // MARK: dialogs and popups (#165)

    /// A window seen for the first time that is a dialog or popup gets placed on the next pass:
    /// an ephemeral visitor, a floating child window (an attached dialog or sheet, #134), or a
    /// floating window that is not an app's main window (AX subrole other than `AXStandardWindow`:
    /// a standalone alert or file panel). A standard window floated by a `[[float]]` rule is the
    /// user's own window and is left where it opens.
    private func popupRequest(for w: WindowSnapshot, kind: WindowKind) -> PopupRequest? {
        switch kind {
        case .ephemeral: break
        case .float where w.parent != nil || !w.isStandard: break
        default: return nil
        }
        return PopupRequest(.place, owner: w.parent ?? ownerHint(pid: w.ref.pid))
    }

    /// The window a popup with no AX parent most likely came from: the focused window if it is the
    /// same app's, else that app's first window tiled in an active row.
    private func ownerHint(pid: Int32) -> WindowRef? {
        if let f = world.focus.window, f.pid == pid, world.location(of: f) != nil { return f }
        return world.screenOrder.lazy.compactMap { self.world.screens[$0] }
            .compactMap { s in self.world.tiled(in: s.active).first { $0.pid == pid } }.first
    }

    /// #165: `WindowEchoes` has learned a sheet will not move (its placement's echo, or a snapshot,
    /// still showed it where it was).
    private func logUnmovable(_ r: WindowRef) {
        Self.log.notice("sheet \(r.id, privacy: .public) \(self.records[r].bundleID ?? "-", privacy: .public) did not move: its owner moves instead")
    }

    // MARK: reconcile

    private func reconcile(parent: (any Span)? = nil, since: ContinuousClock.Instant? = nil) async {
        let since = since ?? now()
        // Placement memory follows the model: whatever the last command or snapshot did, the
        // windows on screen now define where their apps belong.
        placements.merge(PersistedState.placements(world: world, bundleIDs: records.bundleIDs)) { _, live in live }
        generation += 1
        let gen = generation
        // #148: one span per pass, one child for all its writes and one for the raise — counts, not
        // a span per window, so a burst of Fn+D stays a handful of spans a press. A pass a newer
        // one overtook is `superseded`: it returned early, and its writes are the newer pass's now.
        let span = startSpan("reconcile", parent: parent)
        span.setAttribute(key: "generation", value: gen)
        var finished = false
        var writes: (any Span)?
        var frames = 0, parks = 0, failedWrites = 0
        func beginWrites() { if writes == nil { writes = startSpan("reconcile.writes", parent: span) } }
        func endWrites() {
            guard let w = writes else { return }
            w.setAttribute(key: "frames", value: frames)
            w.setAttribute(key: "parks", value: parks)
            w.setAttribute(key: "failures", value: failedWrites)
            w.end(); writes = nil
        }
        func count(_ result: Result<Void, BackendError>) { if case .failure = result { failedWrites += 1 } }
        defer {
            endWrites()
            span.setAttribute(key: "superseded", value: !finished)
            span.end()
        }
        let zero = Set(records.bundleIDs.filter { zeroSliverBundleIDs.contains($0.value) }.map(\.key))
        // Zen and `show-panels` decide whether the panels' edges belong to the layout (M2 design
        // §Decisions: `ShellInsets(config:hidden:)` computed purely in Kit; same insets on every
        // screen — each screen carries both panels).
        let shellInsets = ShellInsets(config: config, hidden: world.zen)
        let insets = Dictionary(uniqueKeysWithValues: world.screenOrder.map { ($0, shellInsets) })
        logUnresolvedLayouts()
        var desired = Reconciler.desired(world: world, displays: displays, config: layoutConfig,
                                         observed: records.observed, prePark: records.prePark, parkedNow: records.parked, zeroSliver: zero,
                                         insets: insets, suspended: drag.map { [$0.ref] } ?? [], refused: echoes.refused,
                                         unmovable: echoes.unmovable)
        // #165: the popups due a placement, and the requests they were placed for.
        let pendingPopups = records.pendingPopups
        let placed = Reconciler.placePopups(pendingPopups, into: &desired, world: world, displays: displays,
                                            observed: records.observed, parkedNow: records.parked, unmovable: echoes.unmovable)
        let placing = pendingPopups.filter { placed.contains($0.key) }
        tiles = DropTarget.tiles(world: world, desired: desired)
        borders = findBorders(desired)
        // The grabbed border's highlight follows it to where this pass puts it.
        if let g = grab {
            show(g.anchor.flatMap { a in
                borders.first { $0.workspace == g.workspace && $0.key == g.key && $0.border.axis == g.axis
                    && $0.border.line == g.line && $0.border.contains(a, tolerance: 1_000) }?.border.indicator
            })
        }
        if let t = drag?.target, tiles[t] == nil { aim(nil) }   // its row went away under the hand (Fn+W/S)
        // #64: a switch is motion. The overlay goes up *before* the first write, so the real windows
        // jump to their final frames underneath it; `play` then slides the proxies after them.
        let shownNow = shownRows(world, desired: desired, insets: insets)
        let transitions = self.transitions(world, to: shownNow, insets: insets)
        // Recorded *before* the first await: an event that lands while the overlay is being
        // prepared (the echo of this very raise) re-enters and reconciles again, and compared to
        // the old rows it would plan this same switch a second time and cancel the first mid-flight.
        lastShown = shownNow
        span.setAttribute(key: "windows", value: desired.count)
        span.setAttribute(key: "transitions", value: transitions.count)
        let trace = span.context
        var animating = false
        // Once the overlay is up, every way out of this pass plays it — including the early
        // returns when a newer pass supersedes this one mid-write (the echo of our own raise does,
        // routinely). That pass compares against the `lastShown` recorded above, plans no motion,
        // and would never play this one: the pictures sat frozen until the watchdog cut them (#66).
        defer { if animating, let animator { Task { await animator.play(trace: trace) } } }
        // #113: a border drag lays out on every move; the hand is the motion, so nothing slides.
        // #140: re-tiles only with `animate-retile`; see `MotionRules.animated`.
        let motion = MotionRules.animated(transitions, animations: config.animations,
                                          animateRetile: config.animateRetile, grabbing: grab != nil)
        if let animator, !motion.isEmpty {
            span.setAttribute(key: "motion", value: MotionRules(motion).kind.rawValue)
            animating = await animator.prepare(motion, trace: trace, since: since)
            span.setAttribute(key: "animating", value: animating)
            if gen != generation { return }          // superseded: the deferred play still lands it
        }
        let plan = Reconciler.plan(desired: desired, observed: records.observed, parkedNow: records.parked)
        // #165: a popup already where its placement puts it is placed; one being written is placed
        // once its write returns, superseded or not, so no later pass drags it back there after
        // the user has moved it.
        for r in placing.keys where !plan.contains(where: { if case .setFrame(r, _) = $0 { true } else { false } }) {
            if records[r].pendingPopup == placing[r] { records[r].pendingPopup = nil }
        }
        for w in plan {
            echoes.record(w)
            beginWrites()
            switch w {
            case .setFrame(let r, let f):
                frames += 1
                let from = records[r].observed
                let result = await backend.setFrame(r, f)
                count(result)
                if let request = placing[r] {
                    if records[r].pendingPopup == request { records[r].pendingPopup = nil }
                    // A first placement of an attached window is also the test of whether it moves.
                    if request.mode == .place, world.owner(of: r) != nil { echoes.probe(r, from: from, to: f) }
                }
                if gen != generation { return }
                records[r].observed = f; records[r].parked = false; records[r].prePark = nil
                note(result, for: r)
            case .setPosition(let r, let o):
                let pre = records[r].parked ? nil : records[r].observed
                parks += 1
                let result = await backend.setPosition(r, o)
                count(result)
                if gen != generation { return }
                if let pre { records[r].prePark = pre }
                if let cur = records[r].observed { records[r].observed = CGRect(origin: o, size: cur.size) }
                records[r].parked = true
                note(result, for: r)
            }
        }
        endWrites()
        if let f = world.focus.window, focusEchoes.recordRaise(of: f) {
            let raise = startSpan("reconcile.raise", parent: span)
            raise.setAttribute(key: "window.id", value: Int(f.id))
            if let b = records[f].bundleID { raise.setAttribute(key: "bundle.id", value: b) }
            let result = await backend.raise(f)
            if case .failure = result { raise.setAttribute(key: "failed", value: true) }
            raise.end()
            if gen != generation { return }
            // Spec §11 as amended: a failed raise never retires. Raising fails for transient reasons
            // — the window is in its own fullscreen Space, the app is mid-transition — and counting
            // it left live windows on screen with no tab (#36). Frame writes are the real signal.
            if case .failure(let e) = result {
                Self.log.notice("raise failed \(f.id, privacy: .public) \(String(describing: e), privacy: .public); not counted")
            }
        }
        if animating, let animator { animating = false; await animator.play(trace: trace) }
        finished = true
        publish()
        // #77: only a pass that finished speaks for what is on screen; a superseded one returned above.
        if let animator, config.animations, gen == generation {
            await animator.prefetch(predictedSwitches(insets: insets, zero: zero))
        }
    }

    private var layoutConfig: LayoutConfig { LayoutConfig(gap: config.gap, screenGap: config.outerGap, layouts: layouts) }

    /// Design §8: a workspace whose layout was deleted (or mistyped) keeps its id and draws the
    /// fallback; the switcher badges it, and the log says so once per id.
    private func logUnresolvedLayouts() {
        for sid in world.screenOrder {
            for ws in world.screens[sid]?.workspaces ?? [] {
                guard let warning = layouts.warning(for: ws.layout), loggedUnresolved.insert(ws.layout).inserted else { continue }
                Self.log.notice("\(warning, privacy: .public)")
            }
        }
    }

    /// #77: the keys the overlay prefetches for — Fn+A, Fn+D, Fn+W, Fn+S — in `prefetch`'s order.
    static let predictedCommands: [Command] = [.focusWindow(.left), .focusWindow(.right),
                                               .focusWorkspace(.up), .focusWorkspace(.down)]

    /// What each of `predictedCommands` would draw from here: the real command on a copy of the
    /// world, the real reconciler, and the planner against `lastShown` — the same path `run` takes,
    /// so the prediction is exactly what the next `prepare` will ask for. Nothing is written.
    private func predictedSwitches(insets: [DisplayID: ShellInsets], zero: Set<WindowRef>) -> [[Transition]] {
        let env = commandEnvironment
        let (observed, prePark, parked) = (records.observed, records.prePark, records.parked)
        return Self.predictedCommands.map { command in
            let next = CommandRunner.run(command, on: world, in: env).world
            let desired = Reconciler.desired(world: next, displays: displays, config: layoutConfig,
                                             observed: observed, prePark: prePark, parkedNow: parked, zeroSliver: zero,
                                             insets: insets, refused: echoes.refused, unmovable: echoes.unmovable)
            return transitions(next, to: shownRows(next, desired: desired, insets: insets), insets: insets)
        }
    }

    /// Each display's active row as `desired` is about to show it: the tiled windows that get a
    /// frame, in tab order, and which of them the row is focused on.
    private func shownRows(_ world: World, desired: [WindowRef: Placement], insets: [DisplayID: ShellInsets]) -> [DisplayID: ShownRow] {
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
                case .untouched?: if let f = records[r].observed { frames[r] = f }
                default: break
                }
            }
            out[sid] = ShownRow(workspace: ws.id, index: screen.activeIndex, order: screen.workspaces.map(\.id),
                                row: row, focused: ws.anchor, frames: frames)
        }
        return out
    }

    private func transitions(_ world: World, to shownNow: [DisplayID: ShownRow], insets: [DisplayID: ShellInsets]) -> [Transition] {
        world.screenOrder.compactMap { sid in
            guard let before = lastShown[sid], let after = shownNow[sid], let screen = world.screens[sid],
                  let display = displays.first(where: { $0.id == sid }) else { return nil }
            let viewport = Reconciler.viewport(screen: screen, display: display, insets: insets[sid, default: .zero])
            return Transition.plan(display: sid, before: before, after: after, viewport: viewport, gap: config.gap)
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
        let desired = Reconciler.desired(world: world, displays: displays, config: layoutConfig,
                                         observed: records.observed, prePark: records.prePark, parkedNow: records.parked,
                                         zeroSliver: [], insets: insets, refused: echoes.refused, unmovable: echoes.unmovable)
        for (ref, frame) in records.observed.sorted(by: { $0.key.id < $1.key.id }) {
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
            Self.log.notice("rescue \(ref.id, privacy: .public) \(self.records[ref].bundleID ?? "-", privacy: .public) from \(String(describing: frame.origin), privacy: .public) (\(reason, privacy: .public))")
            echoes.record(.setFrame(ref, rescued))
            let result = await backend.setFrame(ref, rescued)
            records[ref].observed = rescued
            note(result, for: ref)
        }
    }

    /// Spec §11: three failed *writes* in a row retire the window to `ignored` so we stop fighting
    /// it — until it changes, when `revive` brings it back. Raises never reach here (see `reconcile`).
    private func note(_ result: Result<Void, BackendError>, for r: WindowRef) {
        switch result {
        case .success:
            records[r].failures = 0
        case .failure:
            records[r].failures += 1
            guard records[r].failures >= 3 else { return }
            records[r].failures = 0
            // macOS owns a fullscreen window and the shell writes nothing for it, so a failure
            // there says nothing about manageability (#36).
            guard !world.fullscreen.contains(r) else { return }
            Self.log.notice("retire \(r.id, privacy: .public) pid=\(r.pid) \(self.records[r].bundleID ?? "-", privacy: .public) after 3 failed writes")
            retire(r)
            publishWriteProblems()
        }
    }

    /// Spec §11: `r` goes to `ignored`, keeping who it is and what brings it back
    /// (`WindowRecord.retire`); nothing learned from placing it or from its echoes stays.
    private func retire(_ r: WindowRef) {
        records[r].retire(fullscreen: world.fullscreen.contains(r))
        world.remove(r); world.ignored.insert(r)
        echoes.forget(r); focusEchoes.retired(r)
    }

    /// #174: `r` vanished: nothing the store knew about it outlives it, here or in the echoes.
    private func forget(_ r: WindowRef) {
        records.forget(r); echoes.forget(r); focusEchoes.vanished(r)
    }

    /// #109: a retired window is a write failure that persisted. One problem per app, rebuilt from
    /// `retired` whenever it changes, so a revived or vanished window clears itself.
    private func publishWriteProblems() {
        let apps = Set(records.retired.map { records[$0].bundleID ?? "pid:\($0.pid)" })
        ProblemCenter.shared.replace(prefix: Problem.Key.axWritePrefix, with: apps.map { Problem.axWriteFailing(app: $0) })
    }
}
