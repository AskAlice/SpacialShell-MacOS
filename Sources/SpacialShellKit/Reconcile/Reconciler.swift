import Foundation

public struct LayoutConfig: Sendable, Equatable {
    public var gap: CGFloat
    public init(gap: CGFloat) { self.gap = gap }
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
            var rect = insets[sid, default: .zero].apply(to: screen.rect ?? visible)
            rect = rect.insetBy(dx: config.gap, dy: config.gap)
            rect.size.height -= 1   // macOS may refuse full-height frames on stacked displays
            for (i, ws) in screen.workspaces.enumerated() {
                let active = i == screen.activeIndex
                let tiled = world.tiled(in: ws)
                let focusedIndex = ws.anchor.flatMap { tiled.firstIndex(of: $0) } ?? 0
                let frames = active ? LayoutEngine.frames(ws.layout, count: tiled.count, focused: focusedIndex, in: rect, gap: config.gap) : []
                for w in ws.windows {
                    if suspended.contains(w) { out[w] = .untouched; continue }
                    if world.hidden.contains(w) { out[w] = .untouched; continue }
                    if !active { out[w] = park(w); continue }
                    if ws.floating.contains(w) {
                        if parkedNow.contains(w) {
                            let restored = prePark[w] ?? centered(size: observed[w]?.size ?? fallbackSize, in: rect)
                            out[w] = .frame(restored)
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

    static func centered(size: CGSize, in rect: CGRect) -> CGRect {
        CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
    static func approx(_ a: CGRect, _ b: CGRect, tol: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol && abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
    }
}
