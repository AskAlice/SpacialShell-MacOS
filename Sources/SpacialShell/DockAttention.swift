import Foundation
import SpacialShellKit
import SpacialShellPlatform

/// #126 (G35): the Dock poll (`DockWatcher`, platform) feeding `AttentionTracker` (Kit), and the
/// result handed to the panels. Polls only while the marks can be seen: `dock-attention` on and the
/// panels showing (not Zen, not `show-panels = false`). A `Watcher` (#172): `apply` and `observe`
/// start and stop the poll between them, so `start` has nothing left to do.
@MainActor
final class DockAttention: Watcher {
    private var watcher: DockWatcher?
    private var tracker = AttentionTracker()
    private var enabled = false
    private var panelsShown = true
    private var focused: Int32?
    private let onChange: (Set<Int32>) -> Void

    init(onChange: @escaping (Set<Int32>) -> Void) {
        self.onChange = onChange
    }

    func apply(_ config: Config) {
        enabled = config.dockAttention && config.showPanels
        poll()
    }

    func start() {}

    /// The focused window's app has been seen; Zen hides the marks, so it stops the poll too.
    func observe(_ world: World) {
        focused = world.focus.window?.pid
        tracker.focus(focused, now: Self.now)
        panelsShown = !world.zen
        poll()
        publish()
    }

    /// On quit: the poll stops, and a world still in flight does not restart it. The marks are left
    /// as they are; the panels go with the process.
    func stop() {
        enabled = false
        watcher?.stop()
        watcher = nil
    }

    /// Starts or stops the poll to match whether the marks can be seen.
    private func poll() {
        let on = enabled && panelsShown
        if on, watcher == nil {
            let w = DockWatcher { [weak self] sample in
                Task { @MainActor in self?.feed(sample) }
            }
            w.start()
            watcher = w
        } else if !on, let w = watcher {
            w.stop()
            watcher = nil
            tracker = AttentionTracker()
            tracker.focus(focused, now: Self.now)
            onChange([])
        }
    }

    private func feed(_ sample: DockSample) {
        guard watcher != nil else { return }   // a sample already in flight when the poll stopped
        tracker.feed(sample, now: Self.now)
        publish()
    }

    private func publish() {
        guard watcher != nil else { return }
        onChange(tracker.wanting(now: Self.now))
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
