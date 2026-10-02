import Foundation

/// #90: the rail hover card's memory of what each window last looked like, so a hover draws in its
/// first frame instead of waiting on ScreenCaptureKit. Pure policy — the images, their capture and
/// their downscaling live in the UI layer, which instantiates this with `CGImage`.
///
/// Least-recently-used by window id, capped at `capacity`; an entry older than `freshFor` is still
/// served (a stale picture beats a blank box) but reports `isStale`, so the card refreshes it in the
/// background. Windows that close are dropped by `retain(_:)`, fed from the store's world.
public struct ThumbnailCache<Image> {
    /// ~400 px on the long side is ~400 KB a thumbnail (400×250×4), so the cap holds memory to ~60 MB worst case.
    public static var capacity: Int { 150 }
    /// A hover or an opened view takes anything older again: user-initiated, so kept short.
    public static var freshFor: Duration { .seconds(3) }

    private struct Entry { var image: Image; var taken: ContinuousClock.Instant; var used: UInt64 }
    private var entries: [WindowID: Entry] = [:]
    private var tick: UInt64 = 0
    private let capacity: Int

    public init(capacity: Int = Self.capacity) { self.capacity = capacity }

    public var count: Int { entries.count }

    /// The last picture of `id`, however old; reading it counts as a use.
    public mutating func image(for id: WindowID) -> Image? {
        guard entries[id] != nil else { return nil }
        tick += 1
        entries[id]!.used = tick
        return entries[id]!.image
    }

    /// Never seen, or seen more than `freshFor` ago.
    public func isStale(_ id: WindowID, now: ContinuousClock.Instant = .now) -> Bool {
        guard let e = entries[id] else { return true }
        return now - e.taken >= Self.freshFor
    }

    /// When the held picture of `id` was taken; nil if there is none. For #142's refresh order.
    public func taken(_ id: WindowID) -> ContinuousClock.Instant? { entries[id]?.taken }

    public mutating func insert(_ image: Image, for id: WindowID, taken: ContinuousClock.Instant = .now) {
        tick += 1
        // A picture taken before the one we hold (a slow capture landing late) does not replace it.
        if let e = entries[id], e.taken > taken { entries[id]!.used = tick; return }
        entries[id] = Entry(image: image, taken: taken, used: tick)
        // ponytail: O(n) scan per overflow; n is the cap (150), a linked list if it ever grows.
        while entries.count > capacity, let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key {
            entries[oldest] = nil
        }
    }

    /// Drops every window not in `live` — the ones that closed.
    public mutating func retain(_ live: Set<WindowID>) {
        entries = entries.filter { live.contains($0.key) }
    }
}

extension World {
    /// Every window the model knows, managed or not: what a thumbnail may still be wanted for.
    public var allWindowIDs: Set<WindowID> {
        var ids = Set(screens.values.flatMap { $0.workspaces.flatMap { $0.windows.map(\.id) } })
        for w in ephemeral.union(ignored) { ids.insert(w.id) }
        return ids
    }
}
