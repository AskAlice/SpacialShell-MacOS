import AppKit
import CoreGraphics
import SpacialShellKit
import struct SpacialShellProtocol.WindowRef
import enum SpacialShellProtocol.JSONValue
import SpacialShellPlatform
import SpacialShellUI
import OpenTelemetryApi
import OpenTelemetrySdk
import Sparkle
import os

/// Boot, live wiring, and the way out.
///
/// Boot order is not negotiable (spec §10, T18 handoff): the Accessibility grant has to land
/// *before* `AXWindowBackend.start()`, because the global event monitors it installs are silently
/// `nil` without it and would never be retried; the world has to be built before the store, since
/// the store's first reconcile lays out against it; and the hotkey tap comes up last so a
/// keystroke can't reach a store that has not started.
@MainActor
final class AppRuntime: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: Paths.bundleID, category: "app")

    /// Spec §7.4: apps whose windows must be parked with a zero-width sliver instead of a 1×32 one.
    private static let zeroSliverBundleIDs: Set<String> = ["us.zoom.xos"]
    /// The config file is edited by hand; a save can arrive as several events (write, rename).
    private static let configDebounce = Duration.milliseconds(300)
    /// A world change per keystroke would mean a write per keystroke.
    private static let saveDebounce = Duration.milliseconds(500)

    /// What `config.toml` says, untouched. The settings window shows this as the baseline every
    /// "Use file" returns to, and it is never written back — see `Settings`.
    private var fileConfig = Config()
    /// What the settings window has set on top. App-owned, written to `Paths.settingsFile`.
    private var overrides = SettingsOverrides()
    /// The two layered together: what the shell actually runs on.
    private var config = Config()
    private var backend: AXWindowBackend?
    private var store: WorldStore?
    private var tap: HotkeyTap?
    private var shell: ShellController?
    private var overview: OverviewController?
    private var settingsWindow: SettingsWindowController?
    private var updater: SPUStandardUpdaterController?
    private var layouts: LayoutsController?
    private var cheatSheet: CheatSheetController?
    private var ipc: IPCServer?
    private var saveTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var configWatch: DispatchSourceFileSystemObject?
    private var signalSources: [any DispatchSourceSignal] = []

    /// Holds the pieces the termination path needs, reachable off the main actor.
    private nonisolated let termination = TerminationGate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Before the Accessibility wait: an update must still reach a copy that never got its grant.
        updater = Updates.makeController()
        Task { await boot() }
    }

    // MARK: - Boot

    private func boot() async {
        log.info("stage 1/8: waiting for the Accessibility grant")
        // #109: listed while the wait lasts; the grant-wait window itself is B7 (#130).
        if !AXIsProcessTrusted() { ProblemCenter.shared.report(.accessibilityMissing) }
        await Permissions.waitForAccessibility(bundleID: Paths.bundleID)
        ProblemCenter.shared.clear(Problem.Key.accessibility)
        // Takes effect only at the next launch, so one look at boot is the whole check; a declined
        // capture later (#92) reports the same key from `CaptureGate`.
        if !CGPreflightScreenCaptureAccess() { ProblemCenter.shared.report(.screenRecordingMissing) }

        log.info("stage 2/8: loading config")
        loadOverrides()
        loadConfig()
        // #83: before anything that traces. Read once: turning it on or off takes a relaunch.
        termination.arm(tracing: Tracing.start(config.telemetry))

        log.info("stage 3/8: constructing the AX backend")
        let backend = AXWindowBackend(config: config)
        self.backend = backend

        log.info("stage 4/8: building the world")
        let restored = (try? PersistedState.load(from: Paths.stateFile)) ?? nil
        let topology = DisplayTopology.current()
        let seeded = World.seeded(screens: topology.map(\.id), config: config)
        let initial = restored?.restore(into: seeded, main: topology.first(where: \.isMain)?.id, order: config.categoryOrder) ?? seeded
        log.info("world on \(initial.screenOrder.count) screen(s), restored=\(restored != nil)")

        log.info("stage 5/8: constructing the store")
        let gate = termination
        let dropIndicator = DropIndicator()
        let store = WorldStore(
            backend: backend, config: config, world: initial, zeroSliverBundleIDs: Self.zeroSliverBundleIDs,
            placements: restored?.placements ?? [:], movedApps: restored?.movedApps ?? [],
            // #64: switches slide as screenshot proxies (#65); instant without the grant.
            animator: SwitchOverlay(),
            // #108: the tile a dragged window would swap with.
            onDropTarget: { frame in Task { @MainActor in dropIndicator.show(frame) } },
        ) { [weak self] world, snapshot in
            gate.note(world: world)
            Task { @MainActor in
                self?.ipc?.publish(snapshot)   // #117: returns at once; the diff runs on the IPC queue
                self?.scheduleSave(world)
                self?.shell?.update(world: world, snapshot: snapshot)
                self?.overview?.update(world: world, snapshot: snapshot)
                self?.layouts?.update(world: world)
            }
        }
        self.store = store
        termination.arm(store: store, backend: backend)

        // The shell panels and the overview (M2). Wired before the store starts so the first
        // reconcile's onChange already reaches them; they draw nothing until that first world
        // arrives. Clicks re-enter through the same command pipeline as hotkeys — the store and
        // the overview are captured directly (ruling 8's spirit: these callbacks run off the main
        // actor and must not depend on `self`).
        let appMeta = AppMetaCache()
        let overview = OverviewController(appMeta: appMeta) { command in
            Task { await store.run(command) }
        }
        self.overview = overview

        // Same rule: captured directly, never through `self`. `onChange` hops back onto the main
        // actor to persist and re-layer, which is the only thing that needs the runtime at all.
        let settings = SettingsWindowController(
            file: fileConfig, overrides: overrides,
            configPath: Paths.configFile.path,
            openConfigFile: {
                let url = Paths.configFile
                if !FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.createDirectory(at: Paths.configDir, withIntermediateDirectories: true)
                    try? Data().write(to: url)
                }
                NSWorkspace.shared.open(url)
            },
            checkForUpdates: updater.map { updater in { updater.checkForUpdates(nil) } },
            onChange: { [weak self] new in
                Task { @MainActor in self?.applyOverrides(new) }
            })
        self.settingsWindow = settings

        // #10: the layout popover's settings edits and the editor window. Same door as the settings
        // window: `onChange` persists, re-layers and pushes.
        let layouts = LayoutsController(
            config: config, overrides: overrides,
            send: { command in Task { await store.run(command) } },
            onChange: { [weak self] new in
                Task { @MainActor in self?.applyOverrides(new) }
            })
        self.layouts = layouts

        // One dispatch path for every command source — hotkey tap, panel clicks, and whatever
        // comes next. App-layer surfaces route to their controllers; everything else is a model
        // command for the store. Without this, a panel's `.toggleOverview` (the search glyph's
        // no-launcher fallback) would reach the store, where it is deliberately a no-op.
        let route: @Sendable (Command) -> Void = { command in
            switch command {
            case .toggleOverview:
                Task { @MainActor in overview.toggle() }
            case .openSettings:
                Task { @MainActor in settings.toggle() }
            case .editLayout, .setDefaultLayout, .showLayoutOnBar:
                Task { @MainActor in layouts.handle(command) }
            default:
                Task { await store.run(command) }
            }
        }
        let shell = ShellController(config: config, appMeta: appMeta, send: route)
        self.shell = shell
        // #109: the rail cog's badge. Reporters run on any thread; the panels on the main actor.
        ProblemCenter.shared.observe { problems in Task { @MainActor in shell.update(problems: problems) } }

        log.info("stage 6/8: starting the backend and the store")
        backend.start()
        await store.start()

        log.info("stage 6b/8: starting the control socket")
        let ipc = IPCServer { request in
            switch request.cmd {
            case "version":
                return .ok(id: request.id, data: .object(["version": .string(SpacialShellKit.version)]))
            case "run":
                let name = request.args["command"]?.stringValue ?? ""
                guard let command = KeyBindings.commandNames[name]
                else { return .failure(id: request.id, "unknown command \"\(name)\"") }
                // #88: exactly like a hotkey. App-layer commands go through `route` to their
                // controllers (the store would drop them); model commands are awaited, so a
                // `spacialctl state` straight after sees their effect. #109: the reply carries
                // the store's report — done, a no-op and why, or the error.
                if command.isAppLayer { route(command); return CommandReport.done.response(id: request.id) }
                return await store.run(command).response(id: request.id)
            case "state":
                let state = await store.wireState()
                return .ok(id: request.id, data: (try? JSONValue(encoding: state)) ?? .null)
            case "set-layout":
                // #10, design §6: refuses an id the catalogue does not know (spacialctl exits 1).
                switch await store.wireState().setLayout(request.args["layout"]?.stringValue,
                                                         workspace: request.args["workspace"]?.stringValue) {
                case .success(let command):
                    return await store.run(command).response(id: request.id)
                case .failure(let refusal):
                    return .failure(id: request.id, refusal.message)
                }
            default:
                return .failure(id: request.id, "unknown cmd \(request.cmd)")
            }
        }
        do {
            try ipc.start()
            self.ipc = ipc
            // #117: the first publishes happened before the socket existed; seed the diff base.
            ipc.publish(await store.shellSnapshot())
            termination.arm(ipc: ipc)
        } catch {
            log.error("control socket failed (\(String(describing: error), privacy: .public)); spacialctl is inactive")
            ProblemCenter.shared.report(.controlSocketInactive(String(describing: error)))
        }

        log.info("stage 7/8: starting the hotkey tap")
        // Ruling 8: `route` and the cheat sheet are captured directly, never `self` — these
        // closures run on the tap thread inside the event tap's deadline and must not touch the
        // main actor. Spawning a task that hops there later is fine; blocking on it is not.
        // `onFlags` never consumes events: holding the bare modifier shows the cheat sheet.
        let cheatSheet = CheatSheetController(config: config)
        self.cheatSheet = cheatSheet
        let tap = HotkeyTap(
            table: KeyBindings.table(for: config),
            onCommand: { command in
                // #83: the tap thread's share of a key press — inside the tap's deadline, so it
                // is worth watching. The command's own trace starts in `WorldStore.run`.
                let span = Telemetry.tracer().spanBuilder(spanName: "hotkey.dispatch").setNoParent().startSpan()
                span.setAttribute(key: "command", value: String(String(describing: command).prefix { $0 != "(" }))
                route(command)
                span.end()
            },
            onFlags: { flags in Task { @MainActor in cheatSheet.flagsChanged(flags) } },
            onKeyDown: { backend.noteHumanInput() },
        )
        self.tap = tap
        termination.arm(tap: tap)
        do {
            try tap.start()
        } catch {
            log.error("event tap failed (\(String(describing: error), privacy: .public)); hotkeys are inactive")
            ProblemCenter.shared.report(.hotkeysInactive(String(describing: error)))
        }

        log.info("stage 8/8: config watch and signal handlers")
        watchConfig()
        installSignalHandlers()
        log.info("SpacialShell running")
    }

    // MARK: - Config

    /// A malformed config keeps the previous one: an editor mid-save must not disarm the window
    /// manager. A *missing* config is not an error — it means "all defaults".
    private func loadConfig() {
        do {
            fileConfig = try Config.load(from: Paths.configFile)
            log.info("config loaded from \(Paths.configFile.path, privacy: .public)")
            ProblemCenter.shared.clear(Problem.Key.config)
        } catch CocoaError.fileReadNoSuchFile {
            fileConfig = Config()
            log.info("no config file; using defaults")
            ProblemCenter.shared.clear(Problem.Key.config)
        } catch {
            log.error("config invalid, keeping previous: \(String(describing: error), privacy: .public)")
            ProblemCenter.shared.report(.configInvalid(String(describing: error)))
        }
        config = Settings.effective(config: fileConfig, overrides: overrides)
    }

    /// A missing or unreadable settings file means "nothing overridden" — the file is ours, so a
    /// corrupt one is our problem to shrug off, not the user's config to reject. An unreadable one
    /// is moved aside first: the next save would otherwise overwrite it, destroying every setting
    /// in it for one bad byte.
    private func loadOverrides() {
        guard let data = try? Data(contentsOf: Paths.settingsFile) else { return }
        guard let decoded = try? JSONDecoder().decode(SettingsOverrides.self, from: data) else {
            let aside = Paths.settingsFile.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: Paths.settingsFile, to: aside)
            log.error("settings.json unreadable; moved to \(aside.lastPathComponent, privacy: .public) and starting from defaults")
            return
        }
        overrides = decoded
    }

    private func saveOverrides() {
        do {
            try FileManager.default.createDirectory(at: Paths.stateDir, withIntermediateDirectories: true)
            let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
            try e.encode(overrides).write(to: Paths.settingsFile, options: .atomic)
        } catch {
            log.error("could not write settings.json: \(String(describing: error), privacy: .public)")
        }
    }

    /// The settings window changed something: persist it, re-layer, and push it through the same
    /// path a config-file edit takes.
    private func applyOverrides(_ new: SettingsOverrides) {
        overrides = new
        saveOverrides()
        // Both editors of `settings.json` hold a copy; the one that did not make this change must
        // not write its stale copy back over it on its next edit.
        settingsWindow?.update(overrides: new)
        applyEffectiveConfig()
    }

    /// Watches the *directory*, not the file: editors replace configs by rename, which leaves the
    /// watched file descriptor pointing at an unlinked inode.
    private func watchConfig() {
        try? FileManager.default.createDirectory(at: Paths.configDir, withIntermediateDirectories: true)
        let fd = open(Paths.configDir.path, O_EVTONLY)
        guard fd >= 0 else {
            log.error("cannot watch \(Paths.configDir.path, privacy: .public); config reloads are off")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            // Ruling 8: the handler runs on the main *queue*, which is not the same thing as being
            // on the main actor as far as the compiler is concerned.
            Task { @MainActor in self?.configDidChange() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        configWatch = source
    }

    private func configDidChange() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.configDebounce)
            guard !Task.isCancelled, let self else { return }
            reloadConfig()
        }
    }

    private func reloadConfig() {
        let previous = config
        loadConfig()
        settingsWindow?.update(file: fileConfig)   // the baseline "Use file" returns to has moved
        push(previous: previous)
    }

    /// Re-layer the settings window's overrides over the file and push the result.
    private func applyEffectiveConfig() {
        let previous = config
        config = Settings.effective(config: fileConfig, overrides: overrides)
        push(previous: previous)
    }

    /// One path for both doors into a config change — a file edit and a settings-window edit end
    /// up in exactly the same place, so neither can quietly skip a step the other does.
    private func push(previous: Config) {
        guard config != previous else { return }
        log.info("config changed; re-binding keys and re-laying out")
        if config.axTimeoutMs != previous.axTimeoutMs || config.refreshIntervalMs != previous.refreshIntervalMs {
            // The backend reads both once, at construction; re-creating it live would drop every
            // AX observer and re-adopt every window mid-session.
            log.notice("ax-timeout-ms / refresh-interval-ms changed; those take effect at the next launch")
        }
        tap?.update(table: KeyBindings.table(for: config))
        shell?.update(config: config)
        cheatSheet?.update(config: config)
        layouts?.update(config: config, overrides: overrides)
        guard let store else { return }
        let config = config
        Task { await store.update(config: config) }   // reconcile picks up new insets; onChange re-renders the panels
    }

    // MARK: - State

    private func scheduleSave(_ world: World) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            let placements = await self?.store?.currentPlacements() ?? [:]
            let movedApps = await self?.store?.currentMovedApps() ?? []
            guard !Task.isCancelled else { return }
            do {
                try PersistedState(world: world, placements: placements, movedApps: movedApps).save(to: Paths.stateFile)
            } catch {
                self?.log.error("state save failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Termination

    /// Ruling 10: a `DispatchSourceSignal`, never a raw C handler — the restore has to make AX
    /// calls and wait on them, neither of which is async-signal-safe.
    ///
    /// The handlers run on a **private serial queue**, not the main one. `exportForTermination()`
    /// is actor-isolated and the store's in-flight work hops through the main actor, so blocking
    /// the main thread on the export's semaphore is exactly how to make it time out.
    private func installSignalHandlers() {
        let gate = termination
        // Issue #30. `setEventHandler`'s parameter is *not* `@Sendable`, so a closure written
        // inline here — inside a `@MainActor` type — inherits main-actor isolation. libdispatch
        // then runs it on the termination queue, the isolation preamble's executor check fails,
        // and the process traps (SIGTRAP, exit 133) on the handler's first instruction: before
        // `gate.run`, i.e. before the §7.4 restore, leaving parked windows in their corner.
        // Typing the closure `@Sendable` keeps it nonisolated, which is what it always had to be.
        let handler: @Sendable () -> Void = {
            gate.run(onMainThread: false)
            exit(0)
        }
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: TerminationGate.queue)
            source.setEventHandler(handler: handler)
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        termination.run(onMainThread: true)
    }
}

