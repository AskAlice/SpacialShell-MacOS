import CoreGraphics
import Foundation

/// One display's share of a switch: which windows move, from where. A different arrangement of the
/// same windows is a different key, so pictures are never stretched over another layout.
public struct SwitchPictureKey: Equatable, Sendable {
    public let display: DisplayID, ids: [WindowID], from: [CGRect]
    public init(_ t: Transition) {
        let ms = t.moves.sorted { $0.ref.id < $1.ref.id }
        display = t.display; ids = ms.map(\.ref.id); from = ms.map(\.from)
    }
}

/// #77, #97: the switch overlay's memory of the pictures it flew and prefetched. Pure policy — the
/// images and their capture live in the UI layer's `SwitchOverlay`, which instantiates this.
///
/// Stale-while-revalidate (#97): a switch flies the newest set it has for its key, however old. A
/// slightly stale picture during a 200 ms slide is barely visible; a capture you can feel before
/// anything moves is worse. `needsRefresh` tells the prefetch, after landing, which sets to take
/// again. A key comes from the store's world, so its windows still exist; the overlay also drops
/// the sets of windows the window server no longer lists (`removeAll(where:)`), to free the memory.
public struct SwitchPictureCache<Pictures> {
    public typealias Key = SwitchPictureKey

    /// How many sets that switches flew are kept, most recently used first.
    // ponytail: up to ~7 sets of full-viewport backdrops (tens of MB each on a 5K display); share
    // one backdrop per display if memory shows up.
    public static var kept: Int { 3 }
    /// Older than this, the prefetch takes a set again. It is still flown until then.
    public static var freshFor: Duration { .seconds(3) }

    private struct Entry { let key: Key; let pictures: Pictures; let taken: ContinuousClock.Instant }
    private var flown: [Entry] = []
    private var prefetched: [Entry] = []

    public init() {}

    private func newest(_ key: Key) -> Entry? {
        (flown + prefetched).filter { $0.key == key }.max { $0.taken < $1.taken }
    }

    /// The newest set for `key`, of any age. Reading it counts as flying it.
    public mutating func take(_ key: Key) -> Pictures? {
        guard let e = newest(key) else { return nil }
        prefetched.removeAll { $0.key == key }
        add(e.key, e.pictures, taken: e.taken)
        return e.pictures
    }

    /// No set for `key`, or only one taken `freshFor` or longer ago.
    public func needsRefresh(_ key: Key, now: ContinuousClock.Instant) -> Bool {
        newest(key).map { now - $0.taken >= Self.freshFor } ?? true
    }

    /// A set a switch flew or captured for itself, now the most recently used. A set taken before
    /// the one already held for its key (a slow capture landing late) does not replace it.
    public mutating func add(_ key: Key, _ pictures: Pictures, taken: ContinuousClock.Instant) {
        if let held = newest(key), held.taken > taken { return }
        flown.removeAll { $0.key == key }
        flown.insert(Entry(key: key, pictures: pictures, taken: taken), at: 0)
        flown = Array(flown.prefix(Self.kept))
    }

    /// A set taken ahead of time for a predicted switch.
    public mutating func prefetch(_ key: Key, _ pictures: Pictures, taken: ContinuousClock.Instant) {
        if let held = newest(key), held.taken > taken { return }
        prefetched.removeAll { $0.key == key }
        prefetched.append(Entry(key: key, pictures: pictures, taken: taken))
    }

    /// Drops the prefetches no prediction wants any more.
    public mutating func keepPrefetches(_ wanted: [Key]) {
        prefetched.removeAll { !wanted.contains($0.key) }
    }

    public mutating func removeAll(where dead: (Key) -> Bool) {
        flown.removeAll { dead($0.key) }
        prefetched.removeAll { dead($0.key) }
    }
}

extension Task where Failure == Never, Success: Sendable {
    /// #97: the task's value if it finishes within `budget`, else nil. Either way the task runs on
    /// to the end — the caller stops waiting, it does not cancel.
    public func value(within budget: Duration) async -> Success? {
        let once = Once<Success?>()
        return await withCheckedContinuation { c in
            once.arm(c)
            Task<Void, Never> { once.resume(await self.value) }
            Task<Void, Never> { try? await Task<Never, Never>.sleep(for: budget); once.resume(nil) }
        }
    }
}

/// A continuation resumed by whichever side comes first.
private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var c: CheckedContinuation<T, Never>?
    func arm(_ continuation: CheckedContinuation<T, Never>) { lock.withLock { c = continuation } }
    func resume(_ value: T) {
        let taken = lock.withLock { () -> CheckedContinuation<T, Never>? in defer { c = nil }; return c }
        taken?.resume(returning: value)
    }
}
