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
    public var panelOpacity: Double?
    public var railSide: RailSide?
    public var tabSizing: TabSizing?

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
        if let v = overrides.panelOpacity { c.panelOpacity = v }
        if let v = overrides.railSide { c.railSide = v }
        if let v = overrides.tabSizing { c.tabSizing = v }
        return c
    }
}
