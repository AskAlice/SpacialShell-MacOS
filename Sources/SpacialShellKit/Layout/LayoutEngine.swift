import Foundation
import CoreGraphics

/// #114 (M4 G5): split is an N-column sliding view. It shows `columns` consecutive tiled windows
/// from `start`, a hint the engine clamps (`slide`) so the focused window is always in view; the
/// model keeps the hint in step with focus (`World.slideViews`), so focus moving past either edge
/// slides the view by one and moving inside it moves nothing.
public struct SplitView: Equatable, Sendable {
    public static let defaultColumns = 2
    public static let columnRange = 2...6
    public var columns: Int
    public var start: Int
    public init(columns: Int = defaultColumns, start: Int = 0) { self.columns = columns; self.start = start }

    /// The first index of a `k`-wide view of `count` windows that holds `focused`, as close to
    /// `start` as that allows.
    public static func slide(_ start: Int, focused f: Int, k: Int, count: Int) -> Int {
        min(max(min(max(start, f - k + 1), f), 0), count - k)
    }
}

public enum LayoutEngine {
    /// The smallest frame a tiled window is ever handed (#54). Below this a window is "on screen"
    /// in the model and useless in fact — the I6 failure mode — so a crowded row parks its
    /// overflow instead of shrinking everyone into slivers.
    public static let minSize = CGSize(width: 120, height: 80)

    /// One entry per tiled window index; nil means this layout parks that window. Spec §5.
    ///
    /// **Overflow rule (#54).** When `count` windows cannot all get `minSize`, the layout is laid
    /// out for the largest `k` that fits, over a contiguous run of `k` windows — the *page* that
    /// holds the focused one. Pages are `k` wide from index 0, and the last is pulled back to end
    /// on the last window so it is never short. The rest are nil and the reconciler parks them;
    /// they stay in the workspace, so their tabs stay and the tab bar is how you reach them (the
    /// same contract as `.maximize`). Paging, not "focused leftmost": moving focus inside a page
    /// moves nothing, only crossing its edge flips the page.
    ///
    /// Indices never renumber: entry `i` is always tiled window `i`, framed or nil.
    ///
    /// A rect below `minSize` itself cannot meet the floor at all; the focused window then gets
    /// the whole rect anyway, because a focused window on screen beats a floor.
    ///
    /// Split (#114) is the exception to pages: its view is `split.columns` wide at most and slides
    /// from `split.start` rather than flipping, and the floor narrows it the same way.
    public static func frames(_ layout: BuiltinLayout, count: Int, focused: Int, in rect: CGRect, gap: CGFloat,
                              split: SplitView = SplitView()) -> [CGRect?] {
        guard count > 0 else { return [] }
        let f = min(max(focused, 0), count - 1)
        var out = [CGRect?](repeating: nil, count: count)
        guard let (start, k) = span(layout, count: count, focused: f, in: rect, gap: gap, split: split) else { out[f] = rect; return out }
        out.replaceSubrange(start..<start + k, with: unfloored(layout, count: k, focused: f - start, in: rect, gap: gap, portrait: isPortrait(rect)))
        return out
    }

    /// The #54 page `frames` lays out: its first index and size, nil when not even two fit.
    /// ponytail: linear search down from `count`, re-running the layout each step — O(n²) in
    /// tiny n (windows in one row). Closed-form capacity per layout if rows ever get huge.
    static func span(_ layout: BuiltinLayout, count: Int, focused f: Int, in rect: CGRect, gap: CGFloat,
                     split: SplitView = SplitView()) -> (start: Int, k: Int)? {
        let isSplit = layout == .split
        for k in stride(from: isSplit ? min(split.columns, count) : count, to: 1, by: -1) {
            let start = isSplit ? SplitView.slide(split.start, focused: f, k: k, count: count) : min(f / k * k, count - k)
            if unfloored(layout, count: k, focused: f - start, in: rect, gap: gap, portrait: isPortrait(rect)).allSatisfy({ $0.map(fits) ?? true }) { return (start, k) }
        }
        return nil
    }

