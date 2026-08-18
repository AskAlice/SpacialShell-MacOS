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
    }
}
