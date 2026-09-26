import Foundation

/// #96: when an auto-hiding rail (`rail-autohide`) shows and hides — the Dock's behaviour, as a
/// pure function of where the pointer is and what the rail has open.
///
/// The rail never takes tiling width while auto-hiding (`ShellInsets`), so showing it is only ever
/// an overlay: nothing here re-tiles. The platform side feeds `step` with the pointer and a clock
/// and slides the panel to match `isShown`; it keeps stepping while `needsTicks`.
public struct RailAutohide: Equatable, Sendable {
    /// How long the pointer rests in the edge zone before the rail comes in — long enough that a
    /// pointer merely crossing the edge (to another display, or to a window's edge) does not.
    public static let revealDelay: TimeInterval = 0.3
    /// How long after the pointer leaves the rail it goes — enough to forgive a brief overshoot.
    public static let hideDelay: TimeInterval = 0.4

    public enum Phase: Equatable, Sendable {
        case hidden
        case revealing(at: TimeInterval)
        case shown
        case hiding(at: TimeInterval)
    }

    public private(set) var phase: Phase = .hidden

    public init() {}

    /// Whether the rail is on screen: shown, or shown and waiting out the hide delay.
    public var isShown: Bool {
        switch phase {
        case .shown, .hiding: true
        case .hidden, .revealing: false
        }
    }

    /// A pending delay needs the clock to advance it; `hidden` and a settled `shown` do not.
    public var needsTicks: Bool { phase != .hidden }

    /// - Parameters:
    ///   - inZone: the pointer is in the thin hot zone at the rail's screen edge.
    ///   - overRail: the pointer is over the rail's frame (only meaningful while it is shown).
    ///   - pinned: something the rail opened is still open — its hover card, a drag, a menu. Keeps
    ///     a shown rail shown; never reveals a hidden one.
    public mutating func step(inZone: Bool, overRail: Bool, pinned: Bool, now: TimeInterval) {
        let wanted = inZone || overRail || pinned
        switch phase {
        case .hidden:
            if inZone { phase = .revealing(at: now + Self.revealDelay) }
        case .revealing(let at):
            if !inZone { phase = .hidden } else if now >= at { phase = .shown }
        case .shown:
            if !wanted { phase = .hiding(at: now + Self.hideDelay) }
        case .hiding(let at):
            if wanted { phase = .shown } else if now >= at { phase = .hidden }
        }
    }

    /// Zen, a fullscreen Space, or the setting turned off: gone at once, no delay.
    public mutating func reset() { phase = .hidden }
}
