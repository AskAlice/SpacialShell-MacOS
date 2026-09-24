import Testing
import Foundation
@testable import SpacialShellKit

/// The settings window never writes `config.toml` — no Swift library preserves TOML comments, and
/// the file is the interface the user hand-edits. GUI edits go to an app-owned store that layers
/// over the file instead, so a comment can never be clobbered. This is the seam where the two
/// meet: given what the file says and what the GUI set, what does the shell actually use?
@Suite struct SettingsTests {
    @Test func anOverrideBeatsTheFile() {
        var file = Config(); file.panelWidth = 48
        var gui = SettingsOverrides(); gui.panelWidth = 64
        #expect(Settings.effective(config: file, overrides: gui).panelWidth == 64)
    }

    /// The other half of the rule, and the one that makes the file still worth hand-editing:
    /// a knob the settings window has never touched is the file's to decide.
    @Test func anUnsetOverrideLeavesTheFileAlone() {
        var file = Config(); file.panelWidth = 48
        #expect(Settings.effective(config: file, overrides: SettingsOverrides()).panelWidth == 48)
    }

    /// #60: the focus ring is off by default, so turning it on and styling it must not need the file.
    @Test func theFocusRingAndMotionAreSettable() {
        var gui = SettingsOverrides()
        gui.focusRing = true; gui.highlightColor = "#FF0000"; gui.highlightMs = 0; gui.animations = false
        let c = Settings.effective(config: Config(), overrides: gui)
        #expect(c.focusRing && c.highlightColor == "#FF0000" && c.highlightMs == 0 && !c.animations)
    }

    /// Clearing a knob in the settings window hands it back to the file rather than freezing
    /// whatever the GUI last showed — otherwise there would be no way out of an override.
    @Test func clearingAnOverrideHandsTheKnobBack() {
        var file = Config(); file.panelWidth = 48
        var gui = SettingsOverrides(); gui.panelWidth = 64
        gui.panelWidth = nil
        #expect(Settings.effective(config: file, overrides: gui).panelWidth == 48)
    }

    /// The preset is the escape hatch for a keyboard that cannot emit the `fn` modifier at all —
    /// Karabiner's virtual keyboard is one, since Apple handles `fn` in hardware and a virtual HID
    /// device cannot reproduce it. Someone in that position cannot use the app until they change
    /// this, so it has to be reachable without hand-editing a file.
    @Test func theKeybindingPresetIsOverridable() {
        var file = Config(); file.keybindingPreset = .fn
        var gui = SettingsOverrides(); gui.keybindingPreset = .ctrlAlt
        #expect(Settings.effective(config: file, overrides: gui).keybindingPreset == .ctrlAlt)
        gui.keybindingPreset = nil
        #expect(Settings.effective(config: file, overrides: gui).keybindingPreset == .fn)
    }

    @Test func appearanceKnobsAreOverridable() {
        var file = Config(); file.panelOpacity = 1
        var gui = SettingsOverrides()
        gui.panelOpacity = 0.6
        gui.panelColor = "#112233"
        gui.gap = 16
        let out = Settings.effective(config: file, overrides: gui)
        #expect(out.panelOpacity == 0.6 && out.panelColor == "#112233" && out.gap == 16)
    }

    // MARK: persistence — the store the settings window writes instead of config.toml

    @Test func overridesRoundTripThroughJSON() throws {
        var gui = SettingsOverrides()
        gui.panelWidth = 64; gui.panelOpacity = 0.6; gui.tabSizing = .equal; gui.panelColor = "#112233"
        let data = try JSONEncoder().encode(gui)
        #expect(try JSONDecoder().decode(SettingsOverrides.self, from: data) == gui)
    }

    /// An absent key is how "the file decides" is written down. If unset knobs were encoded as
    /// null, every knob would become an override the moment the settings window saved once, and
    /// config.toml would quietly stop mattering.
    @Test func unsetKnobsAreAbsentFromTheStore() throws {
        let json = String(data: try JSONEncoder().encode(SettingsOverrides()), encoding: .utf8)
        #expect(json == "{}")
    }

    /// A settings file written by a newer build must not stop an older one from starting.
    @Test func unknownKnobsAreIgnored() throws {
        let json = Data(#"{"panelWidth":64,"somethingFromTheFuture":true}"#.utf8)
        let gui = try JSONDecoder().decode(SettingsOverrides.self, from: json)
        #expect(gui.panelWidth == 64)
    }

    /// Per-command merge, not wholesale replacement: rebinding one command in the window must not
    /// discard a rebind the config file made to a different one.
    @Test func keybindingOverridesMergePerCommand() {
        var file = Config(); file.keybindingOverrides = ["cycle-layout": "fn-shift-l"]
        var gui = SettingsOverrides(); gui.keybindingOverrides = ["toggle-float": "fn-shift-f"]
        let out = Settings.effective(config: file, overrides: gui)
        #expect(out.keybindingOverrides["cycle-layout"] == "fn-shift-l")
        #expect(out.keybindingOverrides["toggle-float"] == "fn-shift-f")
    }

    /// And where both name the same command, the window wins — it is the more recent intent.
    @Test func theWindowWinsOnTheSameCommand() {
        var file = Config(); file.keybindingOverrides = ["cycle-layout": "fn-shift-l"]
        var gui = SettingsOverrides(); gui.keybindingOverrides = ["cycle-layout": "fn-shift-k"]
        #expect(Settings.effective(config: file, overrides: gui).keybindingOverrides["cycle-layout"] == "fn-shift-k")
    }
}
