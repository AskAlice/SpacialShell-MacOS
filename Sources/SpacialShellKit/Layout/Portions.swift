import Foundation
import CoreGraphics

// #113 (M4 G9 + G10): resizable portions. Sizes are data on the workspace, the reconciler still
// owns geometry — the engine reads them when it frames a row.
//
// One model covers every layout. A page's tiles are unit zones (a drawn layout's own zones; a
// built-in's generated at this window count), so its shape is a set of *lines*: the distinct
// interior x edges (vertical lines, which set widths) and y edges (horizontal lines, heights).
// A resize moves one line. `Portions` is where each line is now, aligned to the natural lines, so
// a zone edge that sat on natural line `i` sits at `x[i]`; everything else about the layout is
// unchanged. Maximize has no interior line, so nothing in it resizes.

public enum ResizeAxis: String, Sendable, Hashable { case width, height }

/// Where a layout's interior lines are, in unit coordinates (fractions of the tiling rect),
/// in the order of its natural lines. An axis whose count no longer matches the layout (a drawn
/// layout edited since) is ignored, and that axis draws as designed.
public struct Portions: Codable, Hashable, Sendable {
    public var x: [Double]
    public var y: [Double]
    public init(x: [Double] = [], y: [Double] = []) { self.x = x; self.y = y }
    public subscript(axis: ResizeAxis) -> [Double] {
        get { axis == .width ? x : y }
        set { if axis == .width { x = newValue } else { y = newValue } }
    }
}

public enum Resize {
    /// The keyboard step: 5 % of the tiling rect per press (M4 spec P3).
    public static let step = 0.05
    /// Detents: a keyboard step that would cross one stops on it; a mouse drag within
    /// `snapRadius` of one lands on it.
    public static let snaps: [Double] = [0.25, 0.5, 0.75]
    public static let snapRadius = 0.02
    /// The model's own floor: no tile is resized below a tenth of the rect along the axis being
    /// resized (or below what it already had). The engine then enforces the #54 point floor
    /// against the real rect, which the model does not know.
    public static let minPortion = 0.1
    static let eps = 1e-9

    /// The page a workspace is showing, as the resize model sees it.
    public struct Page: Equatable, Sendable {
        /// What `Workspace.portions` is keyed by: a drawn layout's id; a built-in's id and how
        /// many tiles the page shows (`column#3`), so three columns and four keep separate sizes
        /// and closing a window brings the three-column sizes back.
        public let key: String
        /// One per tiled index: that window's natural unit zone, nil when the page parks it.
        public let zones: [LayoutZone?]
        /// Every zone the lines come from (a drawn layout's full list, a built-in's page).
        let all: [LayoutZone]
        /// The natural interior lines, ascending.
        public let x: [Double], y: [Double]

        init(key: String, zones: [LayoutZone?], all: [LayoutZone]) {
            self.key = key; self.zones = zones; self.all = all
            func lines(_ edges: [Double]) -> [Double] {
                var out: [Double] = []
                for v in edges.sorted() where v > Resize.eps && v < 1 - Resize.eps {
                    if let l = out.last, abs(l - v) < Resize.eps { continue }
                    out.append(v)
                }
                return out
            }
            x = lines(all.flatMap { [$0.x, $0.x + $0.w] })
            y = lines(all.flatMap { [$0.y, $0.y + $0.h] })
        }

        public func lines(_ a: ResizeAxis) -> [Double] { a == .width ? x : y }
        public var natural: Portions { Portions(x: x, y: y) }

        /// `p`'s lines on axis `a`, or the natural ones when `p` has none (or stale ones) there.
        public func positions(_ p: Portions?, _ a: ResizeAxis) -> [Double] {
            let n = lines(a)
            guard let v = p?[a], v.count == n.count else { return n }
            return v
        }

        func index(of v: Double, _ a: ResizeAxis) -> Int? { lines(a).firstIndex { abs($0 - v) < Resize.eps } }

