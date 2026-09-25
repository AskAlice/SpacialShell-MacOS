import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// Owns the one hover card: its window, its placement beside the hovered tile, and the capture
/// that fills it in.
///
/// It is a window rather than a popover because the rail lives in a `PanelWindow` that can never
/// become key — an `NSPopover` anchored there would take key status and, with it, focus away from
/// the window the user is actually working in, which is the one thing the shell must never do.
/// A second non-activating panel has no such effect, so the card is furniture like the rail.
///
/// The card draws `WindowThumbnails` in its first frame (#90), stale or not, and only after the
/// hover delay re-captures what is stale and swaps it in. Leaving the tile cancels that capture and
/// hides the window. No stream and no timer, so a rail nobody is pointing at costs nothing but the
/// thumbnails' memory.
@MainActor
final class RailHoverController {
    private let window = PanelWindow()
    private let host: NSHostingView<RailHoverCard>
    /// The workspace the card is currently about — or `trayID` for the tray list; nil when hidden.
    private var shown: UUID?
    /// The tray (#73) is not a workspace, but it shares the card, its placement and its hide grace,
    /// so it takes a fixed id in the same slot.
    static let trayID = UUID()
    private var captureTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var pointerInCard = false
    private let send: @Sendable (Command) -> Void

    /// Long enough that sweeping the rail to reach the tile you want does not fire a capture per
    /// tile on the way; the same 250 ms the design system gives every other hover label.
    private static let hoverDelay = Duration.milliseconds(250)
    /// The pointer needs a moment to cross the gap from tile to card without the card vanishing.
    private static let hideGrace = Duration.milliseconds(180)

