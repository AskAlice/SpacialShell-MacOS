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
    /// The panels are floating cards (M2 design, amended 2026-09-21): every edge gives up
    /// `panel-margin`, and the two edges carrying a card give up the card as well. The reconciler
    /// adds `gap` on top, so a window sits one gap from a card and margin+gap from a bare edge.
    public init(config: Config, hidden: Bool) {
        if hidden || !config.showPanels { top = 0; left = 0; right = 0; bottom = 0; return }
        let m = CGFloat(config.panelMargin)
        top = m + CGFloat(config.panelHeight); bottom = m
        switch config.railSide {
        case .left:  left = m + CGFloat(config.panelWidth); right = m
        case .right: left = m; right = m + CGFloat(config.panelWidth)
        }
    }
    public func apply(to rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + left, y: rect.minY + top,
               width: rect.width - left - right, height: rect.height - top - bottom)
    }
}
