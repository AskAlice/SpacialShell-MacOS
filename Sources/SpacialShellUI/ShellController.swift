import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellPlatform
import SpacialShellProtocol

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
    /// #110: window titles from the store's snapshot feed, published alongside `world`.
    private var titles: [SpacialShellProtocol.WindowRef: String] = [:]
    private var config: Config
    private var problems: [Problem] = []
    private let send: @Sendable (Command) -> Void
    private let appMeta: AppMetaCache
    /// One card for the whole shell, not one per display: only one pointer exists.
    private let hover: RailHoverController
    private let emptySheet = EmptyCheatSheetController()
    /// #10: the cog's layout popover — one for the shell, open on at most one display.
    private let layoutPopover: LayoutPopoverController

    // #96 `rail-autohide`. The hot zone is a rect checked against the pointer rather than a
    // window: a click-through window gets no tracking events, and the event monitors below also
    // see the pointer mid-drag, which is when a tab heading for the rail needs it.
    private var autohide: [DisplayID: RailAutohide] = [:]
    /// Where each auto-hiding rail sits when shown, and its edge zone; only displays it can show on.
    private var railEdges: [DisplayID: (home: NSRect, zone: NSRect)] = [:]
    /// The display the hover card was last opened from — it pins that display's rail.
    private var hoverDisplay: DisplayID?
    private var pointerMonitors: [Any] = []
    private var ticker: Timer?
    /// The Dock-like slide; Reduce Motion makes it instant.
    private static let railSlide: TimeInterval = 0.2
    /// Thin enough to never be in the way, and the pointer rests against the edge, inside it.
    private static let hotZoneWidth: CGFloat = 4
    /// Steps the pending delays while the rail is revealing, shown, or a button is held.
    private static let tickInterval: TimeInterval = 0.05

    public init(config: Config, appMeta: AppMetaCache, send: @escaping @Sendable (Command) -> Void) {
        self.config = config
        self.appMeta = appMeta
        self.send = send
        hover = RailHoverController(send: send)
        layoutPopover = LayoutPopoverController(send: send)
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        watchPointer(config.railAutohide)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func update(world: World, snapshot: ShellSnapshot) {
        self.world = world
        titles = snapshot.titles
        WindowThumbnails.shared.retain(world.allWindowIDs)   // #90: a closed window's thumbnail goes with it
        render()
    }

    /// #109: badges the rail cog. Never activates anything — the list is one hover away.
    public func update(problems: [Problem]) {
        guard problems != self.problems else { return }
        self.problems = problems
        if problems.isEmpty { hover.hide(RailHoverController.problemsID) }
        render()
    }

    public func update(config: Config) {
        let wasAutohide = self.config.railAutohide
        self.config = config
        if wasAutohide != config.railAutohide {
            autohide = [:]
            watchPointer(config.railAutohide)
            // Turning it on: the rails go now, and come back from the edge. Off: `render` puts
            // them back at home.
            if config.railAutohide { for p in panels.values { p.rail.orderOut(nil) } }
        }
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
        let autohides = config.railAutohide
        var seen: Set<DisplayID> = []
        let layouts = LayoutCatalogue(config: config)

        for nsScreen in NSScreen.screens {
            let id = DisplayTopology.uuid(for: nsScreen)
            guard let state = ShellUI.state(for: id, in: world, layouts: layouts, titles: titles) else { continue }
            seen.insert(id)
            let p = panels[id] ?? makePanels(for: id)
            panels[id] = p

            // NSScreen speaks bottom-left y-up; panels are placed directly in it, no flip needed.
            // `rail-side` mirrors the rail; the bar always spans the rest of the top edge.
            // #96: an auto-hiding rail overlays the windows rather than taking width, so the bar
            // spans the whole edge and the rail, when it shows, comes in over the bar's end too.
            let vf = nsScreen.visibleFrame
            let railX = config.railSide == .left ? vf.minX : vf.maxX - railWidth
            let barInset = autohides ? 0 : railWidth
            let barX = config.railSide == .left ? vf.minX + barInset : vf.minX
            let home = NSRect(x: railX, y: vf.minY, width: railWidth, height: vf.height)
            if !autohides { p.rail.setFrame(home, display: true) }   // else `slide` owns the frame
            p.bar.setFrame(NSRect(x: barX, y: vf.maxY - barHeight,
                                  width: vf.width - barInset, height: barHeight), display: true)

            p.railHost.rootView = ScreenPanelView(state: state, launcherURL: config.launcherURL,
                                                  metaFor: appMeta.meta(for:),
                                                  send: forward,
                                                  onHoverTile: { [weak self] item, inside, tile in
                                                      self?.hoverChanged(item, inside: inside, tile: tile,
                                                                         display: id, screen: nsScreen)
                                                  },
                                                  onHoverTray: { [weak self] inside, tile in
                                                      self?.trayHoverChanged(state, inside: inside, tile: tile,
                                                                             display: id, screen: nsScreen)
                                                  },
                                                  problems: problems,
                                                  onHoverProblems: { [weak self] inside, tile in
                                                      self?.problemsHoverChanged(inside: inside, tile: tile,
                                                                                 display: id, screen: nsScreen)
                                                  })
            p.barHost.rootView = WorkspacePanelView(state: state, metaFor: appMeta.meta(for:), sizing: config.tabSizing,
                                                   style: config.tabStyle, chrome: PanelChrome(config: config), send: forward,
                                                   openLayouts: { [weak self] in
                                                       guard let self, let bar = self.panels[id]?.bar else { return }
                                                       self.layoutPopover.toggle(state, bar: bar)
                                                   })
            layoutPopover.update(state)

            // #72: never order the panels onto a display showing a fullscreen Space.
            if visible && !world.showsFullscreenSpace(id) {
                // Bar first: a revealed auto-hiding rail overlaps it and must stay on top.
                p.bar.orderFrontRegardless()
                if !autohides || autohide[id]?.isShown == true { p.rail.orderFrontRegardless() }
                if autohides {
                    let zoneX = config.railSide == .left ? vf.minX - 1 : vf.maxX - Self.hotZoneWidth
                    railEdges[id] = (home, NSRect(x: zoneX, y: vf.minY, width: Self.hotZoneWidth + 1, height: vf.height))
                }
            } else {
                railEdges[id] = nil; autohide[id] = nil
                p.rail.orderOut(nil)
                p.bar.orderOut(nil)
                hover.hideNow()   // Zen or fullscreen hides the rail; a card about it must not outlive it
                if layoutPopover.display == id { layoutPopover.hide() }
            }
        }

        for (id, p) in panels where !seen.contains(id) {
            p.rail.orderOut(nil); p.bar.orderOut(nil)
            p.rail.close(); p.bar.close()
            panels[id] = nil
            railEdges[id] = nil; autohide[id] = nil
            if layoutPopover.display == id { layoutPopover.hide() }
            hover.hideNow()
        }
        emptySheet.update(world: world, config: config)
    }

    /// SwiftUI hands us the tile's frame in the hosting view's space — top-left origin, y down.
    /// The card is placed in screen coordinates, which are bottom-left origin, so the rail
    /// panel's own frame is the only thing needed to translate between the two.
    private func hoverChanged(_ item: WorkspaceRailItem, inside: Bool, tile: CGRect,
                              display: DisplayID, screen: NSScreen) {
        guard inside else { hover.hide(item.id); return }
        guard let inScreen = toScreen(tile, display: display) else { return }
        hoverDisplay = display
        hover.show(item: item, tile: inScreen, railSide: config.railSide,
                   bounds: screen.visibleFrame, metaFor: appMeta.meta(for:))
    }

    /// #73: the tray shares the hover card; it just lists windows instead of previewing a workspace.
    private func trayHoverChanged(_ state: ScreenShellState, inside: Bool, tile: CGRect,
                                  display: DisplayID, screen: NSScreen) {
        guard inside else { hover.hide(RailHoverController.trayID); return }
        guard let inScreen = toScreen(tile, display: display) else { return }
        hoverDisplay = display
        hover.showTray(state.tray, tile: inScreen, railSide: config.railSide,
                       bounds: screen.visibleFrame, metaFor: appMeta.meta(for:))
    }

    /// #109: the cog's problem list shares the hover card too.
    private func problemsHoverChanged(inside: Bool, tile: CGRect, display: DisplayID, screen: NSScreen) {
        guard inside, !problems.isEmpty else { hover.hide(RailHoverController.problemsID); return }
        guard let inScreen = toScreen(tile, display: display) else { return }
        hoverDisplay = display
        hover.showProblems(problems, tile: inScreen, railSide: config.railSide, bounds: screen.visibleFrame)
    }

    private func toScreen(_ tile: CGRect, display: DisplayID) -> CGRect? {
        guard let frame = panels[display]?.rail.frame else { return nil }
        return CGRect(x: frame.minX + tile.minX, y: frame.maxY - tile.maxY, width: tile.width, height: tile.height)
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

    // MARK: - #96 auto-hiding rail

    /// Pointer movement anywhere (global) and over our own panels (local), plus drags and presses.
    /// Installed only while `rail-autohide` is on: otherwise the rail costs no event traffic.
    private func watchPointer(_ on: Bool) {
        pointerMonitors.forEach(NSEvent.removeMonitor); pointerMonitors = []
        stopTicker()
        guard on else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }) { pointerMonitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.tick() }
            return event
        }) { pointerMonitors.append(m) }
    }

    /// One step of every display's `RailAutohide`, then the slides it asks for. Keeps ticking while
    /// a delay is pending or a button is held (a drag can outlast every event the monitors see).
    private func tick() {
        guard config.railAutohide else { stopTicker(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let pointer = NSEvent.mouseLocation
        let pressed = NSEvent.pressedMouseButtons != 0
        var keepTicking = pressed
        for (id, edge) in railEdges {
            var machine = autohide[id] ?? RailAutohide()
            let was = machine.isShown
            // ponytail: any held button pins, not only a drag begun on the rail — so a drag
            // elsewhere during the hide delay keeps it until release. Track the drag's origin if
            // that ever reads as sticky.
            let pinned = pressed || (hoverDisplay == id && hover.shownWorkspace != nil)
            machine.step(inZone: edge.zone.contains(pointer), overRail: edge.home.contains(pointer),
                         pinned: pinned, now: now)
            autohide[id] = machine
            if machine.isShown != was { slide(id, home: edge.home, shown: machine.isShown) }
            keepTicking = keepTicking || machine.needsTicks
        }
        if keepTicking { startTicker() } else { stopTicker() }
    }

    /// Slides the rail in from, or out past, its screen edge. It is ordered out once gone, so the
    /// off-edge frame never shows on a neighbouring display. Non-activating throughout.
    private func slide(_ id: DisplayID, home: NSRect, shown: Bool) {
        guard let rail = panels[id]?.rail else { return }
        let off = home.offsetBy(dx: config.railSide == .left ? -home.width : home.width, dy: 0)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            rail.setFrame(home, display: true)
            if shown { rail.orderFrontRegardless() } else { rail.orderOut(nil) }
            return
        }
        if shown {
            if !rail.isVisible { rail.setFrame(off, display: false) }
            rail.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.railSlide
            ctx.timingFunction = CAMediaTimingFunction(name: shown ? .easeOut : .easeIn)
            rail.animator().setFrame(shown ? home : off, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard !shown, let self, self.autohide[id]?.isShown != true else { return }
                self.panels[id]?.rail.orderOut(nil)
            }
        })
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // `.common`, so it keeps firing while a drag or menu runs the loop in tracking mode.
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    /// The views hold this, not `send` itself, so they stay agnostic of the store's threading.
    private func forward(_ command: Command) {
        send(command)
    }
}
