import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellPlatform

/// Owns one rail + one bar per display and keeps them in step with the world. Pure plumbing: the
/// content is `ShellUI.state(for:in:)`, the geometry is the `panel-width`/`panel-height`/
/// `rail-side` config keys, and every click goes back through the same `Command` pipeline as a
/// hotkey — the panels never touch the model directly.
///
/// Runs entirely on the main actor and is driven by two inputs: `update(world:)` from the store's
/// `onChange`, and `NSApplication.didChangeScreenParametersNotification` for hot-plugs (the world
/// follows via the backend's own snapshot; the notification just re-anchors panel frames early so
/// they don't sit on a dead screen while that snapshot is in flight).
@MainActor
public final class ShellController: NSObject {
    private struct Panels {
        let rail: PanelWindow
        let railHost: NSHostingView<ScreenPanelView>
        let bar: PanelWindow
        let barHost: NSHostingView<WorkspacePanelView>
    }

    private var panels: [DisplayID: Panels] = [:]
    private var world: World?
    private var config: Config
    private let send: @Sendable (Command) -> Void
    private let appMeta: AppMetaCache

    public init(config: Config, appMeta: AppMetaCache, send: @escaping @Sendable (Command) -> Void) {
        self.config = config
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

    public func update(world: World) {
        self.world = world
        render()
    }

    public func update(config: Config) {
        self.config = config
        appMeta.update(config: config)   // `app-categories` changes what a cached AppMeta resolves to
        render()
    }

    @objc private func screensChanged(_ note: Notification) {
        render()
    }

    private func render() {
        guard let world else { return }
        let visible = config.showPanels && !world.zen
        let railWidth = CGFloat(config.panelWidth), barHeight = CGFloat(config.panelHeight)
        var seen: Set<DisplayID> = []

        for nsScreen in NSScreen.screens {
            let id = DisplayTopology.uuid(for: nsScreen)
            guard let state = ShellUI.state(for: id, in: world) else { continue }
            seen.insert(id)
            let p = panels[id] ?? makePanels(for: id)
            panels[id] = p

            // NSScreen speaks bottom-left y-up; panels are placed directly in it, no flip needed.
            // `rail-side` mirrors the rail; the bar always spans the rest of the top edge.
            let vf = nsScreen.visibleFrame
            let railX = config.railSide == .left ? vf.minX : vf.maxX - railWidth
            let barX = config.railSide == .left ? vf.minX + railWidth : vf.minX
            p.rail.setFrame(NSRect(x: railX, y: vf.minY, width: railWidth, height: vf.height), display: true)
            p.bar.setFrame(NSRect(x: barX, y: vf.maxY - barHeight,
                                  width: vf.width - railWidth, height: barHeight), display: true)

            p.railHost.rootView = ScreenPanelView(state: state, launcherURL: config.launcherURL,
                                                  metaFor: appMeta.meta(for:),
                                                  send: forward)
            p.barHost.rootView = WorkspacePanelView(state: state, metaFor: appMeta.meta(for:), sizing: config.tabSizing, send: forward)

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
        let railHost = NSHostingView(rootView: ScreenPanelView(state: placeholder, launcherURL: config.launcherURL,
                                                               metaFor: appMeta.meta(for:), send: forward))
        let barHost = NSHostingView(rootView: WorkspacePanelView(state: placeholder, metaFor: appMeta.meta(for:), sizing: config.tabSizing, send: forward))
        let rail = PanelWindow(); rail.contentView = railHost
        let bar = PanelWindow(); bar.contentView = barHost
        return Panels(rail: rail, railHost: railHost, bar: bar, barHost: barHost)
    }

    /// The views hold this, not `send` itself, so they stay agnostic of the store's threading.
    private func forward(_ command: Command) {
        send(command)
    }
}
