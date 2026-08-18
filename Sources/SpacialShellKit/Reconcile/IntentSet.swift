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
    /// Controller ruling (macOS 26.5): parking at y = maxY − 1 gets clamped so the window's top ~32pt
    /// stays on-screen — observed y lands ~32pt off from what we asked for. Origin intents therefore use
    /// a loose y tolerance (< 40pt) while keeping x tight (< 1pt); frame intents keep the uniform tolerance.
    public mutating func matches(_ ref: WindowRef, frame: CGRect, tolerance: CGFloat = 1) -> Bool {
        guard let i = intents[ref] else { return false }
        let hit: Bool
        switch i {
        case .frame(let f): hit = Reconciler.approx(frame, f, tol: tolerance)
        case .origin(let o): hit = abs(frame.origin.x - o.x) < tolerance && abs(frame.origin.y - o.y) < 40
        }
        if hit { intents[ref] = nil }
        return hit
    }
    public mutating func forget(_ ref: WindowRef) { intents[ref] = nil }
}
