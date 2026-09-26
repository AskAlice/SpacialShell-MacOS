import Foundation

/// #109 (M3 B1, the user-visible half): something the shell cannot do right now and the user can
/// fix — a config it refused, a missing grant, a window it cannot move. Not a log line: each one
/// stays listed (rail cog badge, `spacialctl state`) until the condition it names is gone.
public struct Problem: Codable, Equatable, Sendable, Identifiable {
    /// `error`: something the user asked for is not happening (their config, their hotkeys).
    /// `warning`: the shell works, with less (no previews, a window left alone).
    public enum Severity: String, Codable, Sendable, Comparable {
        case warning, error
        public static func < (a: Self, b: Self) -> Bool { a == .warning && b == .error }
    }

    /// The de-duplication key: one entry per key, and clearing a key is how a fix is recorded.
    public var key: String
    public var severity: Severity
    public var message: String
    public var id: String { key }

    public init(key: String, severity: Severity, message: String) {
        self.key = key; self.severity = severity; self.message = message
    }
}

extension Problem {
    public enum Key {
        public static let config = "config"
        /// #133: keys the file sets that nothing reads. A warning, apart from `config`: the file loaded.
        public static let configUnknownKeys = "config.unknown-keys"
        public static let accessibility = "grant.accessibility"
        /// Both the missing grant and a declined capture (#92): the same fix, so one entry.
        public static let screenRecording = "grant.screen-recording"
        public static let hotkeys = "hotkeys"
        public static let controlSocket = "control-socket"
        public static let telemetry = "telemetry"
        /// Followed by the app's bundle id (or `pid:<n>`): one entry per app, not per window.
        public static let axWritePrefix = "ax-write:"
    }

    public static func configInvalid(_ detail: String) -> Problem {
        Problem(key: Key.config, severity: .error,
                message: "config.toml has an error, so the previous config is still in use: \(detail)")
    }
    public static func configUnknownKeys(_ keys: [String]) -> Problem {
        Problem(key: Key.configUnknownKeys, severity: .warning,
                message: "config.toml has keys SpacialShell doesn't know, so they were skipped: \(keys.joined(separator: ", ")). Check the spelling; the rest of the file is in use.")
    }
    public static let accessibilityMissing = Problem(
        key: Key.accessibility, severity: .error,
        message: "Accessibility access is off, so no window can be arranged. Turn it on in System Settings › Privacy & Security.")
    public static let screenRecordingMissing = Problem(
        key: Key.screenRecording, severity: .warning,
        message: "Screen Recording is off or was declined: hover previews show icons and workspace switches don't animate.")
    public static func hotkeysInactive(_ detail: String) -> Problem {
        Problem(key: Key.hotkeys, severity: .error, message: "Hotkeys are off: the keyboard tap could not start (\(detail)).")
    }
    public static func controlSocketInactive(_ detail: String) -> Problem {
        Problem(key: Key.controlSocket, severity: .warning, message: "spacialctl and Raycast can't reach the shell: \(detail)")
    }
    /// The detail is left out on purpose: every failed batch would otherwise be a new message, and a
    /// new message is a change the UI redraws for. With a fixed text, repeats de-duplicate.
    public static func telemetryFailing(host: String) -> Problem {
        Problem(key: Key.telemetry, severity: .warning, message: "Traces aren't reaching \(host). See the telemetry log for why.")
    }
    public static func axWriteFailing(app: String) -> Problem {
        Problem(key: Key.axWritePrefix + app, severity: .warning,
                message: "\(app) refuses to be moved or resized, so its windows are left where they are until they change.")
    }
}

/// The current problems: keyed, de-duplicated, cleared on fix. Pure — `ProblemCenter` holds the
/// shared one.
public struct Problems: Equatable, Sendable {
    private var byKey: [String: Problem] = [:]
    public init() {}

    /// Errors first, then by key, so the list is stable between redraws.
    public var all: [Problem] {
        byKey.values.sorted { $0.severity != $1.severity ? $0.severity > $1.severity : $0.key < $1.key }
    }
    public var isEmpty: Bool { byKey.isEmpty }

    /// Adds or replaces the entry for `problem.key`. Returns whether anything changed: reporting the
    /// same problem again is a no-op, which is what keeps a repeating failure from redrawing.
    @discardableResult
    public mutating func report(_ problem: Problem) -> Bool {
        guard byKey[problem.key] != problem else { return false }
        byKey[problem.key] = problem
        return true
    }

    @discardableResult
    public mutating func clear(_ key: String) -> Bool {
        byKey.removeValue(forKey: key) != nil
    }

    /// Makes the entries under `prefix` exactly `current`: for a source that knows its whole set at
    /// once (the store's retired windows), so what is fixed clears without tracking each fix.
    @discardableResult
    public mutating func replace(prefix: String, with current: [Problem]) -> Bool {
        var next = byKey.filter { !$0.key.hasPrefix(prefix) }
        for p in current where p.key.hasPrefix(prefix) { next[p.key] = p }
        guard next != byKey else { return false }
        byKey = next
        return true
    }
}

/// The one shared list. Sources are everywhere — the boot path, the store actor, the capture gate,
/// the telemetry exporter's HTTP thread — so it is a lock rather than an actor: reporting never
/// awaits. `onChange` runs only when the list actually changed, on the reporter's thread.
public final class ProblemCenter: @unchecked Sendable {
    public static let shared = ProblemCenter()

    private let lock = NSLock()
    private var problems = Problems()
    private var observer: (@Sendable ([Problem]) -> Void)?

    public init() {}

    public var current: [Problem] { lock.withLock { problems.all } }

    /// Replaces the observer and calls it once with the current list.
    public func observe(_ f: @escaping @Sendable ([Problem]) -> Void) {
        let now = lock.withLock { observer = f; return problems.all }
        f(now)
    }

    public func report(_ problem: Problem) { mutate { $0.report(problem) } }
    public func clear(_ key: String) { mutate { $0.clear(key) } }
    public func replace(prefix: String, with current: [Problem]) { mutate { $0.replace(prefix: prefix, with: current) } }

    private func mutate(_ change: (inout Problems) -> Bool) {
        let published: (([Problem]) -> Void, [Problem])? = lock.withLock {
            guard change(&problems), let observer else { return nil }
            return (observer, problems.all)
        }
        if let (f, list) = published { f(list) }
    }
}
