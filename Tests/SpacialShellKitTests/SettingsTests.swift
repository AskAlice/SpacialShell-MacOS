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

    /// Switch motion is settable without touching the file.
    @Test func switchAnimationIsSettable() {
        var gui = SettingsOverrides(); gui.animations = false
        #expect(!Settings.effective(config: Config(), overrides: gui).animations)
    }

    /// #29: the empty-workspace cheat sheet defaults on, reads from the file, and the settings
    /// window can override it.
    @Test func emptyCheatsheetKey() throws {
        #expect(Config().emptyCheatsheet)
        let file = try Config.parse(toml: "empty-cheatsheet = false")
        #expect(!file.emptyCheatsheet)
        var gui = SettingsOverrides(); gui.emptyCheatsheet = true
        #expect(Settings.effective(config: file, overrides: gui).emptyCheatsheet)
    }

    /// #60: overrides saved before the focus ring was removed still carry its fields; they must
    /// decode (and be dropped) rather than wipe every other override.
    @Test func removedFocusRingOverridesStillDecode() throws {
        let json = ##"{"focusRing":true,"highlightColor":"#FF0000","highlightMs":0,"panelWidth":64}"##
        let o = try JSONDecoder().decode(SettingsOverrides.self, from: Data(json.utf8))
        #expect(o.panelWidth == 64)
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
        var gui = SettingsOverrides()
        gui.panelColor = "#11223399"     // the colour well carries opacity as alpha
        gui.gap = 16
        let out = Settings.effective(config: Config(), overrides: gui)
        #expect(out.panelColor == "#11223399" && out.gap == 16)
        #expect(HexColor.rgba(out.panelColor)?.3 == 0x99 / 255.0)
    }

    // MARK: persistence — the store the settings window writes instead of config.toml

    @Test func overridesRoundTripThroughJSON() throws {
        var gui = SettingsOverrides()
        gui.panelWidth = 64; gui.tabSizing = .equal; gui.panelColor = "#112233"; gui.tabStyle = .name
        let data = try JSONEncoder().encode(gui)
        #expect(try JSONDecoder().decode(SettingsOverrides.self, from: data) == gui)
        #expect(Settings.effective(config: Config(), overrides: gui).tabStyle == .name)   // #116
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

    /// #74: the Workspaces pane. The order replaces the file's wholesale, and `[]` is a value
    /// (routing off), not "unset".
    @Test func categoryOrderAndMaxWorkspacesAreOverridable() {
        var file = Config(); file.categoryOrder = [.web, .terminal]; file.maxWorkspaces = 12
        var gui = SettingsOverrides(); gui.categoryOrder = [.media, .web]; gui.maxWorkspaces = 5
        var out = Settings.effective(config: file, overrides: gui)
        #expect(out.categoryOrder == [.media, .web] && out.maxWorkspaces == 5)
        gui.categoryOrder = []; gui.maxWorkspaces = 0
        out = Settings.effective(config: file, overrides: gui)
        #expect(out.categoryOrder.isEmpty && out.maxWorkspaces == 1, "off is a value; the cap never drops below one")
        gui.categoryOrder = nil; gui.maxWorkspaces = nil
        out = Settings.effective(config: file, overrides: gui)
        #expect(out.categoryOrder == [.web, .terminal] && out.maxWorkspaces == 12)
    }
    @Test func overridesSavedBeforeTheWorkspacesPaneStillDecode() throws {
        let old = try JSONDecoder().decode(SettingsOverrides.self, from: Data(#"{"panelWidth":64,"gap":4}"#.utf8))
        #expect(old.panelWidth == 64 && old.categoryOrder == nil && old.maxWorkspaces == nil)
        var gui = SettingsOverrides(); gui.categoryOrder = [.coding]; gui.maxWorkspaces = 7
        #expect(try JSONDecoder().decode(SettingsOverrides.self, from: JSONEncoder().encode(gui)) == gui)
    }
}
