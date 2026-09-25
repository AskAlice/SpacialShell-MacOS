import Foundation
import ScreenCaptureKit
import SpacialShellKit

/// #92: every ScreenCaptureKit call goes through here, so a pending approval shows one prompt, not
/// one per parallel capture. The policy (one at a time until a picture comes back, a 10-minute
/// silence after a decline) is `CaptureApproval` in Kit; this does the waiting and reads the errors.
///
/// `nil` means "unavailable": the switch places instantly and the hover card keeps its icons.
actor CaptureGate {
    static let shared = CaptureGate()

    private var approval = CaptureApproval()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Whether a prefetch may capture: only once a user-initiated capture has succeeded.
    var admitsPrefetch: Bool { approval.admitsPrefetch }

    /// A window listing: may prompt and may be declined, but its success does not prove approval.
    static func listing(isolation: isolated (any Actor)? = #isolation,
                        _ op: () async throws -> SCShareableContent) async -> SCShareableContent? {
        await run(proves: false, op)
    }

    static func image(isolation: isolated (any Actor)? = #isolation,
                      _ op: () async throws -> CGImage) async -> CGImage? {
        await run(proves: true, op)
    }

    /// Runs `op` in the caller's isolation, so neither it nor its result crosses into the gate;
    /// only the admission and the outcome do.
    private static func run<T>(isolation: isolated (any Actor)? = #isolation, proves: Bool,
                               _ op: () async throws -> T) async -> T? {
        guard await shared.admit() else { return nil }
        do {
            let value = try await op()
            await shared.end(proves ? .captured : .listed)
            return value
        } catch {
            await shared.end(declines(error) ? .declined : .failed)
            return nil
        }
    }

    private func admit() async -> Bool {
        while !Task.isCancelled {
            switch approval.begin(now: .now) {
            case .skip: return false
            case .run: return true
            // ponytail: a cancelled waiter stays parked until the in-flight capture ends (one
            // screenshot, well under a second); cancellation handlers if that ever shows.
            case .wait: await withCheckedContinuation { waiters.append($0) }
            }
        }
        return false
    }

    private func end(_ outcome: CaptureApproval.Outcome) {
        approval.end(outcome, now: .now)
        let woken = waiters; waiters = []
        for w in woken { w.resume() }
    }

    /// The user said no, or the app lacks the grant: `SCShareableContent` and `SCScreenshotManager`
    /// report both as `SCStreamError.userDeclined` (-3801); `missingEntitlements` (-3803) is the
    /// same answer for a build the system will not let capture at all.
    static func declines(_ error: Error) -> Bool {
        let e = error as NSError
        return e.domain == SCStreamErrorDomain
            && [SCStreamError.Code.userDeclined.rawValue, SCStreamError.Code.missingEntitlements.rawValue].contains(e.code)
    }
}