/// The way out (spec §7.4), reachable from a signal handler on a background queue *and* from
/// `applicationWillTerminate` on the main thread. Every step is bounded: a hung app must not cost
/// us the whole termination grace period, and every window we can still reach gets moved.
final class TerminationGate: @unchecked Sendable {
    static let queue = DispatchQueue(label: "\(Paths.bundleID).termination")
    private static let log = Logger(subsystem: Paths.bundleID, category: "termination")
    /// Ruling 10. The export only has to get four values out of an actor.
    private static let exportBudget: TimeInterval = 3
    /// Handed to `restoreAllForTermination`, which spends it across all windows.
    private static let restoreBudget = Duration.seconds(6)
    private static let teardownBudget: TimeInterval = 1

    private let lock = NSLock()
    private var store: WorldStore?
    private var backend: AXWindowBackend?
    private var tap: HotkeyTap?
    private var ipc: IPCServer?
    private var tracing: TracerProviderSdk?
    private var didTerminate = false
    /// The most recent world `WorldStore.onChange` published. The fallback when the export times
    /// out — see `fallbackExport`.
    private var lastWorld: World?

    func arm(store: WorldStore, backend: AXWindowBackend) {
        lock.lock(); self.store = store; self.backend = backend; lock.unlock()
    }

    func arm(tap: HotkeyTap) {
        lock.lock(); self.tap = tap; lock.unlock()
    }

