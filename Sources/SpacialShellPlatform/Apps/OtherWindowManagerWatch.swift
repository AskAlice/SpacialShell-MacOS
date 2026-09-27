import AppKit
import Darwin
import SpacialShellKit

/// #138 (G34): lists a warning while another window manager from `other-window-managers` runs.
///
/// Scans at start, whenever an app launches or quits, and when the list or the silenced set
/// changes. Public APIs only: `NSWorkspace.runningApplications` for apps (bundle id and name), and
/// libproc's `proc_listallpids` / `proc_name` for everything else — yabai and skhd run as bare
/// daemons that `NSWorkspace` does not list. A daemon started later with no app launching is
/// caught at the next app launch or quit, which is often enough for a warning.
@MainActor
public final class OtherWindowManagerWatch {
    private let problems: ProblemCenter
    /// The problem keys answered "Don't warn again". They live in settings.json, not in `Config`,
    /// so `apply` asks for them.
    private let silencedWarnings: @MainActor () -> Set<String>
    private var list: [String] = []
    private var silenced: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    public init(problems: ProblemCenter = .shared, silenced: @escaping @MainActor () -> Set<String> = { [] }) {
        self.problems = problems
        self.silencedWarnings = silenced
    }

    /// Watches app launches and quits; the first scan is `apply`'s.
    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan() }
            })
        }
    }

    /// A config reload or a "Don't warn again": rescans only when something changed.
    public func update(list: [String], silenced: Set<String>) {
        guard list != self.list || silenced != self.silenced else { return }
        self.list = list
        self.silenced = silenced
        scan()
    }

    public func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        problems.replace(prefix: Problem.Key.otherWindowManagerPrefix, with: [])
    }

    private func scan() {
        let current = list.isEmpty ? [] : OtherWindowManagers.problems(list: list, processes: Self.processes(),
                                                                       silenced: silenced)
        problems.replace(prefix: Problem.Key.otherWindowManagerPrefix, with: current)
    }

    /// Every process but this one: apps with their bundle id and name, the rest by executable name.
    static func processes() -> [RunningProcess] {
        let me = getpid()
        var out: [RunningProcess] = []
        var seen: Set<pid_t> = [me]
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != me {
            seen.insert(app.processIdentifier)
            out.append(RunningProcess(bundleID: app.bundleIdentifier,
                                      name: app.executableURL?.lastPathComponent ?? app.localizedName ?? "",
                                      displayName: app.localizedName))
        }
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return out }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)   // headroom for processes born meanwhile
        let filled = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        var name = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        for pid in pids.prefix(Int(max(0, filled))) where pid > 0 && !seen.contains(pid) {
            guard proc_name(pid, &name, UInt32(name.count)) > 0 else { continue }
            out.append(RunningProcess(bundleID: nil, name: String(cString: name)))
        }
        return out
    }
}

/// #172: the runtime's watcher lifecycle. `apply` runs on every config push, which is also how a
/// "Don't warn again" arrives; `update` rescans only when the list or the silenced set changed.
extension OtherWindowManagerWatch: Watcher {
    public func apply(_ config: Config) {
        update(list: config.otherWindowManagers, silenced: silencedWarnings())
    }
}