    init(send: @escaping @Sendable (Command) -> Void) {
        self.send = send
        host = NSHostingView(rootView: RailHoverCard(title: "", subtitle: nil,
                                                     content: .message(""), onGrantAccess: {}))
        window.contentView = host
        window.hasShadow = true
        // Above the rail it sits next to, and above the tiled windows it describes.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }

    /// `tile` and `bounds` are screen coordinates (bottom-left origin, like `NSScreen`).
    func show(item: WorkspaceRailItem, tile: CGRect, railSide: RailSide, bounds: CGRect,
              metaFor: (Int32) -> AppMeta) {
        hideTask?.cancel(); hideTask = nil
        guard shown != item.id else { return }
        captureTask?.cancel()
        shown = item.id

        let apps = distinctApps(item, metaFor: metaFor)
        let thumbs = WindowThumbnails.shared
        let items = item.windows.map { ref in
            let meta = metaFor(ref.pid)
            return WindowPreviewItem(ref: ref, name: meta.name, icon: meta.icon, image: thumbs.image(for: ref.id))
        }
        let card = content(for: item, items: items)
        render(title: title(item), subtitle: subtitle(item, apps: apps), content: card)
        place(near: tile, railSide: railSide, bounds: bounds)
        window.orderFrontRegardless()

        guard case .previews = card else { return }
        let stale = items.prefix(RailHoverCard.maxPreviews).map(\.ref).filter { thumbs.isStale($0.id) }
        guard !stale.isEmpty else { return }
        captureTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverDelay)
            guard !Task.isCancelled else { return }
            let taken = ContinuousClock.now
            let images = await WindowPreviewCapture.images(for: stale, longSide: WindowThumbnails.longSide)
            // Kept even if the hover has moved on: the next hover over this workspace is instant.
            await thumbs.add(Array(images), taken: taken)
            guard !Task.isCancelled, let self, self.shown == item.id else { return }
            var filled = items
            for i in filled.indices { filled[i].image = thumbs.image(for: filled[i].ref.id) }
            self.render(title: self.title(item), subtitle: self.subtitle(item, apps: apps),
                        content: .previews(filled))
        }
    }

    /// The rail tray (#73): the windows no tab brings back, as rows of icon + title. Rows show the
    /// app's name at once and swap in the window title when AX answers, like a preview landing.
    func showTray(_ refs: [SpacialShellProtocol.WindowRef], tile: CGRect, railSide: RailSide, bounds: CGRect,
                  metaFor: (Int32) -> AppMeta) {
        hideTask?.cancel(); hideTask = nil
        guard shown != Self.trayID else { return }
        captureTask?.cancel()
        shown = Self.trayID

        let items = refs.map { ref in
            let meta = metaFor(ref.pid)
            return WindowPreviewItem(ref: ref, name: meta.name, icon: meta.icon, image: nil)
        }
        let title = "Hidden windows and popups"
        let subtitle = refs.count == 1 ? "1 window · click to bring it back" : "\(refs.count) windows · click one to bring it back"
        render(title: title, subtitle: subtitle, content: .windows(items))
        place(near: tile, railSide: railSide, bounds: bounds)
        window.orderFrontRegardless()

        let shownRefs = Array(refs.prefix(RailHoverCard.maxRows))
        captureTask = Task { [weak self] in
            let titles = await WindowTitles.titles(for: shownRefs)
            guard !Task.isCancelled, !titles.isEmpty, let self, self.shown == Self.trayID else { return }
            let named = items.map { WindowPreviewItem(ref: $0.ref, name: titles[$0.ref.id] ?? $0.name, icon: $0.icon, image: nil) }
            self.render(title: title, subtitle: subtitle, content: .windows(named))
        }
    }

    /// The pointer left `item`. Hides after a grace period, unless it has landed on the card
    /// itself — without which the "Open Screen Recording settings…" button could never be
    /// reached. A late exit for a tile the card has already moved on from is ignored.
    func hide(_ item: UUID) {
        guard shown == item else { return }
        hideAfterGrace()
    }

    private func hideAfterGrace() {
        captureTask?.cancel(); captureTask = nil
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideGrace)
            guard !Task.isCancelled, let self, !self.pointerInCard else { return }
            self.hideNow()
        }
    }

    func hideNow() {
        captureTask?.cancel(); captureTask = nil
        hideTask?.cancel(); hideTask = nil
        shown = nil
        pointerInCard = false
        window.orderOut(nil)
        // Let go of the card's images; the thumbnails themselves stay in `WindowThumbnails`.
        render(title: "", subtitle: nil, content: .message(""))
    }

    /// A preview was clicked: the same command as clicking its tab, which activates the window's
    /// workspace and focuses it there. The card goes with the click — it describes a workspace
    /// the user has just left or entered, and would otherwise outlive the switch.
    ///
    /// A tray row sends `.recoverWindow` instead (#73): it also un-minimizes a popup and brings one
    /// back from off every display, and like the tab click it never re-files the window.
    func select(_ ref: SpacialShellProtocol.WindowRef) {
        send(shown == Self.trayID ? .recoverWindow(ref) : .focusWindowRef(ref))
        hideNow()
    }

    /// The workspace the card is about, for tests; nil when hidden.
    var shownWorkspace: UUID? { shown }

    // MARK: - drawing

    private func render(title: String, subtitle: String?, content: RailHoverCard.Content) {
        host.rootView = RailHoverCard(
            title: title, subtitle: subtitle, content: content,
            onGrantAccess: { ScreenRecordingAccess.request() },
            onHoverCard: { [weak self] inside in
                guard let self else { return }
                self.pointerInCard = inside
                if inside { self.hideTask?.cancel() } else { self.hideAfterGrace() }
            },
            onSelect: { [weak self] in self?.select($0) })
        host.layoutSubtreeIfNeeded()
    }

    private func content(for item: WorkspaceRailItem, items: [WindowPreviewItem]) -> RailHoverCard.Content {
        if item.isTrailingEmpty {
            return .message("Opens a new workspace — or drop a tab here to move its window into one.")
        }
        if items.isEmpty {
            return .message("Nothing here yet. Drop a tab on this tile, or open something from the launcher.")
        }
        guard ScreenRecordingAccess.isGranted else { return .needsScreenRecording }
        return .previews(items)
    }

    private func title(_ item: WorkspaceRailItem) -> String {
        item.isTrailingEmpty ? "New workspace" : "\(item.name) (\(item.index + 1))"
    }

    private func subtitle(_ item: WorkspaceRailItem, apps: [AppMeta]) -> String? {
        if item.isTrailingEmpty { return nil }
        let count = item.windowCount == 1 ? "1 window" : "\(item.windowCount) windows"
        guard let label = AppCategories.summarise(apps.map(\.category))?.label else { return count }
        return "\(count) · \(label)"
    }

    private func distinctApps(_ item: WorkspaceRailItem, metaFor: (Int32) -> AppMeta) -> [AppMeta] {
        var seen: Set<Int32> = []
        return item.windows.compactMap { seen.insert($0.pid).inserted ? metaFor($0.pid) : nil }
    }

    /// Beside the tile, on the side the rail is not: vertically centred on the tile, then nudged
    /// back inside the screen so a card next to the bottom tile is not half off the display.
    private func place(near tile: CGRect, railSide: RailSide, bounds: CGRect) {
        let size = host.fittingSize
        let gap: CGFloat = 8
        let x = railSide == .left ? tile.maxX + gap : tile.minX - gap - size.width
        var y = tile.midY - size.height / 2
        y = min(max(y, bounds.minY + gap), bounds.maxY - size.height - gap)
        window.setFrame(NSRect(x: min(max(x, bounds.minX), bounds.maxX - size.width), y: y,
                               width: size.width, height: size.height), display: true)
    }
}