    func arm(ipc: IPCServer) {
        lock.lock(); self.ipc = ipc; lock.unlock()
    }

    func arm(tracing: TracerProviderSdk?) {
        lock.lock(); self.tracing = tracing; lock.unlock()
    }

    /// Called from `WorldStore`'s `onChange`, off the main actor.
    func note(world: World) {
        lock.lock(); lastWorld = world; lock.unlock()
    }

    /// Idempotent: SIGTERM followed by `applicationWillTerminate` must not restore twice.
    func run(onMainThread: Bool) {
        lock.lock()
        if didTerminate {
            lock.unlock()
            return
        }
        didTerminate = true
        let store = self.store, backend = self.backend, tap = self.tap, ipc = self.ipc, tracing = self.tracing
        lock.unlock()
        // #83: last, after the windows are back — the flush waits on the network, bounded by the
        // exporter's timeout. It sends the spans of this very shutdown too.
        defer { tracing?.shutdown() }

        // First, stop taking commands: a keystroke or IPC request landing between the export and
        // the restore would move windows the restore has already decided about.
        tap?.stop()
        ipc?.stop()
        guard let store, let backend else { return }

        let export = Box<TerminationExport>()
        let exported = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            export.value = await store.exportForTermination()
            exported.signal()
        }
        if !wait(exported, Self.exportBudget, onMainThread: onMainThread) {
            Self.log.error("world export timed out; falling back to the last published world")
        }

