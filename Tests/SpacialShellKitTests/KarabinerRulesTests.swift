import Testing
import Foundation
@testable import SpacialShellKit

/// #196: the Karabiner-Elements rules file the hotkey table becomes.
@Suite struct KarabinerRulesTests {
    let path = "/Applications/SpacialShell.app/Contents/MacOS/spacialctl"

    func export(_ toml: String = "") throws -> [String: Any] {
        let data = KarabinerRules.export(table: KeyBindings.table(for: try Config.parse(toml: toml)), spacialctlPath: path)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func manipulators(_ root: [String: Any]) throws -> [[String: Any]] {
        let rules = try #require(root["rules"] as? [[String: Any]])
        #expect(rules.count == 1)
        return try #require(rules[0]["manipulators"] as? [[String: Any]])
    }

    /// (key_code, mandatory modifiers) → the shell command.
    func byChord(_ ms: [[String: Any]]) -> [String: String] {
        var out: [String: String] = [:]
        for m in ms {
            let from = m["from"] as! [String: Any]
            let mods = (from["modifiers"] as! [String: Any])["mandatory"] as? [String] ?? []
            let cmd = ((m["to"] as! [[String: Any]])[0])["shell_command"] as! String
            out[(mods + [from["key_code"] as! String]).joined(separator: "+")] = cmd
        }
        return out
    }

    func run(_ name: String) -> String { "'\(path)' run \(name)" }

    /// Karabiner's root structure: a title, rules with a description, basic manipulators.
    @Test func shapeIsKarabinersAssetFile() throws {
        let root = try export()
        #expect(root["title"] as? String == "SpacialShell")
        let rule = try #require((root["rules"] as? [[String: Any]])?.first)
        #expect((rule["description"] as? String)?.isEmpty == false)
        let ms = try manipulators(root)
        #expect(!ms.isEmpty)
        for m in ms {
            #expect(m["type"] as? String == "basic")
            let from = try #require(m["from"] as? [String: Any])
            #expect(from["key_code"] is String)
            #expect((from["modifiers"] as? [String: Any])?["optional"] as? [String] == ["caps_lock"])
            #expect((m["to"] as? [[String: Any]])?.count == 1)
        }
    }

    @Test func fnPreset() throws {
        let ms = try manipulators(try export())
        let w = try #require(ms.first { ($0["to"] as! [[String: Any]])[0]["shell_command"] as? String == run("focus-workspace-up")
                                        && (($0["from"] as! [String: Any])["modifiers"] as! [String: Any])["mandatory"] as? [String] == ["fn"] })
        #expect(w["from"] as? NSDictionary == ["key_code": "w", "modifiers": ["mandatory": ["fn"], "optional": ["caps_lock"]]] as NSDictionary)
        let chords = byChord(ms)
        #expect(chords["fn+shift+d"] == run("move-window-right"))
        #expect(chords["fn+control+equal_sign"] == run("balance"))
        #expect(chords["fn+option+a"] == run("focus-screen-left"))
        #expect(chords["control+option+up_arrow"] == run("focus-workspace-up"))   // the arrows, on every preset
        // Fn+⇧← is bound as Home (what the tap sees); Karabiner sees the arrow.
        #expect(chords["fn+shift+left_arrow"] == run("move-window-to-screen-left"))
        #expect(chords["fn+option+shift+page_up"] == nil)
        #expect(chords["fn+option+shift+up_arrow"] == run("move-workspace-to-screen-up"))
        #expect(chords["control+option+w"] == nil)
    }

    @Test func ctrlAltPreset() throws {
        let chords = byChord(try manipulators(try export("keybinding-preset = \"ctrl-alt\"\n")))
        #expect(chords["control+option+w"] == run("focus-workspace-up"))
        #expect(chords["control+option+shift+s"] == run("move-window-down"))
        #expect(chords["control+option+command+a"] == run("shrink-width"))
        #expect(chords["fn+w"] == nil)
    }

    @Test func punctuationKeysUseKarabinersNames() throws {
        let chords = byChord(try manipulators(try export()))
        #expect(chords["fn+open_bracket"] == run("focus-screen-prev"))
        #expect(chords["fn+shift+close_bracket"] == run("move-window-to-screen-next"))
        #expect(chords["fn+spacebar"] == run("cycle-layout"))
        #expect(chords["fn+escape"] == run("toggle-shell-ui"))
        #expect(chords["fn+comma"] == run("open-settings"))
        let rebound = byChord(try manipulators(try export("[keybindings]\n\"ctrl-alt-backtick\" = \"toggle-float\"\n\"ctrl-alt-minus\" = \"balance\"\n")))
        #expect(rebound["control+option+grave_accent_and_tilde"] == run("toggle-float"))
        #expect(rebound["control+option+hyphen"] == run("balance"))
    }

    /// #188's switcher is held open and picks on release; #132's spatial view opens on a held
    /// Fn+W/S. Neither survives a one-shot shell command, and the description says so.
    @Test func modalAndHeldCommandsAreSkippedAndNamed() throws {
        let root = try export()
        let commands = byChord(try manipulators(root)).values
        #expect(!commands.contains { $0.contains("switch-app-window") })
        #expect(commands.contains(run("toggle-spatial-view")))   // the toggle itself is one-shot
        let description = try #require((root["rules"] as? [[String: Any]])?.first?["description"] as? String)
        #expect(description.contains("⌘`"))
        #expect(description.contains("Fn+⇧`"))
        #expect(description.contains("Fn+W"))
        #expect(description.contains("spatial view"))
    }

    @Test func reexportIsByteIdentical() throws {
        let table = KeyBindings.table(for: try Config.parse(toml: ""))
        let first = KarabinerRules.export(table: table, spacialctlPath: path)
        // A dictionary rebuilt from shuffled pairs has a different iteration order.
        let shuffled = Dictionary(uniqueKeysWithValues: table.shuffled())
        #expect(KarabinerRules.export(table: shuffled, spacialctlPath: path) == first)
    }

    @Test func pathsAndOddLayoutIdsAreQuotedForTheShell() {
        let chord = KeyBindings.parse("fn-x")!
        let data = KarabinerRules.export(table: [chord: .setLayout(LayoutID(rawValue: "it's mine"))],
                                         spacialctlPath: "/Users/o'neil/spacialctl")
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#"'/Users/o'\\''neil/spacialctl' run 'set-layout-it'\\''s mine'"#))
    }
}
