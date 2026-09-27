import Foundation
import SpacialShellProtocol

/// One `config.toml` key (#168): its TOML name, the `Config` property it sets, and, when the
/// settings window can set it too, its `SettingsOverrides` property.
///
/// `Config.keys` lists every key once. Everything else is derived from that list: decoding the
/// file, `settings.json`'s coding, `Settings.effective`'s merge and the unknown-key checker's
/// known names (#133). A key's default is its `Config` property's initial value: decoding starts
/// from `Config()`, and a key the file leaves out keeps it.
struct ConfigKey: Sendable {
    /// The TOML name, `panel-width`.
    let name: String
    /// The `Config` property it sets. Only the table's own test reads it: each property once.
    let property: PartialKeyPath<Config> & Sendable
    /// The keys a table or `[[array]]` of tables takes, for the unknown-key checker. Nil for a
    /// value, and for a free-form map (`[keybindings]`), whose keys are data.
    let subkeys: Set<String>?
    /// How `settings.json` sets it; nil when only the file does.
    let override: Override?
    let decode: @Sendable (inout Config, KeyedDecodingContainer<Name>) throws -> Void

    /// A key `settings.json` can set. Its JSON name is its `SettingsOverrides` property's name,
    /// which is what the synthesized encoder wrote before #168, so older files still read.
    struct Override: Sendable {
        let name: String
        let decode: @Sendable (inout SettingsOverrides, KeyedDecodingContainer<Name>) throws -> Void
        let encode: @Sendable (SettingsOverrides, inout KeyedEncodingContainer<Name>) throws -> Void
        let apply: @Sendable (SettingsOverrides, inout Config) -> Void

        /// `decode` is for a value that needs more than `decodeIfPresent` (`layouts`, lossily);
        /// `apply` lays the window's value over the file's.
        init<V: Codable & Sendable>(
            _ name: String, _ path: WritableKeyPath<SettingsOverrides, V?> & Sendable,
            decode: @escaping @Sendable (KeyedDecodingContainer<Name>, Name) throws -> V?
                = { try $0.decodeIfPresent(V.self, forKey: $1) },
            apply: @escaping @Sendable (inout Config, V) -> Void
        ) {
            let key = Name(name)
            self.name = name
            self.decode = { o, c in o[keyPath: path] = try decode(c, key) }
            self.encode = { o, c in try c.encodeIfPresent(o[keyPath: path], forKey: key) }
            self.apply = { o, c in if let v = o[keyPath: path] { apply(&c, v) } }
        }
    }
}

extension ConfigKey {
    /// A key only the file sets: decode the value, `clamp` it, set it. `subkeys` names a table's
    /// own keys, for the unknown-key checker.
    static func key<V: Codable & Sendable>(
        _ name: String, _ path: WritableKeyPath<Config, V> & Sendable,
        clamp: @escaping @Sendable (V) -> V = { $0 }, subkeys: Set<String>? = nil
    ) -> ConfigKey {
        make(name, path, override: nil, clamp: clamp, normalize: nil, invalid: nil, subkeys: subkeys)
    }

    /// A key the settings window can set too, as the camel-cased `SettingsOverrides` property
    /// (`panel-width` is `panelWidth`). The window's value replaces the file's unless `merge` says
    /// otherwise, and is clamped the same way. `normalize` is for the file's text only: nil rejects
    /// the file, saying `invalid`. (A `settings.json` value is the window's own, and is taken as is.)
    static func key<V: Codable & Sendable>(
        _ name: String, _ path: WritableKeyPath<Config, V> & Sendable,
        override: WritableKeyPath<SettingsOverrides, V?> & Sendable,
        merge: @escaping @Sendable (_ file: V, _ gui: V) -> V = { $1 },
        clamp: @escaping @Sendable (V) -> V = { $0 },
        normalize: (@Sendable (V) -> V?)? = nil, invalid: String? = nil
    ) -> ConfigKey {
        let knob = Override(camelCase(name), override) { c, v in c[keyPath: path] = clamp(merge(c[keyPath: path], v)) }
        return make(name, path, override: knob, clamp: clamp, normalize: normalize, invalid: invalid, subkeys: nil)
    }