        // The export may have landed while we were giving up on it; prefer it either way.
        if let e = export.value ?? fallbackExport(onMainThread: onMainThread) {
            // The 500 ms save debounce is about to be abandoned by `exit(0)`, so the last few
            // commands would be lost. This write is synchronous and happens before the restore:
            // the restore moves every window off its workspace, so a save after it would persist
            // a layout that no longer matches anything.
            do {
                var state = PersistedState(world: e.world, placements: e.placements, movedApps: e.movedApps)
                // The fallback export (store timed out) carries no placement memory; the debounced
                // save left a good one on disk moments ago, so keep that rather than forget where
                // every app lived.
                if state.placements.isEmpty, let saved = (try? PersistedState.load(from: Paths.stateFile)) ?? nil {
                    state.placements = saved.placements; state.movedApps = saved.movedApps
                }
                try state.save(to: Paths.stateFile)
            } catch {
                Self.log.error("final state save failed: \(String(describing: error), privacy: .public)")
            }
            Self.log.info("restoring windows before exit")
            backend.restoreAllForTermination(
                world: e.world, displays: e.displays, observed: e.observed, stranded: e.stranded,
                parked: e.parked, deadline: Self.restoreBudget)
        }

        // `AXWindowBackend.stop()` is main-actor isolated. On the main thread we are already there;
        // from the signal queue we have to hop, and the main actor is free to answer.
        if onMainThread {
            MainActor.assumeIsolated { backend.stop() }
        } else {
            run(Self.teardownBudget, onMainThread: false) { await MainActor.run { backend.stop() } }
        }
        run(Self.teardownBudget, onMainThread: onMainThread) { await store.stop() }
        Self.log.info("terminated cleanly")
    }

    /// A timed-out export must not mean "leave every window in its parking corner" — that is the
    /// one outcome §7.4 exists to prevent, and it would happen precisely when the store is busiest.
    /// The last world `onChange` published is at most one command stale and describes the same
    /// parked windows. `observed` is empty, so the restore uses its own fallback size: a window at
    /// a sensible size in the middle of the screen beats a 1×32 sliver in a corner.
    ///
    /// `parked` is every placed window, i.e. this path keeps centring *everything*. Which windows
    /// are parked lives only in the store's side tables, and the published world does not carry
    /// it — so the choice is between scrambling a tiled layout and leaving a parked window in its
    /// corner, and §7.4 is unambiguous about which of those is worse. The real export, which knows,
    /// moves only the parked ones; this is the degraded path when the store could not answer.
    private func fallbackExport(onMainThread: Bool) -> TerminationExport? {
        lock.lock(); let world = lastWorld; lock.unlock()
        guard let world, let displays = currentDisplays(onMainThread: onMainThread), !displays.isEmpty else {
            Self.log.error("no fallback world or no displays; windows are left where they are")
            return nil
        }
        let placed = Set(world.screens.values.flatMap { $0.workspaces.flatMap(\.windows) })
        return (world: world, displays: displays, observed: [:], stranded: [:], parked: placed, placements: [:], movedApps: [])
    }

    /// `DisplayTopology.current()` is `@MainActor`. On the main thread we are already there; from
    /// the signal queue the main actor is free, so the hop is bounded and cheap.
    private func currentDisplays(onMainThread: Bool) -> [DisplayInfo]? {
        if onMainThread { return MainActor.assumeIsolated { DisplayTopology.current() } }
        let displays = Box<[DisplayInfo]>()
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            displays.value = await MainActor.run { DisplayTopology.current() }
            done.signal()
        }
        guard done.wait(timeout: .now() + Self.teardownBudget) == .success else { return nil }
        return displays.value
    }

    private func run(
        _ budget: TimeInterval, onMainThread: Bool, _ body: @escaping @Sendable () async -> Void,
    ) {
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            await body()
            done.signal()
        }
        _ = wait(done, budget, onMainThread: onMainThread)
    }

    /// Ruling 10's bridge: a bounded `Task` + `DispatchSemaphore`. With one refinement for the
    /// main-thread path (`applicationWillTerminate`, which is how a bundled app is told about a
    /// logout): the store can only answer once its in-flight work finishes, and that work — a
    /// refresh session — hops through the **main actor**. Blocking the main thread outright is
    /// therefore the one sure way to *cause* the timeout we are guarding against, and the cost of
    /// that timeout is every window left in its parking corner. So on the main thread the wait is
    /// sliced, and the main run loop (which is what drains the main actor) is serviced in between.
    /// Same total budget either way.
    private func wait(_ semaphore: DispatchSemaphore, _ budget: TimeInterval, onMainThread: Bool) -> Bool {
        guard onMainThread else { return semaphore.wait(timeout: .now() + budget) == .success }
        let deadline = Date(timeIntervalSinceNow: budget)
        while Date() < deadline {
            // The 5 ms semaphore wait is also what paces the loop — `RunLoop.run(before:)` returns
            // immediately when there is nothing to service, and must not be allowed to spin.
            if semaphore.wait(timeout: .now() + .milliseconds(5)) == .success { return true }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        return semaphore.wait(timeout: .now()) == .success
    }
}

/// What `WorldStore.exportForTermination()` hands back.
private typealias TerminationExport = (
    world: World, displays: [DisplayInfo], observed: [WindowRef: CGRect], stranded: [WindowRef: CGRect],
    parked: Set<WindowRef>, placements: [String: UUID], movedApps: Set<String>
)

/// A one-shot handoff out of a `Task` into a semaphore-blocked thread.
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
