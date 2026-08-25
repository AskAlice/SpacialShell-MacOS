import Foundation
// `import Foundation` alone exposes the `CGRect` *name* on macOS but not its labelled
// `init(x:y:width:height:)` / `.origin` / `.size` API — that needs CoreGraphics itself. Scoped to
// this file only; every other file in this target stays Foundation-only. Disclosed per plan.
import CoreGraphics

/// Wire geometry. `CGRect`'s synthesised `Codable` encodes as `[[x,y],[w,h]]` — hostile to any
/// non-Swift consumer, and Raycast is one.
public struct RectDTO: Hashable, Codable, Sendable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public init(_ r: CGRect) {
        self.x = r.origin.x; self.y = r.origin.y; self.width = r.size.width; self.height = r.size.height
    }
    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Wire edge insets — the panel-reserved margin per screen edge (rail width, top-bar height, …).
public struct EdgeInsetsDTO: Hashable, Codable, Sendable {
    public var top, left, right, bottom: Double
    public init(top: Double, left: Double, right: Double, bottom: Double) {
        self.top = top; self.left = left; self.right = right; self.bottom = bottom
    }
    public static let zero = EdgeInsetsDTO(top: 0, left: 0, right: 0, bottom: 0)
}
