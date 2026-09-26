import Foundation
import CoreGraphics

public enum Geometry {
    /// NSScreen (bottom-left, y-up) ⇄ AX/World (top-left, y-down). Self-inverse for a given
    /// `mainHeight` (the height of the screen whose frame origin is (0,0)).
    public static func flip(_ r: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }
}

/// #118: which display lies "that way" from another. Frames are global, top-left origin, y-down,
/// so up is a smaller y. The display whose centre is nearest wins among those whose centre lies in
/// the direction's 90° cone (the direction is the dominant axis); only when the cone is empty does
/// the half-plane count, so a display above but far off to the side is still reachable by ↑ and a
/// slightly-raised neighbour to the right is never taken for "up". Shared with #136 (whole
/// workspace to a display), which resolves its target the same way.
public enum DisplayNeighbours {
    public static func neighbour(of id: DisplayID, _ dir: Direction, in displays: [DisplayInfo]) -> DisplayID? {
        guard let src = displays.first(where: { $0.id == id }) else { return nil }
        let o = CGPoint(x: src.frame.midX, y: src.frame.midY)
        // (along the direction, across it, distance²) for every other display.
        let rel = displays.filter { $0.id != id }.map { d -> (DisplayID, CGFloat, CGFloat, CGFloat) in
            let dx = d.frame.midX - o.x, dy = d.frame.midY - o.y
            let (along, across): (CGFloat, CGFloat) = switch dir {
            case .left: (-dx, dy)
            case .right: (dx, dy)
            case .up: (-dy, dx)
            case .down: (dy, dx)
            }
            return (d.id, along, abs(across), dx * dx + dy * dy)
        }
        let halfPlane = rel.filter { $0.1 > 0 }
        let cone = halfPlane.filter { $0.1 >= $0.2 }
        return (cone.isEmpty ? halfPlane : cone).min { $0.3 < $1.3 }?.0
    }
}

public struct ShellInsets: Sendable, Equatable {
    public var top: CGFloat, left: CGFloat, right: CGFloat, bottom: CGFloat
    public static let zero = ShellInsets(top: 0, left: 0, right: 0, bottom: 0)
    init(top: CGFloat, left: CGFloat, right: CGFloat, bottom: CGFloat) {
        self.top = top; self.left = left; self.right = right; self.bottom = bottom
    }
    public init(config: Config, hidden: Bool) {
        if hidden || !config.showPanels { top = 0; left = 0; right = 0; bottom = 0; return }
        top = CGFloat(config.panelHeight); bottom = 0
        // #96: an auto-hiding rail is an overlay when it shows, so it never takes tiling width.
        let rail = config.railAutohide ? 0 : CGFloat(config.panelWidth)
        switch config.railSide {
        case .left:  left = rail; right = 0
        case .right: left = 0; right = rail
        }
    }
    public func apply(to rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + left, y: rect.minY + top,
               width: rect.width - left - right, height: rect.height - top - bottom)
    }
}