        /// A zone's edges moved to where `p` has their lines, `t` of the way from natural (the
        /// engine's floor clamp blends back towards natural until the page fits).
        func remap(_ z: LayoutZone, _ p: Portions, t: Double = 1) -> LayoutZone {
            func map(_ v: Double, _ a: ResizeAxis) -> Double {
                guard let i = index(of: v, a) else { return v }
                let n = lines(a)[i]
                return n + (positions(p, a)[i] - n) * t
            }
            let x0 = map(z.x, .width), x1 = map(z.x + z.w, .width)
            let y0 = map(z.y, .height), y1 = map(z.y + z.h, .height)
            return LayoutZone(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
        }

        /// Line `i` on axis `a` moved to `to`, kept inside what every zone touching it allows:
        /// none drops below `minPortion`, or below what it had if it was already smaller. Lines
        /// only bound the zones they edge, so a grid's full-row line can pass its short row's.
        func moving(_ p: Portions?, _ a: ResizeAxis, line i: Int, to: Double) -> Portions? {
            var pos = positions(p, a)
            guard pos.indices.contains(i) else { return nil }
            let home = lines(a)[i], cur = pos[i]
            func at(_ v: Double) -> Double { index(of: v, a).map { pos[$0] } ?? v }
            var lo = 0.0, hi = 1.0
            for z in all {
                let (lead, trail) = a == .width ? (z.x, z.x + z.w) : (z.y, z.y + z.h)
                if abs(trail - home) < Resize.eps { let l = at(lead); lo = max(lo, l + min(Resize.minPortion, cur - l)) }
                if abs(lead - home) < Resize.eps { let t = at(trail); hi = min(hi, t - min(Resize.minPortion, t - cur)) }
            }
            pos[i] = min(max(to, lo), hi)
            var out = p ?? natural
            if out.x.count != x.count { out.x = x }
            if out.y.count != y.count { out.y = y }
            out[a] = pos
            return out.isNatural(self) ? nil : out
        }
    }

    /// Fn+⌃A/D/W/S: tile `index` grows or shrinks along `axis` by one step. Its trailing line moves
    /// when it has one (the tile's right or bottom edge), else its leading one — the last column
    /// grows leftwards. A step that would cross a detent stops on it. Returns the new portions
    /// (nil = back to natural) and whether anything moved; `moved` is false for a tile with no
    /// interior edge on that axis (maximize, a full-width row).
    public static func step(_ page: Page, _ p: Portions?, index: Int, axis: ResizeAxis, grow: Bool) -> (portions: Portions?, moved: Bool) {
        guard let (line, trailing) = edge(page, index: index, axis: axis) else { return (p, false) }
        let sign: Double = grow == trailing ? 1 : -1
        let cur = page.positions(p, axis)[line]
        var to = cur + sign * step
        // The detent nearest the start that the step crosses (a step landing on one counts).
        let crossed = snaps.filter { s in abs(s - cur) > eps && (sign > 0 ? s > cur && s <= to + eps : s < cur && s >= to - eps) }
        if let s = sign > 0 ? crossed.min() : crossed.max() { to = s }
        let next = page.moving(p, axis, line: line, to: to)
        return (next, abs(page.positions(next, axis)[line] - cur) > eps)
    }

    /// The line a step moves for tile `index` along `axis`, and whether it is the tile's trailing
    /// edge; nil when the tile has no interior edge that way.
    private static func edge(_ page: Page, index: Int, axis: ResizeAxis) -> (line: Int, trailing: Bool)? {
        guard page.zones.indices.contains(index), let z = page.zones[index] else { return nil }
        let (lead, trail) = axis == .width ? (z.x, z.x + z.w) : (z.y, z.y + z.h)
        if let i = page.index(of: trail, axis) { return (i, true) }
        if let i = page.index(of: lead, axis) { return (i, false) }
        return nil
    }

    /// #109, #160: why a step that moved nothing did nothing — the tile has no edge along `axis`
    /// (every tile in maximize, a full-width row), or its edge is already at the limit. A resize
    /// key and a four-finger swipe report it as the no-op's reason.
    public static func stuck(_ page: Page, index: Int, axis: ResizeAxis) -> String {
        edge(page, index: index, axis: axis) == nil
            ? "the focused tile has no edge to move \(axis == .width ? "sideways" : "up or down") in this layout"
            : "already at the limit"
    }

