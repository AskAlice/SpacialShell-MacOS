import Foundation

/// #130 (M3 B7): what the grant-wait window says while SpacialShell waits for the Accessibility
/// grant. Pure, so the one judgement in it — when a missing grant starts to look like a stale TCC
/// row rather than a user still on their way to System Settings — is tested without a window.
public struct GrantWait: Equatable, Sendable {
    /// Long enough that a user who is walking to System Settings, unlocking the padlock and
    /// switching SpacialShell on is never told their grant looks broken; short enough that someone
    /// staring at a switch that is already on does not sit there for a minute.
    public static let suspectStaleAfter: Duration = .seconds(20)

    /// Whole seconds since the wait began. The window redraws once a second, so finer is noise.
    public var elapsed: Int

    public init(elapsed: Duration) {
        self.elapsed = max(0, Int(elapsed.components.seconds))
    }

    /// The grant has not arrived for long enough that a switch which is already on — and does
    /// nothing — is the likelier story. The fix is the user's (no API clears a TCC row), so the
    /// window says how.
    public var suspectsStaleGrant: Bool { .seconds(elapsed) >= Self.suspectStaleAfter }

    /// The line beside the spinner: the elapsed time is the progress, as there is no fraction to
    /// show for a switch the user has not flipped yet.
    public var status: String {
        elapsed < 1 ? "Waiting for access…" : "Waiting for access… \(Self.format(elapsed))"
    }

    static func format(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
    }
}
