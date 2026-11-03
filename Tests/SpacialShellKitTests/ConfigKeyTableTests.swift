import Testing
import Foundation
@testable import SpacialShellKit

/// #168: `Config.keys` is the one place a key is declared. These keep it honest against the two
/// structs it describes, so a property without a row, or a row pointing at the wrong property,
/// fails here instead of silently never loading.
@Suite struct ConfigKeyTableTests {
    /// `Config` properties that are not keys the file sets.
    static let notKeys: Set<String> = ["fileLayoutIDs"]   // derived from `[[layout]]` while decoding

    /// Key paths compare by identity, so no two rows set one property; and there are as many rows
    /// as properties, so none is left out. The names are only for the failure message.
    @Test func everyConfigPropertyIsInTheTableExactlyOnce() {
        let properties = Set(Mirror(reflecting: Config()).children.compactMap(\.label)).subtracting(Self.notKeys)
        let paths = Config.keys.map { $0.property as PartialKeyPath<Config> }
        #expect(Set(paths).count == paths.count, "a property is set by two keys")
        let named = Set(paths.map { String(String(reflecting: $0).split(separator: ".").last ?? "") })
        #expect(paths.count == properties.count,
                "no key for \(properties.subtracting(named).sorted()); not a property: \(named.subtracting(properties).sorted())")
    }

    /// #210: keys the settings window deliberately leaves to `config.toml`, each with why. Every
    /// other key must be settable in the window, so a new key needs a control or a line here.
    static let fileOnly: [String: String] = [
        "ax-timeout-ms": "diagnostic; read once at launch",
        "refresh-interval-ms": "diagnostic; read once at launch",
        "telemetry": "diagnostic export settings",
        "other-window-managers": "advanced: which other managers to warn about",
        "panel-opacity": "the panel colour well's opacity slider sets it",
        "keybindings": "the Keybindings pane edits keybinding-overrides",
        "category-colors": "table: a colour per category, hand-edited",
        "app-categories": "table: app to category map, hand-edited",
        "workspace": "table: [[workspace]] seeds, hand-edited",
        "ephemeral": "table: app rule list, hand-edited",
        "float": "table: app rule list, hand-edited",
        "ignore": "table: app rule list, hand-edited",
        "tile": "table: app rule list, hand-edited",
    ]

    @Test func everyKeyIsInTheWindowOrSaysWhyNot() {
        let names = Set(Config.keys.map(\.name))
        let unsettable = Config.keys.filter { $0.override == nil }.map(\.name)
        #expect(Set(unsettable) == Set(Self.fileOnly.keys),
                "no control and no reason: \(Set(unsettable).subtracting(Self.fileOnly.keys).sorted()); settable or gone: \(Set(Self.fileOnly.keys).subtracting(unsettable).sorted())")
        #expect(Set(Self.fileOnly.keys).isSubset(of: names))
    }

    @Test func everyKeyNameIsUnique() {
        let names = Config.keys.map(\.name)
        #expect(Set(names).count == names.count)
    }

    /// `settings.json`'s knobs are exactly the overridable keys, plus `silencedWarnings` (which is
    /// the app's, not a config knob). A property with no row would be written by nobody and read by
    /// nobody: set in the window, gone on the next launch.
    @Test func everySettingsOverridesPropertyIsAKnob() {
        let properties = Set(Mirror(reflecting: SettingsOverrides()).children.compactMap(\.label))
        let knobs = Config.keys.compactMap(\.override?.name)
        #expect(Set(knobs).count == knobs.count)
        #expect(Set(knobs + ["silencedWarnings"]) == properties)
    }

    /// The fixture sets every knob, so the round trips below cover every one.
    @Test func theFixtureSetsEveryKnob() {
        for child in Mirror(reflecting: ConfigCharacterizationTests.fullOverrides).children {
            #expect(String(describing: child.value) != "nil", "set \(child.label ?? "?") in fullOverrides")
        }
    }

    /// Encode → decode gives back what was set: no knob is written and not read, or read into
    /// another property.
    @Test func everyKnobRoundTripsThroughSettingsJSON() throws {
        let all = ConfigCharacterizationTests.fullOverrides
        let data = try JSONEncoder().encode(all)
        #expect(try JSONDecoder().decode(SettingsOverrides.self, from: data) == all)

        // One knob at a time: it decodes on its own, and it changes what the shell uses.
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let base = ConfigCharacterizationTests.fullConfig
        for knob in Config.keys.compactMap(\.override?.name) {
            let json = try JSONSerialization.data(withJSONObject: [knob: try #require(object[knob], "\(knob) not encoded")])
            let one = try JSONDecoder().decode(SettingsOverrides.self, from: json)
            #expect(one != SettingsOverrides(), "\(knob) did not decode")
            let changes = Settings.effective(config: base, overrides: one) != base
                || Settings.effective(config: Config(), overrides: one) != Config()
            #expect(changes, "\(knob) changes nothing")
        }
    }

    /// `docs/config.md` stays the reference: every key has a row in a key table, or a `[table]`
    /// heading.
    @Test func everyKeyIsDocumented() throws {
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/config.md")
        let text = try String(contentsOf: docs, encoding: .utf8)
        for key in Config.keys.map(\.name) {
            #expect(text.contains("| `\(key)` |") || text.contains("[\(key)]"), "docs/config.md has no row for \(key)")
        }
    }
}
