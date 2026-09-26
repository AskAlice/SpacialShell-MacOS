import Foundation

/// #130 (M3 B7): the alert surface. Most problems are listed and wait to be looked at (the rail
/// cog's badge, `spacialctl state`). A few break something the user is about to reach for — the
/// hotkeys, `spacialctl` — and would otherwise be found only by pressing a key that does nothing.
/// Those also *interrupt*: once, in a window, when they first appear. The list stays the record;
/// the alert is only how the user hears about it.
extension Problem {
    /// Whether this problem opens an alert when it first appears, as well as being listed.
    public var interrupts: Bool {
        Self.interruptingKeys.contains(key) || Self.interruptingPrefixes.contains { key.hasPrefix($0) }
    }

    /// Whether its alert offers "Don't warn again" (#138). Only for a warning the user may
    /// reasonably choose to live with; an error means something they asked for is not happening,
    /// and silencing it would only hide that.
    public var canSilence: Bool {
        severity == .warning && Self.silenceablePrefixes.contains { key.hasPrefix($0) }
    }

    /// The alert's headline; the message is its body. General on purpose: each message already
    /// opens by naming what broke, and a headline saying it again reads as a stutter.
    public var title: String {
        if key.hasPrefix(Key.otherWindowManagerPrefix) { return "Another window manager is running" }
        return severity == .error ? "Part of SpacialShell didn't start" : "SpacialShell needs your attention"
    }

    static let interruptingKeys: Set<String> = [Key.hotkeys, Key.controlSocket]
    static let interruptingPrefixes: [String] = [Key.otherWindowManagerPrefix]
    static let silenceablePrefixes: [String] = [Key.otherWindowManagerPrefix]
}

/// Which problems to alert about now. Pure: the app feeds it every change of the problem list and
/// shows what comes back.
///
/// Each key alerts **once per launch**. A problem that clears and comes back does not alert again —
/// it is listed again, which is enough for something the user has already been told about, and a
/// flapping condition would otherwise open a window every time it flapped.
public struct ProblemAlerts: Equatable, Sendable {
    public private(set) var announced: Set<String> = []

    public init() {}

    /// The problems in `current` that should alert now, in `current`'s order (errors first), each
    /// then counted as announced.
    public mutating func due(in current: [Problem]) -> [Problem] {
        let due = current.filter { $0.interrupts && !announced.contains($0.key) }
        announced.formUnion(due.map(\.key))
        return due
    }
}
