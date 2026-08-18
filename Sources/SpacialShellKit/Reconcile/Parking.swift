import Foundation

public enum ParkingCorner: Sendable, Equatable { case bottomRight, bottomLeft }

/// Spec §7.4 — AeroSpace's corner-sliver parking (MacWindow.hideInCorner, refresh.swift OptimalHideCorner).
public enum Parking {
    /// Pick the corner whose probe points fall on the fewest neighbouring displays. Default bottom-right.
    public static func corner(for display: DisplayInfo, among all: [DisplayInfo]) -> ParkingCorner {
        let v = display.visibleFrame
        let others = all.filter { $0.id != display.id }
        func hits(_ probes: [(CGPoint, Int)]) -> Int {
            probes.reduce(0) { acc, p in acc + (others.contains { $0.frame.contains(p.0) } ? p.1 : 0) }
        }
        let dx = v.width * 0.1, dy = v.height * 0.1
        let br = hits([(CGPoint(x: v.maxX + 2, y: v.maxY + 2), 10), (CGPoint(x: v.maxX + dx, y: v.maxY - dy), 1), (CGPoint(x: v.maxX - dx, y: v.maxY + dy), 1)])
        let bl = hits([(CGPoint(x: v.minX - 2, y: v.maxY + 2), 10), (CGPoint(x: v.minX - dx, y: v.maxY - dy), 1), (CGPoint(x: v.minX + dx, y: v.maxY + dy), 1)])
        return bl < br ? .bottomLeft : .bottomRight
    }

    /// Top-left origin that leaves a `sliver`×`sliver` pt corner of the window on screen. sliver 0 for Zoom.
    public static func origin(windowSize: CGSize, visibleFrame v: CGRect, corner: ParkingCorner, sliver: CGFloat) -> CGPoint {
        switch corner {
        case .bottomRight: return CGPoint(x: v.maxX - sliver, y: v.maxY - sliver)
        case .bottomLeft:  return CGPoint(x: v.minX + sliver - windowSize.width, y: v.maxY - sliver)
        }
    }
}