    private static func make<V: Codable & Sendable>(
        _ name: String, _ path: WritableKeyPath<Config, V> & Sendable, override: Override?,
        clamp: @escaping @Sendable (V) -> V, normalize: (@Sendable (V) -> V?)?, invalid: String?, subkeys: Set<String>?
    ) -> ConfigKey {
        let key = Name(name)
        return ConfigKey(
            name: name, property: path, subkeys: subkeys, override: override,
            decode: { config, c in
                guard var v = try c.decodeIfPresent(V.self, forKey: key) else { return }
                if let normalize {
                    guard let n = normalize(v) else {
                        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: invalid ?? "\(name) is not valid")
                    }
                    v = n
                }
                config[keyPath: path] = clamp(v)
            })
    }

    /// A key whose unset state means something (`screen-gap` follows `gap`): absent stays nil.
    static func optional<V: Codable & Sendable>(
        _ name: String, _ path: WritableKeyPath<Config, V?> & Sendable,
        override: WritableKeyPath<SettingsOverrides, V?> & Sendable
    ) -> ConfigKey {
        let key = Name(name)
        return ConfigKey(
            name: name, property: path, subkeys: nil,
            override: Override(camelCase(name), override) { c, v in c[keyPath: path] = v },
            decode: { config, c in
                if let v = try c.decodeIfPresent(V.self, forKey: key) { config[keyPath: path] = v }
            })
    }

    /// A table's own keys, from its `CodingKeys`.
    static func names<K: CodingKey & CaseIterable>(_: K.Type) -> Set<String> { Set(K.allCases.map(\.stringValue)) }

    /// `panel-width` → `panelWidth`: `settings.json`'s name for an overridable key. It is persisted:
    /// renaming a TOML key renames it too, and `settingsJSONKeepsItsKeyNames` fails.
    static func camelCase(_ name: String) -> String {
        let parts = name.split(separator: "-")
        return parts.enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }.joined()
    }
}

