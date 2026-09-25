import Foundation
import TOMLDecoder
// `LayoutID` (used below as a default-argument shorthand, e.g. `= .maximize`) is a
// `SpacialShellProtocol.LayoutID` typealias (M2 D4, #9); Swift requires the declaring module to be
// imported in any file that resolves an implicit-member default argument against it, even though
// the typealias itself is visible through `SpacialShellKit`.
import SpacialShellProtocol

public struct AppRule: Codable, Equatable, Sendable {
    public var bundleId: String
    public var titleRegex: String?
    public init(bundleId: String, titleRegex: String? = nil) { self.bundleId = bundleId; self.titleRegex = titleRegex }
    enum CodingKeys: String, CodingKey { case bundleId = "bundle-id", titleRegex = "title-regex" }
    func matches(bundleID: String?, title: String) -> Bool {
        guard bundleID == bundleId else { return false }
        guard let re = titleRegex else { return true }
        return title.range(of: re, options: .regularExpression) != nil
    }
}

public struct WorkspaceSeed: Codable, Equatable, Sendable {
    public var name: String
    public var symbol: String
    public var layout: LayoutID
    public init(name: String, symbol: String = "square.grid.2x2", layout: LayoutID = .maximize) { self.name = name; self.symbol = symbol; self.layout = layout }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        layout = try c.decodeIfPresent(LayoutID.self, forKey: .layout) ?? .maximize
    }
}

public enum KeybindingPreset: String, Codable, Sendable { case fn, ctrlAlt = "ctrl-alt" }
public enum RailSide: String, Codable, Sendable { case left, right }

/// How the tab bar spends its width.
/// - `fit`: each tab is as wide as its content, packed left. One tab sits at the left edge.
/// - `equal`: every tab takes 1/n of the bar and centres its content, the way Safari does.
public enum TabSizing: String, Codable, Sendable { case fit, equal }

