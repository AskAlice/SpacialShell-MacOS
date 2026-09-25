import Foundation

/// #92: whether a screen capture may run now. macOS shows its capture-approval prompt once for every
/// request made while approval is pending, so parallel captures stack identical prompts. Pure policy —
/// the ScreenCaptureKit calls and the waiting live in the UI layer's `CaptureGate`.
///
/// - **unknown** (every launch starts here): one capture at a time; the rest wait.
/// - **approved** (a picture came back): any number at once, prefetch included.
/// - **declined** (a permission error): nothing runs until `backoff` has passed, then unknown again.
public struct CaptureApproval: Sendable {
    public enum State: Equatable, Sendable { case unknown, approved, declined(until: ContinuousClock.Instant) }
    public enum Admission: Equatable, Sendable { case run, wait, skip }
    public enum Outcome: Sendable {
        /// A picture came back: the proof of approval.
        case captured
        /// Succeeded without proving approval (a window listing): the next request still runs alone.
        case listed
        /// The user declined, or the grant is missing.
        case declined
        /// Anything else; says nothing about approval.
        case failed
    }

    /// How long a decline silences every capture. Relaunching also clears it.
    public static var backoff: Duration { .seconds(600) }

    public private(set) var state: State = .unknown
    private var inFlight = 0

    public init() {}

    /// Prefetch never starts the first-ever capture: it runs only once one has succeeded.
    public var admitsPrefetch: Bool { state == .approved }

    /// `.run` must be matched by one `end`; `.wait` means ask again after the next `end`.
    public mutating func begin(now: ContinuousClock.Instant) -> Admission {
        if case .declined(let until) = state {
            guard now >= until else { return .skip }
            state = .unknown
        }
        if state == .unknown, inFlight > 0 { return .wait }
        inFlight += 1
        return .run
    }

    public mutating func end(_ outcome: Outcome, now: ContinuousClock.Instant) {
        inFlight = max(0, inFlight - 1)
        switch outcome {
        case .captured: if state == .unknown { state = .approved }
        case .declined: state = .declined(until: now + Self.backoff)
        case .listed, .failed: break
        }
    }
}
