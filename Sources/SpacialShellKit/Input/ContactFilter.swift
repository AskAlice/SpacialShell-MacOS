import Foundation

/// #202: one contact on the trackpad: `NSTouch.identity`'s hash, and its normalized position.
public struct TouchContact: Equatable, Sendable {
    public var id: Int, x: Double, y: Double
    public init(id: Int, x: Double, y: Double) { self.id = id; self.x = x; self.y = y }
}

/// #202: which contacts are the swipe's fingers. A palm or a thumb resting on the trackpad is a
/// contact macOS does not always mark as resting, and counting it turned two moving fingers into
/// a three-finger swipe. Here only contacts that have **moved** count: each is measured from where
/// it landed, joins once it has gone `minMove`, and — once others are moving — only if it goes
/// their way. Nothing moved yet is no fingers at all, so the recognizer sees the count rise as the
/// fingers set off (1, 2, 3) and starts at the real one; a palm that never moves never joins.
///
/// A real palm is never quite still: it rolls along a fraction of the fingers' way as the hand
/// swipes, or settles a few millimetres as it lands. So moving is not enough: a contact joins
/// only once it has gone `joinShare` of the farthest contact's way, and leaves once it falls
/// under `leaveShare` of it. Fingers on one hand travel nearly alike; a palm falls behind. A
/// contact leaving while still down is a `TouchFrame.regrouped` frame, not a finger lifting.
///
/// The frame it makes is a `TouchFrame` of the movers alone: their count and their centroid. When
/// none is down (the fingers lifted, a palm still resting) it is a lift. macOS's interleaved empty
/// frames keep every contact's start: state is forgotten only after `SwipeRecognizer.liftGrace`.
public struct ContactFilter: Equatable, Sendable {
    /// About 3 mm across a 15 cm trackpad: past fingers settling as they land, well short of a
    /// swipe's threshold, so the count is settled before the recognizer can fire.
    public static let minMove = 0.02
    /// A late joiner must head within about 45° of the group's way.
    public static let coherence = 0.7
    /// The share of the farthest contact's travel a contact must make to join, and under which a
    /// joined one leaves. Fingers of one swipe stay above about 0.7 of each other; the gap
    /// between the two keeps a contact near the line from flickering in and out.
    public static let joinShare = 0.6
    public static let leaveShare = 0.4

    private struct Start: Equatable, Sendable { var x: Double, y: Double }
    private var starts: [Int: Start] = [:]
    private var movers: Set<Int> = []
    private var emptySince: TimeInterval?

    public init() {}

    public mutating func frame(_ contacts: [TouchContact], time: TimeInterval?) -> TouchFrame {
        guard !contacts.isEmpty else {
            if emptySince == nil { emptySince = time }
            if time == nil { forget() }
            return TouchFrame(fingers: 0, x: 0, y: 0, time: time)
        }
        if let since = emptySince {
            emptySince = nil
            if let t = time, t - since > SwipeRecognizer.liftGrace { forget() }   // a real lift
        }
        let here = Set(contacts.map(\.id))
        starts = starts.filter { here.contains($0.key) }
        movers.formIntersection(here)
        for c in contacts where starts[c.id] == nil { starts[c.id] = Start(x: c.x, y: c.y) }

        func moved(_ c: TouchContact) -> (dx: Double, dy: Double) { (c.x - starts[c.id]!.x, c.y - starts[c.id]!.y) }
        func length(_ d: (dx: Double, dy: Double)) -> Double { (d.dx * d.dx + d.dy * d.dy).squareRoot() }
        let farthest = contacts.map { length(moved($0)) }.max() ?? 0
        let behind = contacts.filter { movers.contains($0.id) && length(moved($0)) < Self.leaveShare * farthest }
        movers.subtract(behind.map(\.id))
        let candidates = contacts.filter {
            !movers.contains($0.id) && length(moved($0)) >= max(Self.minMove, Self.joinShare * farthest)
        }
        // The group's way: the movers', or — for the first to set off — the candidates' own mean, so
        // one heading against the rest is left out from the start.
        let group = (movers.isEmpty ? candidates : contacts.filter { movers.contains($0.id) }).map(moved)
        let gx = group.reduce(0) { $0 + $1.dx }, gy = group.reduce(0) { $0 + $1.dy }
        let glen = (gx * gx + gy * gy).squareRoot()
        var joining: [Int] = []
        for c in candidates {
            let d = moved(c)
            if glen == 0 || (d.dx * gx + d.dy * gy) / (length(d) * glen) >= Self.coherence { joining.append(c.id) }
        }
        movers.formUnion(joining)

        let fingers = contacts.filter { movers.contains($0.id) }
        guard !fingers.isEmpty else { return TouchFrame(fingers: 0, x: 0, y: 0, time: time) }
        var out = TouchFrame(positions: fingers.map { (x: $0.x, y: $0.y) }, time: time)
        out.regrouped = !behind.isEmpty
        return out
    }

    private mutating func forget() { starts = [:]; movers = [] }
}
