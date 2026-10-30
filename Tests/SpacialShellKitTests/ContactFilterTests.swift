import Testing
import Foundation
@testable import SpacialShellKit

/// #202: only the contacts that move together are fingers. A palm or thumb resting on the trackpad
/// never counts, so two moving fingers and a palm are no three-finger swipe.
@Suite struct ContactFilterTests {
    typealias C = TouchContact
    /// Fingers 1…n at y 0.5, moved right by `dx`; a palm (id 99) still at the bottom.
    func frame(_ n: Int, dx: Double, palm: Bool, t: TimeInterval) -> [C] {
        (1...n).map { C(id: $0, x: 0.2 + 0.1 * Double($0) + dx, y: 0.5) } + (palm ? [C(id: 99, x: 0.5, y: 0.05)] : [])
    }

    /// Runs a swipe through filter and recognizer; what it recognizes.
    func swipe(_ n: Int, palm: Bool) -> Swipe? {
        var f = ContactFilter(), r = SwipeRecognizer(fingers: [3, 4])
        var out: Swipe?
        for i in 0...20 {
            let t = Double(i) * 0.008
            if let s = r.feed(f.frame(frame(n, dx: Double(i) * 0.012, palm: palm, t: t), time: t)) { out = s }
        }
        return out
    }

    @Test func twoFingersAndAPalmAreNoThreeFingerSwipe() {
        #expect(swipe(2, palm: true) == nil)
    }

    @Test func threeFingersWithAPalmAreAThreeFingerSwipe() {
        #expect(swipe(3, palm: true) == Swipe(fingers: 3, direction: .right))
    }

    @Test func fourFingersAreAFourFingerSwipe() {
        #expect(swipe(4, palm: false) == Swipe(fingers: 4, direction: .right))
        #expect(swipe(4, palm: true) == Swipe(fingers: 4, direction: .right))
    }

    /// A real palm is not still: it rolls along as the hand swipes, a fraction of the fingers' way,
    /// or settles a few millimetres as it lands. Neither makes it a finger.
    func driftingSwipe(_ n: Int, palm: (Int) -> (x: Double, y: Double)) -> Swipe? {
        var f = ContactFilter(), r = SwipeRecognizer(fingers: [3, 4])
        var out: Swipe?
        for i in 0...20 {
            let t = Double(i) * 0.008, p = palm(i)
            let contacts = frame(n, dx: Double(i) * 0.012, palm: false, t: t) + [C(id: 99, x: p.x, y: p.y)]
            if let s = r.feed(f.frame(contacts, time: t)) { out = s }
        }
        return out
    }

    @Test func aPalmRollingWithTheHandIsNoFinger() {
        let rolling = { (i: Int) in (x: 0.5 + Double(i) * 0.004, y: 0.05) }   // a third of the fingers' way
        #expect(driftingSwipe(2, palm: rolling) == nil)
        #expect(driftingSwipe(3, palm: rolling) == Swipe(fingers: 3, direction: .right))
    }

    @Test func aPalmThatSettledBeforeTheSwipeIsNoFinger() {
        // Lands, slides 4.5 mm up within the first frames, then rests while the fingers swipe.
        let settling = { (i: Int) in (x: 0.5, y: 0.05 + 0.01 * Double(min(i, 3))) }
        var f = ContactFilter()
        _ = f.frame([C(id: 99, x: 0.5, y: 0.05)], time: 0)
        _ = f.frame([C(id: 99, x: 0.5, y: 0.08)], time: 0.008)
        #expect(driftingSwipe(2, palm: settling) == nil)
        #expect(driftingSwipe(3, palm: settling) == Swipe(fingers: 3, direction: .right))
    }

    /// The palm rolled along early and was counted; once the fingers outpace it, it is dropped, and
    /// the swipe is the fingers' own count, not none.
    @Test func aPalmLeftBehindIsDroppedAndTheSwipeStillFires() {
        let early = { (i: Int) in (x: 0.5 + 0.008 * Double(min(i, 4)), y: 0.05) }   // keeps up, then stops
        #expect(driftingSwipe(3, palm: early) == Swipe(fingers: 3, direction: .right))
        #expect(driftingSwipe(2, palm: early) == nil)
    }

    /// Nothing has moved yet: no fingers. The movers join as they move.
    @Test func onlyMovedContactsCount() {
        var f = ContactFilter()
        #expect(f.frame(frame(3, dx: 0, palm: true, t: 0), time: 0).fingers == 0)
        #expect(f.frame(frame(3, dx: 0.03, palm: true, t: 0.01), time: 0.01).fingers == 3)
        let moved = f.frame(frame(3, dx: 0.06, palm: true, t: 0.02), time: 0.02)
        #expect(moved.fingers == 3)
        #expect(abs(moved.y - 0.5) < 1e-9, "the palm is not in the centroid")
    }

    /// A contact moving against the group is not one of its fingers.
    @Test func aContactMovingTheOtherWayIsNotCounted() {
        var f = ContactFilter()
        _ = f.frame([C(id: 1, x: 0.3, y: 0.5), C(id: 2, x: 0.4, y: 0.5), C(id: 3, x: 0.6, y: 0.5)], time: 0)
        let out = f.frame([C(id: 1, x: 0.34, y: 0.5), C(id: 2, x: 0.44, y: 0.5), C(id: 3, x: 0.56, y: 0.5)], time: 0.01)
        #expect(out.fingers == 2)
    }

    /// macOS interleaves an empty frame with each moving one: that is not a lift, and the
    /// contacts keep their starts across it.
    @Test func interleavedEmptyFramesKeepTheContacts() {
        var f = ContactFilter()
        _ = f.frame(frame(3, dx: 0, palm: false, t: 0), time: 0)
        #expect(f.frame([], time: 0.004).fingers == 0)
        #expect(f.frame(frame(3, dx: 0.03, palm: false, t: 0.005), time: 0.005).fingers == 3, "moved since the start")
    }

    /// The fingers lift while the palm stays down: that is the end of the gesture (a drag ends).
    @Test func thePalmAloneIsALift() {
        var f = ContactFilter()
        _ = f.frame(frame(4, dx: 0, palm: true, t: 0), time: 0)
        #expect(f.frame(frame(4, dx: 0.05, palm: true, t: 0.01), time: 0.01).fingers == 4)
        #expect(f.frame([C(id: 99, x: 0.5, y: 0.05)], time: 0.02).fingers == 0)
    }
}
