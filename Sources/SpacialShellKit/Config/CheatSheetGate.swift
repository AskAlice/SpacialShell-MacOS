/// #185: whether a bare-modifier hold may start the cheat sheet's timer. The sheet never shows
/// over the spatial view, and a hold that met the view is spent: when the view closes with the
/// modifier still down, the sheet waits for a fresh press rather than popping up over the desktop
/// the user has just landed on.
public struct CheatSheetGate: Sendable {
    private var spent = false

    public init() {}

    /// A modifier change. `bare`: only the preset's modifier is down. `suppressed`: the spatial
    /// view is open. True when a hold may start (or keep) the timer.
    public mutating func modifier(bare: Bool, suppressed: Bool) -> Bool {
        guard bare else { spent = false; return false }
        if suppressed { spent = true }
        return !spent
    }

    /// The spatial view opened. A hold in progress is spent; with nothing held, nothing is.
    public mutating func spatialOpened(modifierHeld: Bool) {
        if modifierHeld { spent = true }
    }
}
