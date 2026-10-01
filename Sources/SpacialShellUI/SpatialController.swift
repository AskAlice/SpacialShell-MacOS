import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellPlatform
import SpacialShellProtocol

/// #132 (M3 B9): owns the spatialisation view. Two ways in:
///
/// - `toggle-spatial-view` (`Fn+Z`) opens it until the chord again, a click, or a jump.
/// - **Holding** `Fn+W` / `Fn+S` (an autorepeat from the hotkey tap) opens it the ⌘Tab way:
///   keep Fn down and tap W/S to ride between rows — each tap is the ordinary command, so the
///   world moves and the camera follows — and let go of Fn to land where you are.
///
/// App-layer, like the overview: opening it changes nothing in the model, and every click in it
/// re-enters the store as a `Command`. Covers the focused display, in a non-activating panel
/// above the shell's own, so the window you were in keeps key focus throughout.
///
/// #181: the chips draw `WindowThumbnails`' pictures in the first frame, and opening the view (or
/// the camera moving to another row) asks `ThumbnailRefresher` to take every chip in view whose
/// picture is missing or stale; each row's pictures swap in as they land.
@MainActor
public final class SpatialController {
    private let panel = PanelWindow()
    private var host: NSHostingView<SpatialStripView>?
    private let appMeta: AppMetaCache
    private let send: @Sendable (Command) -> Void
    private var config: Config
    private var world: World?
    private var titles: [SpacialShellProtocol.WindowRef: String] = [:]
    public private(set) var isOpen = false
    /// #185: told when the view opens, so the cheat sheet gets out of its way.
    public var onOpen: () -> Void = {}
    /// Opened by holding the workspace keys: it closes when the modifier is let go.
    private var held = false
    /// #181: what the last thumbnail refresh was asked for — the display, the row the camera
    /// centred and the chips in view; nil when none has been asked for since the view opened.
    private var refreshedFor: RefreshKey?
    private struct RefreshKey: Equatable {
        let display: SpacialShellProtocol.DisplayID
        let active: Int
        let chips: Set<SpacialShellProtocol.WindowRef>
    }

    public init(config: Config, appMeta: AppMetaCache, send: @escaping @Sendable (Command) -> Void) {
        self.config = config
        self.appMeta = appMeta
        self.send = send
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)   // over the rail and the bar
    }

    public func update(world: World, snapshot: ShellSnapshot) {
        self.world = world
        titles = snapshot.titles
        if isOpen { render() }
    }

    public func update(config: Config) {
        self.config = config
        if isOpen { render() }
    }

    public func toggle() {
        if isOpen { close() } else { open(held: false) }
    }

    /// An autorepeat of a workspace chord: the keys are being held.
    public func holdStarted() {
        guard !isOpen else { return }
        open(held: true)
    }

    /// Fed from the tap's `onFlags`. A held-open view lands when the preset's modifier goes.
    public func flagsChanged(_ flags: CGEventFlags) {
        guard isOpen, held, !SpatialView.isHeld(flags, preset: config.keybindingPreset) else { return }
        close()
    }

    private func open(held: Bool) {
        guard world != nil else { return }
        self.held = held
        isOpen = true
        onOpen()
        render()
        panel.orderFrontRegardless()
    }

    private func close() {
        guard isOpen else { return }
        isOpen = false
        held = false
        refreshedFor = nil
        ThumbnailRefresher.shared.cancelRefresh()
        panel.orderOut(nil)
        panel.contentView = nil
        host = nil
    }

    private func render() {
        guard let world else { return }
        let screen = NSScreen.screens.first { DisplayTopology.uuid(for: $0) == world.focus.screen }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        // The mini-desktops are the tiling area's shape: the visible frame less the panels and the gap.
        let panels = config.showPanels && !world.zen
        let vf = screen.visibleFrame
        let viewport = CGSize(width: vf.width - (panels && !config.railAutohide ? config.panelWidth : 0) - 2 * config.gap,
                              height: vf.height - (panels ? config.panelHeight : 0) - 2 * config.gap)
        guard let state = SpatialView.state(for: world.focus.screen, in: world, layouts: LayoutCatalogue(config: config),
                                            titles: titles, viewport: viewport, gap: config.gap) else { return }
        let thumbs = WindowThumbnails.shared
        let view = SpatialStripView(state: state, metaFor: appMeta.meta(for:), send: { [send] in send($0) },
                                    thumbnails: Self.thumbnails(for: state, from: thumbs),
                                    dismiss: { [weak self] in self?.close() },
                                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if let host {
            host.rootView = view     // the same view identity: the camera animates to the new row
        } else {
            let host = NSHostingView(rootView: view)
            self.host = host
            panel.contentView = host
        }
        if panel.frame != vf { panel.setFrame(vf, display: true) }

        // After the frame is drawn from the cache, never before it. Asked again only when what is
        // in view changes (another row, another display, a window arriving), not per render: a
        // render follows every landing.
        let visible = SpatialView.visibleRows(count: state.rows.count, active: state.activeIndex,
                                              rowHeight: SpatialStripView.rowHeight(in: vf.size, aspect: state.aspect),
                                              spacing: SpatialStripView.spacing, viewHeight: vf.height)
        let key = RefreshKey(display: state.display, active: state.activeIndex,
                             chips: Set(state.rows[visible].flatMap(\.windows)))
        guard refreshedFor != key else { return }
        refreshedFor = key
        ThumbnailRefresher.shared.refresh(ThumbnailRefresh.onOpen(
            state, visible: visible, skip: world.hidden.union(world.offSpace).union(world.fullscreen), isStale: thumbs.isStale)) {
            [weak self] in
            guard let self, self.isOpen else { return }
            self.render()
        }
    }

    /// The cached picture of every chip, and (#197) every other tab beside it, that has one. A
    /// placeholder (#128) has no window, and its id is its own, so a picture cached under the same
    /// number belongs to some real window.
    private static func thumbnails(for state: SpatialState,
                                   from thumbs: WindowThumbnails) -> [SpacialShellProtocol.WindowRef: NSImage] {
        var out: [SpacialShellProtocol.WindowRef: NSImage] = [:]
        for ref in state.rows.flatMap(\.windows) where !ref.isPlaceholder {
            out[ref] = thumbs.image(for: ref.id)
        }
        return out
    }
}
