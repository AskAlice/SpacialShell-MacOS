import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellPlatform

/// Owns one rail + one bar per display and keeps them in step with the world. Pure plumbing: the
/// content is `ShellUI.state(for:in:)`, the geometry is `[ui]` config, and every click goes back
/// through the same `Command` pipeline as a hotkey — the panels never touch the model directly.
///
/// Runs entirely on the main actor and is driven by two inputs: `update(world:)` from the store's
/// `onChange`, and `NSApplication.didChangeScreenParametersNotification` for hot-plugs (the world
/// follows via the backend's own snapshot; the notification just re-anchors panel frames early so
/// they don't sit on a dead screen while that snapshot is in flight).
@MainActor
final class ShellController: NSObject {
    private struct Panels {
        let rail: PanelWindow
        let railHost: NSHostingView<ScreenPanelView>
        let bar: PanelWindow
        let barHost: NSHostingView<WorkspacePanelView>
    }

    private var panels: [DisplayID: Panels] = [:]
    private var world: World?
    private var ui: UIConfig
    private let send: @Sendable (Command) -> Void
    private let appMeta: AppMetaCache

    init(ui: UIConfig, appMeta: AppMetaCache, send: @escaping @Sendable (Command) -> Void) {
        self.ui = ui
        self.appMeta = appMeta
        self.send = send
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(world: World) {
        self.world = world
        render()
    }

    func update(ui: UIConfig) {
        self.ui = ui
        render()
    }

    @objc private func screensChanged(_ note: Notification) {
        render()
    }

    private func render() {
        guard let world else { return }
        let visible = ui.enabled && world.shellUIVisible
        let railWidth = CGFloat(ui.railWidth), barHeight = CGFloat(ui.barHeight)
        var seen: Set<DisplayID> = []

        for nsScreen in NSScreen.screens {
            let id = DisplayTopology.uuid(for: nsScreen)
            guard let state = ShellUI.state(for: id, in: world) else { continue }
            seen.insert(id)
            let p = panels[id] ?? makePanels(for: id)
            panels[id] = p

            // NSScreen speaks bottom-left y-up; panels are placed directly in it, no flip needed.
            let vf = nsScreen.visibleFrame
            p.rail.setFrame(NSRect(x: vf.minX, y: vf.minY, width: railWidth, height: vf.height), display: true)
            p.bar.setFrame(NSRect(x: vf.minX + railWidth, y: vf.maxY - barHeight,
                                  width: vf.width - railWidth, height: barHeight), display: true)

            p.railHost.rootView = ScreenPanelView(state: state, send: forward)
            p.barHost.rootView = WorkspacePanelView(state: state, metaFor: appMeta.meta(for:), send: forward)

            if visible {
                p.rail.orderFrontRegardless()
                p.bar.orderFrontRegardless()
            } else {
                p.rail.orderOut(nil)
                p.bar.orderOut(nil)
            }
        }

        for (id, p) in panels where !seen.contains(id) {
            p.rail.orderOut(nil); p.bar.orderOut(nil)
            p.rail.close(); p.bar.close()
            panels[id] = nil
        }
    }

    private func makePanels(for id: DisplayID) -> Panels {
        let placeholder = ScreenShellState(display: id, isFocusedScreen: false, rail: [], tabs: [], layout: .maximize)
        let railHost = NSHostingView(rootView: ScreenPanelView(state: placeholder, send: forward))
        let barHost = NSHostingView(rootView: WorkspacePanelView(state: placeholder, metaFor: appMeta.meta(for:), send: forward))
        let rail = PanelWindow(); rail.contentView = railHost
        let bar = PanelWindow(); bar.contentView = barHost
        return Panels(rail: rail, railHost: railHost, bar: bar, barHost: barHost)
    }

    /// The views hold this, not `send` itself, so they stay agnostic of the store's threading.
    private func forward(_ command: Command) {
        send(command)
    }
}