    /// Any layout, built-in or drawn (#9, design §4.3). A built-in is today's generator, verbatim.
    /// A drawn layout pages exactly as #54 does, with the page size fixed at its *usable* zones —
    /// the ones that still meet `minSize` in this rect: the page holding the focused window fills
    /// zones 0…k-1 in array order, the rest park and keep their tabs, and trailing zones stay empty
    /// when there are fewer windows than zones. No zone is the focus zone: focus picks the page,
    /// so moving focus inside a page moves nothing.
    public static func frames(_ def: LayoutDef, count: Int, focused: Int, in rect: CGRect, gap: CGFloat,
                              split: SplitView = SplitView()) -> [CGRect?] {
        switch def.body {
        case .builtin(let b):
            return frames(b, count: count, focused: focused, in: rect, gap: gap, split: split)
        case .zones(let zones):
            guard count > 0 else { return [] }
            let usable = zones.map { self.rect(for: $0, in: rect, gap: gap) }.filter(fits)
            let f = min(max(focused, 0), count - 1)
            var out = [CGRect?](repeating: nil, count: count)
            guard !usable.isEmpty else { out[f] = rect; return out }
            let k = min(count, usable.count)
            let start = min(f / k * k, count - k)                // #54's page formula
            for i in 0..<k { out[start + i] = usable[i] }
            return out
        }
    }

    /// Design §4.2: a zone maps onto the rect inflated by one gap, less one gap in each dimension —
    /// each zone owns a gutter at its trailing edge, and the rect's own trailing gutter is the outer
    /// gap. The only mapping that reproduces `columns`/`rows` term for term.
    static func rect(for z: LayoutZone, in r: CGRect, gap g: CGFloat) -> CGRect {
        CGRect(x: r.minX + z.x * (r.width + g), y: r.minY + z.y * (r.height + g),
               width: z.w * (r.width + g) - g, height: z.h * (r.height + g) - g)
    }

    /// How many of `count` windows `def` shows at once in `rect`. The default rect is big enough
    /// that no floor engages: the model's own question ("can this layout show two?"), asked by
    /// `moveWindow`, which has no display geometry.
    public static func capacity(_ def: LayoutDef, count: Int,
                                in rect: CGRect = CGRect(x: 0, y: 0, width: 100_000, height: 100_000),
                                gap: CGFloat = 0) -> Int {
        frames(def, count: count, focused: 0, in: rect, gap: gap).compactMap { $0 }.count
    }

    static func fits(_ r: CGRect) -> Bool { r.width >= minSize.width && r.height >= minSize.height }

    /// #122 (M4 G6): taller than wide. A square is landscape.
    public static func isPortrait(_ r: CGRect) -> Bool { r.height > r.width }

    /// `portrait` (#122) turns the built-ins to the long axis: split and column stack as rows,
    /// half takes the top half and lays the rest side by side below it, and grid has at least as
    /// many rows as columns. Grid still fills row-major with its last row widened. It is a flag,
    /// not read off `rect`, because the resize model (#113) asks for the shape in a unit square.
    static func unfloored(_ layout: BuiltinLayout, count: Int, focused f: Int, in rect: CGRect, gap: CGFloat,
                          portrait: Bool) -> [CGRect?] {
        let along = portrait ? rows : columns, across = portrait ? columns : rows
        switch layout {
        case .maximize:
            var out = [CGRect?](repeating: nil, count: count); out[f] = rect; return out
        case .split, .column:   // split's view (#114) is `span`'s: what it shows is laid out along the long axis
            return along(count, rect, gap)
        case .half:
            if count == 1 { return [rect] }
            let halves = along(2, rect, gap)
            return [halves[0] as CGRect?] + across(count - 1, halves[1], gap).map { $0 as CGRect? }
        case .grid:
            let long = Int(Double(count).squareRoot().rounded(.up))
            let cols = portrait ? Int((Double(count) / Double(long)).rounded(.up)) : long
            let nRows = Int((Double(count) / Double(cols)).rounded(.up))
            let rowRects = rows(nRows, in: rect, gap: gap)
            var out: [CGRect?] = []
            for r in 0..<nRows { out += columns(min(cols, count - r * cols), in: rowRects[r], gap: gap).map { $0 as CGRect? } }
            return out
        }
    }

    static func columns(_ n: Int, in rect: CGRect, gap: CGFloat) -> [CGRect] {
        let w = (rect.width - gap * CGFloat(n - 1)) / CGFloat(n)
        return (0..<n).map { CGRect(x: rect.minX + CGFloat($0) * (w + gap), y: rect.minY, width: w, height: rect.height) }
    }
    static func rows(_ n: Int, in rect: CGRect, gap: CGFloat) -> [CGRect] {
        let h = (rect.height - gap * CGFloat(n - 1)) / CGFloat(n)
        return (0..<n).map { CGRect(x: rect.minX, y: rect.minY + CGFloat($0) * (h + gap), width: rect.width, height: h) }
    }
}
