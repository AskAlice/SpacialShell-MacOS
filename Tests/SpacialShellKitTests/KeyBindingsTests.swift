import Testing
@testable import SpacialShellKit

@Suite struct KeyBindingsTests {
    @Test func parsesChords() {
        #expect(KeyBindings.parse("fn-w") == Chord(keyCode: 13, fn: true, control: false, option: false, shift: false, command: false))
        #expect(KeyBindings.parse("ctrl-alt-shift-left") == Chord(keyCode: 123, fn: false, control: true, option: true, shift: true, command: false))
        #expect(KeyBindings.parse("fn-space")?.keyCode == 49)
        #expect(KeyBindings.parse("bogus-w") == nil)
        #expect(KeyBindings.parse("fn-nokey") == nil)
    }
    @Test func fnPresetHasMaterialShellDefaults() throws {
        let t = KeyBindings.table(for: try Config.parse(toml: ""))
        #expect(t[KeyBindings.parse("fn-w")!] == .focusWorkspace(.up))
        #expect(t[KeyBindings.parse("fn-shift-d")!] == .moveWindow(.right))
        #expect(t[KeyBindings.parse("fn-0")!] == .focusWorkspaceIndex(10))
        #expect(t[KeyBindings.parse("fn-q")!] == .closeFocusedWindow)
        #expect(t[KeyBindings.parse("fn-space")!] == .cycleLayout)
        #expect(t[KeyBindings.parse("fn-esc")!] == .toggleShellUI)
        #expect(t[KeyBindings.parse("fn-g")!] == .toggleFloat)
        #expect(t[KeyBindings.parse("fn-rightSquareBracket")!] == .focusScreen(.next))
        #expect(t[KeyBindings.parse("ctrl-alt-up")!] == .focusWorkspace(.up))          // arrows always on ctrl-alt
        #expect(t[KeyBindings.parse("ctrl-alt-shift-right")!] == .moveWindow(.right))
        #expect(t[KeyBindings.parse("fn-f")!] == nil)                                     // Globe+F is Apple's
    }
    @Test func ctrlAltPresetAndOverrides() throws {
        let t = KeyBindings.table(for: try Config.parse(toml: "keybinding-preset = \"ctrl-alt\"\n[keybindings]\n\"ctrl-alt-x\" = \"toggle-float\"\n"))
        #expect(t[KeyBindings.parse("ctrl-alt-w")!] == .focusWorkspace(.up))
        #expect(t[KeyBindings.parse("fn-w")!] == nil)
        #expect(t[KeyBindings.parse("ctrl-alt-x")!] == .toggleFloat)
        #expect(t[KeyBindings.parse("ctrl-alt-shift-1")!] == .moveWindowToWorkspaceIndex(1))
        // ⌥ is already in the prefix, so the whole-app chord would collide with ⌃⌥⇧W: unbound here.
        #expect(t[KeyBindings.parse("ctrl-alt-shift-w")!] == .moveWindowToWorkspace(.up))
        #expect(!t.values.contains(.moveAppToWorkspace(.up)))
    }
    /// #105 and #98 on the grammar: +Shift moves the window, +Shift+Option the whole app.
    @Test func moveToWorkspaceNAndMoveAppChords() throws {
        let t = KeyBindings.table(for: try Config.parse(toml: ""))
        #expect(t[KeyBindings.parse("fn-shift-1")!] == .moveWindowToWorkspaceIndex(1))
        #expect(t[KeyBindings.parse("fn-shift-0")!] == .moveWindowToWorkspaceIndex(10))
        #expect(t[KeyBindings.parse("fn-alt-shift-w")!] == .moveAppToWorkspace(.up))
        #expect(t[KeyBindings.parse("fn-alt-shift-s")!] == .moveAppToWorkspace(.down))
        #expect(KeyBindings.commandNames["move-window-to-workspace-3"] == .moveWindowToWorkspaceIndex(3))
        #expect(KeyBindings.commandNames["move-app-down"] == .moveAppToWorkspace(.down))
    }

    // MARK: rebinding (settings window)

    /// `keybindings` in config.toml is chord -> command and is applied *after* the defaults, so it
    /// can only ever add a chord. That is fine for a file you hand-edit, and useless for a
    /// settings window: picking a new chord for "cycle layout" has to stop the old one working,
    /// or every rebind silently leaves a second way in.
    @Test func anOverrideReplacesTheDefaultChordForThatCommand() {
        var c = Config()
        c.keybindingOverrides = ["cycle-layout": "fn-shift-l"]
        let t = KeyBindings.table(for: c)
        #expect(t[KeyBindings.parse("fn-shift-l")!] == .cycleLayout)
        #expect(t[KeyBindings.parse("fn-space")!] == nil, "the default chord must stop working")
    }

    /// Rebinding one command must not disturb any other.
    @Test func anOverrideLeavesOtherCommandsAlone() {
        var c = Config()
        c.keybindingOverrides = ["cycle-layout": "fn-shift-l"]
        let t = KeyBindings.table(for: c)
        #expect(t[KeyBindings.parse("fn-w")!] == .focusWorkspace(.up))
        #expect(t[KeyBindings.parse("fn-q")!] == .closeFocusedWindow)
    }

    /// An override that names a command or a chord we cannot parse is ignored rather than fatal —
    /// a settings file is ours, but a config file is the user's and may say anything.
    @Test func anUnparseableOverrideIsIgnored() {
        var c = Config()
        c.keybindingOverrides = ["cycle-layout": "fn-nonsense", "not-a-command": "fn-shift-p"]
        let t = KeyBindings.table(for: c)
        #expect(t[KeyBindings.parse("fn-space")!] == .cycleLayout, "an unusable override leaves the default alone")
        #expect(t[KeyBindings.parse("fn-shift-p")!] == nil)
    }

    /// The arrow bindings are a second way into the same commands and are not the preset's job,
    /// so an override of a command also clears its arrow chord — otherwise the old binding lives on.
    @Test func anOverrideAlsoClearsTheArrowChord() {
        var c = Config()
        c.keybindingOverrides = ["focus-workspace-up": "fn-shift-u"]
        let t = KeyBindings.table(for: c)
        #expect(t[KeyBindings.parse("fn-shift-u")!] == .focusWorkspace(.up))
        #expect(t[KeyBindings.parse("ctrl-alt-up")!] == nil)
        #expect(t[KeyBindings.parse("fn-w")!] == nil)
    }
}
