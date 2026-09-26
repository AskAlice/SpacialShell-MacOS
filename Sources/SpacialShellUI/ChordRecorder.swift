import AppKit
import SwiftUI
import SpacialShellKit

/// Press a chord, get a chord. The only honest way to ask for a keybinding — typing `fn-shift-a`
/// into a text field asks the user to know our spelling of every key.
///
/// It captures with a **local** monitor, which only sees events aimed at this app's key window.
/// A global tap here would fight the shell's own hotkey tap for the very chord being recorded.
struct ChordRecorder: NSViewRepresentable {
    let onCapture: (Chord) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = CaptureView()
        v.onCapture = onCapture
        v.onCancel = onCancel
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? CaptureView else { return }
        v.onCapture = onCapture
        v.onCancel = onCancel
    }

    final class CaptureView: NSView {
        var onCapture: ((Chord) -> Void)?
        var onCancel: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Torn down on leaving the window rather than in deinit: the monitor token is `Any?`,
            // which a nonisolated deinit is not allowed to touch under strict concurrency.
            if window == nil { stop() } else { start() }
        }

        private func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // Escape cancels rather than binding: a user who opened this by mistake needs a
                // way out that is not itself a keybinding.
                if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                    self.onCancel?()
                    return nil
                }
                let f = event.modifierFlags
                let chord = Chord(keyCode: event.keyCode,
                                  // As `HotkeyTap.chord` (#31): macOS flags every arrow with fn,
                                  // and the tap ignores it there, so a recorded one must too.
                                  fn: f.contains(.function) && !(123...126).contains(event.keyCode),
                                  control: f.contains(.control),
                                  option: f.contains(.option),
                                  shift: f.contains(.shift),
                                  command: f.contains(.command))
                // A bare key is a real binding the shell would swallow globally, so it is refused
                // here rather than discovered later when "w" stops typing.
                guard chord.fn || chord.control || chord.option || chord.command else { return nil }
                self.onCapture?(chord)
                return nil   // swallow it; this keystroke was the answer, not input
            }
        }

        private func stop() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
    }
}
