import Testing
import Foundation
@testable import SpacialShellKit

/// #140 (G13): re-tile motion, built with limits. What animates, under which rules, and when the
/// capture budget turns it into instant placement. Pure; the overlay only asks.
@Suite struct MotionRulesTests {
    let r = CGRect(x: 0, y: 0, width: 100, height: 100)
    func t(_ kind: Transition.Kind, display: DisplayID = "D1") -> Transition {
        Transition(display: display, viewport: r, moves: [.init(ref: WindowRef(id: 1, pid: 1), from: r, to: r)], kind: kind)
    }

    @Test func aPassIsARetileOnlyWhenEveryDisplayRetiles() {
        #expect(MotionRules([t(.retile), t(.retile, display: "D2")]).kind == .retile)
        #expect(MotionRules([t(.retile), t(.switch, display: "D2")]).kind == .switch, "a switch sets the rules")
        #expect(MotionRules([t(.switch)]).kind == .switch)
        #expect(MotionRules([]).kind == .switch)
    }

    /// Off by default: a re-tile is placed instantly, and the animator is not even asked. A switch
    /// on another display in the same pass still slides.
    @Test func retilesAnimateOnlyWithAnimateRetile() {
        let pass = [t(.retile), t(.switch, display: "D2")]
        #expect(MotionRules.animated(pass, animations: true, animateRetile: false, grabbing: false) == [pass[1]])
        #expect(MotionRules.animated(pass, animations: true, animateRetile: true, grabbing: false) == pass)
        #expect(MotionRules.animated([t(.retile)], animations: true, animateRetile: false, grabbing: false).isEmpty)
    }

    /// `animations` is the master switch, and a border drag (#113) never animates.
    @Test func nothingAnimatesWithAnimationsOffOrWhileDragging() {
        let pass = [t(.retile), t(.switch, display: "D2")]
        #expect(MotionRules.animated(pass, animations: false, animateRetile: true, grabbing: false).isEmpty)
        #expect(MotionRules.animated(pass, animations: true, animateRetile: true, grabbing: true).isEmpty)
    }

    /// ~250 ms for a re-tile, the switch's 200 ms unchanged; the same 80 ms budget for both.
    @Test func aRetileFliesALittleLonger() {
        #expect(MotionRules([t(.retile)]).duration == .milliseconds(250))
        #expect(MotionRules([t(.switch)]).duration == .milliseconds(200))
        #expect(MotionRules.captureBudget == .milliseconds(80))
    }

    /// A re-tile captures fresh, keeps nothing, and skips the rail-thumbnail ingest (20% of the
    /// CPU inside a re-tile at 8 windows, M4 spec §7). A switch keeps all three as they were.
    @Test func aRetileSkipsTheCacheAndTheThumbnails() {
        let retile = MotionRules([t(.retile)]), sw = MotionRules([t(.switch)])
        #expect(!retile.usesPictureCache && !retile.feedsThumbnails)
        #expect(sw.usesPictureCache && sw.feedsThumbnails)
    }

    /// Reduce Motion is respected: instant. So is a missing Screen Recording grant.
    @Test func theGateBeforeCapturing() {
        #expect(MotionRules.gate(screenRecording: true, reduceMotion: false) == .animate)
        #expect(MotionRules.gate(screenRecording: true, reduceMotion: true) == .instant(.reduceMotion))
        #expect(MotionRules.gate(screenRecording: false, reduceMotion: true) == .instant(.noGrant))
    }

    /// The budget is a hard cutoff: a wait that ran out, or a capture that came back after the
    /// budget anyway, is instant; so is one missing a picture.
    @Test func theBudgetVerdict() {
        #expect(MotionRules.verdict(took: .milliseconds(72), complete: true) == .animate)
        #expect(MotionRules.verdict(took: .milliseconds(80), complete: true) == .animate, "the budget itself is in")
        #expect(MotionRules.verdict(took: .milliseconds(84), complete: true) == .instant(.overBudget))
        #expect(MotionRules.verdict(took: nil, complete: false) == .instant(.overBudget))
        #expect(MotionRules.verdict(took: .milliseconds(20), complete: false) == .instant(.captureFailed))
        // The test hook's stretched budget (`SpacialMotionScale`) is the one that counts.
        #expect(MotionRules.verdict(took: .milliseconds(112), complete: true, budget: .milliseconds(160)) == .animate)
    }

    /// `animate-retile`: off by default, read from the file, known to #133's checker, and a
    /// settings-window override over the file.
    @Test func animateRetileKey() throws {
        #expect(!Config().animateRetile)
        #expect(!(try Config.parse(toml: "")).animateRetile)
        let on = try Config.parse(toml: "animate-retile = true\n")
        #expect(on.animateRetile)
        #expect(Config.unknownKeys(toml: "animations = true\nanimate-retile = true\n").isEmpty)
        #expect(Config.unknownKeys(toml: "animate-retiles = true\n") == ["animate-retiles"])

        var gui = SettingsOverrides(); gui.animateRetile = true
        #expect(Settings.effective(config: Config(), overrides: gui).animateRetile)
        #expect(!Settings.effective(config: on, overrides: { var o = SettingsOverrides(); o.animateRetile = false; return o }()).animateRetile)
        let back = try JSONDecoder().decode(SettingsOverrides.self, from: JSONEncoder().encode(gui))
        #expect(back.animateRetile == true)
    }
}
