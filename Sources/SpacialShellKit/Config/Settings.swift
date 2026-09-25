import Foundation

/// What the settings window has set, layered over `config.toml`.
///
/// Every field is optional and `nil` means "the file decides". The settings window never writes
/// the TOML: no Swift library preserves its comments (toml++ has had the request open since 2020,
/// and the community implementation was closed unmerged), and the file is the interface the user
/// hand-edits. Ghostty reached the same arrangement for the same reason.
public struct SettingsOverrides: Codable, Equatable, Sendable {
    public var panelWidth: Double?
    public var panelHeight: Double?
    public var gap: Double?
    public var panelColor: String?
    public var railSide: RailSide?
    public var tabSizing: TabSizing?
    public var keybindingPreset: KeybindingPreset?
    public var animations: Bool?
    public var emptyCheatsheet: Bool?
    /// command -> chord. Merged over the file's own overrides per command rather than replacing
    /// the map wholesale, so rebinding one command in the settings window cannot silently discard
    /// a rebind the file made to a different one.
    public var keybindingOverrides: [String: String]?

    public init() {}
}

public enum Settings {
    /// What the shell actually uses: the file, with anything the settings window has set on top.
    public static func effective(config: Config, overrides: SettingsOverrides) -> Config {
        var c = config
        if let v = overrides.panelWidth { c.panelWidth = v }
        if let v = overrides.panelHeight { c.panelHeight = v }
        if let v = overrides.gap { c.gap = v }
        if let v = overrides.panelColor { c.panelColor = v }
        if let v = overrides.railSide { c.railSide = v }
        if let v = overrides.tabSizing { c.tabSizing = v }
        if let v = overrides.keybindingPreset { c.keybindingPreset = v }
        if let v = overrides.animations { c.animations = v }
        if let v = overrides.emptyCheatsheet { c.emptyCheatsheet = v }
        if let v = overrides.keybindingOverrides { c.keybindingOverrides.merge(v) { _, gui in gui } }
        return c
    }
}
