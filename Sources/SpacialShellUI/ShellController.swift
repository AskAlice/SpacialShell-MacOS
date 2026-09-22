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
        /// T20: covers the whole display, click-through, and draws the focus ring inside itself.
        let ring: HighlightPanel
        let ringHost: NSHostingView<FocusRingView>
    }

    private var panels: [DisplayID: Panels] = [:]
    private var world: World?
    private var config: Config
    private let send: @Sendable (Command) -> Void
    private let appMeta: AppMetaCache
    /// One card for the whole shell, not one per display: only one pointer exists.
    private let hover = RailHoverController()

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

    /// Where the store says the focused window is about to be, in AX top-left coordinates; nil when
    /// nothing has a tiled frame to draw around.
    private var focusedFrame: CGRect?

    public func update(world: World) {
        self.world = world
        render()
    }

    /// T20. Arrives from `WorldStore`'s reconcile, ahead of the AX write, so the ring is already at
    /// the destination when the window gets there.
    public func update(focusedFrame: CGRect?) {
        self.focusedFrame = focusedFrame
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
            // Floating cards: every edge gives up `panel-margin`, and the bar starts a margin past
            // the rail rather than butting against it. The same margin is what `ShellInsets` hands
            // the reconciler, so the window area meets the cards exactly — plus the tiling `gap`.
            let m = CGFloat(config.panelMargin)
            let railX = config.railSide == .left ? vf.minX + m : vf.maxX - m - railWidth
            let barX = config.railSide == .left ? railX + railWidth + m : vf.minX + m
            p.rail.setFrame(NSRect(x: railX, y: vf.minY + m, width: railWidth, height: vf.height - 2 * m),
                            display: true)
            p.bar.setFrame(NSRect(x: barX, y: vf.maxY - m - barHeight,
                                  width: vf.width - 2 * m - railWidth - m, height: barHeight), display: true)

            // The ring panel covers the whole display. `focusedFrame` is AX top-left and global;
            // the ring view draws in its own top-left space, so the frame only needs shifting by
            // the panel's origin — the flip from NSScreen's y-up happens once, here.
            p.ring.setFrame(vf, display: true)
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            let ringFrame = focusedFrame.flatMap { f -> CGRect? in
                let screenTop = mainHeight - vf.maxY          // AX y of this display's visible top
                let local = CGRect(x: f.minX - vf.minX, y: f.minY - screenTop, width: f.width, height: f.height)
                // Only draw a ring for a window on *this* display.
                return local.intersects(CGRect(origin: .zero, size: vf.size)) ? local : nil
            }
            p.ringHost.rootView = FocusRingView(frame: ringFrame,
                                                color: FocusRingView.color(for: config),
                                                animation: FocusRingView.animation(for: config))
            p.railHost.rootView = ScreenPanelView(state: state, launcherURL: config.launcherURL,
                                                  metaFor: appMeta.meta(for:),
                                                  send: forward,
                                                  onHoverTile: { [weak self] item, inside, tile in
                                                      self?.hoverChanged(item, inside: inside, tile: tile,
                                                                         display: id, screen: nsScreen)
                                                  })
            p.barHost.rootView = WorkspacePanelView(state: state, metaFor: appMeta.meta(for:), sizing: config.tabSizing,
                                                   chrome: PanelChrome(config: config), send: forward)

            if visible {
                p.rail.orderFrontRegardless()
                p.bar.orderFrontRegardless()
            } else {
                p.rail.orderOut(nil)
                p.bar.orderOut(nil)
                hover.hideNow()   // Zen hides the rail; a card about it must not outlive it
            }
            // The ring is not chrome: Zen hides the panels and gives their edges back to the
            // layout, but the tiling — and therefore which window has focus — is still there.
            if ringFrame != nil { p.ring.orderFrontRegardless() } else { p.ring.orderOut(nil) }
        }

        for (id, p) in panels where !seen.contains(id) {
            p.rail.orderOut(nil); p.bar.orderOut(nil); p.ring.orderOut(nil)
            p.rail.close(); p.bar.close(); p.ring.close()
            panels[id] = nil
            hover.hideNow()
        }
    }

    /// SwiftUI hands us the tile's frame in the hosting view's space — top-left origin, y down.
    /// The card is placed in screen coordinates, which are bottom-left origin, so the rail
    /// panel's own frame is the only thing needed to translate between the two.
    private func hoverChanged(_ item: WorkspaceRailItem, inside: Bool, tile: CGRect,
                              display: DisplayID, screen: NSScreen) {
        guard inside else { hover.hide(item.id); return }
        guard let panel = panels[display]?.rail else { return }
        let frame = panel.frame
        let inScreen = CGRect(x: frame.minX + tile.minX, y: frame.maxY - tile.maxY,
                              width: tile.width, height: tile.height)
        hover.show(item: item, tile: inScreen, railSide: config.railSide,
                   bounds: screen.visibleFrame, metaFor: appMeta.meta(for:))
    }

    private func makePanels(for id: DisplayID) -> Panels {
        let placeholder = ScreenShellState(display: id, isFocusedScreen: false, rail: [], tabs: [], layout: .maximize)
        let railHost = NSHostingView(rootView: ScreenPanelView(state: placeholder, launcherURL: config.launcherURL,
                                                               metaFor: appMeta.meta(for:), send: forward))
        let barHost = NSHostingView(rootView: WorkspacePanelView(state: placeholder, metaFor: appMeta.meta(for:), sizing: config.tabSizing, send: forward))
        let ringHost = NSHostingView(rootView: FocusRingView(frame: nil,
                                                             color: FocusRingView.color(for: config),
                                                             animation: FocusRingView.animation(for: config)))
        let rail = PanelWindow(); rail.contentView = railHost
        let bar = PanelWindow(); bar.contentView = barHost
        let ring = HighlightPanel(); ring.contentView = ringHost
        return Panels(rail: rail, railHost: railHost, bar: bar, barHost: barHost, ring: ring, ringHost: ringHost)
    }

    /// The views hold this, not `send` itself, so they stay agnostic of the store's threading.
    private func forward(_ command: Command) {
        send(command)
    }
}
