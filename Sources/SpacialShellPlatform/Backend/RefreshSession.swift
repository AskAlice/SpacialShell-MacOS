import AppKit
import CoreGraphics
import SpacialShellKit
import struct SpacialShellKit.WindowRef

/// Builds one `Snapshot` from every regular app (plus any accessory already in the registry).
/// Spec §7.6: every event coalesces into a session like this one; the newest session wins.
///
/// `@MainActor` because it reads `NSWorkspace` and `NSScreen`; the per-app AX work it awaits
/// happens on each app's own thread, and the main actor is free while it waits.
struct RefreshSession {
    let apps: AXAppRegistry

    @MainActor func run() async -> Snapshot {
        let displays = DisplayTopology.current()
        let workspace = NSWorkspace.shared
        let allRunning = workspace.runningApplications
        // Ruling 7 (belt and braces): `AXApp.getOrCreate` refuses these two as well — AX requests
        // to our own pid deadlock, and loginwindow's "windows" are the lock screen's (spec §7.1).
        let mine = ProcessInfo.processInfo.processIdentifier
        let regular = allRunning.filter {
            $0.activationPolicy == .regular
                && $0.processIdentifier != mine
                && $0.bundleIdentifier != loginwindowBundleId
        }

        var infos: [AppInfo] = []
        var windows: [WindowSnapshot] = []
        var visited: Set<pid_t> = []
        for nsApp in regular {
            guard let app = apps.getOrCreate(nsApp) else { continue }
            visited.insert(app.pid)
            infos.append(AppInfo(pid: app.pid, bundleID: app.bundleID, isHidden: nsApp.isHidden))
            windows += await app.snapshotWindows()
        }
        // An app already in the registry that has since dropped out of `.regular` (Photos' media
        // helpers, apps that flip to `.accessory` while their windows are still open) keeps being
        // observed until its process exits — dropping it here would read as "every window closed".
        let aliveByPid = Dictionary(allRunning.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        for app in apps.all() where !visited.contains(app.pid) {
            guard let nsApp = aliveByPid[app.pid] else { continue }
            visited.insert(app.pid)
            infos.append(AppInfo(pid: app.pid, bundleID: app.bundleID, isHidden: nsApp.isHidden))
            windows += await app.snapshotWindows()
        }

        // Ruling 8: only pids that have left the process table are reaped — an app that is merely
        // not `.regular` is still alive and still ours to talk to.
        apps.reapTerminated(alive: Set(aliveByPid.keys))

        let front = workspace.frontmostApplication
        let focused = await front.flatMap { apps.get($0.processIdentifier) }?.focusedWindowRef()
        return Snapshot(
            displays: displays,
            apps: infos,
            windows: windows,
            focused: focused,
            loginwindowFrontmost: front?.bundleIdentifier == loginwindowBundleId,
        )
    }
}

/// pid → `AXApp`, owned by the backend. Deviation from the brief: the map itself is `AXApp`'s
/// (spec §7.1 — the same map `getOrCreate` dedupes against and the AX notification callback routes
/// through), so this type holds no storage of its own, only the two things every app needs at
/// creation time. A second map would keep handing out apps whose run loop had already exited.
///
/// Thread-safe by construction: both stored properties are immutable and `Sendable`, and every
/// call forwards into `AXApp`'s lock-guarded registry. AX threads call `onEvent` from arbitrary
/// threads.
final class AXAppRegistry: Sendable {
    let timeoutMs: Int
    private let onEvent: @Sendable (pid_t, AXAppEvent) -> Void

    init(timeoutMs: Int, onEvent: @escaping @Sendable (pid_t, AXAppEvent) -> Void) {
        self.timeoutMs = timeoutMs
        self.onEvent = onEvent
    }

    func get(_ pid: pid_t) -> AXApp? { AXApp.registered(pid) }

    /// Returns nil for our own pid and for loginwindow (spec §7.1), and for an app whose AX
    /// application element could not be created.
    func getOrCreate(_ nsApp: NSRunningApplication) -> AXApp? {
        let pid = nsApp.processIdentifier
        return AXApp.getOrCreate(nsApp, timeoutMs: timeoutMs, onEvent: { [onEvent] event in onEvent(pid, event) })
    }

    func all() -> [AXApp] { AXApp.allRegistered() }

    func reapTerminated(alive: Set<pid_t>) { AXApp.reapTerminated(alive: alive) }
}
