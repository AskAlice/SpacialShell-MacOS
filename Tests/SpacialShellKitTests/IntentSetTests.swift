import Testing
import Foundation
@testable import SpacialShellKit

// NOTE: `IntentSet.matches` is `mutating`, and on this toolchain (Swift 6.3.3 / swift-testing 1902)
// the `#expect` macro's call-expression decomposition cannot invoke a mutating method directly on
// the captured receiver ("cannot use mutating member on immutable value: '$0' is immutable" — a
// swift-testing macro limitation, reproduced with a minimal `mutating func matches` on any struct,
// independent of this implementation). Each call is bound to a local `let` before `#expect` so the
// same sequence of record/matches calls and the same assertions run as in the brief.
@Suite struct IntentSetTests {
    let a = WindowRef(id: 1, pid: 1)
    @Test func matchingFrameEventIsAbsorbedOnce() {
        var s = IntentSet()
        s.record(.setFrame(a, CGRect(x: 10, y: 10, width: 100, height: 100)))
        let firstMatch = s.matches(a, frame: CGRect(x: 10.5, y: 10, width: 100, height: 99.5))
        #expect(firstMatch)
        let secondMatch = s.matches(a, frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        #expect(!secondMatch)   // consumed
    }
    @Test func positionIntentMatchesOriginOnly() {
        var s = IntentSet()
        s.record(.setPosition(a, CGPoint(x: 999, y: 699)))
        let match = s.matches(a, frame: CGRect(x: 999, y: 699, width: 400, height: 300))
        #expect(match)
    }
    @Test func unrelatedFrameDoesNotMatchAndKeepsIntent() {
        var s = IntentSet()
        s.record(.setFrame(a, CGRect(x: 10, y: 10, width: 100, height: 100)))
        let unrelated = s.matches(a, frame: CGRect(x: 500, y: 10, width: 100, height: 100))
        #expect(!unrelated)
        let stillThere = s.matches(a, frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        #expect(stillThere)
    }
    @Test func newerIntentReplacesOlder() {
        var s = IntentSet()
        s.record(.setFrame(a, CGRect(x: 1, y: 1, width: 1, height: 1)))
        s.record(.setFrame(a, CGRect(x: 2, y: 2, width: 2, height: 2)))
        let matchesOld = s.matches(a, frame: CGRect(x: 1, y: 1, width: 1, height: 1))
        #expect(!matchesOld)
        let matchesNew = s.matches(a, frame: CGRect(x: 2, y: 2, width: 2, height: 2))
        #expect(matchesNew)
    }
    @Test func originIntentToleratesTitleBarClamp() {
        var s = IntentSet()
        s.record(.setPosition(a, CGPoint(x: 999, y: 699)))
        let clamped = s.matches(a, frame: CGRect(x: 999, y: 668, width: 400, height: 300))
        #expect(clamped)
        s.record(.setPosition(a, CGPoint(x: 999, y: 699)))
        let wrongX = s.matches(a, frame: CGRect(x: 950, y: 699, width: 400, height: 300))
        #expect(!wrongX)
    }
}
