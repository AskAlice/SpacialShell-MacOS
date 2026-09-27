import Foundation

/// #184: the bound chords the hotkey tap swallows before the store is running.
///
/// The tap is armed first thing in boot: while no tap exists, every bound chord reaches macOS
/// instead (Globe+S opens Type to Siri). But the store it drives only runs a few seconds later,
/// after the first AX snapshot and adoption. A chord pressed in between is held here, as the command
/// it was bound to when pressed, and replayed in press order once the store runs. One older than
/// `maxAge` by then is dropped: stale navigation is worse than none. After `ready`, every chord
/// passes straight through.
///
/// Pure: the clock is injected, and nothing here is thread-safe on its own (`HotkeyOutlet` holds
/// one under its lock).
public struct EarlyChords: Sendable {
    public static let maxAge = Duration.seconds(2)

    /// What `ready` hands back: the commands to run now, in press order, and how many went stale.
    public struct Replay: Equatable, Sendable {
        public let commands: [Command]
        public let dropped: Int

        public init(commands: [Command], dropped: Int) {
            self.commands = commands
            self.dropped = dropped
        }
    }

    public private(set) var isReady = false
    private var held: [(command: Command, pressed: ContinuousClock.Instant)] = []
    /// Chords let go before `ready` because they were already stale; they count as dropped.
    private var expired = 0
    private let now: @Sendable () -> ContinuousClock.Instant

    public init(now: @escaping @Sendable () -> ContinuousClock.Instant) {
        self.now = now
    }

    /// How many chords are held. For tests and the log.
    public var heldCount: Int { held.count }

    /// A bound chord's command, as the tap fires it. Returns it when it should run now; nil when it
    /// is held for `ready`.
    public mutating func receive(_ command: Command) -> Command? {
        guard !isReady else { return command }
        let at = now()
        // A boot that hangs must not grow this without bound: what is already stale goes now.
        // Presses arrive in time order, so the stale ones are always at the front.
        let stale = held.prefix { at - $0.pressed > Self.maxAge }.count
        held.removeFirst(stale)
        expired += stale
        held.append((command, at))
        return nil
    }

    /// The store is running. Returns the held commands still fresh, in press order, and from now on
    /// `receive` passes every command straight through. A second call has nothing to replay.
    public mutating func ready() -> Replay {
        let at = now()
        let fresh = held.filter { at - $0.pressed <= Self.maxAge }.map(\.command)
        let replay = Replay(commands: fresh, dropped: expired + held.count - fresh.count)
        held = []
        expired = 0
        isReady = true
        return replay
    }
}

/// #184: what the hotkey tap's callbacks go to. The tap is armed at stage 2b of boot; what they
/// drive (the store through `route`, the cheat sheet, the spatial view, the backend's human-input
/// mark) exists from stage 7. Until `connect`, a command is held by `EarlyChords` and the rest (flag
/// changes, keyDowns, autorepeats) is dropped: none of them means anything to a shell not yet up.
///
/// Every method but `connect` is called on the tap thread, inside the event tap's deadline, and
/// returns at once. `Flags` is the tap's modifier-flags type; generic so Kit stays free of
/// CoreGraphics' event types.
public final class HotkeyOutlet<Flags: Sendable>: @unchecked Sendable {
    public struct Handlers: Sendable {
        public var command: @Sendable (Command) -> Void
        public var flags: @Sendable (Flags) -> Void
        public var keyDown: @Sendable () -> Void
        public var repeated: @Sendable (Command) -> Void

        public init(
            command: @escaping @Sendable (Command) -> Void,
            flags: @escaping @Sendable (Flags) -> Void,
            keyDown: @escaping @Sendable () -> Void,
            repeated: @escaping @Sendable (Command) -> Void,
        ) {
            self.command = command
            self.flags = flags
            self.keyDown = keyDown
            self.repeated = repeated
        }
    }

    private let lock = NSLock()
    private var early: EarlyChords
    private var handlers: Handlers?

    public init(now: @escaping @Sendable () -> ContinuousClock.Instant) {
        early = EarlyChords(now: now)
    }

    public func command(_ command: Command) {
        // The handler runs outside the lock; `connect` replays under it, so a chord pressed during
        // the replay waits here and runs after it, never before.
        let (run, handlers) = lock.withLock { (early.receive(command), self.handlers) }
        if let run, let handlers { handlers.command(run) }
    }

    public func flags(_ flags: Flags) { lock.withLock { handlers }?.flags(flags) }
    public func keyDown() { lock.withLock { handlers }?.keyDown() }
    public func repeated(_ command: Command) { lock.withLock { handlers }?.repeated(command) }

    /// Once, when the store is running: replays the held commands through `handlers.command`, in
    /// press order, and from then on every callback goes straight to `handlers`. A second call
    /// changes nothing and replays nothing.
    @discardableResult
    public func connect(_ handlers: Handlers) -> EarlyChords.Replay {
        lock.withLock {
            guard self.handlers == nil else { return EarlyChords.Replay(commands: [], dropped: 0) }
            self.handlers = handlers
            let replay = early.ready()
            for command in replay.commands { handlers.command(command) }
            return replay
        }
    }
}
