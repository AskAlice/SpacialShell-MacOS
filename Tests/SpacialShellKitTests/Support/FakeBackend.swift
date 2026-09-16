import Foundation
@testable import SpacialShellKit

/// In-memory backend: records writes, lets tests push events, applies writes to its own frames.
actor FakeBackend: WindowBackend {
    enum Call: Equatable { case setFrame(WindowRef, CGRect), setPosition(WindowRef, CGPoint), raise(WindowRef), close(WindowRef), unhide(WindowRef) }
    var calls: [Call] = []
    var frames: [WindowRef: CGRect] = [:]
    var snapshot: Snapshot
    nonisolated let events: AsyncStream<BackendEvent>
    private let continuation: AsyncStream<BackendEvent>.Continuation

    /// Test hooks. `failWrites` makes writes for those refs report `.ax(-25200)` (three-strikes, spec §11);
    /// the write gate suspends the Nth write so a test can interleave another store call mid-plan.
    var failWrites: Set<WindowRef> = []
    var writeGate: CheckedContinuation<Void, Never>?
    var gateOnWriteNumber: Int?
    private var writeCount = 0

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
        for w in snapshot.windows { frames[w.ref] = w.frame }
        (events, continuation) = AsyncStream.makeStream()
    }
    func currentSnapshot() -> Snapshot { snapshot }
    func setFrame(_ ref: WindowRef, _ frame: CGRect) async -> Result<Void, BackendError> {
        await gateIfNeeded()
        calls.append(.setFrame(ref, frame))
        if failWrites.contains(ref) { return .failure(.ax(-25200)) }
        frames[ref] = frame; return .success(())
    }
    func setPosition(_ ref: WindowRef, _ o: CGPoint) async -> Result<Void, BackendError> {
        await gateIfNeeded()
        calls.append(.setPosition(ref, o))
        if failWrites.contains(ref) { return .failure(.ax(-25200)) }
        if let f = frames[ref] { frames[ref] = CGRect(origin: o, size: f.size) }; return .success(())
    }
    func raise(_ ref: WindowRef) -> Result<Void, BackendError> {
        calls.append(.raise(ref))
        if failWrites.contains(ref) { return .failure(.ax(-25200)) }
        return .success(())
    }
    func close(_ ref: WindowRef) -> Result<Void, BackendError> { calls.append(.close(ref)); return .success(()) }
    func unhide(_ ref: WindowRef) -> Result<Void, BackendError> {
        calls.append(.unhide(ref))
        if failWrites.contains(ref) { return .failure(.ax(-25200)) }
        return .success(())
    }

    func push(_ e: BackendEvent) { if case .snapshot(let s) = e { snapshot = s; for w in s.windows where frames[w.ref] == nil { frames[w.ref] = w.frame } }; continuation.yield(e) }
    func reset() { calls = []; writeCount = 0 }
    func finish() { continuation.finish() }

    // MARK: test hooks

    func fail(_ ref: WindowRef) { failWrites.insert(ref) }
    /// Suspend the `n`th write (1-based, counted from the last `reset()`) until `releaseGate()`.
    func armGate(onWriteNumber n: Int) { gateOnWriteNumber = n }
    func isGateArmed() -> Bool { writeGate != nil }
    func releaseGate() { let c = writeGate; writeGate = nil; c?.resume() }

    private func gateIfNeeded() async {
        writeCount += 1
        guard gateOnWriteNumber == writeCount else { return }
        gateOnWriteNumber = nil
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in writeGate = c }
    }
}
