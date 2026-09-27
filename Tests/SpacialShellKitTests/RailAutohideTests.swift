import Testing
import Foundation
@testable import SpacialShellKit

/// #96: the auto-hiding rail's reveal/hide state machine, and the insets it implies.
@Suite struct RailAutohideTests {
    let reveal = RailAutohide.revealDelay, hide = RailAutohide.hideDelay

    @Test func restingInTheZoneRevealsAfterTheDelay() {
        var m = RailAutohide()
        m.step(inZone: true, overRail: false, pinned: false, now: 0)
        #expect(!m.isShown && m.needsTicks)
        m.step(inZone: true, overRail: false, pinned: false, now: reveal - 0.01)
        #expect(!m.isShown)
        m.step(inZone: true, overRail: false, pinned: false, now: reveal)
        #expect(m.isShown)
    }

    @Test func crossingTheZoneDoesNotReveal() {
        var m = RailAutohide()
        m.step(inZone: true, overRail: false, pinned: false, now: 0)
        m.step(inZone: false, overRail: false, pinned: false, now: 0.1)
        #expect(m.phase == .hidden && !m.needsTicks)
        m.step(inZone: false, overRail: false, pinned: false, now: 5)
        #expect(!m.isShown)
    }

    @Test func staysWhileOverTheRailThenHidesAfterTheDelay() {
        var m = shown()
        m.step(inZone: false, overRail: true, pinned: false, now: 10)
        #expect(m.phase == .shown)
        m.step(inZone: false, overRail: false, pinned: false, now: 11)
        #expect(m.isShown)   // still on screen through the hide delay
        m.step(inZone: false, overRail: false, pinned: false, now: 11 + hide - 0.01)
        #expect(m.isShown)
        m.step(inZone: false, overRail: false, pinned: false, now: 11 + hide)
        #expect(m.phase == .hidden)
    }

    @Test func returningDuringTheHideDelayKeepsItShown() {
        var m = shown()
        m.step(inZone: false, overRail: false, pinned: false, now: 10)
        m.step(inZone: false, overRail: true, pinned: false, now: 10.1)
        #expect(m.phase == .shown)
        m.step(inZone: false, overRail: true, pinned: false, now: 20)
        #expect(m.phase == .shown)
    }

    /// The hover card sits beside the rail, so reaching it leaves the rail; a drag or menu from the
    /// rail can take the pointer anywhere. Either way the rail stays until it closes.
    @Test func aPinKeepsItShownAndHidingResumesAfter() {
        var m = shown()
        m.step(inZone: false, overRail: false, pinned: true, now: 10)
        m.step(inZone: false, overRail: false, pinned: true, now: 100)
        #expect(m.phase == .shown)
        m.step(inZone: false, overRail: false, pinned: false, now: 101)
        m.step(inZone: false, overRail: false, pinned: false, now: 101 + hide)
        #expect(m.phase == .hidden)
    }

    @Test func aPinNeverRevealsAHiddenRail() {
        var m = RailAutohide()
        m.step(inZone: false, overRail: false, pinned: true, now: 0)
        m.step(inZone: false, overRail: false, pinned: true, now: 10)
        #expect(m.phase == .hidden)
    }

    @Test func resetHidesAtOnce() {
        var m = shown()
        m.reset()
        #expect(m.phase == .hidden && !m.isShown)
    }

    /// Autohide takes the rail's inset away on whichever side it is on; the bar's stays.
    @Test func autohideRemovesTheRailInsetOnEitherSide() {
        for side in [RailSide.left, .right] {
            var c = Config(); c.railSide = side; c.panelWidth = 48; c.panelHeight = 34; c.railAutohide = true
            let i = ShellInsets(config: c, hidden: false)
            #expect(i == ShellInsets(top: 34, left: 0, right: 0, bottom: 0))
            #expect(i.apply(to: CGRect(x: 0, y: 0, width: 1000, height: 700)) == CGRect(x: 0, y: 34, width: 1000, height: 666))
        }
    }

    @Test func railAutohideKey() throws {
        #expect(!Config().railAutohide)
        let file = try Config.parse(toml: "rail-autohide = true")
        #expect(file.railAutohide)
        var gui = SettingsOverrides(); gui.railAutohide = false
        #expect(!Settings.effective(config: file, overrides: gui).railAutohide)
    }

    private func shown() -> RailAutohide {
        var m = RailAutohide()
        m.step(inZone: true, overRail: false, pinned: false, now: 0)
        m.step(inZone: true, overRail: true, pinned: false, now: reveal)
        #expect(m.phase == .shown)
        return m
    }
}
