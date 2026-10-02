import Foundation
@testable import SpacialShellKit

/// In-memory backend: records writes, lets tests push events, applies writes to its own frames.
actor FakeBackend: WindowBackend {
    enum Call: Equatable { case setFrame(WindowRef, CGRect), setPosition(WindowRef, CGPoint), raise(WindowRef), raiseWithoutActivating(WindowRef), close(WindowRef), setFullscreen(WindowRef, Bool), unhide(WindowRef), warpPointer(CGPoint), launch(String) }
    var calls: [Call] = []
    var frames: [WindowRef: CGRect] = [:]
    var snapshot: Snapshot
    nonisolated let events: AsyncStream<BackendEvent>
    private let continuation: AsyncStream<BackendEvent>.Continuation

    /// Test hooks. `failWrites` makes writes for those refs report `.ax(-25200)` (three-strikes, spec §11);
    /// the write gate suspends the Nth write so a test can interleave another store call mid-plan.
    var failWrites: Set<WindowRef> = []
    var failRaises: Set<WindowRef> = []
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
        move(ref, to: frame); return .success(())
    }
    func setPosition(_ ref: WindowRef, _ o: CGPoint) async -> Result<Void, BackendError> {
        await gateIfNeeded()
        calls.append(.setPosition(ref, o))
        if failWrites.contains(ref) { return .failure(.ax(-25200)) }
        if let f = frames[ref] { move(ref, to: CGRect(origin: o, size: f.size)) }; return .success(())
    }
    func raise(_ ref: WindowRef) -> Result<Void, BackendError> {
        calls.append(.raise(ref))
        if failWrites.contains(ref) || failRaises.contains(ref) { return .failure(.ax(-25200)) }
        return .success(())
    }
    func raiseWithoutActivating(_ ref: WindowRef) -> Result<Void, BackendError> {
        calls.append(.raiseWithoutActivating(ref))
        return .success(())
    }
    func close(_ ref: WindowRef) -> Result<Void, BackendError> { calls.append(.close(ref)); return .success(()) }
    func setFullscreen(_ ref: WindowRef, _ on: Bool) -> Result<Void, BackendError> {
        calls.append(.setFullscreen(ref, on))
        if failWrites.contains(ref) { return .failure(.ax(-25200)) }
        return .success(())
    }

    func unhide(_ ref: WindowRef) -> Result<Void, BackendError> {
        calls.append(.unhide(ref))
        if failWrites.contains(ref) { return .failure(.ax(-25200)) }
        return .success(())
    }

    /// #107: where the pointer is; a warp moves it. nil = unknown, as a backend that cannot read it.
    var pointer: CGPoint?
    func launch(bundleID: String) -> Result<Void, BackendError> { calls.append(.launch(bundleID)); return .success(()) }
    func pointerLocation() -> CGPoint? { pointer }
    func warpPointer(to p: CGPoint) { calls.append(.warpPointer(p)); pointer = p }
    func setPointer(_ p: CGPoint?) { pointer = p }
    /// The app in front, as macOS says now; nil (unknown) unless a test sets it.
    private var front: Int32?
    func frontmostPid() -> Int32? { front }
    func setFrontmost(_ pid: Int32?) { front = pid }

    func push(_ e: BackendEvent) { if case .snapshot(let s) = e { snapshot = s; for w in s.windows where frames[w.ref] == nil { frames[w.ref] = w.frame } }; continuation.yield(e) }
    func reset() { calls = []; writeCount = 0 }
    func finish() { continuation.finish() }

    // MARK: test hooks

    /// #165: true sheets, each bound to its owner's title bar: a write to one reports success and
    /// changes nothing, and moving the owner carries it along — what macOS does with an AX sheet.
    var sheets: [WindowRef: WindowRef] = [:]
    func pin(_ sheet: WindowRef, to owner: WindowRef) { sheets[sheet] = owner }
    /// A window appearing where its app opened it, before the store hears of it.
    func open(_ ref: WindowRef, at frame: CGRect) { frames[ref] = frame }
    private func move(_ ref: WindowRef, to frame: CGRect) {
        guard sheets[ref] == nil else { return }
        let was = frames[ref]
        frames[ref] = frame
        guard let was else { return }
        for (s, o) in sheets where o == ref { frames[s] = frames[s]?.offsetBy(dx: frame.minX - was.minX, dy: frame.minY - was.minY) }
    }

    func fail(_ ref: WindowRef) { failWrites.insert(ref) }
    /// Fail only `raise` for this window — what a window in another Space, or an app mid-transition,
    /// does in reality (spec §11 as amended 2026-09-15).
    func failRaise(_ ref: WindowRef) { failRaises.insert(ref) }
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
