import Foundation

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
    public static func frames(_ layout: Layout, count: Int, focused: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
        guard count > 0 else { return [] }
        let f = min(max(focused, 0), count - 1)
        // ponytail: linear search down from `count`, re-running the layout each step — O(n²) in
        // tiny n (windows in one row). Closed-form capacity per layout if rows ever get huge.
        for k in stride(from: count, to: 1, by: -1) {
            let start = min(f / k * k, count - k)
            let page = unfloored(layout, count: k, focused: f - start, in: rect, gap: gap)
            guard page.allSatisfy({ $0.map(fits) ?? true }) else { continue }
            var out = [CGRect?](repeating: nil, count: count)
            out.replaceSubrange(start..<start + k, with: page)
            return out
        }
        var out = [CGRect?](repeating: nil, count: count); out[f] = rect; return out
    }

    static func fits(_ r: CGRect) -> Bool { r.width >= minSize.width && r.height >= minSize.height }

    static func unfloored(_ layout: Layout, count: Int, focused f: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
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
