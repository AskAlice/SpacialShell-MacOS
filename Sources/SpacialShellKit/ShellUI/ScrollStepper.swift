/// #121: turns a stream of scroll events over a panel into discrete steps — one per mouse-wheel
/// notch, one per trackpad gesture — and says which events the panel should leave alone.
///
/// Only the vertical axis steps. A gesture whose first movement is sideways is passed through
/// whole, momentum included: over the tab bar that is the overflowing row's own horizontal scroll
/// (#14), which keeps working. A vertical one is swallowed whole, so its momentum cannot step again.
public struct ScrollStepper: Sendable {
    public enum Phase: Sendable {
        case none       // a mouse-wheel notch: no gesture around it
        case began, changed, ended
        case momentum   // the trackpad's coast after the fingers lift
    }

    /// Points of trackpad travel before a gesture steps: a deliberate flick, not a resting finger.
    public static let threshold: Double = 12

    private enum Axis { case vertical, horizontal }
    private var axis: Axis?
    private var travel: Double = 0
    private var stepped = false

    public init() {}

    /// Feed one event's deltas (AppKit's `scrollingDeltaX/Y`). Nil: let the event through.
    /// 0: swallow it. -1 / +1: swallow it and step back (up, left) / forward (down, right).
    /// A positive `dy` (wheel rolled away, or content pulled down) is back.
    public mutating func feed(dx: Double, dy: Double, phase: Phase) -> Int? {
        switch phase {
        case .none:
            guard dy != 0, abs(dy) >= abs(dx) else { return nil }
            return dy > 0 ? -1 : 1
        case .began:
            axis = nil; travel = 0; stepped = false
        case .changed, .ended, .momentum:
            break
        }
        if axis == nil, dx != 0 || dy != 0 { axis = abs(dy) >= abs(dx) ? .vertical : .horizontal }
        guard axis == .vertical else { return nil }
        guard phase != .momentum, !stepped else { return 0 }
        travel += dy
        guard abs(travel) >= Self.threshold else { return 0 }
        stepped = true
        return travel > 0 ? -1 : 1
    }
}