    /// A mouse drag of line `line` to unit position `u`: snapped onto a detent within `snapRadius`.
    public static func drag(_ page: Page, _ p: Portions?, axis: ResizeAxis, line: Int, to u: Double) -> Portions? {
        let snapped = snaps.first { abs($0 - u) <= snapRadius } ?? u
        return page.moving(p, axis, line: line, to: snapped)
    }

    /// #162: the four-finger drag's gain — how far the edge moves, as a fraction of the tiling
    /// rect's width, per unit of normalized trackpad travel. 1 is proportional: the full trackpad
    /// width drags the edge across the full row. The one knob to tune.
    public static let swipeGain = 1.0

    /// #162: the line a four-finger drag moves for tile `index`, the same edge a resize key moves
    /// (the trailing one, else the leading one), or nil when the tile has none sideways (maximize,
    /// a full-width row).
    public static func swipeLine(_ page: Page, index: Int) -> Int? { edge(page, index: index, axis: .width)?.line }

    /// #162: where a four-finger drag puts the edge that started at unit position `start`, after
    /// `travel` (normalized trackpad x): it follows the fingers, `swipeGain` to one. What happens
    /// there is a mouse drag's, `drag`: the same detents, the same floor.
    public static func swiped(from start: Double, travel: Double) -> Double { start + travel * swipeGain }

    /// A shared edge between two framed tiles, which the mouse can drag: the gap between them,
    /// in the same global top-left coordinates as the frames.
    public struct Border: Equatable, Sendable {
        public let axis: ResizeAxis
        public let line: Int
        public let rect: CGRect
        /// Within `tolerance` points of the gap, along the axis it moves on — enough to catch a
        /// hand aiming at a narrow gap, and the width of a window's own resize handle.
        public func contains(_ p: CGPoint, tolerance: CGFloat = 6) -> Bool {
            let r = axis == .width ? rect.insetBy(dx: -tolerance, dy: 0) : rect.insetBy(dx: 0, dy: -tolerance)
            return r.contains(p)
        }
        /// What the hover indicator draws: the gap, at least 4 pt thick.
        public var indicator: CGRect {
            axis == .width ? rect.insetBy(dx: min(0, (rect.width - 4) / 2), dy: 0)
                           : rect.insetBy(dx: 0, dy: min(0, (rect.height - 4) / 2))
        }
    }

    /// Every border on a page, from the frames the engine actually gave it: two tiles share one
    /// where the first's trailing natural edge is the second's leading one and they overlap across.
    public static func borders(_ page: Page, frames: [CGRect?]) -> [Border] {
        var out: [Border] = []
        let shown = page.zones.indices.compactMap { i -> (LayoutZone, CGRect)? in
            guard let z = page.zones[i], frames.indices.contains(i), let f = frames[i] else { return nil }
            return (z, f)
        }
        for (a, fa) in shown {
            for (b, fb) in shown {
                if let i = page.index(of: a.x + a.w, .width), abs(b.x - (a.x + a.w)) < eps {
                    let y0 = max(fa.minY, fb.minY), y1 = min(fa.maxY, fb.maxY)
                    if y1 > y0 { out.append(Border(axis: .width, line: i, rect: CGRect(x: fa.maxX, y: y0, width: max(fb.minX - fa.maxX, 0), height: y1 - y0))) }
                }
                if let i = page.index(of: a.y + a.h, .height), abs(b.y - (a.y + a.h)) < eps {
                    let x0 = max(fa.minX, fb.minX), x1 = min(fa.maxX, fb.maxX)
                    if x1 > x0 { out.append(Border(axis: .height, line: i, rect: CGRect(x: x0, y: fa.maxY, width: x1 - x0, height: max(fb.minY - fa.maxY, 0)))) }
                }
            }
        }
        return out
    }

