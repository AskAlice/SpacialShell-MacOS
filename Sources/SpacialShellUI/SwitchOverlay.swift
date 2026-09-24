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
}

@MainActor
private final class Stage {
    private struct Sprite { let layer: CALayer; let to: CGRect }

    private var panels: [NSPanel] = []
    private var sprites: [Sprite] = []
    /// Bumped by every prepare and teardown, so a capture or a landing that belongs to a switch
    /// that has since been dropped does nothing.
    private var token = 0
    private var busy = false

    static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "motion")
    static let duration: CFTimeInterval = 0.25
    /// The pictures must not be pulled before the window server has drawn the real windows under
    /// them; the feasibility study's hand-off rule. 250 ms of flight already covers the AX writes.
    // ponytail: fixed hold rather than polling CGWindowList for the landed frame — poll if a seam shows.
    static let landingHold = Duration.milliseconds(50)
    /// An overlay whose `play` never came (its reconcile was superseded) must not outlive it.
    static let watchdog = Duration.seconds(1)

    func prepare(_ transitions: [Transition]) async -> Bool {
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
        guard let shots = await Self.capture(transitions), mine == token else {
            if mine == token { busy = false }
            Self.log.notice("switch instant: capture failed or superseded (\(moves) moves)")
            return false
        }
        Self.log.notice("switch animating \(moves) moves on \(transitions.count) display(s); capture \(String(describing: ContinuousClock.now - started), privacy: .public)")
        show(transitions, shots)
        // One frame for the window server to composite the overlay before anything moves under it.
        try? await Task.sleep(for: .milliseconds(16))
        guard mine == token else { return false }
        Task { [weak self] in
            try? await Task.sleep(for: Self.watchdog)
            guard let self, self.token == mine else { return }
            self.teardown()
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
            }
        }
        for s in sprites { s.layer.frame = s.to }
        CATransaction.commit()
    }

    private func teardown() {
        token += 1
        busy = false
        for p in panels { p.orderOut(nil) }
        panels = []
        sprites = []
    }

    // MARK: - drawing

    private func show(_ transitions: [Transition], _ shots: Shots) {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for t in transitions {
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
            root.contents = shots.backdrops[t.display]
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

    private struct Shots { var backdrops: [DisplayID: CGImage] = [:]; var windows: [WindowID: CGImage] = [:] }

    /// Every picture a switch needs, or nil if any is missing — a window with no image would pop
    /// in at the end instead of sliding, which is worse than no animation at all.
    private static func capture(_ transitions: [Transition]) async -> Shots? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var byID: [CGWindowID: SCWindow] = [:]
        for w in content.windows where w.owningApplication?.processID != ownPID { byID[w.windowID] = w }
        let refs = transitions.flatMap { $0.moves.map(\.ref) }
        // `ref.id` is minted by SpacialShell (#18); `captureIDs` is the public match to the window server.
        let captureIDs = WindowIdentities.captureIDs(for: refs.map(\.id))

        // ponytail: captures run one after another (~40 ms each); a TaskGroup if the lead-in feels slow.
        var shots = Shots()
        for t in transitions {
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
            guard let back = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: moving),
                configuration: backdrop) else { return nil }
            shots.backdrops[t.display] = back

            for (m, window) in zip(t.moves, moving) {
                let config = SCStreamConfiguration()
                config.width = max(1, Int((window.frame.width * scale).rounded()))
                config.height = max(1, Int((window.frame.height * scale).rounded()))
                config.showsCursor = false
                guard let image = try? await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: window),
                    configuration: config) else { return nil }
                shots.windows[m.ref.id] = image
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
