import Foundation

/// #140 (G13): what a reconcile's motion is allowed to do, decided from its transitions and the
/// config alone. `WorldStore` asks `animated` what to hand the animator; the overlay
/// (`SwitchOverlay`, which owns the pixels) asks the rest: how long the flight is, whether it may
/// use and keep cached pictures, whether its captures feed the rail thumbnails, and, once the
/// capture is in, whether it animates at all.
///
/// Re-tiles run under the limits #140 was built with (M4 spec §7, "build with limits"): the same
/// 80 ms capture budget as a switch, over which the windows are placed instantly; always a fresh
/// capture; and no rail-thumbnail ingest, which was a fifth of the CPU at 8 windows.
public struct MotionRules: Equatable, Sendable {
    public let kind: Transition.Kind

    /// A pass runs under re-tile rules only when every display in it re-tiles. One switching
    /// display makes it a switch, and a neighbour re-tiling in the same pass rides along with it.
    public init(_ transitions: [Transition]) {
        kind = !transitions.isEmpty && transitions.allSatisfy(\.isRetile) ? .retile : .switch
    }

    /// What the store hands the animator for one pass; empty means place instantly without asking.
    /// Nothing with `animations` off, or while a border is being dragged (#113: the hand is the
    /// motion). Re-tiles only with `animate-retile` on: off, they are dropped here and those
    /// displays are placed instantly, while a switch on another display still slides.
    public static func animated(_ transitions: [Transition], animations: Bool, animateRetile: Bool,
                                grabbing: Bool) -> [Transition] {
        guard animations, !grabbing else { return [] }
        return animateRetile ? transitions : transitions.filter { !$0.isRetile }
    }

    /// A switch's 200 ms (#64). A re-tile is a little longer, ~250 ms as #140 asked: sizes change
    /// as well as places.
    public var duration: Duration { kind == .retile ? .milliseconds(250) : .milliseconds(200) }

    /// #97: how long a pass with no kept pictures waits for its capture. Over it, the windows are
    /// placed instantly; that holds for re-tiles too (#140), so the measured tail (2 of 10 over at
    /// 8 windows in the VM) costs an instant re-tile, never a late one.
    public static let captureBudget = Duration.milliseconds(80)

    /// #77, #97: a switch flies kept pictures and keeps what it captures for the next one. A
    /// re-tile does neither: its set is keyed by the frames it is leaving, which no later pass
    /// starts from, and its backdrop leaves out `Transition.offstage`, which a switch's does not.
    public var usesPictureCache: Bool { kind == .switch }

    /// #90: a switch's captures also refresh the rail's hover thumbnails. A re-tile's do not:
    /// re-scaling every picture was 20% of the CPU inside a re-tile at 8 windows (#140).
    public var feedsThumbnails: Bool { kind == .switch }

    /// Why a pass is placed instantly instead of animated.
    public enum Instant: String, Sendable, Equatable {
        case noGrant = "no-grant", reduceMotion = "reduce-motion"
        case overBudget = "over-budget", captureFailed = "capture-failed"
    }

    public enum Verdict: Sendable, Equatable {
        case animate
        case instant(Instant)
    }

    /// Before anything is captured: no Screen Recording grant, or Reduce Motion on, is instant.
    public static func gate(screenRecording: Bool, reduceMotion: Bool) -> Verdict {
        if !screenRecording { return .instant(.noGrant) }
        if reduceMotion { return .instant(.reduceMotion) }
        return .animate
    }

    /// Once the capture is in, or the wait for it is over. `took` is nil when the budget ran out
    /// first. A capture that finished but took longer than the budget (the wait and the capture
    /// race, and the capture can win late) is still over it: the budget is a hard cutoff.
    /// `complete` is false when any picture is missing: a window with no image would pop in at the
    /// end instead of flying, which is worse than no animation at all.
    public static func verdict(took: Duration?, complete: Bool, budget: Duration = captureBudget) -> Verdict {
        guard let took, took <= budget else { return .instant(.overBudget) }
        return complete ? .animate : .instant(.captureFailed)
    }
}
