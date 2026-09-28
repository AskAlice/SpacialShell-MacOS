import AppKit
import os
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
///
/// #179: resting the pointer on a preview rings it and, after `peekDwell`, peeks its window —
/// `.peek`, the real window shown centred with everything else hidden — until the pointer leaves
/// it, another preview takes over (a swap, never a restore in between), or the card goes.
///
/// #182: at most one card is ever on screen, and none once the pointer is on neither the rail nor
/// the card. SwiftUI's exit events alone cannot promise that — a tile removed from under the
/// pointer never reports one, and neither does a pointer that leaves across a screen edge — so
/// while the card shows, a pointer monitor hides it once the pointer has been outside both for
/// the hide grace, and the shell hides it when its row goes or moves, or the rail slides away.
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
    /// The card as last drawn, so a highlight change redraws it exactly as it is.
    private var drawn: (title: String, subtitle: String?, content: RailHoverCard.Content) = ("", nil, .message(""))
    /// #179: the preview under the pointer, and the window this card last asked to peek (nil once
    /// it asked for the peek to end).
    private var highlighted: SpacialShellProtocol.WindowRef?
    private var peeking: SpacialShellProtocol.WindowRef?
    private var peekTask: Task<Void, Never>?
    private let peekDwell: Duration
    /// #182: the row the shown workspace sat at, so a re-render can tell it has moved.
    private var shownIndex: Int?

    // #182 pointer safety net. The pointer and the clock are injected so a test can move them.
    private let pointer: () -> CGPoint
    private let now: () -> ContinuousClock.Instant
    /// Puts the card on screen. Tests pass a no-op: a test run that ordered real cards front left
    /// them on the user's display for as long as the runner lived (#182's "stuck card").
    private let present: (NSWindow) -> Void
    /// The rail panel the card was opened from, in screen coordinates; nil when it is off screen.
    var railFrame: () -> CGRect? = { nil }
    private var pointerMonitors: [Any] = []
    /// When the pointer was first seen outside both rail and card; nil while it is on either.
    private var outsideSince: ContinuousClock.Instant?
    /// Re-checks once the grace is up, since a pointer at rest outside sends no more events.
    private var pointerCheck: Task<Void, Never>?
    private static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "hover")

    /// Long enough that sweeping the rail to reach the tile you want does not fire a capture per
    /// tile on the way; the same 250 ms the design system gives every other hover label.
    private static let hoverDelay = Duration.milliseconds(250)
    /// The pointer needs a moment to cross the gap from tile to card without the card vanishing.
    private static let hideGrace = Duration.milliseconds(180)
    /// #179: how long the pointer rests on a preview before its window is peeked, and on nothing
    /// before the peek ends — so crossing the card moves no windows, and crossing the gap between
    /// two previews swaps the peek without putting the first window back in between.
    static let peekDwell = Duration.milliseconds(150)

    init(send: @escaping @Sendable (Command) -> Void, peekDwell: Duration = RailHoverController.peekDwell,
         pointer: @escaping () -> CGPoint = { NSEvent.mouseLocation },
         now: @escaping () -> ContinuousClock.Instant = { .now },
         present: @escaping (NSWindow) -> Void = { $0.orderFrontRegardless() }) {
        self.send = send
        self.peekDwell = peekDwell
        self.pointer = pointer
        self.now = now
        self.present = present
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
        endPeek()   // #179: a peek belongs to the workspace the card was about
        shown = item.id
        shownIndex = item.index

        // #183: named as the spatial view names the row.
        let title = AppCategories.rowTitle(
            name: item.name,
            category: AppCategories.rowCategory(item.category, windows: item.windows) { metaFor($0).category },
            isTrailingEmpty: item.isTrailingEmpty)
        let subtitle = self.subtitle(item)
        let thumbs = WindowThumbnails.shared
        // #128: a placeholder has no window to picture — and its id is its own, so a thumbnail
        // cached under the same number belongs to some real window. It shows its app's icon.
        let items = item.windows.map { ref in
            let meta = metaFor(ref.pid)
            return WindowPreviewItem(ref: ref, name: meta.name, icon: meta.icon,
                                     image: ref.isPlaceholder ? nil : thumbs.image(for: ref.id))
        }
        let card = content(for: item, items: items)
        render(title: title, subtitle: subtitle, content: card)
        place(near: tile, railSide: railSide, bounds: bounds)
        appear("workspace \(item.index + 1)")

        guard case .previews = card else { return }
        let stale = items.prefix(RailHoverCard.maxPreviews).map(\.ref).filter { !$0.isPlaceholder && thumbs.isStale($0.id) }
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
            for i in filled.indices where !filled[i].ref.isPlaceholder { filled[i].image = thumbs.image(for: filled[i].ref.id) }
            self.render(title: title, subtitle: subtitle, content: .previews(filled))
        }
    }

    /// The rail tray (#73): the windows no tab brings back, as rows of icon + title. Rows show the
    /// app's name at once and swap in the window title when AX answers, like a preview landing.
    func showTray(_ refs: [SpacialShellProtocol.WindowRef], tile: CGRect, railSide: RailSide, bounds: CGRect,
                  metaFor: (Int32) -> AppMeta) {
        hideTask?.cancel(); hideTask = nil
        guard shown != Self.trayID else { return }
        captureTask?.cancel()
        endPeek()
        shown = Self.trayID

        let items = refs.map { ref in
            let meta = metaFor(ref.pid)
            return WindowPreviewItem(ref: ref, name: meta.name, icon: meta.icon, image: nil)
        }
        let title = "Hidden windows and popups"
        let subtitle = refs.count == 1 ? "1 window · click to bring it back" : "\(refs.count) windows · click one to bring it back"
        render(title: title, subtitle: subtitle, content: .windows(items))
        place(near: tile, railSide: railSide, bounds: bounds)
        appear("tray")

        let shownRefs = Array(refs.prefix(RailHoverCard.maxRows))
        captureTask = Task { [weak self] in
            let titles = await WindowTitles.titles(for: shownRefs)
            guard !Task.isCancelled, !titles.isEmpty, let self, self.shown == Self.trayID else { return }
            let named = items.map { WindowPreviewItem(ref: $0.ref, name: titles[$0.ref.id] ?? $0.name, icon: $0.icon, image: nil) }
            self.render(title: title, subtitle: subtitle, content: .windows(named))
        }
    }

    /// #109: the cog's problem list. Same card, placement and hide grace as the tray; nothing to
    /// capture, so it is drawn at once.
    static let problemsID = UUID()
    func showProblems(_ problems: [Problem], tile: CGRect, railSide: RailSide, bounds: CGRect) {
        hideTask?.cancel(); hideTask = nil
        guard shown != Self.problemsID else { return }
        captureTask?.cancel()
        endPeek()
        shown = Self.problemsID
        render(title: problems.count == 1 ? "1 problem" : "\(problems.count) problems",
               subtitle: "Each clears itself once it is fixed", content: .problems(problems))
        place(near: tile, railSide: railSide, bounds: bounds)
        appear("problems")
    }

    /// The pointer left `item`. Hides after a grace period, unless it has landed on the card
    /// itself — without which the "Open Screen Recording settings…" button could never be
    /// reached. A late exit for a tile the card has already moved on from is ignored.
    func hide(_ item: UUID) {
        guard shown == item else { return }
        hideAfterGrace("left the tile")
    }

    private func hideAfterGrace(_ reason: String) {
        captureTask?.cancel(); captureTask = nil
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideGrace)
            guard !Task.isCancelled, let self, !self.pointerInCard else { return }
            self.hideNow(reason)
        }
    }

    /// `reason` is for the trace (#182): `log stream --level debug --predicate 'category == "hover"'`.
    func hideNow(_ reason: String = "dismissed") {
        if let shown { Self.log.debug("hover card hide \(shown, privacy: .public) \(reason, privacy: .public)") }
        captureTask?.cancel(); captureTask = nil
        hideTask?.cancel(); hideTask = nil
        endPeek()
        stopWatchingPointer()
        shown = nil
        shownIndex = nil
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
    ///
    /// #179: the click ends a peek by itself (every command but `.peek` does), and the window it
    /// focuses stays on screen; no `.peek(nil)` follows it to race the focus.
    func select(_ ref: SpacialShellProtocol.WindowRef) {
        peekTask?.cancel(); peekTask = nil
        peeking = nil
        send(shown == Self.trayID ? .recoverWindow(ref) : .focusWindowRef(ref))
        hideNow("clicked")
    }

    /// #182: the rail `state` was drawn afresh. A tile removed or moved by that never reports an
    /// exit, so a card about a workspace that has gone, or moved to another row, would be left
    /// beside a tile that is no longer it; and one about a tray that has emptied, beside nothing.
    func railChanged(_ state: ScreenShellState) {
        guard let shown else { return }
        switch shown {
        case Self.problemsID:
            return   // `ShellController.update(problems:)` owns this one
        case Self.trayID:
            if state.tray.isEmpty { hideNow("tray emptied") }
        default:
            guard let row = state.rail.first(where: { $0.id == shown }) else { return hideNow("workspace gone") }
            if row.index != shownIndex { hideNow("workspace moved") }
        }
    }

    // MARK: - #182 pointer safety net

    /// On screen, and watching the pointer until it is hidden again.
    private func appear(_ what: String) {
        Self.log.debug("hover card show \(self.shown?.uuidString ?? "-", privacy: .public) \(what, privacy: .public)")
        // A new tile's hover: the pointer is on the rail, whatever the card last heard about it.
        pointerInCard = false
        present(window)
        guard pointerMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }) { pointerMonitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.checkPointer() }
            return event
        }) { pointerMonitors.append(m) }
    }

    private func stopWatchingPointer() {
        pointerMonitors.forEach(NSEvent.removeMonitor); pointerMonitors = []
        pointerCheck?.cancel(); pointerCheck = nil
        outsideSince = nil
    }

    /// The pointer moved (or the grace ran out). Hides the card once the pointer has been off both
    /// the rail and the card for the hide grace, whatever exits SwiftUI did or did not deliver.
    func checkPointer() {
        guard shown != nil else { return }
        let p = pointer()
        if window.frame.contains(p) || railFrame()?.contains(p) == true {
            outsideSince = nil
            pointerCheck?.cancel(); pointerCheck = nil
            return
        }
        let t = now()
        guard let since = outsideSince else {
            outsideSince = t
            pointerCheck = Task { [weak self] in
                try? await Task.sleep(for: Self.hideGrace)
                guard !Task.isCancelled else { return }
                self?.checkPointer()
            }
            return
        }
        if t - since >= Self.hideGrace { hideNow("pointer off rail and card") }
    }

    /// #179: the pointer entered or left a preview. Entering rings it at once and peeks its window
    /// after `peekDwell`; leaving takes the ring off and ends the peek after the same dwell, unless
    /// another preview is entered first — then that one's peek replaces it directly. A late exit
    /// from a preview the pointer has already left for another is ignored.
    func previewHovered(_ ref: SpacialShellProtocol.WindowRef, inside: Bool) {
        if inside {
            highlighted = ref
        } else {
            guard highlighted == ref else { return }
            highlighted = nil
        }
        redraw()
        schedulePeek(highlighted)
    }

    private func schedulePeek(_ ref: SpacialShellProtocol.WindowRef?) {
        peekTask?.cancel(); peekTask = nil
        // Nothing to end. A preview is always asked for again, even the one peeked: a hotkey may
        // have ended that peek in the model since.
        guard ref != nil || peeking != nil else { return }
        peekTask = Task { [weak self, peekDwell] in
            try? await Task.sleep(for: peekDwell)
            guard !Task.isCancelled, let self else { return }
            self.peekTask = nil
            self.peeking = ref
            self.send(.peek(ref))
        }
    }

    /// #179: the model's peek, on every publish. One this card no longer wants, and is not about
    /// to ask for, is ended: commands leave for the store in separate tasks, so a `.peek` can land
    /// after the click or the `.peek(nil)` that should have ended it, and a `.peek(nil)` sent while
    /// the screen was locked was refused.
    func modelPeeked(_ peek: SpacialShellProtocol.WindowRef?) {
        guard peek != nil, peeking == nil, peekTask == nil else { return }
        send(.peek(nil))
    }

    /// Ends a peek now, without the dwell: the card is going, or is about something else now.
    private func endPeek() {
        peekTask?.cancel(); peekTask = nil
        highlighted = nil
        if peeking != nil { peeking = nil; send(.peek(nil)) }
    }

    /// The preview ringed and the window peeked, for tests.
    var peekState: (highlighted: SpacialShellProtocol.WindowRef?, peeking: SpacialShellProtocol.WindowRef?) { (highlighted, peeking) }

    /// The workspace the card is about, for tests; nil when hidden.
    var shownWorkspace: UUID? { shown }

    // MARK: - drawing

    private func render(title: String, subtitle: String?, content: RailHoverCard.Content) {
        drawn = (title, subtitle, content)
        redraw()
    }

    private func redraw() {
        host.rootView = RailHoverCard(
            title: drawn.title, subtitle: drawn.subtitle, content: drawn.content,
            onGrantAccess: { ScreenRecordingAccess.request() },
            onHoverCard: { [weak self] inside in
                guard let self else { return }
                self.pointerInCard = inside
                if inside { self.hideTask?.cancel() } else { self.hideAfterGrace("left the card") }
            },
            onSelect: { [weak self] in self?.select($0) },
            highlighted: highlighted,
            onHoverPreview: { [weak self] ref, inside in self?.previewHovered(ref, inside: inside) },
            onProblemAction: { [weak self] command in
                self?.send(command)
                self?.hideNow("clicked")   // the dialog it opens is where the user's attention goes
            })
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

    /// The window count. The category is the title now (#183), so it is not repeated here.
    private func subtitle(_ item: WorkspaceRailItem) -> String? {
        if item.isTrailingEmpty { return nil }
        return item.windowCount == 1 ? "1 window" : "\(item.windowCount) windows"
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
