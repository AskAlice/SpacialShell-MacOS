import Foundation

/// A running process, as the platform sees it: enough to match an `other-window-managers` entry.
public struct RunningProcess: Equatable, Sendable {
    /// Nil for a process with no bundle — a daemon such as yabai or skhd.
    public var bundleID: String?
    /// The executable's name (`proc_name`, or the bundle's executable).
    public var name: String
    /// What to call it in a message: the app's localized name when it has one.
    public var displayName: String?

    public init(bundleID: String?, name: String, displayName: String? = nil) {
        self.bundleID = bundleID; self.name = name; self.displayName = displayName
    }
}

/// #138 (G34): another window manager moving the same windows is two hands on one wheel — each
/// undoes the other, and it looks like a SpacialShell bug. So a running one is a warning.
///
/// The list is data (`other-window-managers` in config.toml). An entry matches a process by bundle
/// id exactly, or by executable name ignoring case, which is how the daemons with no bundle
/// (yabai, skhd) are found.
public enum OtherWindowManagers {
    /// AeroSpace, yabai (and skhd, the hotkey daemon that drives it), Amethyst, Rectangle, Magnet.
    public static let defaults = [
        "bobko.aerospace", "yabai", "skhd", "com.amethyst.Amethyst", "com.knollsoft.Rectangle",
        "com.crowdcafe.windowmagnet",
    ]

    /// The entries of `list` running among `processes`, each once, in list order, with the name
    /// to show for it.
    public static func running(_ list: [String], in processes: [RunningProcess]) -> [(entry: String, name: String)] {
        var out: [(entry: String, name: String)] = []
        for entry in list where !entry.isEmpty && !out.contains(where: { $0.entry == entry }) {
            let hit = processes.first { $0.bundleID == entry }
                ?? processes.first { $0.name.caseInsensitiveCompare(entry) == .orderedSame }
            if let hit { out.append((entry, hit.displayName ?? hit.name)) }
        }
        return out
    }

    /// What to list: one warning per running entry, minus the ones the user said "Don't warn
    /// again" to (`silenced`, problem keys). A silenced one is not listed either — it was a
    /// deliberate choice to run both, and a badge that never goes away would nag about it.
    public static func problems(list: [String], processes: [RunningProcess], silenced: Set<String>) -> [Problem] {
        running(list, in: processes)
            .map { Problem.otherWindowManager(entry: $0.entry, name: $0.name) }
            .filter { !silenced.contains($0.key) }
    }
}

extension Problem.Key {
    /// #138: followed by the `other-window-managers` entry that matched.
    public static let otherWindowManagerPrefix = "other-wm:"
}

extension Problem {
    public static func otherWindowManager(entry: String, name: String) -> Problem {
        Problem(key: Key.otherWindowManagerPrefix + entry, severity: .warning,
                message: "\(name) is running and also moves windows or takes hotkeys, so it and SpacialShell can fight over the same window or key. Quit one of them, or choose Don't warn again to keep both.")
    }
}
