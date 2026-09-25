import AppKit
import SwiftUI
import SpacialShellKit

/// The settings window. The first window this app owns that can take focus — every panel is a
/// non-activating `PanelWindow` that can never become key — so it is an ordinary titled window
/// and behaves like one.
///
/// The shell will not try to tile it: the backend drops its own pid before it enumerates anything
/// (`RefreshSession`, `AXApp`), so SpacialShell's windows are invisible to SpacialShell. It simply
/// floats where it is put, centred on first open.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var overrides: SettingsOverrides
    private var file: Config
    private let onChange: (SettingsOverrides) -> Void
    private let openConfigFile: () -> Void
    private let checkForUpdates: (() -> Void)?
    private let configPath: String

    public init(file: Config, overrides: SettingsOverrides,
                configPath: String,
                openConfigFile: @escaping () -> Void,
                checkForUpdates: (() -> Void)? = nil,
                onChange: @escaping (SettingsOverrides) -> Void) {
        self.file = file
        self.overrides = overrides
        self.configPath = configPath
        self.openConfigFile = openConfigFile
        self.checkForUpdates = checkForUpdates
        self.onChange = onChange
    }

    /// The file changed on disk while the window is open — the baseline every "Use file" returns
    /// to has moved, so re-render against it.
    public func update(file: Config) {
        self.file = file
        if window != nil { rebuild() }
    }

    /// Another editor of `settings.json` (the layouts popover and editor, #10) changed it.
    public func update(overrides: SettingsOverrides) {
        guard overrides != self.overrides else { return }
        self.overrides = overrides
        if window != nil { rebuild() }
    }

    public func toggle() {
        if let w = window, w.isVisible { w.close() } else { show() }
    }

    public func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "SpacialShell Settings"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        rebuild()
        // LSUIElement apps are not activated by ordering a window front, and an unactivated
        // settings window cannot take keyboard input — so ask for activation explicitly.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func rebuild() {
        guard let window else { return }
        let view = SettingsView(
            file: file,
            overrides: Binding(get: { [weak self] in self?.overrides ?? SettingsOverrides() },
                               set: { [weak self] new in
                                   guard let self, new != self.overrides else { return }
                                   self.overrides = new
                                   self.onChange(new)
                               }),
            configPath: configPath,
            openConfigFile: openConfigFile,
            checkForUpdates: checkForUpdates)
        if let host = window.contentView as? NSHostingView<SettingsView> {
            host.rootView = view
        } else {
            window.contentView = NSHostingView(rootView: view)
        }
    }

    public func windowWillClose(_ notification: Notification) {
        // Nothing to save: every edit is applied and written as it happens, so closing is not a
        // decision point and there is no dialog to put in the user's way.
    }
}