extension Config {
    /// Every key `config.toml` can set, in the order they decode (the first bad value is the one
    /// reported). Adding a key is one line here, plus its `Config` property (whose initial value is
    /// the default); give it `override:` and a `SettingsOverrides` property for the settings
    /// window to set it. `ConfigKeyTableTests` checks the table against both structs.
    static let keys: [ConfigKey] = [
        .key("keybinding-preset", \.keybindingPreset, override: \.keybindingPreset),
        .key("gap", \.gap, override: \.gap),
        .optional("screen-gap", \.screenGap, override: \.screenGap),
        .key("default-layout", \.defaultLayout, override: \.defaultLayout),
        .key("ax-timeout-ms", \.axTimeoutMs),
        .key("refresh-interval-ms", \.refreshIntervalMs),
        .key("start-at-login", \.startAtLogin),
        .key("panel-width", \.panelWidth, override: \.panelWidth),
        .key("panel-height", \.panelHeight, override: \.panelHeight),
        .key("rail-side", \.railSide, override: \.railSide),
        .key("tab-sizing", \.tabSizing, override: \.tabSizing),
        .key("tab-style", \.tabStyle, override: \.tabStyle),
        .key("rail-icon-style", \.railIconStyle, override: \.railIconStyle),
        .key("dock-attention", \.dockAttention, override: \.dockAttention),
        categoryColorsKey,
        .key("launcher-url", \.launcherURL),
        .key("show-panels", \.showPanels),
        .key("crowd-threshold", \.crowdThreshold),
        .key("category-order", \.categoryOrder, override: \.categoryOrder),
        .key("max-workspaces", \.maxWorkspaces, override: \.maxWorkspaces, clamp: { max(1, $0) }),
        .key("other-window-managers", \.otherWindowManagers),
        .key("persist-state", \.persistState, override: \.persistState),
        .key("animations", \.animations, override: \.animations),
        .key("animate-retile", \.animateRetile, override: \.animateRetile),
        .key("empty-cheatsheet", \.emptyCheatsheet, override: \.emptyCheatsheet),
        .key("rail-autohide", \.railAutohide, override: \.railAutohide),
        .key("pointer-warp", \.pointerWarp, override: \.pointerWarp),
        .key("workspace-wrap", \.workspaceWrap, override: \.workspaceWrap),
        .key("gestures", \.gestures, override: \.gestures),
        // Clamped rather than refused, like `panel-opacity`: a 2 or a 10 is a typo, not a reason
        // to throw the whole file away.
        .key("gesture-fingers", \.gestureFingers,
             clamp: { min(Config.gestureFingerRange.upperBound, max(Config.gestureFingerRange.lowerBound, $0)) }),
        .key("gesture-invert", \.gestureInvert, override: \.gestureInvert),
        .key("gesture-layout", \.gestureLayout, override: \.gestureLayout),
        .key("focus-follows-mouse", \.focusFollowsMouse, override: \.focusFollowsMouse),
        .key("focus-follows-mouse-delay-ms", \.focusFollowsMouseDelayMs, clamp: FocusFollowsMouse.clamp),
        .key("panel-color", \.panelColor, override: \.panelColor,
             normalize: HexColor.normalize, invalid: "panel-color must be \"system\" or #RRGGBB"),
        // Clamped rather than refused: an out-of-range opacity is a typo, not a reason to reject
        // the whole config and fall back to defaults the user never asked for.
        .key("panel-opacity", \.panelOpacity, clamp: { min(1, max(0, $0)) }),
        .key("app-categories", \.appCategories),
        .key("workspace", \.workspaces, subkeys: ConfigKey.names(WorkspaceSeed.CodingKeys.self)),
        layoutsKey,
        .key("layout-bar", \.layoutBar, override: \.layoutBar),
        .key("ephemeral", \.ephemeral, subkeys: ConfigKey.names(AppRule.CodingKeys.self)),
        .key("float", \.float, subkeys: ConfigKey.names(AppRule.CodingKeys.self)),
        .key("ignore", \.ignore, subkeys: ConfigKey.names(AppRule.CodingKeys.self)),
        .key("tile", \.tile, subkeys: ConfigKey.names(AppRule.CodingKeys.self)),
        .key("keybindings", \.keybindings),
        // Merged per command, not replaced: rebinding one command in the window cannot discard a
        // rebind the file made to another.
        .key("keybinding-overrides", \.keybindingOverrides, override: \.keybindingOverrides,
             merge: { file, gui in file.merging(gui) { _, gui in gui } }),
        .key("telemetry", \.telemetry, subkeys: ConfigKey.names(TelemetryConfig.CodingKeys.self)),
    ]

    /// #115: a key that is not a category is left for `unknownKeys` to name; a bad colour rejects
    /// the file, as a bad `panel-color` does.
    private static let categoryColorsKey = ConfigKey(
        name: "category-colors", property: \Config.categoryColors, subkeys: Set(AppCategory.allCases.map(\.rawValue)),
        override: nil,
        decode: { config, c in
            let key = ConfigKey.Name("category-colors")
            for (name, raw) in try c.decodeIfPresent([String: String].self, forKey: key) ?? [:] {
                guard let category = AppCategory(rawValue: name) else { continue }
                guard let hex = HexColor.normalize(raw), hex != "system" else {
                    throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "category-colors.\(name) must be #RRGGBB")
                }
                config.categoryColors[category] = hex
            }
        })

    /// #9: `[[layout]]`, decoded one entry at a time in both stores, so a bad one is dropped with
    /// a log line instead of rejecting the file. The window's layouts merge per id over the
    /// file's (design §3.1), under `settings.json`'s older plural name.
    private static let layoutsKey = ConfigKey(
        name: "layout", property: \Config.layouts, subkeys: ConfigKey.names(LayoutDef.CodingKeys.self),
        override: .init("layouts", \.layouts, decode: { try LayoutDef.lossy($0, $1) }) { c, gui in
            c.layouts = LayoutDef.merge(file: c.layouts, gui: gui)
        },
        decode: { config, c in config.layouts = try LayoutDef.lossy(c, ConfigKey.Name("layout")) ?? [] })
}

extension ConfigKey {
    /// A key by name, in `config.toml` or `settings.json`. There is no enum of them to keep in
    /// step: `Config.keys` is the list.
    struct Name: CodingKey {
        let stringValue: String
        init(_ name: String) { stringValue = name }
        init(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }
}
