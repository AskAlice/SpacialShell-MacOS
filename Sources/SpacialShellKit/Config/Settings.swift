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
    /// #124.
    public var screenGap: Double?
    public var panelColor: String?
    public var railSide: RailSide?
    public var tabSizing: TabSizing?
    public var tabStyle: TabStyle?
    /// #115. `category-colors` stays the file's: a colour per category is a hand-edit, not a knob.
    public var railIconStyle: RailIconStyle?
    /// #126.
    public var dockAttention: Bool?
    public var keybindingPreset: KeybindingPreset?
    public var animations: Bool?
    /// #140.
    public var animateRetile: Bool?
    public var emptyCheatsheet: Bool?
    public var railAutohide: Bool?
    public var pointerWarp: Bool?
    /// #120.
    public var workspaceWrap: Bool?
    /// #141. `gesture-fingers` stays the file's: it is a one-time choice, made alongside System Settings.
    public var gestures: Bool?
    public var gestureInvert: Bool?
    /// #160.
    public var gestureLayout: Bool?
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

    /// Every key optional and tolerant, as the synthesized decoder was. The knobs are the
    /// `Config.keys` entries with an `override`, named as their properties are (`layouts` lossily);
    /// `ConfigKeyTableTests` checks each property here is one of them, or `silencedWarnings`.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: ConfigKey.Name.self)
        for key in Config.keys { try key.override?.decode(&self, c) }
        silencedWarnings = try c.decodeIfPresent([String].self, forKey: Self.silencedWarningsKey)
    }

    /// An unset knob is left out, not written as null: absent is how "the file decides" is stored.
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: ConfigKey.Name.self)
        for key in Config.keys { try key.override?.encode(self, &c) }
        try c.encodeIfPresent(silencedWarnings, forKey: Self.silencedWarningsKey)
    }

    /// The one key here that is not a config knob. Persisted: renaming it forgets every answer.
    private static let silencedWarningsKey = ConfigKey.Name("silencedWarnings")
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
        for key in Config.keys { key.override?.apply(overrides, &c) }
        return c
    }
}
