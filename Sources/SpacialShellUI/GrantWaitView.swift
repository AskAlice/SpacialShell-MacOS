import AppKit
import SwiftUI
import SpacialShellKit

/// #130 (M3 B7): what a first launch shows until the Accessibility grant lands. Without it the
/// wait was a silent hang — no rail, no windows moving, and a log line nobody reads.
///
/// Props in, closures out: `GrantWait` is the state (Kit), and the two buttons are the app's.
struct GrantWaitView: View {
    let wait: GrantWait
    let openSettings: () -> Void
    let quit: () -> Void

    static let width: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "accessibility")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Text("SpacialShell needs Accessibility access")
                        .font(.system(size: 13, weight: .semibold))
                    Text("It moves and resizes windows through Accessibility, so nothing can be arranged until you allow it. In System Settings › Privacy & Security › Accessibility, switch SpacialShell on. This window closes by itself once it is on.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if wait.suspectsStaleGrant {
                        Text("Already on? After an update the switch can stay on and do nothing. Select SpacialShell in that list, remove it with −, then switch it back on.")
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(wait.status)
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.leading, 54)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Quit", action: quit)
                Button("Open System Settings…", action: openSettings)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The window around `GrantWaitView`: an ordinary titled window, since it has buttons to click and
/// the app has nothing else on screen yet. It has no close button: closing it would bring back the
/// silent hang it exists to end, so the ways out are the grant and Quit.
@MainActor
public final class GrantWaitController {
    private var window: NSWindow?
    private let openSettings: () -> Void
    private let quit: () -> Void

    public init(openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.openSettings = openSettings
        self.quit = quit
    }

    /// Shows the window on the first call, and redraws it on every later one (once a second).
    public func update(_ wait: GrantWait) {
        let view = GrantWaitView(wait: wait, openSettings: openSettings, quit: quit)
        if let window, let host = window.contentView as? NSHostingView<GrantWaitView> {
            host.rootView = view
            window.setContentSize(host.fittingSize)
            return
        }
        let host = NSHostingView(rootView: view)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "SpacialShell"
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.center()
        window = w
        // An accessory app's window only comes forward, and takes clicks, once the app is active.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    public func close() {
        window?.close()
        window = nil
    }
}
