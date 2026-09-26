import AppKit
import OSLog
import OpenTelemetryApi
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
/// last few prepared sets stay, so a switch whose pictures are already here starts with no capture.
///
/// #97: stale-while-revalidate — a kept set flies however old it is (the prefetch after landing
/// takes it again), and a switch with nothing kept waits at most `captureBudget` for its capture
/// before placing instantly; the late capture still lands in the cache for next time.
///
/// #140: re-tiles (a layout change, a window opening or closing next to the others) fly on the same
/// overlay, under `MotionRules`: a little longer, captured fresh every time, never cached, and
/// without feeding the rail thumbnails. The store only asks with `animate-retile` on.
///
/// The overlay is click-through and never key, like every other panel here. Anything that goes
/// wrong — no Screen Recording grant, reduce-motion, a window ScreenCaptureKit will not hand over —
/// answers "place instantly", which is always safe: the
/// real windows are at real frames the whole time. A second switch while one is in flight drops
/// that flight and animates the new one from where the windows really are.
public final class SwitchOverlay: SwitchAnimator {
    private let stage: Stage

    @MainActor public init() { stage = Stage() }

    public func prepare(_ transitions: [Transition], trace: SpanContext?, since: ContinuousClock.Instant) async -> Bool {
        await stage.prepare(transitions, trace: trace, since: since)
    }
    public func play(trace: SpanContext?) async { await stage.play(trace: trace) }
    public func prefetch(_ predicted: [[Transition]]) async { await stage.prefetch(predicted) }
}

@MainActor
private final class Stage {
    private struct Sprite { let layer: CALayer; let to: CGRect }

    private typealias Key = SwitchPictureKey
    /// Every picture one transition needs; never partial. Immutable, and so is a `CGImage`.
    private struct Pictures: @unchecked Sendable {
        let key: Key; let backdrop: CGImage; let windows: [WindowID: CGImage]; let taken: ContinuousClock.Instant
    }

    private var panels: [NSPanel] = []
    private var sprites: [Sprite] = []
    /// Bumped by every prepare and teardown, so a capture or a landing that belongs to a switch
    /// that has since been dropped does nothing.
    private var token = 0
    private var busy = false
    /// The sets switches flew and the current prefetches; `listing` evicts what the window server
    /// no longer has.
    private var cache = SwitchPictureCache<Pictures>()
    private var prefetchTask: Task<Void, Never>?
    /// A prefetch that arrived mid-flight; it starts once the overlay lands.
    private var pendingPrefetch: [[Transition]]?
    private var content: (listing: SCShareableContent, at: ContinuousClock.Instant)?
    /// #148: the flight in the air, ended when it lands or is dropped.
    private var playSpan: (any Span)?
    /// #140: the re-tile being measured, only with `SPACIAL_LOG_RETILE=1` (see `RetileProbe`).
    private var probe: RetileProbe?
    /// How long the flight `play` starts lasts: the prepared pass's `MotionRules.duration`.
    private var flight: CFTimeInterval = Stage.duration

