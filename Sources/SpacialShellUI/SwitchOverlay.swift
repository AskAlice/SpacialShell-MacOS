import AppKit
import OSLog
import QuartzCore
import ScreenCaptureKit
import SpacialShellKit
import SpacialShellPlatform
import SpacialShellProtocol

/// #64's motion, as #65 ruled it: screenshot proxies (mechanism 3b in
/// `2026-09-12-window-animation-feasibility.md`).
///
/// `prepare` captures, per display, a backdrop — the tiling area with the moving windows taken out,
/// so whatever else is there (wallpaper, floating windows, the gaps) stays put — and one image per
/// moving window, then covers the tiling area with them, each window drawn where it was. The store
/// writes the real frames underneath; `play` slides the images to where the real windows now are
/// and drops the overlay on landing, when the pictures sit exactly over the windows they show.
///
/// #77: the pictures are kept. `prefetch` takes the next switches' pictures ahead of time, and the
/// last few prepared sets stay, so a switch whose pictures are already here and fresh starts with
/// no capture at all.
///
/// The overlay is click-through and never key, like every other panel here. Anything that goes
/// wrong — no Screen Recording grant, reduce-motion, a window ScreenCaptureKit will not hand over —
/// answers "place instantly", which is always safe: the
/// real windows are at real frames the whole time. A second switch while one is in flight drops
/// that flight and animates the new one from where the windows really are.
public final class SwitchOverlay: SwitchAnimator {
    private let stage: Stage

    @MainActor public init() { stage = Stage() }

    public func prepare(_ transitions: [Transition]) async -> Bool { await stage.prepare(transitions) }
    public func play() async { await stage.play() }
    public func prefetch(_ predicted: [[Transition]]) async { await stage.prefetch(predicted) }
}

@MainActor
private final class Stage {
    private struct Sprite { let layer: CALayer; let to: CGRect }

    /// One display's share of a switch: which windows move, from where. A different arrangement of
    /// the same windows is a different key, so pictures are never stretched over another layout.
    private struct Key: Equatable {
        let display: DisplayID, ids: [WindowID], from: [CGRect]
        init(_ t: Transition) {
            let ms = t.moves.sorted { $0.ref.id < $1.ref.id }
            display = t.display; ids = ms.map(\.ref.id); from = ms.map(\.from)
        }
    }
    /// Every picture one transition needs; never partial.
    private struct Pictures { let key: Key; let backdrop: CGImage; let windows: [WindowID: CGImage]; let taken: ContinuousClock.Instant }

    private var panels: [NSPanel] = []
    private var sprites: [Sprite] = []
    /// Bumped by every prepare and teardown, so a capture or a landing that belongs to a switch
    /// that has since been dropped does nothing.
    private var token = 0
    private var busy = false
    /// The last `preparedKept` sets a switch flew, most recently used first, and the current
    /// prefetches. A key comes from the store's own world, so a closed window is never asked for;
    /// `listing` still evicts what the window server no longer has, to free the memory.
    // ponytail: up to ~7 sets of full-viewport backdrops (tens of MB each on a 5K display); share
    // one backdrop per display if memory shows up.
    private var prepared: [Pictures] = []
    private var prefetched: [Pictures] = []
    private var prefetchTask: Task<Void, Never>?
    /// A prefetch that arrived mid-flight; it starts once the overlay lands.
    private var pendingPrefetch: [[Transition]]?
    private var content: (listing: SCShareableContent, at: ContinuousClock.Instant)?

