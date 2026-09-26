import Foundation

/// #139 (G31): whether `state.json` is read and written. Pure; the app asks it before every read
/// and write, the termination save included.
///
/// Two inputs. `persist-state` (config, default on): off means the file is neither read at launch
/// nor written — it is left as it is, so turning the key back on picks up where it was. And a
/// **reset** (`spacialctl reset-state`, the settings window's button): the file is deleted and
/// nothing is written again until the next launch, which therefore starts fresh. The arrangement
/// on screen is kept for the rest of the session; re-tiling every window out from under the user
/// is not what "forget what you remember" asks for.
///
/// Neither touches the exit path's restore of parked windows (spec §7.4): that is about the
/// windows on screen now, not about what is remembered.
public struct StatePersistence: Equatable, Sendable {
    /// `persist-state`.
    public var enabled: Bool
    /// A reset happened this session.
    public private(set) var wasReset = false

    public init(enabled: Bool) { self.enabled = enabled }

    /// Read at launch: only when on. A reset cannot precede the launch read.
    public var reads: Bool { enabled }
    /// Write, debounced and at exit: when on and not reset since launch.
    public var writes: Bool { enabled && !wasReset }

    /// Marks the session reset. The caller deletes the file.
    public mutating func reset() { wasReset = true }
}

extension Problem.Key {
    /// #139: listed from a reset until the relaunch that makes it take effect.
    public static let stateReset = "state.reset"
}

extension Problem {
    /// A warning, not news: it names the one surprising consequence — nothing is saved until the
    /// relaunch — for as long as it holds.
    public static let stateReset = Problem(
        key: Key.stateReset, severity: .warning,
        message: "Saved state was reset: the windows stay where they are, nothing more is saved, and the next launch starts fresh. Quit and relaunch SpacialShell to start fresh now.")
}