    static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "motion")
    /// Test hook (#81), like the Simulator's slow animations: `defaults write sh.emu.SpacialShell
    /// SpacialMotionScale 100` stretches every switch (and its watchdog) 100x, so the e2e suite can
    /// photograph one mid-flight in a guest that cannot record 200 ms of motion. Unset: 1.
    static let scale = max(1, UserDefaults.standard.double(forKey: "SpacialMotionScale"))
    static let duration: CFTimeInterval = seconds(MotionRules([]).duration) * scale
    /// The pictures must not be pulled before the window server has drawn the real windows under
    /// them; the feasibility study's hand-off rule. 200 ms of flight already covers the AX writes.
    // ponytail: fixed hold rather than polling CGWindowList for the landed frame — poll if a seam shows.
    static let landingHold = Duration.milliseconds(30)
    /// An overlay whose `play` never came (its reconcile was superseded) must not outlive it.
    static let watchdog = Duration.seconds(1 * scale)
    /// #97: how long a switch with no kept pictures waits for its capture before placing instantly.
    /// Much longer and the switch reads as firing on key-up. Scaled by the test hook, so a slow
    /// guest still gets its slide.
    static let captureBudget = MotionRules.captureBudget * scale
    /// One window-server listing serves a burst of switches and their prefetches.
    static let listingFreshFor = Duration.seconds(1)

    /// #148: a child of the reconcile pass that asked for it.
    private static func span(_ name: String, trace: SpanContext?) -> any Span {
        let b = Telemetry.tracer().spanBuilder(spanName: name)
        if let trace { b.setParent(trace) } else { b.setNoParent() }
        return b.startSpan()
    }

    func prepare(_ transitions: [Transition], trace: SpanContext?, since: ContinuousClock.Instant) async -> Bool {
        // A real switch outranks every prefetch.
        prefetchTask?.cancel(); prefetchTask = nil
        let span = Self.span("animation.prepare", trace: trace)
        var outcome = "instant"
        // #97: command to slide (or to instant placement): the delay the key press feels.
        defer {
            span.setAttribute(key: "latency.ms", value: Self.ms(.now - since))
            span.setAttribute(key: "outcome", value: outcome); span.end()
        }
        // A switch that arrives mid-flight drops that flight (its real windows are already at their
        // final frames) and animates from there, never queueing, so the model is never behind the
        // motion. Skipping instead meant the second of two quick presses never animated (#66).
        // ponytail: restart, not a smooth retarget — a held key restarts every repeat and only the
        // last one slides; blend from the in-flight positions if that feels choppy.
        let rules = MotionRules(transitions)
        let kind = rules.kind.rawValue
        let moves = transitions.reduce(0) { $0 + $1.moves.count }
        span.setAttribute(key: "moves", value: moves)
        span.setAttribute(key: "displays", value: transitions.count)
        span.setAttribute(key: "kind", value: kind)
        if busy { teardown(); Self.log.notice("\(kind, privacy: .public) restarted: previous still in flight") }
        if case .instant(let why) = MotionRules.gate(screenRecording: ScreenRecordingAccess.isGranted,
                                                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
            outcome = why.rawValue
            Self.log.notice("\(kind, privacy: .public) instant: \(why.rawValue, privacy: .public)")
            return false
        }
        busy = true
        token += 1
        let mine = token
        flight = Self.seconds(rules.duration) * Self.scale

        let probe = RetileProbe.enabled && rules.kind == .retile ? RetileProbe(windows: moves, since: since, flight: flight) : nil
        self.probe = probe
        let started = ContinuousClock.now
        // #97: a kept set flies whatever its age; the prefetch after landing takes it again. A
        // re-tile is captured fresh every time and never kept (#140: `MotionRules.usesPictureCache`).
        let hits = transitions.map { rules.usesPictureCache ? cache.take(Key($0)) : nil }
        let missing = zip(transitions, hits).filter { $0.1 == nil }.map(\.0)
        let hit = missing.isEmpty ? "hit" : missing.count == transitions.count ? "miss" : "partial"
        span.setAttribute(key: "cache", value: hit)
        var result: [Pictures]?? = .some([])
        if !missing.isEmpty {
            // Its own task, so a switch's capture that overruns the budget still lands in the cache.
            let job = Task { [weak self] () -> [Pictures]? in
                guard let self, let got = await self.capture(missing, rules: rules, probe: probe) else { return nil }
                if rules.usesPictureCache { for p in got { self.cache.add(p.key, p, taken: p.taken) } }
                return got
            }
            probe?.captureBegan()
            result = await job.value(within: Self.captureBudget)
        }
        let capture = ContinuousClock.now - started
        probe?.captureEnded(capture)
        span.setAttribute(key: "capture.ms", value: Self.ms(capture))
        guard mine == token else { outcome = "superseded"; probe?.abandoned(outcome); return false }
        // #97, #140: over the budget, or any picture missing, and the windows are placed instantly.
        let captured = result ?? nil
        if case .instant(let why) = MotionRules.verdict(took: result == nil ? nil : capture, complete: captured != nil,
                                                       budget: Self.captureBudget) {
            busy = false
            outcome = why.rawValue
            probe?.abandoned(outcome); self.probe = nil
            Self.log.notice("\(kind, privacy: .public) instant: \(why.rawValue, privacy: .public) (\(moves) moves); capture \(Self.ms(capture), format: .fixed(precision: 1), privacy: .public) ms; latency \(Self.ms(.now - since), format: .fixed(precision: 1), privacy: .public) ms")
            return false
        }
        var fresh = (captured ?? []).makeIterator()
        let pictures = hits.map { $0 ?? fresh.next()! }
        show(transitions, pictures)
        probe?.shown()
        // One frame for the window server to composite the overlay before anything moves under it.
        try? await Task.sleep(for: .milliseconds(16))
        guard mine == token else { outcome = "superseded"; return false }
        outcome = "animating"
        Self.log.notice("\(kind, privacy: .public) animating \(moves) moves on \(transitions.count) display(s); cache \(hit, privacy: .public); capture \(Self.ms(capture), format: .fixed(precision: 1), privacy: .public) ms; latency \(Self.ms(.now - since), format: .fixed(precision: 1), privacy: .public) ms")
        Task { [weak self] in
            try? await Task.sleep(for: Self.watchdog)
            guard let self, self.token == mine else { return }
            self.teardown()
            self.startPrefetch()
        }
        return true
    }

    func play(trace: SpanContext?) {
        guard busy, !sprites.isEmpty else { return }
        let mine = token
        playSpan?.end()
        playSpan = Self.span("animation.play", trace: trace)
        playSpan?.setAttribute(key: "sprites", value: sprites.count)
        probe?.playing(on: panels.first?.contentView)
        CATransaction.begin()
        CATransaction.setAnimationDuration(flight)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1))
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.landingHold)
                guard let self, self.token == mine else { return }
                self.playSpan?.setAttribute(key: "landed", value: true)
                self.probe?.landed(); self.probe = nil
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
        playSpan?.end(); playSpan = nil
        probe?.abandoned("dropped before landing"); probe = nil
        token += 1
        busy = false
        for p in panels { p.orderOut(nil) }
        panels = []
        sprites = []
    }

    private static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
    private static func seconds(_ d: Duration) -> CFTimeInterval { ms(d) / 1000 }

    // MARK: - cache

    /// Takes whatever the predicted switches lack or hold only stale (#97: the revalidate half),
    /// one switch at a time at low priority, and
    /// stops the moment a real switch starts (`prepare` cancels it; `busy` is checked between).
    private func startPrefetch() {
        guard let predicted = pendingPrefetch else { return }
        pendingPrefetch = nil
        prefetchTask?.cancel()
        guard ScreenRecordingAccess.isGranted, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        cache.keepPrefetches(predicted.joined().map(Key.init))
        prefetchTask = Task(priority: .utility) { [weak self] in
            guard await CaptureGate.shared.admitsPrefetch else { return }   // #92: never the first capture
            for ts in predicted {
                guard let self, !Task.isCancelled, !self.busy else { return }
                let missing = ts.filter { self.cache.needsRefresh(Key($0), now: .now) }
                guard !missing.isEmpty, let pictures = await self.capture(missing, rules: MotionRules(missing)),
                      !Task.isCancelled else { continue }
                for p in pictures { self.cache.prefetch(p.key, p, taken: p.taken) }
            }
        }
    }

    /// The window server's listing, reused for `listingFreshFor`. Every new one evicts the pictures
    /// of windows it no longer has.
    private func listing(refresh: Bool) async -> SCShareableContent? {
        if !refresh, let content, ContinuousClock.now - content.at < Self.listingFreshFor { return content.listing }
        guard let listing = await CaptureGate.listing({
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }) else { return nil }
        content = (listing, .now)
        let live = Set(listing.windows.map(\.windowID))
        cache.removeAll { key in
            let ids = WindowIdentities.captureIDs(for: key.ids)
            return !key.ids.allSatisfy { ids[$0].map(live.contains) == true }
        }
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
    private func capture(_ transitions: [Transition], rules: MotionRules, probe: RetileProbe? = nil) async -> [Pictures]? {
        guard !transitions.isEmpty else { return [] }
        let taken = ContinuousClock.now
        // A reused listing can predate a window that has just opened: one retry with a new one.
        var shots: [Shot]?
        for refresh in [false, true] where shots == nil {
            guard let listing = await listing(refresh: refresh) else { return nil }
            shots = Self.shots(transitions, in: listing)
        }
        guard let shots else { return nil }

        // All at once: the backdrop and every window, on every display. Each is timed (#140).
        let measured = probe != nil
        let images = await withTaskGroup(of: (Slot, CGImage?, Duration).self) { group in
            for s in shots {
                group.addTask {
                    let sp = RetileProbe.signposter
                    let state = measured ? sp.beginInterval("retile.shot", id: sp.makeSignpostID()) : nil
                    let t0 = ContinuousClock.now
                    let image = await CaptureGate.image { try await SCScreenshotManager.captureImage(contentFilter: s.filter, configuration: s.config) }
                    if let state { sp.endInterval("retile.shot", state) }
                    return (s.slot, image, ContinuousClock.now - t0)
                }
            }
            var out: [(Slot, CGImage?, Duration)] = []
            for await r in group { out.append(r) }
            return out
        }
        var backdrops: [Int: CGImage] = [:], windows: [Int: [WindowID: CGImage]] = [:]
        for (slot, image, took) in images {
            if case .window = slot { probe?.shot(window: true, took) } else { probe?.shot(window: false, took) }
            guard let image else { return nil }
            switch slot {
            case .backdrop(let i): backdrops[i] = image
            case .window(let i, let id): windows[i, default: [:]][id] = image
            }
        }
        // #90: rail hover thumbnails, no extra capture. Not from a re-tile (#140: its CPU hot spot).
        if rules.feedsThumbnails { WindowThumbnails.shared.ingest(windows.values.joined()) }
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
        let refs = transitions.flatMap { $0.moves.map(\.ref) + $0.offstage }
        // `ref.id` is minted by SpacialShell (#18); `captureIDs` is the public match to the window server.
        let captureIDs = WindowIdentities.captureIDs(for: refs.map(\.id))

        var shots: [Shot] = []
        for (i, t) in transitions.enumerated() {
            let center = CGPoint(x: t.viewport.midX, y: t.viewport.midY)
            guard let display = content.displays.first(where: { $0.frame.contains(center) }) else { return nil }
            let scale = Self.scale(of: display)
            let moving = t.moves.compactMap { captureIDs[$0.ref.id].flatMap { byID[$0] } }
            guard moving.count == t.moves.count else { return nil }
            // #140: a re-tile's arriving and leaving windows are left out of the backdrop too. One
            // the window server no longer lists (closed) is simply not there to leave out.
            let offstage = t.offstage.compactMap { captureIDs[$0.id].flatMap { byID[$0] } }

            let backdrop = SCStreamConfiguration()
            backdrop.sourceRect = t.viewport.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            backdrop.width = Int((t.viewport.width * scale).rounded())
            backdrop.height = Int((t.viewport.height * scale).rounded())
            backdrop.showsCursor = false
            shots.append(Shot(slot: .backdrop(i), filter: SCContentFilter(display: display, excludingWindows: moving + offstage),
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
