import AppKit
import Carbon.HIToolbox
import os
import SpacialShellKit
import struct SpacialShellProtocol.WindowRef

/// #193: while another app holds Secure Event Input, no key-down reaches the hotkey tap, so the
/// tap itself can never notice. This polls for it apart from key events and lists a Problem naming
/// the window asking for a password (`SecureInputWatch`), cleared once secure input is off. #195:
/// the windows with a focused password field also go to `onPrompts`, so the store never leaves
/// one parked out of sight (title matches only name a window; they never move one).
///
/// Every `interval`: `IsSecureEventInputEnabled()`, which is cheap. Only while it is on, every app
/// is asked for a password prompt (`AXApp.passwordPrompt`), concurrently, each bounded by its AX
/// messaging timeout — and less often the longer nothing changes, since Terminal's Secure Keyboard
/// Entry can stay on all day. Not `kCGSSessionSecureInputPID`: it follows the frontmost app, not
/// the one that turned secure input on. Not while the screen is locked: the lock screen holds it.
@MainActor
public final class SecureInputWatcher {
    private static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "hotkeys")
    static let interval: TimeInterval = 2

    private let problems: ProblemCenter
    /// The world as the store has it now, for the workspace names: pulled per scan, never cached.
    private let world: @Sendable () async -> World
    /// Called after every scan, changed or not: the store dedupes, and may not have placed a
    /// window the last report named.
    private let onPrompts: @MainActor ([WindowRef]) -> Void
    private var watch = SecureInputWatch()
    private var timer: Timer?
    private var scanning = false
    /// While secure input stays on and scans find the same thing, the gap between scans doubles:
    /// 2, 4, 8, then 16 s. Secure input turning off is still seen at the next tick.
    private var unchangedScans = 0
    private var ticksToSkip = 0

    public init(problems: ProblemCenter = .shared, world: @escaping @Sendable () async -> World,
                onPrompts: @escaping @MainActor ([WindowRef]) -> Void = { _ in }) {
        self.problems = problems
        self.world = world
        self.onPrompts = onPrompts
    }

    private func poll() {
        guard !scanning, !Self.screenLocked() else { return }
        let on = IsSecureEventInputEnabled()
        if !on { unchangedScans = 0; ticksToSkip = 0 }
        guard on || !watch.listed.isEmpty else { return }   // off, and nothing listed to clear
        if on, ticksToSkip > 0 { ticksToSkip -= 1; return }
        scanning = true
        Task {
            var found = on ? await Self.passwordPrompts() : []
            for i in found.indices { found[i].app = NSRunningApplication(processIdentifier: found[i].ref.pid)?.localizedName }
            let world = await self.world()
            scanning = false
            guard timer != nil else { return }   // stopped while it scanned
            let changed = report(on: on, found, world)
            onPrompts(found.filter(\.secureField).map(\.ref))
            unchangedScans = changed ? 0 : unchangedScans + 1
            ticksToSkip = (1 << min(unchangedScans, 3)) - 1
        }
    }

    private func report(on: Bool, _ found: [SecureInputCandidate], _ world: World) -> Bool {
        guard let listed = watch.observe(on: on, candidates: found, world: world) else { return false }
        if !on {
            Self.log.notice("secure input off")
        } else if found.isEmpty {
            Self.log.notice("secure input on; no window asking for a password found")
        }
        for c in found {
            Self.log.notice("secure input on; \(c.app ?? "?", privacy: .public) pid=\(c.ref.pid, privacy: .public) window=\(c.ref.id, privacy: .public) '\(c.title, privacy: .public)' \(c.secureField ? "has a focused password field" : "is titled like a password prompt", privacy: .public)")
        }
        problems.replace(prefix: Problem.Key.secureInput, with: listed)
        return true
    }

    /// Sorted, so the same prompts in another order are not a change.
    static func passwordPrompts() async -> [SecureInputCandidate] {
        await withTaskGroup(of: SecureInputCandidate?.self) { group in
            for app in AXApp.allRegistered() { group.addTask { await app.passwordPrompt() } }
            var found: [SecureInputCandidate] = []
            for await c in group { if let c { found.append(c) } }
            return found.sorted { ($0.ref.pid, $0.ref.id) < ($1.ref.pid, $1.ref.id) }
        }
    }

    static func screenLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

/// #172: started with the other watchers; `stop` on quit ends the polling and takes the entry down.
extension SecureInputWatcher: Watcher {
    public func apply(_ config: Config) {}

    public func start() {
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        problems.replace(prefix: Problem.Key.secureInput, with: [])
    }
}
