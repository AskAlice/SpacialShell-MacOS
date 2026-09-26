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
    /// Opened by holding the workspace keys: it closes when the modifier is let go.
    private var held = false

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
        render()
        panel.orderFrontRegardless()
    }

    private func close() {
        guard isOpen else { return }
        isOpen = false
        held = false
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
        let view = SpatialStripView(state: state, metaFor: appMeta.meta(for:), send: { [send] in send($0) },
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
    }
}
