import Testing
@testable import SpacialShellKit

/// #185: the cheat sheet never shows over the spatial view, and a hold that met the view is spent.
@Suite struct CheatSheetGateTests {
    /// Feeds modifier changes in order and returns what the gate answered to each.
    func answers(_ g: inout CheatSheetGate, _ steps: [(bare: Bool, suppressed: Bool)]) -> [Bool] {
        steps.map { g.modifier(bare: $0.bare, suppressed: $0.suppressed) }
    }

    @Test func aBareHoldMayShowTheSheet() {
        var g = CheatSheetGate()
        #expect(answers(&g, [(true, false)]) == [true])
    }

    @Test func aHoldWhileTheSpatialViewIsOpenNeverShowsIt() {
        var g = CheatSheetGate()
        #expect(answers(&g, [(true, true)]) == [false])
    }

    /// The view closes with Fn still down: that same hold must not bring the sheet up afterwards.
    @Test func aHoldThatMetTheSpatialViewIsSpentUntilReleased() {
        var g = CheatSheetGate()
        // held with the view open · same hold, view now closed · released · a fresh hold
        #expect(answers(&g, [(true, true), (true, false), (false, false), (true, false)])
                == [false, false, false, true])
    }

    /// The view opens while Fn is already held (Fn+W held opens it): that hold is spent too.
    @Test func openingTheViewSpendsTheHoldInProgress() {
        var g = CheatSheetGate()
        #expect(answers(&g, [(true, false)]) == [true])
        g.spatialOpened(modifierHeld: true)
        #expect(answers(&g, [(true, false), (false, false), (true, false)]) == [false, false, true])
    }

    @Test func openingTheViewWithNothingHeldSpendsNothing() {
        var g = CheatSheetGate()
        g.spatialOpened(modifierHeld: false)
        #expect(answers(&g, [(true, false)]) == [true])
    }
}
