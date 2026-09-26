import Foundation

/// Remembers frames we asked for so the resulting AX moved/resized notifications are not mistaken for user actions.
public struct IntentSet: Sendable {
    private enum Intent { case frame(CGRect), origin(CGPoint) }
    private var intents: [WindowRef: Intent] = [:]
    public init() {}
    public mutating func record(_ w: Write) {
        switch w {
        case .setFrame(let r, let f): intents[r] = .frame(f)
        case .setPosition(let r, let o): intents[r] = .origin(o)
        }
    }
    /// True if `frame` is what we asked for (±1 pt); the intent is consumed.
    /// Origin intents use `Reconciler.titleBarClampTolerance` on y — macOS clamps a parked window
    /// so its title bar stays on screen, so the frame that echoes back is ~32 pt off what we asked
    /// for — while keeping x tight; frame intents keep the uniform tolerance.
    public mutating func matches(_ ref: WindowRef, frame: CGRect, tolerance: CGFloat = 1) -> Bool {
        guard let i = intents[ref] else { return false }
        let hit: Bool
        switch i {
        case .frame(let f): hit = Reconciler.approx(frame, f, tol: tolerance)
        case .origin(let o):
            hit = abs(frame.origin.x - o.x) < tolerance
                && abs(frame.origin.y - o.y) < Reconciler.titleBarClampTolerance
        }
        if hit { intents[ref] = nil }
        return hit
    }
    public mutating func forget(_ ref: WindowRef) { intents[ref] = nil }
    /// #125: the frame we last asked this window for and have not heard back, if any.
    public func frame(for ref: WindowRef) -> CGRect? { if case .frame(let f)? = intents[ref] { f } else { nil } }
}
