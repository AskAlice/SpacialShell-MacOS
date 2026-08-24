import Foundation
import CoreGraphics

public enum Geometry {
    /// NSScreen (bottom-left, y-up) ⇄ AX/World (top-left, y-down). Self-inverse for a given
    /// `mainHeight` (the height of the screen whose frame origin is (0,0)).
    public static func flip(_ r: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
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
        switch config.railSide {
        case .left:  left = CGFloat(config.panelWidth); right = 0
        case .right: left = 0; right = CGFloat(config.panelWidth)
        }
    }
    public func apply(to rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + left, y: rect.minY + top,
               width: rect.width - left - right, height: rect.height - top - bottom)
    }
}
