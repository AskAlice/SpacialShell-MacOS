import AppKit
import ApplicationServices
import CoreGraphics
import SpacialShellProtocol

/// Window identity, minted by us instead of read out of the window server (issue #17, #18).
///
/// The old source was `_AXUIElementGetWindow`, an undocumented symbol whose presence is an
/// automatic App Store rejection. The spike on `prototype/window-identity` measured the obvious
/// replacement — derive a `CGWindowID` by matching `CGWindowListCopyWindowInfo` on pid + frame +
/// title — and it does not work: 64.8% of standard windows resolved with no wrong answers, or
/// 94.4% with an ordering tiebreak that returned *confidently wrong* ids for every minimized
/// same-app window (16/16). Identity that is silently wrong is worse than no identity, because
/// every write in the model is addressed by it.
///
/// The framing was the mistake. SpacialShell never needed a `CGWindowID`; it needed a stable key,
/// and `AXUIElement` already is one. Measured on a live desktop: two independently-fetched
/// references to the same window are different pointers but compare `CFEqual`, hash equal, and
/// round-trip through a Swift `Dictionary` exactly — across move, minimize, hide/unhide and time
/// (6/6 windows, every sample). So ids are minted here at first sight and keyed to the element.
///
/// Consequences, all of which the M1 design already anticipated in §13.3:
/// - Ids are unique within a run and meaningless across runs. They always were: a `CGWindowID` is
///   per-session too, and `PersistedState` has never contained a window id, a `WindowRef` or a pid.
/// - Ids are process-wide monotonic, not per-app, so a bare id stays unique across apps exactly as
///   a `CGWindowID` was. `WindowRef` still carries the pid alongside.
/// - An id is no longer a window-server handle. The two places that genuinely need one —
///   `getWindowLevel` and the rail's hover previews — resolve it through `captureID(for:)` below
///   and are allowed to fail.
public enum WindowIdentities {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var forward: [AXUIElement: WindowID] = [:]
    private nonisolated(unsafe) static var reverse: [WindowID: AXUIElement] = [:]
    /// Starts above the plausible `CGWindowID` range so a stale id from before the swap can never
    /// silently resolve onto a real window-server id in a log or a dump.
    private nonisolated(unsafe) static var next: WindowID = 1_000_000

    /// The id for this element, minted on first sight. Stable for as long as the window lives.
    public static func id(for element: AXUIElement) -> WindowID {
        lock.withLock {
            if let existing = forward[element] { return existing }
            let id = next
            next &+= 1
            forward[element] = id
            reverse[id] = element
            return id
        }
    }

    /// Drop a dead window, so a long session does not accumulate entries for closed windows.
    public static func forget(_ id: WindowID) {
        lock.withLock {
            guard let element = reverse.removeValue(forKey: id) else { return }
            forward.removeValue(forKey: element)
        }
    }

    public static func element(for id: WindowID) -> AXUIElement? {
        lock.withLock { reverse[id] }
    }

    /// Best-effort `CGWindowID` for a minted id, for the two consumers that need a real
    /// window-server handle. Returns nil rather than guessing when the match is ambiguous.
    ///
    /// Scoped to the on-screen list deliberately: that is where the spike measured the match to be
    /// strongest, and both callers only care about on-screen windows anyway. A window parked in a
    /// corner sliver for an inactive workspace is still on screen, so previews for inactive
    /// workspaces keep working.
    public static func captureID(for id: WindowID) -> CGWindowID? {
        captureIDs(for: [id])[id]
    }

    /// Batched form: one `CGWindowListCopyWindowInfo` pass for many ids.
    public static func captureIDs(for ids: [WindowID]) -> [WindowID: CGWindowID] {
        guard !ids.isEmpty else { return [:] }
        let listed = onScreenList()
        guard !listed.isEmpty else { return [:] }
        var out: [WindowID: CGWindowID] = [:]
        for id in ids {
            guard let element = element(for: id) else { continue }
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success else { continue }
            guard let frame = element.frameOrNil() else { continue }
            let title = element.get(Ax.titleAttr) ?? ""
            let pool = listed.filter { $0.pid == pid }
            guard !pool.isEmpty else { continue }
            if pool.count == 1 { out[id] = pool[0].id; continue }
            let byFrame = pool.filter { approximatelyEqual($0.bounds, frame) }
            if byFrame.count == 1 { out[id] = byFrame[0].id; continue }
            // Title needs the Screen Recording grant to be populated at all, and it broke a tie in
            // only 0.5% of the spike's sample — so this is a long shot, not a safety net.
            let byTitle = byFrame.filter { $0.title != nil && $0.title == title }
            if byTitle.count == 1 { out[id] = byTitle[0].id }
        }
        return out
    }

    public struct Listed {
        public let id: CGWindowID
        public let pid: pid_t
        public let bounds: CGRect
        public let title: String?
        public let layer: Int
    }

    public static func onScreenList() -> [Listed] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { d in
            guard let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t,
                  let b = d[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary)
            else { return nil }
            return Listed(
                id: id, pid: pid, bounds: rect,
                title: d[kCGWindowName as String] as? String,
                layer: d[kCGWindowLayer as String] as? Int ?? 0
            )
        }
    }

    /// 1pt: AX and the window server round differently, and a window mid-move disagrees by more
    /// than a rounding error anyway — in which case no match is the right answer.
    private static func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1
            && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }

    #if DEBUG
        /// Tests only: a clean slate, so one test's minted ids cannot leak into another's.
        static func resetForTesting() {
            lock.withLock {
                forward.removeAll()
                reverse.removeAll()
                next = 1_000_000
            }
        }

        static var trackedCount: Int { lock.withLock { reverse.count } }
    #endif
}

extension AXUIElement {
    /// Top-left origin plus size, as one rect. `Ax.topLeftCornerAttr` and `Ax.sizeAttr` separately
    /// everywhere else; this exists because the matcher needs both or neither.
    func frameOrNil() -> CGRect? {
        guard let origin = get(Ax.topLeftCornerAttr), let size = get(Ax.sizeAttr) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
