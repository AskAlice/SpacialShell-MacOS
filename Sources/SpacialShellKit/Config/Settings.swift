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
    /// #74. Replaces the file's `category-order` wholesale: the list is one setting, and its order
    /// is the point. `[]` is a real value (routing off), distinct from nil (the file decides).
    public var categoryOrder: [AppCategory]?
    public var maxWorkspaces: Int?
    /// #9: layouts drawn in the editor. Merged per id over the file's `[[layout]]`, the GUI
    /// winning (design §3.1), and decoded one entry at a time: a bad entry is dropped and logged,
    /// never the file (design §3.2 — the file-level move-aside is `AppRuntime.loadOverrides`).
    public var layouts: [LayoutDef]?
    /// #9. Replaces the file's `layout-bar` wholesale, like `categoryOrder`.
    public var layoutBar: [LayoutID]?
    public var defaultLayout: LayoutID?

    public init() {}

    /// Every key optional and tolerant, as the synthesized decoder was — plus `layouts`, lossily.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        panelWidth = try c.decodeIfPresent(Double.self, forKey: .panelWidth)
        panelHeight = try c.decodeIfPresent(Double.self, forKey: .panelHeight)
        gap = try c.decodeIfPresent(Double.self, forKey: .gap)
        panelColor = try c.decodeIfPresent(String.self, forKey: .panelColor)
        railSide = try c.decodeIfPresent(RailSide.self, forKey: .railSide)
        tabSizing = try c.decodeIfPresent(TabSizing.self, forKey: .tabSizing)
        keybindingPreset = try c.decodeIfPresent(KeybindingPreset.self, forKey: .keybindingPreset)
        animations = try c.decodeIfPresent(Bool.self, forKey: .animations)
        emptyCheatsheet = try c.decodeIfPresent(Bool.self, forKey: .emptyCheatsheet)
        keybindingOverrides = try c.decodeIfPresent([String: String].self, forKey: .keybindingOverrides)
        categoryOrder = try c.decodeIfPresent([AppCategory].self, forKey: .categoryOrder)
        maxWorkspaces = try c.decodeIfPresent(Int.self, forKey: .maxWorkspaces)
        layouts = try LayoutDef.lossy(c, .layouts)
        layoutBar = try c.decodeIfPresent([LayoutID].self, forKey: .layoutBar)
        defaultLayout = try c.decodeIfPresent(LayoutID.self, forKey: .defaultLayout)
    }
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
        if let v = overrides.categoryOrder { c.categoryOrder = v }
        if let v = overrides.maxWorkspaces { c.maxWorkspaces = max(1, v) }
        if let v = overrides.keybindingOverrides { c.keybindingOverrides.merge(v) { _, gui in gui } }
        if let v = overrides.layouts { c.layouts = LayoutDef.merge(file: c.layouts, gui: v) }
        if let v = overrides.layoutBar { c.layoutBar = v }
        if let v = overrides.defaultLayout { c.defaultLayout = v }
        return c
    }
}