    /// The unit position of a pointer at `v` (x or y) in a tiling rect, inverting design §4.2:
    /// the middle of the gap after a zone ending at `u` is `min + u·(size + gap) − gap/2`.
    public static func unit(_ v: CGFloat, axis: ResizeAxis, in rect: CGRect, gap: CGFloat) -> Double {
        axis == .width ? Double((v - rect.minX + gap / 2) / (rect.width + gap))
                       : Double((v - rect.minY + gap / 2) / (rect.height + gap))
    }
}

extension Portions {
    func isNatural(_ page: Resize.Page) -> Bool {
        func same(_ a: [Double], _ b: [Double]) -> Bool { a.count != b.count || zip(a, b).allSatisfy { abs($0 - $1) < Resize.eps } }
        return same(x, page.x) && same(y, page.y)
    }
}

extension LayoutEngine {
    /// #113: the page `frames(def…)` shows, in unit zones — nil when nothing on it can resize
    /// (no windows, or the #54 floor left only the focused window on the whole rect).
    public static func page(_ def: LayoutDef, count: Int, focused: Int, in rect: CGRect, gap: CGFloat,
                            split: SplitView = SplitView()) -> Resize.Page? {
        guard count > 0 else { return nil }
        let f = min(max(focused, 0), count - 1)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        var zones = [LayoutZone?](repeating: nil, count: count)
        switch def.body {
        case .builtin(let b):
            guard let (start, k) = span(b, count: count, focused: f, in: rect, gap: gap, split: split) else { return nil }
            let portrait = isPortrait(rect)
            for (i, r) in unfloored(b, count: k, focused: f - start, in: unit, gap: 0, portrait: portrait).enumerated() {
                zones[start + i] = r.map { LayoutZone(x: $0.minX, y: $0.minY, w: $0.width, h: $0.height) }
            }
            let shown = zones.compactMap { $0 }
            // #122: a portrait page is a different shape, so it keeps its own sizes.
            return Resize.Page(key: "\(def.id.rawValue)#\(shown.count)" + (portrait ? "@portrait" : ""), zones: zones, all: shown)
        case .zones(let all):
            let usable = all.filter { fits(self.rect(for: $0, in: rect, gap: gap)) }
            guard !usable.isEmpty else { return nil }
            let k = min(count, usable.count), start = min(f / k * k, count - k)
            for i in 0..<k { zones[start + i] = usable[i] }
            return Resize.Page(key: def.id.rawValue, zones: zones, all: all)
        }
    }

    /// `frames(def…)` with the workspace's portions applied. A page the portions leave with a tile
    /// under the #54 floor is blended back towards natural until it fits, so the floor always
    /// holds and a resize never changes how many windows the page shows.
    public static func frames(_ def: LayoutDef, count: Int, focused: Int, in rect: CGRect, gap: CGFloat,
                              portions: [String: Portions], split: SplitView = SplitView()) -> [CGRect?] {
        let base = frames(def, count: count, focused: focused, in: rect, gap: gap, split: split)
        guard !portions.isEmpty, let page = page(def, count: count, focused: focused, in: rect, gap: gap, split: split),
              let p = portions[page.key], !p.isNatural(page) else { return base }
        func build(_ t: Double) -> [CGRect?] {
            page.zones.map { $0.map { self.rect(for: page.remap($0, p, t: t), in: rect, gap: gap) } }
        }
        func ok(_ fs: [CGRect?]) -> Bool { fs.allSatisfy { $0.map(fits) ?? true } }
        let full = build(1)
        if ok(full) { return full }
        var lo = 0.0, hi = 1.0
        for _ in 0..<12 { let mid = (lo + hi) / 2; if ok(build(mid)) { lo = mid } else { hi = mid } }
        return lo > 0 ? build(lo) : base
    }
}

extension World {
    /// The resize model of the focused screen's active row, in `rect` (the default is the
    /// geometry-free question `capacity` asks), with the focused tile's index. Nil when there is
    /// no tiled focused window there.
    public func resizePage(layouts: LayoutCatalogue, in rect: CGRect = CGRect(x: 0, y: 0, width: 100_000, height: 100_000),
                           gap: CGFloat = 0) -> (workspace: UUID, page: Resize.Page, index: Int)? {
        guard let s = screens[focus.screen], let f = focus.window else { return nil }
        let ws = s.active, row = tiled(in: ws)
        guard let i = row.firstIndex(of: f) else { return nil }
        let focused = ws.anchor.flatMap { row.firstIndex(of: $0) } ?? 0
        guard let page = LayoutEngine.page(layouts.resolve(ws.layout).def, count: row.count, focused: focused, in: rect, gap: gap,
                                           split: ws.split(in: row))
        else { return nil }
        return (ws.id, page, i)
    }
}
