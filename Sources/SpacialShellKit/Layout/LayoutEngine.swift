import Foundation

public enum LayoutEngine {
    /// One entry per tiled window index; nil means this layout parks that window. Spec §5.
    public static func frames(_ layout: Layout, count: Int, focused: Int, in rect: CGRect, gap: CGFloat) -> [CGRect?] {
        guard count > 0 else { return [] }
        let f = min(max(focused, 0), count - 1)
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
