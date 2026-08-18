import Foundation
@testable import SpacialShellKit

/// In-memory backend: records writes, lets tests push events, applies writes to its own frames.
actor FakeBackend: WindowBackend {
    enum Call: Equatable { case setFrame(WindowRef, CGRect), setPosition(WindowRef, CGPoint), raise(WindowRef), close(WindowRef) }
    var calls: [Call] = []
    var frames: [WindowRef: CGRect] = [:]
    var snapshot: Snapshot
    nonisolated let events: AsyncStream<BackendEvent>
    private let continuation: AsyncStream<BackendEvent>.Continuation

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
        for w in snapshot.windows { frames[w.ref] = w.frame }
        (events, continuation) = AsyncStream.makeStream()
    }
    func currentSnapshot() -> Snapshot { snapshot }
    func setFrame(_ ref: WindowRef, _ frame: CGRect) -> Result<Void, BackendError> { calls.append(.setFrame(ref, frame)); frames[ref] = frame; return .success(()) }
    func setPosition(_ ref: WindowRef, _ o: CGPoint) -> Result<Void, BackendError> {
        calls.append(.setPosition(ref, o)); if let f = frames[ref] { frames[ref] = CGRect(origin: o, size: f.size) }; return .success(())
    }
    func raise(_ ref: WindowRef) -> Result<Void, BackendError> { calls.append(.raise(ref)); return .success(()) }
    func close(_ ref: WindowRef) -> Result<Void, BackendError> { calls.append(.close(ref)); return .success(()) }

    func push(_ e: BackendEvent) { if case .snapshot(let s) = e { snapshot = s; for w in s.windows where frames[w.ref] == nil { frames[w.ref] = w.frame } }; continuation.yield(e) }
    func reset() { calls = [] }
    func finish() { continuation.finish() }
}
