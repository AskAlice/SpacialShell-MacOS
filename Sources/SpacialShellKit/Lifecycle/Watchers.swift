/// #172: one lifecycle for the runtime's watchers — the hotkey tap, trackpad gestures, focus follows
/// the mouse, the Dock's attention marks and the other-window-manager watch. Each watches something
/// outside the shell (an event tap, the Dock, the running processes) and turns it into commands or
/// Problems; the runtime only starts them, hands them the config and the world, and stops them.
///
/// The UI controllers are not watchers: they draw, and keep the runtime's own update calls.
@MainActor
public protocol Watcher: AnyObject {
    /// The config, mapped to this watcher's own settings. Runs once before `start`, with the boot
    /// config, and again on **every** config push, changed or not (a "Don't warn again" changes
    /// settings.json and not the config), so it must be idempotent.
    func apply(_ config: Config)
    /// Once, right after the first `apply`. Throwing leaves the watcher off for the session.
    func start() throws
    /// Every world the store publishes. Defaults to ignoring it.
    func observe(_ world: World)
    /// Terminal. Runs on quit.
    func stop()
}

public extension Watcher {
    func observe(_ world: World) {}
}

/// The running watchers, in start order.
///
/// Each is started where the runtime registers it, so boot keeps its stage order: a watcher may
/// need something an earlier stage built (the Dock marks draw on the shell panels). The hotkey tap
/// needs nothing but the config, so it comes up first, before the store; what it fires before the
/// store runs is held and replayed (#184, `HotkeyOutlet`). A watcher that fails to start is logged
/// and left out of everything after, and the rest carry on — a dead hotkey tap must not also take
/// the trackpad.
/// `stop` runs every stop once, in reverse start order.
@MainActor
public final class Watchers {
    private var running: [any Watcher] = []
    private var stopped = false
    private let log: (String) -> Void

    /// `log` gets a line for each watcher that fails to start.
    public init(log: @escaping (String) -> Void) {
        self.log = log
    }

    /// Applies `config` and starts `watcher` now. `name` is for the log. Returns the error when it
    /// failed to start, so the caller can list a Problem. After `stop`, nothing starts: a boot still
    /// under way when the quit came must not arm a watcher that nobody will stop.
    @discardableResult
    public func start(_ watcher: any Watcher, _ name: String, config: Config) -> (any Error)? {
        guard !stopped else { return nil }
        watcher.apply(config)
        do {
            try watcher.start()
        } catch {
            log("\(name) failed to start (\(String(describing: error))); it stays off")
            return error
        }
        running.append(watcher)
        return nil
    }

    public func apply(_ config: Config) {
        for watcher in running { watcher.apply(config) }
    }

    public func observe(_ world: World) {
        for watcher in running { watcher.observe(world) }
    }

    /// Idempotent: the quit can arrive by signal and then again by `applicationWillTerminate`.
    public func stop() {
        stopped = true
        let stopping = running
        running = []
        for watcher in stopping.reversed() { watcher.stop() }
    }
}
