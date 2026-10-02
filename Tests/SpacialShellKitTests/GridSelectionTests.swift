import Testing
import CoreGraphics
@testable import SpacialShellKit

/// #200: the overview's keyboard selection over its sections (windows, then applications), each
/// laid out in a fixed number of columns. Arrows move by row and column, Tab jumps section, and
/// a narrowed search clamps the selection.
@Suite struct GridSelectionTests {
    typealias S = GridSelection
    /// Windows: 6 in rows of 4 (the second row is short). Apps: 9 in rows of 7.
    func both() -> S { S(sections: [.init(count: 6, columns: 4), .init(count: 9, columns: 7)]) }

    @Test func startsOnTheFirstResult() {
        #expect(both().at == .init(section: 0, index: 0))
        #expect(S(sections: [.init(count: 0, columns: 4), .init(count: 3, columns: 7)]).at == .init(section: 1, index: 0))
        #expect(S(sections: [.init(count: 0, columns: 4)]).at == nil)
    }

    @Test func leftAndRightRunThroughAndAcrossSections() {
        var s = both()
        s.move(.left)
        #expect(s.at == .init(section: 0, index: 0), "nothing before the first")
        for _ in 0..<5 { s.move(.right) }
        #expect(s.at == .init(section: 0, index: 5))
        s.move(.right)
        #expect(s.at == .init(section: 1, index: 0), "on into the apps")
        s.move(.left)
        #expect(s.at == .init(section: 0, index: 5))
    }

    @Test func upAndDownKeepTheColumn() {
        var s = both()
        s.move(.right); s.move(.right); s.move(.right)                 // column 3 of row 0
        s.move(.down)
        #expect(s.at == .init(section: 0, index: 5), "row 1 is short: its last item")
        s.move(.down)
        #expect(s.at == .init(section: 1, index: 1), "into the apps, same column as index 5 had (1)")
        s.move(.down)
        #expect(s.at == .init(section: 1, index: 8))
        s.move(.down)
        #expect(s.at == .init(section: 1, index: 8), "nothing below the last row")
        s.move(.up); s.move(.up)
        #expect(s.at == .init(section: 0, index: 5), "back up: the windows' last row, clamped")
        s.move(.up)
        #expect(s.at == .init(section: 0, index: 1))
        s.move(.up)
        #expect(s.at == .init(section: 0, index: 1), "nothing above the first row")
    }

    @Test func thePointerSelectsWithinBounds() {
        var s = both()
        s.select(.init(section: 1, index: 4))
        #expect(s.at == .init(section: 1, index: 4))
        s.select(.init(section: 0, index: 9))
        #expect(s.at == .init(section: 1, index: 4), "out of range: ignored")
    }

    @Test func tabJumpsSectionsAndWraps() {
        var s = both()
        s.move(.right)
        s.tab(backward: false)
        #expect(s.at == .init(section: 1, index: 0))
        s.tab(backward: false)
        #expect(s.at == .init(section: 0, index: 0), "wraps")
        s.tab(backward: true)
        #expect(s.at == .init(section: 1, index: 0))
    }

    @Test func narrowingClampsAndEmptySectionsAreSkipped() {
        var s = both()
        for _ in 0..<5 { s.move(.right) }                             // windows index 5
        s.resize([.init(count: 2, columns: 4), .init(count: 9, columns: 7)])
        #expect(s.at == .init(section: 0, index: 1))
        s.resize([.init(count: 0, columns: 4), .init(count: 9, columns: 7)])
        #expect(s.at == .init(section: 1, index: 0))
        s.tab(backward: false)
        #expect(s.at == .init(section: 1, index: 0), "the only section with items")
        s.resize([.init(count: 0, columns: 4), .init(count: 0, columns: 7)])
        #expect(s.at == nil)
        s.move(.down)
        #expect(s.at == nil)
    }

    /// #205: Fn+Tab's cycling walks every result in reading order, across sections, and wraps.
    @Test func stepWalksAllResultsAndWraps() {
        var s = S(sections: [.init(count: 2, columns: 4), .init(count: 2, columns: 7)])
        s.step(forward: true); #expect(s.at == .init(section: 0, index: 1))
        s.step(forward: true); #expect(s.at == .init(section: 1, index: 0))
        s.step(forward: true); s.step(forward: true)
        #expect(s.at == .init(section: 0, index: 0), "wraps to the first")
        s.step(forward: false)
        #expect(s.at == .init(section: 1, index: 1), "and back to the last")
    }
}

/// #205: Fn+Tab held like alt-tab: Tab and ⇧Tab cycle while the modifier is down, and letting go
/// opens the selection — but only after cycling; a plain Fn+Tab tap keeps the overview for search.
@Suite struct OverviewHoldTests {
    let fn: CGEventFlags = .maskSecondaryFn

    @Test func cyclingThenReleasingOpens() {
        var h = OverviewHold(held: fn)!
        h.stepped()
        #expect(h.flagsChanged(fn) == .holding)
        #expect(h.flagsChanged([]) == .open)
    }

    @Test func aPlainTapKeepsTheOverviewOpen() {
        var h = OverviewHold(held: fn)!
        #expect(h.flagsChanged([]) == .letGo)
    }

    @Test func nothingHeldIsNoHold() {
        #expect(OverviewHold(held: [.maskShift]) == nil)
    }

    /// Tab and ⇧Tab with the held modifiers step; nothing else is bound.
    @Test func theStepChordsUseTheHeldModifiers() {
        let chords = OverviewHold(held: [.maskControl, .maskAlternate])!.stepChords
        let tab = KeyCodes.byName["tab"]!
        #expect(chords[Chord(keyCode: tab, fn: false, control: true, option: true, shift: false, command: false)] == .overviewStep(reverse: false))
        #expect(chords[Chord(keyCode: tab, fn: false, control: true, option: true, shift: true, command: false)] == .overviewStep(reverse: true))
        #expect(chords.count == 2)
    }
}