public enum HexColor {
    public static func normalize(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased() == "system" { return "system" }
        let hex = t.hasPrefix("#") ? String(t.dropFirst()) : t
        guard hex.count == 6 || hex.count == 8, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + hex.uppercased()
    }
    public static func rgba(_ s: String) -> (Double, Double, Double, Double)? {
        guard let n = normalize(s), n != "system" else { return nil }
        let h = String(n.dropFirst())
        func byte(_ i: Int) -> Double {
            let a = h.index(h.startIndex, offsetBy: i)
            return Double(Int(h[a..<h.index(a, offsetBy: 2)], radix: 16)!) / 255
        }
        return (byte(0), byte(2), byte(4), h.count == 8 ? byte(6) : 1)
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var keybindingPreset: KeybindingPreset = .fn
    public var gap: Double = 8
    /// Any id: a built-in, a `[[layout]]`, or one drawn in the editor. An id nothing defines is
    /// kept, and resolves to maximize (#9).
    public var defaultLayout: LayoutID = .maximize
    public var axTimeoutMs: Int = 1000
    public var refreshIntervalMs: Int = 2000
    public var startAtLogin: Bool = false
    public var panelWidth: Double = 48
    public var panelHeight: Double = 34
    public var railSide: RailSide = .left
    public var tabSizing: TabSizing = .fit
    public var launcherURL: String = "raycast://"
    public var showPanels: Bool = true
    /// #13: an app arriving at launch with *more* windows than this, and no remembered placement,
    /// gets a workspace of its own instead of piling into the active one (observed: 36 windows in
    /// one tab bar). 8 is about where the tab bar stops being readable.
    public var crowdThreshold: Int = 8
    /// #74: where an app's first window lands when nothing remembers it. Each category listed
    /// here gets one row per display, shared by every app of that category, created at its place
    /// in this order; every other app gets a row of its own after them. Empty turns routing off.
    public var categoryOrder: [AppCategory] = Config.defaultCategoryOrder
    /// #74: routing never grows a display past this many rows; past it, new apps join the last row.
    public var maxWorkspaces: Int = 12
    /// Switching is motion (#64, ruled in #65): windows slide as screenshot proxies when the Screen
    /// Recording grant is present, and are placed instantly without it or with this off.
    public var animations: Bool = true
    /// #29: an empty workspace on the focused display shows the cheat sheet, dimmed, as its
    /// background, so a fresh screen answers "what can I press?" without holding anything.
    public var emptyCheatsheet: Bool = true
    /// Both panels' material tint and how opaque they are. "system" means the stock vibrancy
    /// material; a hex colour replaces it. One pair for both surfaces — split them only if the
    /// rail and bar ever need to differ.
    public var panelColor: String = "system"
    public var panelOpacity: Double = 1
    public var workspaces: [WorkspaceSeed] = []
    /// #9: `[[layout]]` — drawn zone layouts. Decoded one entry at a time, so a bad one is
    /// dropped with a log line instead of rejecting the file.
    public var layouts: [LayoutDef] = []
    /// #9: what Fn+Space cycles and the switcher's bar shows (≤ 8; ids that resolve).
    public var layoutBar: [LayoutID] = Config.defaultLayoutBar
    public var ephemeral: [AppRule] = Config.defaultEphemeral
    public var float: [AppRule] = []
    public var ignore: [AppRule] = []
    /// Tile these even when macOS calls them dialogs. System Settings is one: it only resizes
    /// vertically, so the AX heuristics file it as a floating dialog, and it then sat outside the
    /// layout — the user expects it in its row, sized to it.
    public var tile: [AppRule] = Config.defaultTile
    /// chord -> command, *added* to the defaults. Hand-edited, additive, and cannot unbind.
    public var keybindings: [String: String] = [:]
    /// command -> chord, *replacing* the default for that command. This is what the settings
    /// window writes: picking a new chord has to stop the old one working, or every rebind
    /// silently leaves a second way in.
    public var keybindingOverrides: [String: String] = [:]
    /// bundle-id → category, for the apps the built-in table and `LSApplicationCategoryType`
    /// both get wrong. Any table of this kind is permanently incomplete; this is the knob.
    public var appCategories: [String: AppCategory] = [:]

    /// Decision 2026-09-24 (#70): System Settings used to be here, and so never got a tab — but it
    /// is a window you work in, not a visitor. Calculator is the one app that really is a popup.
    public static let defaultEphemeral = [AppRule(bundleId: "com.apple.calculator")]
    public static let defaultTile = [AppRule(bundleId: "com.apple.systempreferences")]
    public static let defaultLayoutBar: [LayoutID] = LayoutDef.builtins.map(\.id)
    public static let defaultCategoryOrder: [AppCategory] = [.web, .terminal, .coding, .media, .utilities]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case keybindingPreset = "keybinding-preset", gap, defaultLayout = "default-layout", axTimeoutMs = "ax-timeout-ms",
             refreshIntervalMs = "refresh-interval-ms", startAtLogin = "start-at-login", workspaces = "workspace",
             ephemeral, float, ignore, tile, keybindings,
             panelWidth = "panel-width", panelHeight = "panel-height", railSide = "rail-side", tabSizing = "tab-sizing",
             launcherURL = "launcher-url", showPanels = "show-panels", crowdThreshold = "crowd-threshold", animations, appCategories = "app-categories",
             panelColor = "panel-color", panelOpacity = "panel-opacity",
             keybindingOverrides = "keybinding-overrides"
        case emptyCheatsheet = "empty-cheatsheet"
        case categoryOrder = "category-order", maxWorkspaces = "max-workspaces"
        case layouts = "layout", layoutBar = "layout-bar"
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        keybindingPreset = try c.decodeIfPresent(KeybindingPreset.self, forKey: .keybindingPreset) ?? .fn
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 8
        defaultLayout = try c.decodeIfPresent(LayoutID.self, forKey: .defaultLayout) ?? .maximize
        axTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .axTimeoutMs) ?? 1000
        refreshIntervalMs = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMs) ?? 2000
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        panelWidth = try c.decodeIfPresent(Double.self, forKey: .panelWidth) ?? 48
        panelHeight = try c.decodeIfPresent(Double.self, forKey: .panelHeight) ?? 34
        railSide = try c.decodeIfPresent(RailSide.self, forKey: .railSide) ?? .left
        tabSizing = try c.decodeIfPresent(TabSizing.self, forKey: .tabSizing) ?? .fit
        launcherURL = try c.decodeIfPresent(String.self, forKey: .launcherURL) ?? "raycast://"
        showPanels = try c.decodeIfPresent(Bool.self, forKey: .showPanels) ?? true
        crowdThreshold = try c.decodeIfPresent(Int.self, forKey: .crowdThreshold) ?? 8
        categoryOrder = try c.decodeIfPresent([AppCategory].self, forKey: .categoryOrder) ?? Config.defaultCategoryOrder
        maxWorkspaces = max(1, try c.decodeIfPresent(Int.self, forKey: .maxWorkspaces) ?? 12)
        animations = try c.decodeIfPresent(Bool.self, forKey: .animations) ?? true
        emptyCheatsheet = try c.decodeIfPresent(Bool.self, forKey: .emptyCheatsheet) ?? true
        if let raw = try c.decodeIfPresent(String.self, forKey: .panelColor) {
            guard let n = HexColor.normalize(raw) else {
                throw DecodingError.dataCorruptedError(forKey: .panelColor, in: c, debugDescription: "panel-color must be \"system\" or #RRGGBB")
            }
            panelColor = n
        } else { panelColor = "system" }
        // Clamped rather than refused: an out-of-range opacity is a typo, not a reason to reject
        // the whole config and fall back to defaults the user never asked for.
        panelOpacity = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .panelOpacity) ?? 1))
        appCategories = try c.decodeIfPresent([String: AppCategory].self, forKey: .appCategories) ?? [:]
        workspaces = try c.decodeIfPresent([WorkspaceSeed].self, forKey: .workspaces) ?? []
        layouts = try LayoutDef.lossy(c, .layouts) ?? []
        layoutBar = try c.decodeIfPresent([LayoutID].self, forKey: .layoutBar) ?? Config.defaultLayoutBar
        ephemeral = try c.decodeIfPresent([AppRule].self, forKey: .ephemeral) ?? Config.defaultEphemeral
        float = try c.decodeIfPresent([AppRule].self, forKey: .float) ?? []
        ignore = try c.decodeIfPresent([AppRule].self, forKey: .ignore) ?? []
        tile = try c.decodeIfPresent([AppRule].self, forKey: .tile) ?? Config.defaultTile
        keybindings = try c.decodeIfPresent([String: String].self, forKey: .keybindings) ?? [:]
        keybindingOverrides = try c.decodeIfPresent([String: String].self, forKey: .keybindingOverrides) ?? [:]
    }

    public static func parse(toml: String) throws -> Config { try TOMLDecoder().decode(Config.self, from: toml) }
    public static func load(from url: URL) throws -> Config { try parse(toml: String(contentsOf: url, encoding: .utf8)) }

    /// ponytail: hand-written TOML (no encoder in deps). Round-trips values; drops comments.
    public func render() -> String {
        func q(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var o = """
        # written by SpacialShell settings; hand-edited comments are not preserved
        keybinding-preset = \(q(keybindingPreset.rawValue))
        gap = \(gap)
        default-layout = \(q(defaultLayout.rawValue))
        ax-timeout-ms = \(axTimeoutMs)
        refresh-interval-ms = \(refreshIntervalMs)
        start-at-login = \(startAtLogin)
        panel-width = \(panelWidth)
        panel-height = \(panelHeight)
        rail-side = \(q(railSide.rawValue))
        launcher-url = \(q(launcherURL))
        show-panels = \(showPanels)
        crowd-threshold = \(crowdThreshold)
        category-order = [\(categoryOrder.map { q($0.rawValue) }.joined(separator: ", "))]
        max-workspaces = \(maxWorkspaces)
        animations = \(animations)
        empty-cheatsheet = \(emptyCheatsheet)
        layout-bar = [\(layoutBar.map { q($0.rawValue) }.joined(separator: ", "))]

        """
        func rules(_ name: String, _ items: [AppRule]) {
            for r in items {
                o += "\n[[\(name)]]\nbundle-id = \(q(r.bundleId))\n"
                if let t = r.titleRegex { o += "title-regex = \(q(t))\n" }
            }
        }
        for w in workspaces {
            o += "\n[[workspace]]\nname = \(q(w.name))\nsymbol = \(q(w.symbol))\nlayout = \(q(w.layout.rawValue))\n"
        }
        for l in layouts {
            guard case .zones(let zones) = l.body else { continue }
            o += "\n[[layout]]\nid = \(q(l.id.rawValue))\nname = \(q(l.name))\n"
            if let s = l.symbol { o += "symbol = \(q(s))\n" }
            o += "zones = [\n" + zones.map { "  { x = \($0.x), y = \($0.y), w = \($0.w), h = \($0.h) },\n" }.joined() + "]\n"
        }
        rules("ephemeral", ephemeral); rules("float", float); rules("ignore", ignore); rules("tile", tile)
        if !keybindings.isEmpty {
            o += "\n[keybindings]\n"
            for k in keybindings.keys.sorted() { o += "\(q(k)) = \(q(keybindings[k]!))\n" }
        }
        return o
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try render().write(to: url, atomically: true, encoding: .utf8)
    }

    /// Spec §7.3 rule 0: config wins over heuristics. Order: ephemeral, float, ignore, tile.
    public func kindOverride(bundleID: String?, title: String) -> WindowKind? {
        if ephemeral.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .ephemeral }
        if float.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .float }
        if ignore.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .ignore }
        if tile.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .tile }
        return nil
    }
}