    static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "motion")
    static let duration: CFTimeInterval = 0.2
    /// The pictures must not be pulled before the window server has drawn the real windows under
    /// them; the feasibility study's hand-off rule. 200 ms of flight already covers the AX writes.
    // ponytail: fixed hold rather than polling CGWindowList for the landed frame — poll if a seam shows.
    static let landingHold = Duration.milliseconds(30)
    /// An overlay whose `play` never came (its reconcile was superseded) must not outlive it.
    static let watchdog = Duration.seconds(1)
    static let preparedKept = 3
    /// How old a picture may be and still fly. The real window is uncovered at landing, so anything
    /// that changed since the picture was taken pops in then; older pictures are taken again.
    // ponytail: a fixed age, not change tracking — watch window damage with an SCStream if 3 s shows.
    static let freshFor = Duration.seconds(3)
    /// One window-server listing serves a burst of switches and their prefetches.
    static let listingFreshFor = Duration.seconds(1)

    func prepare(_ transitions: [Transition]) async -> Bool {
        // A real switch outranks every prefetch.
        prefetchTask?.cancel(); prefetchTask = nil
        // A switch that arrives mid-flight drops that flight (its real windows are already at their
        // final frames) and animates from there, never queueing, so the model is never behind the
        // motion. Skipping instead meant the second of two quick presses never animated (#66).
        // ponytail: restart, not a smooth retarget — a held key restarts every repeat and only the
        // last one slides; blend from the in-flight positions if that feels choppy.
        let moves = transitions.reduce(0) { $0 + $1.moves.count }
        if busy { teardown(); Self.log.notice("switch restarted: previous still in flight") }
        guard ScreenRecordingAccess.isGranted else {
            Self.log.notice("switch instant: no Screen Recording grant"); return false
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            Self.log.notice("switch instant: reduce motion"); return false
        }
        busy = true
        token += 1
        let mine = token

        let started = ContinuousClock.now
        let hits = transitions.map { cached(Key($0)) }
        let missing = zip(transitions, hits).filter { $0.1 == nil }.map(\.0)
        guard let captured = await capture(missing), mine == token else {
            if mine == token { busy = false }
            Self.log.notice("switch instant: capture failed or superseded (\(moves) moves)")
            return false
        }
        var fresh = captured.makeIterator()
        let pictures = hits.map { $0 ?? fresh.next()! }
        remember(pictures)
        let cache = missing.isEmpty ? "hit" : missing.count == transitions.count ? "miss" : "partial"
        Self.log.notice("switch animating \(moves) moves on \(transitions.count) display(s); cache \(cache, privacy: .public); capture \(String(describing: ContinuousClock.now - started), privacy: .public)")
        show(transitions, pictures)
        // One frame for the window server to composite the overlay before anything moves under it.
        try? await Task.sleep(for: .milliseconds(16))
        guard mine == token else { return false }
        Task { [weak self] in
            try? await Task.sleep(for: Self.watchdog)
            guard let self, self.token == mine else { return }
            self.teardown()
            self.startPrefetch()
        }
        return true
    }

    func play() {
        guard busy, !sprites.isEmpty else { return }
        let mine = token
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1))
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.landingHold)
                guard let self, self.token == mine else { return }
                self.teardown()
                self.startPrefetch()
            }
        }
        for s in sprites { s.layer.frame = s.to }
        CATransaction.commit()
    }

    /// Never while a switch is on screen: a prefetch that arrives mid-flight waits for the landing.
    func prefetch(_ predicted: [[Transition]]) {
        pendingPrefetch = predicted
        if !busy { startPrefetch() }
    }

    private func teardown() {
        token += 1
        busy = false
        for p in panels { p.orderOut(nil) }
        panels = []
        sprites = []
    }

    // MARK: - cache

    private func cached(_ key: Key) -> Pictures? {
        (prepared + prefetched).first { $0.key == key && ContinuousClock.now - $0.taken < Self.freshFor }
    }

    private func remember(_ used: [Pictures]) {
        for p in used.reversed() {
            prepared.removeAll { $0.key == p.key }
            prepared.insert(p, at: 0)
        }
        prepared = Array(prepared.prefix(Self.preparedKept))
    }

    /// Takes whatever the predicted switches still lack, one switch at a time at low priority, and
    /// stops the moment a real switch starts (`prepare` cancels it; `busy` is checked between).
    private func startPrefetch() {
        guard let predicted = pendingPrefetch else { return }
        pendingPrefetch = nil
        prefetchTask?.cancel()
        guard ScreenRecordingAccess.isGranted, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let wanted = predicted.joined().map(Key.init)
        prefetched.removeAll { !wanted.contains($0.key) }
        prefetchTask = Task(priority: .utility) { [weak self] in
            for ts in predicted {
                guard let self, !Task.isCancelled, !self.busy else { return }
                let missing = ts.filter { self.cached(Key($0)) == nil }
                guard !missing.isEmpty, let pictures = await self.capture(missing), !Task.isCancelled else { continue }
                for p in pictures {
                    self.prefetched.removeAll { $0.key == p.key }
                    self.prefetched.append(p)
                }
            }
        }
    }

    /// The window server's listing, reused for `listingFreshFor`. Every new one evicts the pictures
    /// of windows it no longer has.
    private func listing(refresh: Bool) async -> SCShareableContent? {
        if !refresh, let content, ContinuousClock.now - content.at < Self.listingFreshFor { return content.listing }
        guard let listing = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return nil }
        content = (listing, .now)
        let live = Set(listing.windows.map(\.windowID))
        func alive(_ p: Pictures) -> Bool {
            let ids = WindowIdentities.captureIDs(for: p.key.ids)
            return p.key.ids.allSatisfy { ids[$0].map(live.contains) == true }
        }
        prepared.removeAll { !alive($0) }
        prefetched.removeAll { !alive($0) }
        return listing
    }

    // MARK: - drawing

    private func show(_ transitions: [Transition], _ pictures: [Pictures]) {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (t, shots) in zip(transitions, pictures) {
            let vp = t.viewport
            let panel = OverlayPanel()
            panel.setFrame(NSRect(x: vp.minX, y: mainHeight - vp.maxY, width: vp.width, height: vp.height),
                           display: false)
            let view = NSView(frame: NSRect(origin: .zero, size: vp.size))
            // Layer-*hosting*: the layer is assigned before `wantsLayer`, so AppKit never touches
            // its geometry, and it keeps Core Animation's bottom-left origin. The AX → layer flip is
            // done explicitly by `local` below. (Setting `isGeometryFlipped` on a layer-*backed*
            // view did not hold — AppKit owns it — and rows travelled the wrong way vertically:
            // Fn+S came in from the top, #66.)
            let root = CALayer()
            view.layer = root
            view.wantsLayer = true
            /// An AX (top-left, global) rect in this layer's bottom-left space.
            func local(_ r: CGRect) -> CGRect {
                CGRect(x: r.minX - vp.minX, y: vp.maxY - r.maxY, width: r.width, height: r.height)
            }
            root.masksToBounds = true
            root.contents = shots.backdrop
            root.contentsGravity = .resize
            for m in t.moves {
                guard let image = shots.windows[m.ref.id] else { continue }
                let layer = CALayer()
                layer.contents = image
                layer.contentsGravity = .resize
                layer.frame = local(m.from)
                root.addSublayer(layer)
                sprites.append(Sprite(layer: layer, to: local(m.to)))
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        CATransaction.commit()
    }

    // MARK: - capture

    private enum Slot: Sendable { case backdrop(Int), window(Int, WindowID) }
    /// One screenshot to take. Its filter and configuration are built once and then only read, by
    /// the one child task that takes it.
    private struct Shot: @unchecked Sendable { let slot: Slot; let filter: SCContentFilter; let config: SCStreamConfiguration }

    /// Every picture the transitions need, in their order, or nil if any is missing — a window with
    /// no image would pop in at the end instead of sliding, which is worse than no animation at all.
    private func capture(_ transitions: [Transition]) async -> [Pictures]? {
        guard !transitions.isEmpty else { return [] }
        let taken = ContinuousClock.now
        // A reused listing can predate a window that has just opened: one retry with a new one.
        var shots: [Shot]?
        for refresh in [false, true] where shots == nil {
            guard let listing = await listing(refresh: refresh) else { return nil }
            shots = Self.shots(transitions, in: listing)
        }
        guard let shots else { return nil }

        // All at once: the backdrop and every window, on every display.
        let images = await withTaskGroup(of: (Slot, CGImage?).self) { group in
            for s in shots {
                group.addTask { (s.slot, try? await SCScreenshotManager.captureImage(contentFilter: s.filter, configuration: s.config)) }
            }
            var out: [(Slot, CGImage?)] = []
            for await r in group { out.append(r) }
            return out
        }
        var backdrops: [Int: CGImage] = [:], windows: [Int: [WindowID: CGImage]] = [:]
        for (slot, image) in images {
            guard let image else { return nil }
            switch slot {
            case .backdrop(let i): backdrops[i] = image
            case .window(let i, let id): windows[i, default: [:]][id] = image
            }
        }
        var out: [Pictures] = []
        for (i, t) in transitions.enumerated() {
            guard let back = backdrops[i] else { return nil }
            out.append(Pictures(key: Key(t), backdrop: back, windows: windows[i] ?? [:], taken: taken))
        }
        return out
    }

    private static func shots(_ transitions: [Transition], in content: SCShareableContent) -> [Shot]? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var byID: [CGWindowID: SCWindow] = [:]
        for w in content.windows where w.owningApplication?.processID != ownPID { byID[w.windowID] = w }
        let refs = transitions.flatMap { $0.moves.map(\.ref) }
        // `ref.id` is minted by SpacialShell (#18); `captureIDs` is the public match to the window server.
        let captureIDs = WindowIdentities.captureIDs(for: refs.map(\.id))

        var shots: [Shot] = []
        for (i, t) in transitions.enumerated() {
            let center = CGPoint(x: t.viewport.midX, y: t.viewport.midY)
            guard let display = content.displays.first(where: { $0.frame.contains(center) }) else { return nil }
            let scale = Self.scale(of: display)
            let moving = t.moves.compactMap { captureIDs[$0.ref.id].flatMap { byID[$0] } }
            guard moving.count == t.moves.count else { return nil }

            let backdrop = SCStreamConfiguration()
            backdrop.sourceRect = t.viewport.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            backdrop.width = Int((t.viewport.width * scale).rounded())
            backdrop.height = Int((t.viewport.height * scale).rounded())
            backdrop.showsCursor = false
            shots.append(Shot(slot: .backdrop(i), filter: SCContentFilter(display: display, excludingWindows: moving),
                              config: backdrop))

            for (m, window) in zip(t.moves, moving) {
                let config = SCStreamConfiguration()
                config.width = max(1, Int((window.frame.width * scale).rounded()))
                config.height = max(1, Int((window.frame.height * scale).rounded()))
                config.showsCursor = false
                shots.append(Shot(slot: .window(i, m.ref.id), filter: SCContentFilter(desktopIndependentWindow: window),
                                  config: config))
            }
        }
        return shots
    }

    private static func scale(of display: SCDisplay) -> CGFloat {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        }?.backingScaleFactor ?? 2
    }
}

/// The furniture the proxies fly in: click-through, never key, above the tiled windows. It covers
/// only the tiling area, which the rail and bar sit outside of, so it never hides a panel.
private final class OverlayPanel: PanelWindow {
    override init() {
        super.init()
        ignoresMouseEvents = true
    }
}
