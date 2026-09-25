import Foundation

public struct LayoutConfig: Sendable, Equatable {
    public var gap: CGFloat
    /// #9: what a workspace's layout id means. Every caller builds this from the effective config,
    /// so the #77 prediction and the real switch can never disagree about a layout.
    public var layouts: LayoutCatalogue
    public init(gap: CGFloat, layouts: LayoutCatalogue = .builtins) { self.gap = gap; self.layouts = layouts }
}

public enum Placement: Sendable, Equatable { case frame(CGRect), parked(CGPoint), untouched }
public enum Write: Sendable, Equatable { case setFrame(WindowRef, CGRect), setPosition(WindowRef, CGPoint) }

public enum Reconciler {
    static let fallbackSize = CGSize(width: 800, height: 600)

    /// Controller ruling (macOS 26.5): a window parked at `y = maxY − 1` is clamped by macOS so
    /// its title bar stays on screen, and the frame that comes back sits roughly 32 pt above the
    /// origin we asked for. Anything that compares a parked window's *y* against what we requested
    /// has to allow for that; x is unaffected and stays exact. 40 pt is the observed ~32 with room
    /// for a taller title bar.
    static let titleBarClampTolerance: CGFloat = 40

    /// Spec §5, §7.4, §8. Ignored windows are absent from the result.
    public static func desired(world: World, displays: [DisplayInfo], config: LayoutConfig,
                               observed: [WindowRef: CGRect], prePark: [WindowRef: CGRect],
                               parkedNow: Set<WindowRef>, zeroSliver: Set<WindowRef>,
                               insets: [DisplayID: ShellInsets] = [:],
                               suspended: Set<WindowRef> = []) -> [WindowRef: Placement] {
        var out: [WindowRef: Placement] = [:]
        let byId = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        for (sid, screen) in world.screens {
            guard let display = byId[sid] else { continue }
            let corner = Parking.corner(for: display, among: displays)
            let visible = display.visibleFrame
            func park(_ w: WindowRef) -> Placement {
                let size = observed[w]?.size ?? fallbackSize
                return .parked(Parking.origin(windowSize: size, visibleFrame: visible, corner: corner, sliver: zeroSliver.contains(w) ? 0 : 1))
            }
            var rect = viewport(screen: screen, display: display, insets: insets[sid, default: .zero])
            rect = rect.insetBy(dx: config.gap, dy: config.gap)
            rect.size.height -= 1   // macOS may refuse full-height frames on stacked displays
            for (i, ws) in screen.workspaces.enumerated() {
                let active = i == screen.activeIndex
                let tiled = world.tiled(in: ws)
                let focusedIndex = ws.anchor.flatMap { tiled.firstIndex(of: $0) } ?? 0
                let frames = active ? LayoutEngine.frames(config.layouts.resolve(ws.layout).def, count: tiled.count, focused: focusedIndex, in: rect, gap: config.gap) : []
                for w in ws.windows {
                    if suspended.contains(w) { out[w] = .untouched; continue }
                    // macOS owns a fullscreen window's frame and Space: never frame it, never park it.
                    // Same for one on another Space (#55) — a write there lands where nobody can see.
                    if world.hidden.contains(w) || world.fullscreen.contains(w) || world.offSpace.contains(w) {
                        out[w] = .untouched; continue
                    }
                    if !active { out[w] = park(w); continue }
                    if ws.floating.contains(w) {
                        if parkedNow.contains(w) {
                            let restored = prePark[w] ?? centered(size: observed[w]?.size ?? fallbackSize, in: rect)
                            out[w] = .frame(restored)
                        } else if let o = observed[w], mostlyOn(o, displays) != sid {
                            // The model filed it on this display (a move-to-screen, a spill) but
                            // it is sitting on another: carry it here, centred. Floating windows
                            // are otherwise never written, so the move stayed model-only and the
                            // store's frame-owner rule (#72) filed it straight back.
                            out[w] = .frame(centered(size: o.size, in: rect))
                        } else { out[w] = .untouched }
                        continue
                    }
                    let ti = tiled.firstIndex(of: w)!
                    out[w] = frames[ti].map { .frame($0) } ?? park(w)
                }
            }
        }
        for w in world.ephemeral { out[w] = .untouched }
        return out
    }

    /// The area a display's windows are tiled in: its visible frame (or the screen's own rect),
    /// less whatever the shell panels claim. Also the clip a switch animation slides within (#64).
    public static func viewport(screen: Screen, display: DisplayInfo, insets: ShellInsets) -> CGRect {
        insets.apply(to: screen.rect ?? display.visibleFrame)
    }

    /// Writes needed to move reality to `desired`. Unparks/frames first, then parks. Stable order by window id.
    public static func plan(desired: [WindowRef: Placement], observed: [WindowRef: CGRect], parkedNow: Set<WindowRef>) -> [Write] {
        var frames: [Write] = [], parks: [Write] = []
        for (w, p) in desired.sorted(by: { $0.key.id < $1.key.id }) {
            switch p {
            case .untouched: continue
            case .frame(let f):
                if let o = observed[w], approx(o, f), !parkedNow.contains(w) { continue }
                frames.append(.setFrame(w, f))
            case .parked(let origin):
                // `titleBarClampTolerance`: parking at (maxX-1, maxY-1) gets clamped by macOS to
                // roughly (maxX-1, maxY-32). Naive origin comparison would re-park every reconcile
                // cycle, so once a window is already parked we only compare x — y is off by up to
                // `titleBarClampTolerance` through no fault of ours, and ignoring it entirely is
                // the same judgement, made once.
                if parkedNow.contains(w), let o = observed[w], abs(o.origin.x - origin.x) < 1 { continue }
                parks.append(.setPosition(w, origin))
            }
        }
        return frames + parks
    }

    /// Is this frame beyond reach — off every display? (#52.) A parking corner leaves a 1 pt sliver
    /// on screen by design, and a window dragged half off an edge is still grabbable, so "reachable"
    /// is generous: a tenth of the window visible somewhere counts. Anything less is a window the
    /// user cannot click, however healthy the model believes it to be.
    public static func isBeyondReach(_ frame: CGRect, displays: [DisplayInfo], minVisible: CGFloat = 0.1) -> Bool {
        let area = frame.width * frame.height
        guard area > 0 else { return true }
        let visible = displays.map { d -> CGFloat in
            let i = d.visibleFrame.intersection(frame)
            return i.isNull ? 0 : i.width * i.height
        }.max() ?? 0
        return visible / area < minVisible
    }

    /// The display holding most of `frame`, nil when it is on none.
    static func mostlyOn(_ frame: CGRect, _ displays: [DisplayInfo]) -> DisplayID? {
        displays.map { d -> (DisplayID, CGFloat) in
            let a = d.frame.intersection(frame); return (d.id, a.isNull ? 0 : a.width * a.height)
        }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }

    static func centered(size: CGSize, in rect: CGRect) -> CGRect {
        CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
    static func approx(_ a: CGRect, _ b: CGRect, tol: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol && abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
    }
}
