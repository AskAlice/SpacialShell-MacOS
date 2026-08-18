import Foundation

public actor WorldStore {
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
    private var fullscreen: Set<WindowRef> = []
    private var intents = IntentSet()
    private var failures: [WindowRef: Int] = [:]
    private var lastRaised: WindowRef?
    private var locked = false
    /// Bumped by every `reconcile()`; an in-flight pass abandons itself once a newer pass has started.
    /// Only a *newer reconcile* invalidates a plan — early-return event paths (intent echoes, locked,
    /// floating/unknown moves) must not abort a multi-write plan that is already in flight.
    private var generation = 0
    private var eventTask: Task<Void, Never>?
    private var started = false

    public init(backend: any WindowBackend, config: Config, world: World?, zeroSliverBundleIDs: Set<String>, onChange: @escaping @Sendable (World) -> Void) {
        self.backend = backend; self.config = config; self.zeroSliverBundleIDs = zeroSliverBundleIDs; self.onChange = onChange
        self.world = world ?? World.seeded(screens: [], config: config)
    }

    public func start() async {
        guard !started else { return }; started = true
        await apply(.snapshot(await backend.currentSnapshot()))
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
    public func exportForTermination() -> (world: World, displays: [DisplayInfo], observed: [WindowRef: CGRect], stranded: [WindowRef: CGRect]) {
        (world, displays, observed, stranded)
    }
    public func update(config: Config) async { self.config = config; await reconcile() }

    public func run(_ command: Command) async {
        guard !locked else { return }   // spec §7.7: no writes and no model changes while locked
        let (next, effects) = CommandRunner.apply(command, to: world)
        world = next
        for e in effects { if case .close(let r) = e { _ = await backend.close(r) } }
        await reconcile()
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
        case .screenLocked:
            locked = true; return
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
            observed[w.ref] = w.frame
            bundleIDs[w.ref] = w.bundleID
            let known = world.location(of: w.ref) != nil || world.ephemeral.contains(w.ref) || world.ignored.contains(w.ref)
            if w.isFullscreen {
                if !fullscreen.contains(w.ref) { fullscreen.insert(w.ref); world.remove(w.ref); world.ignored.insert(w.ref) }
                continue
            } else if fullscreen.contains(w.ref) {
                fullscreen.remove(w.ref); world.ignored.remove(w.ref)
            }
            if !known || (!fullscreen.contains(w.ref) && world.location(of: w.ref) == nil && !world.ephemeral.contains(w.ref) && !world.ignored.contains(w.ref)) {
                let kind = config.kindOverride(bundleID: w.bundleID, title: w.title) ?? w.kind
                world.adopt(w.ref, kind: kind, on: screenFor(w.frame), parent: w.parent)
                if kind == .ephemeral { centerEphemeral(w.ref, size: w.frame.size) }
            }
            world.setHidden(w.ref, w.isMinimized || hiddenApps.contains(w.ref.pid))
        }
        if !s.loginwindowFrontmost {
            let all = Set(world.screens.values.flatMap { $0.workspaces.flatMap(\.windows) }).union(world.ephemeral).union(world.ignored)
            for gone in all.subtracting(present) {
                world.remove(gone); observed[gone] = nil; prePark[gone] = nil; parked.remove(gone); bundleIDs[gone] = nil; fullscreen.remove(gone); intents.forget(gone)
                stranded[gone] = nil
                failures[gone] = nil; if lastRaised == gone { lastRaised = nil }
            }
        }
        applyNativeFocus(s.focused)
    }

    private func applyNativeFocus(_ r: WindowRef?) {
        guard let r else { return }
        if world.ephemeral.contains(r) { world.focus.window = r; return }
        guard let loc = world.location(of: r), !world.hidden.contains(r) else { return }
        if world.screens[loc.screen]!.activeIndex != loc.index { world.activate(index: loc.index, on: loc.screen) }
        world.focus = Focus(screen: loc.screen, window: r)
        world.screens[loc.screen]!.workspaces[loc.index].anchor = r
        world.normalize()
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
        generation += 1
        let gen = generation
        let zero = Set(bundleIDs.filter { zeroSliverBundleIDs.contains($0.value) }.map(\.key))
        let desired = Reconciler.desired(world: world, displays: displays, config: LayoutConfig(gap: config.gap),
                                         observed: observed, prePark: prePark, parkedNow: parked, zeroSliver: zero)
        for (r, size) in pendingCenter {
            let d = displays.first { $0.id == world.focus.screen } ?? displays.first
            guard let d else { continue }
            let f = Reconciler.centered(size: size, in: d.visibleFrame)
            intents.record(.setFrame(r, f))
            let result = await backend.setFrame(r, f)
            if gen != generation { return }          // superseded mid-write: side tables belong to the newer pass
            observed[r] = f
            note(result, for: r)
        }
        pendingCenter = []
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
            note(result, for: f)
        }
        onChange(world)
    }

    /// Spec §11: three failed writes in a row retire the window to `ignored` so we stop fighting it.
    private func note(_ result: Result<Void, BackendError>, for r: WindowRef) {
        switch result {
        case .success:
            failures[r] = nil
        case .failure:
            failures[r, default: 0] += 1
            guard failures[r, default: 0] >= 3 else { return }
            failures[r] = nil
            // Remember where it belongs before the side tables that know are cleared.
            if parked.contains(r), let frame = prePark[r] ?? observed[r] { stranded[r] = frame }
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
