import Foundation
import CoreGraphics

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
    public static func frames(_ layout: BuiltinLayout, count: Int, focused: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
        guard count > 0 else { return [] }
        let f = min(max(focused, 0), count - 1)
        var out = [CGRect?](repeating: nil, count: count)
        guard let (start, k) = span(layout, count: count, focused: f, in: rect, gap: gap) else { out[f] = rect; return out }
        out.replaceSubrange(start..<start + k, with: unfloored(layout, count: k, focused: f - start, in: rect, gap: gap))
        return out
    }

    /// The #54 page `frames` lays out: its first index and size, nil when not even two fit.
    /// ponytail: linear search down from `count`, re-running the layout each step — O(n²) in
    /// tiny n (windows in one row). Closed-form capacity per layout if rows ever get huge.
    static func span(_ layout: BuiltinLayout, count: Int, focused f: Int, in rect: CGRect, gap: CGFloat) -> (start: Int, k: Int)? {
        for k in stride(from: count, to: 1, by: -1) {
            let start = min(f / k * k, count - k)
            if unfloored(layout, count: k, focused: f - start, in: rect, gap: gap).allSatisfy({ $0.map(fits) ?? true }) { return (start, k) }
        }
        return nil
    }

    /// Any layout, built-in or drawn (#9, design §4.3). A built-in is today's generator, verbatim.
    /// A drawn layout pages exactly as #54 does, with the page size fixed at its *usable* zones —
    /// the ones that still meet `minSize` in this rect: the page holding the focused window fills
    /// zones 0…k-1 in array order, the rest park and keep their tabs, and trailing zones stay empty
    /// when there are fewer windows than zones. No zone is the focus zone: focus picks the page,
    /// so moving focus inside a page moves nothing.
    public static func frames(_ def: LayoutDef, count: Int, focused: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
        switch def.body {
        case .builtin(let b):
            return frames(b, count: count, focused: focused, in: rect, gap: gap)
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

    static func unfloored(_ layout: BuiltinLayout, count: Int, focused f: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
        switch layout {
        case .maximize:
            var out = [CGRect?](repeating: nil, count: count); out[f] = rect; return out
        case .split:
            if count == 1 { return [rect] }
            let (a, b) = f == count - 1 ? (f - 1, f) : (f, f + 1)
            let cols = columns(2, in: rect, gap: gap)
            var out = [CGRect?](repeating: nil, count: count); out[a] = cols[0]; out[b] = cols[1]; return out
        case .column:
            return columns(count, in: rect, gap: gap)
        case .half:
            if count == 1 { return [rect] }
            let cols = columns(2, in: rect, gap: gap)
            return [cols[0] as CGRect?] + rows(count - 1, in: cols[1], gap: gap).map { $0 as CGRect? }
        case .grid:
            let cols = Int(Double(count).squareRoot().rounded(.up))
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
