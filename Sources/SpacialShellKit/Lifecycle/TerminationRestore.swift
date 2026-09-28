import Foundation

/// Spec §7.4, #190: the way out's restore, without the AX. `frames` decides where every parked
/// window goes; `run` makes every write at once and waits for all of them within one deadline.
/// The backend supplies the write; `AXWindowBackend.restoreAllForTermination` is the caller.
public enum TerminationRestore {
    /// Answers a write: called once, from any thread, with what the write came to.
    public typealias Done = @Sendable (Result<Void, BackendError>) -> Void
    public typealias Write = (WindowRef, CGRect, @escaping Done) -> Void

    static let fallbackSize = CGSize(width: 800, height: 600)

    /// Every window in `parked`, centred on its screen's visible frame at the size last observed
    /// (800×600 when none was), and every window in `stranded` (retired while parked, so in no
    /// workspace) at its recorded size on the main display. A window whose display has gone, or
    /// that no workspace holds, goes to the main display rather than being skipped. The size is
    /// clamped to the visible frame, so every frame lies inside one.
    ///
    /// Only parked windows move: a tiled window is already where the user can reach it.
    public static func frames(world: World, displays: [DisplayInfo], observed: [WindowRef: CGRect],
                              stranded: [WindowRef: CGRect], parked: Set<WindowRef>) -> [WindowRef: CGRect] {
        guard let main = displays.first(where: \.isMain) ?? displays.first else { return [:] }
        func centred(_ size: CGSize, on display: DisplayInfo) -> CGRect {
            let visible = display.visibleFrame
            return Reconciler.centered(size: CGSize(width: min(size.width, visible.width), height: min(size.height, visible.height)),
                                       in: visible)
        }
        var out: [WindowRef: CGRect] = [:]
        for (ref, frame) in stranded { out[ref] = centred(frame.size, on: main) }
        for ref in parked {
            let display = world.screenContaining(ref).flatMap { id in displays.first { $0.id == id } } ?? main
            out[ref] = centred(observed[ref]?.size ?? fallbackSize, on: display)
        }
        return out
    }

    /// Hands every write out before waiting on any, then waits for them all until `deadline`
    /// (seconds) has passed. Returns each window whose write failed, with its error, or had not
    /// answered by then (`.timeout`); empty when every window is back. Nothing to write returns at
    /// once.
    public static func run(_ frames: [WindowRef: CGRect], deadline: TimeInterval, write: Write) -> [WindowRef: BackendError] {
        guard !frames.isEmpty else { return [:] }
        let outcome = Outcome(pending: Set(frames.keys))
        let group = DispatchGroup()
        for (ref, frame) in frames {
            group.enter()
            write(ref, frame) { result in
                outcome.answer(ref, result)
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + deadline)
        return outcome.failures
    }

    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: Set<WindowRef>
        private var failed: [WindowRef: BackendError] = [:]
        init(pending: Set<WindowRef>) { self.pending = pending }

        func answer(_ ref: WindowRef, _ result: Result<Void, BackendError>) {
            lock.withLock {
                pending.remove(ref)
                if case .failure(let e) = result { failed[ref] = e }
            }
        }

        var failures: [WindowRef: BackendError] {
            lock.withLock { failed.merging(pending.map { ($0, .timeout) }) { f, _ in f } }
        }
    }
}
