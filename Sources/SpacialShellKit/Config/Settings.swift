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
    public var tabStyle: TabStyle?
    public var keybindingPreset: KeybindingPreset?
    public var animations: Bool?
    public var emptyCheatsheet: Bool?
    public var railAutohide: Bool?
    public var pointerWarp: Bool?
    /// #120.
    public var workspaceWrap: Bool?
    /// #141. `gesture-fingers` stays the file's: it is a one-time choice, made alongside System Settings.
    public var gestures: Bool?
    public var gestureInvert: Bool?
    /// #135. `focus-follows-mouse-delay-ms` stays the file's, like `gesture-fingers`.
    public var focusFollowsMouse: Bool?
    /// #139.
    public var persistState: Bool?
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
    /// #138: problem keys the user answered "Don't warn again" to. Not a config knob — nothing in
    /// `Config` changes — so `Settings.effective` leaves it alone; the app reads it directly. Nil
    /// and `[]` both mean none; the settings window's "Warn again" sets it back to nil.
    public var silencedWarnings: [String]?

    public init() {}

    /// #138: adds `key` to `silencedWarnings`, once.
    public mutating func silence(_ key: String) {
        var keys = silencedWarnings ?? []
        guard !keys.contains(key) else { return }
        keys.append(key)
        silencedWarnings = keys
    }

    /// Every key optional and tolerant, as the synthesized decoder was — plus `layouts`, lossily.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        panelWidth = try c.decodeIfPresent(Double.self, forKey: .panelWidth)
        panelHeight = try c.decodeIfPresent(Double.self, forKey: .panelHeight)
        gap = try c.decodeIfPresent(Double.self, forKey: .gap)
        panelColor = try c.decodeIfPresent(String.self, forKey: .panelColor)
        railSide = try c.decodeIfPresent(RailSide.self, forKey: .railSide)
        tabSizing = try c.decodeIfPresent(TabSizing.self, forKey: .tabSizing)
        tabStyle = try c.decodeIfPresent(TabStyle.self, forKey: .tabStyle)
        keybindingPreset = try c.decodeIfPresent(KeybindingPreset.self, forKey: .keybindingPreset)
        animations = try c.decodeIfPresent(Bool.self, forKey: .animations)
        emptyCheatsheet = try c.decodeIfPresent(Bool.self, forKey: .emptyCheatsheet)
        railAutohide = try c.decodeIfPresent(Bool.self, forKey: .railAutohide)
        pointerWarp = try c.decodeIfPresent(Bool.self, forKey: .pointerWarp)
        workspaceWrap = try c.decodeIfPresent(Bool.self, forKey: .workspaceWrap)
        gestures = try c.decodeIfPresent(Bool.self, forKey: .gestures)
        gestureInvert = try c.decodeIfPresent(Bool.self, forKey: .gestureInvert)
        focusFollowsMouse = try c.decodeIfPresent(Bool.self, forKey: .focusFollowsMouse)
        persistState = try c.decodeIfPresent(Bool.self, forKey: .persistState)
        keybindingOverrides = try c.decodeIfPresent([String: String].self, forKey: .keybindingOverrides)
        categoryOrder = try c.decodeIfPresent([AppCategory].self, forKey: .categoryOrder)
        maxWorkspaces = try c.decodeIfPresent(Int.self, forKey: .maxWorkspaces)
        layouts = try LayoutDef.lossy(c, .layouts)
        layoutBar = try c.decodeIfPresent([LayoutID].self, forKey: .layoutBar)
        defaultLayout = try c.decodeIfPresent(LayoutID.self, forKey: .defaultLayout)
        silencedWarnings = try c.decodeIfPresent([String].self, forKey: .silencedWarnings)
    }
}

/// #10: the edits the layout popover and editor make. They only ever touch `settings.json`'s side;
/// `config.toml` is the user's (design §3.1).
extension SettingsOverrides {
    /// Save: replace the entry with this id in place, so the menu order holds, or append it.
    public mutating func saveLayout(_ def: LayoutDef) {
        var list = layouts ?? []
        if let i = list.firstIndex(where: { $0.id == def.id }) { list[i] = def } else { list.append(def) }
        layouts = list
    }

    /// Delete (a drawn layout) and Reset (a file layout the editor changed) are the same edit: the
    /// settings.json entry goes, and the file's, if there is one, shows through again. Workspaces
    /// keep the id (design §8), and so does a `defaultLayout` naming it — the badge says so.
    public mutating func removeLayout(_ id: LayoutID) {
        layouts = layouts?.filter { $0.id != id }
        if layouts?.isEmpty == true { layouts = nil }
    }

    /// A popover toggle. Writes the whole bar (it replaces the file's wholesale, like
    /// `categoryOrder`), starting from what is on the bar now. Returns false when the bar is
    /// already full and `id` would not fit.
    @discardableResult
    public mutating func setLayout(_ id: LayoutID, onBar: Bool, current: [LayoutID]) -> Bool {
        guard onBar != current.contains(id) else { return true }
        var bar = current.filter { $0 != id }
        if onBar {
            guard bar.count < LayoutCatalogue.maxBar else { return false }
            bar.append(id)
        }
        layoutBar = bar
        return true
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
        if let v = overrides.tabStyle { c.tabStyle = v }
        if let v = overrides.keybindingPreset { c.keybindingPreset = v }
        if let v = overrides.animations { c.animations = v }
        if let v = overrides.emptyCheatsheet { c.emptyCheatsheet = v }
        if let v = overrides.railAutohide { c.railAutohide = v }
        if let v = overrides.pointerWarp { c.pointerWarp = v }
        if let v = overrides.workspaceWrap { c.workspaceWrap = v }
        if let v = overrides.gestures { c.gestures = v }
        if let v = overrides.gestureInvert { c.gestureInvert = v }
        if let v = overrides.focusFollowsMouse { c.focusFollowsMouse = v }
        if let v = overrides.persistState { c.persistState = v }
        if let v = overrides.categoryOrder { c.categoryOrder = v }
        if let v = overrides.maxWorkspaces { c.maxWorkspaces = max(1, v) }
        if let v = overrides.keybindingOverrides { c.keybindingOverrides.merge(v) { _, gui in gui } }
        if let v = overrides.layouts { c.layouts = LayoutDef.merge(file: c.layouts, gui: v) }
        if let v = overrides.layoutBar { c.layoutBar = v }
        if let v = overrides.defaultLayout { c.defaultLayout = v }
        return c
    }
}
