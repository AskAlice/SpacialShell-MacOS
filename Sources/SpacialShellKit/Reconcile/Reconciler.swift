import Foundation

public struct LayoutConfig: Sendable, Equatable {
    /// Between tiles.
    public var gap: CGFloat
    /// #124: between the row and the screen edge (`screen-gap`); `gap` unless set.
    public var screenGap: CGFloat
    /// #9: what a workspace's layout id means. Every caller builds this from the effective config,
    /// so the #77 prediction and the real switch can never disagree about a layout.
    public var layouts: LayoutCatalogue
    public init(gap: CGFloat, screenGap: CGFloat? = nil, layouts: LayoutCatalogue = .builtins) {
        self.gap = gap; self.screenGap = screenGap ?? gap; self.layouts = layouts
    }
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

    /// Spec §5, §7.4, §8. Ignored windows and placeholders (#128) are absent from the result.
    /// `refused` and `unmovable` are what `WindowEchoes` learned from the echoes of our writes (#169).
    public static func desired(world: World, displays: [DisplayInfo], config: LayoutConfig,
                               observed: [WindowRef: CGRect], prePark: [WindowRef: CGRect],
                               parkedNow: Set<WindowRef>, zeroSliver: Set<WindowRef>,
                               insets: [DisplayID: ShellInsets] = [:],
                               suspended: Set<WindowRef> = [], refused: [WindowRef: Refusal] = [:],
                               unmovable: Set<WindowRef> = []) -> [WindowRef: Placement] {
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
            let rect = tilingRect(screen: screen, display: display, insets: insets[sid, default: .zero], screenGap: config.screenGap)
            for (i, ws) in screen.workspaces.enumerated() {
                let active = i == screen.activeIndex
                var attached: [(WindowRef, owner: WindowRef)] = []
                let tiled = world.tiled(in: ws)
                let focusedIndex = ws.anchor.flatMap { tiled.firstIndex(of: $0) } ?? 0
                let frames = active ? LayoutEngine.frames(config.layouts.resolve(ws.layout).def, count: tiled.count, focused: focusedIndex, in: rect, gap: config.gap, portions: ws.portions, split: ws.split(in: tiled)) : []
                for w in ws.windows {
                    // #128: a placeholder has no window — nothing to frame, park or leave alone.
                    if w.isPlaceholder { continue }
                    if suspended.contains(w) { out[w] = .untouched; continue }
                    // macOS owns a fullscreen window's frame and Space: never frame it, never park it.
                    // Same for one on another Space (#55) — a write there lands where nobody can see.
                    if world.hidden.contains(w) || world.fullscreen.contains(w) || world.offSpace.contains(w) {
                        out[w] = .untouched; continue
                    }
                    if let p = world.parents[w], World.isAttached(w, parent: p, in: ws) { attached.append((w, world.root(of: w))); continue }
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
                    out[w] = frames[ti].map { .frame(refused[w]?.fitted(in: $0, bounds: rect) ?? $0) } ?? park(w)
                }
                // #134: a sheet keeps its place on its owner — framed, parked or left alone with it,
                // at the offset it had from the owner. A parked pair measures from where both were
                // before parking, not from the corner macOS clamped them into.
                func base(_ r: WindowRef) -> CGRect? { parkedNow.contains(r) ? prePark[r] ?? observed[r] : observed[r] }
                func offsetOf(_ w: WindowRef, _ p: WindowRef) -> CGVector? {
                    zip2(base(w), base(p)).map { CGVector(dx: $0.minX - $1.minX, dy: $0.minY - $1.minY) }
                }
                // #165: a sheet macOS will not let us move (bound to its owner's title bar) that
                // would hang off the display moves its tiled owner sideways instead, just far
                // enough, for as long as it is open. Measured before any sheet is placed, so every
                // window attached to that owner follows the shifted tile.
                for (w, p) in attached where unmovable.contains(w) && !ws.floating.contains(p) {
                    guard case .frame(let f)? = out[p], let d = offsetOf(w, p), let size = observed[w]?.size else { continue }
                    let dx = sheetShift(CGRect(x: f.minX + d.dx, y: f.minY + d.dy, width: size.width, height: size.height),
                                        display: visible)
                    if abs(dx) > 0.5 { out[p] = .frame(f.offsetBy(dx: dx, dy: 0)) }
                }
                for (w, p) in attached {
                    let offset = offsetOf(w, p)
                    let size = observed[w]?.size ?? fallbackSize
                    switch out[p] {
                    case .frame(let f)?:
                        // Unmeasured (never seen): centred across the owner, at its top, like a sheet.
                        let d = offset ?? CGVector(dx: (f.width - size.width) / 2, dy: 0)
                        out[w] = .frame(CGRect(x: f.minX + d.dx, y: f.minY + d.dy, width: size.width, height: size.height))
                    case .parked(let o)?:
                        out[w] = offset.map { .parked(CGPoint(x: o.x + $0.dx, y: o.y + $0.dy)) } ?? park(w)
                    default:
                        out[w] = .untouched
                    }
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

    /// The rect the layout engine divides: the viewport less the outer gap (`screen-gap`, #124;
    /// the engine puts `gap` only between tiles). Also what a resize (#113) measures its portions against.
    public static func tilingRect(screen: Screen, display: DisplayInfo, insets: ShellInsets, screenGap: CGFloat) -> CGRect {
        var rect = viewport(screen: screen, display: display, insets: insets).insetBy(dx: screenGap, dy: screenGap)
        rect.size.height -= 1   // macOS may refuse full-height frames on stacked displays
        return rect
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

    private static func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? { if let a, let b { (a, b) } else { nil } }

    /// `frame` moved the least distance that puts it fully inside `bounds`, on each axis. On an
    /// axis where it is longer than `bounds` it is centred on them, or with `topAlignTall`, a
    /// too-tall frame is aligned to their top instead (#165: a popup's title bar stays reachable).
    /// Shared by #164's refused tiles and #165's popups.
    static func keepInside(_ frame: CGRect, _ bounds: CGRect, topAlignTall: Bool = false) -> CGRect {
        func clamp(_ o: CGFloat, _ len: CGFloat, _ lo: CGFloat, _ hi: CGFloat, leading: Bool) -> CGFloat {
            len >= hi - lo ? (leading ? lo : lo + (hi - lo - len) / 2) : min(max(o, lo), hi - len)
        }
        var f = frame
        f.origin.x = clamp(frame.minX, frame.width, bounds.minX, bounds.maxX, leading: false)
        f.origin.y = clamp(frame.minY, frame.height, bounds.minY, bounds.maxY, leading: topAlignTall)
        return f
    }

    static func centered(size: CGSize, in rect: CGRect) -> CGRect {
        CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
    static func approx(_ a: CGRect, _ b: CGRect, tol: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol && abs(a.width - b.width) < tol && abs(a.height - b.height) < tol
    }
}
