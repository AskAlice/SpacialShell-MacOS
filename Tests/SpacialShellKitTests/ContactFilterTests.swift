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
