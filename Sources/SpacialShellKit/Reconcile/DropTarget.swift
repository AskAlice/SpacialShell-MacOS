import Foundation

/// #108: where a tiled window dragged by its title bar would land.
public enum DropTarget {
    /// What a drop can land on: every tiled window the reconciler is framing in an active row, on
    /// any display, by the frame it gives it. Floating, parked, hidden, fullscreen and suspended
    /// windows are not tiles.
    public static func tiles(world: World, desired: [WindowRef: Placement]) -> [WindowRef: CGRect] {
        var out: [WindowRef: CGRect] = [:]
        for screen in world.screens.values {
            for w in world.tiled(in: screen.active) {
                if case .frame(let f) = desired[w] { out[w] = f }
            }
        }
        return out
    }

    /// The tile under `point` that is not the dragged window itself; nil over a gap, a panel, or
    /// nothing at all.
    public static func tile(at point: CGPoint, dragging: WindowRef, in tiles: [WindowRef: CGRect]) -> WindowRef? {
        tiles.first { $0.key != dragging && $0.value.contains(point) }?.key
    }
}
