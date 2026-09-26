import AppKit
import SwiftUI
import SpacialShellKit

/// #130 (M3 B7): the alert a problem that `interrupts` opens when it first appears — the hotkeys
/// or the control socket failing to start, which used to be log lines. The same `Problem` stays
/// listed under the rail cog; this is only how the user first hears of it.
///
/// A window rather than `NSAlert.runModal()`: a modal alert blocks the main thread, and the main
/// thread is what drives every window move. The shell keeps working while this is up.
struct ProblemAlertView: View {
    let problem: Problem
    /// Alerts still queued behind this one, so "OK" is not a surprise when another follows.
    let queued: Int
    /// `true` when "Don't warn again" was ticked (#138; only offered where `canSilence`).
    let dismiss: (_ silence: Bool) -> Void
    @State private var silence = false

    static let width: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: ProblemsList.symbol(problem.severity))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 28))
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text(problem.title).font(.system(size: 13, weight: .semibold))
                    Text(problem.message)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(problem.canSilence
                         ? "Until then it is listed under the rail's settings button."
                         : "It stays listed under the rail's settings button until it is fixed.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                if problem.canSilence {
                    Toggle("Don't warn again", isOn: $silence)
                        .toggleStyle(.checkbox).font(.system(size: 11))
                        .padding(.leading, 50)
                }
                if queued > 0 {
                    Text(queued == 1 ? "1 more" : "\(queued) more")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(queued > 0 ? "Next" : "OK") { dismiss(silence) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Queues the problems `ProblemAlerts` says are due and shows them one at a time. Fed the whole
/// problem list on every change, like the rail's badge.
@MainActor
public final class ProblemAlertController: NSObject, NSWindowDelegate {
    /// #138: "Don't warn again" was ticked on the alert for this problem key.
    public var onSilence: (String) -> Void = { _ in }
    private var alerts = ProblemAlerts()
    private var queue: [Problem] = []
    private var shown: Problem?
    private var window: NSWindow?

    public override init() {}

    public func update(problems: [Problem]) {
        // A queued alert whose problem has since gone is news about nothing: drop it. The one on
        // screen stays until dismissed — pulling it from under the pointer would be worse.
        let live = Set(problems.map(\.key))
        queue.removeAll { !live.contains($0.key) }
        queue += alerts.due(in: problems)
        if shown == nil { showNext() } else { redraw() }
    }

    private func showNext() {
        guard !queue.isEmpty else { close(); return }
        shown = queue.removeFirst()
        redraw()
    }

    private func redraw() {
        guard let shown else { return }
        let view = ProblemAlertView(problem: shown, queued: queue.count) { [weak self] silence in
            if silence { self?.onSilence(shown.key) }
            self?.showNext()
        }
        if let window, let host = window.contentView as? NSHostingView<ProblemAlertView> {
            // Same alert (the queue count moved): keep the view, and a ticked box with it. A new
            // alert gets a new host, so its "Don't warn again" starts unticked.
            if host.rootView.problem.key == shown.key {
                host.rootView = view
            } else {
                window.contentView = NSHostingView(rootView: view)
            }
            window.setContentSize(window.contentView?.fittingSize ?? host.fittingSize)
            return
        }
        let host = NSHostingView(rootView: view)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "SpacialShell"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = host
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func close() {
        shown = nil
        window?.delegate = nil
        window?.close()
        window = nil
    }

    /// The close button is "OK" for everything queued: the user has seen that there are problems,
    /// and the rest are listed under the cog.
    public func windowWillClose(_ notification: Notification) {
        queue.removeAll()
        shown = nil
        window = nil
    }
}
