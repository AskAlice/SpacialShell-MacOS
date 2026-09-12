import Foundation
import TOMLDecoder
// `Layout` (used below as a default-argument shorthand, e.g. `= .maximize`) is now a
// `SpacialShellProtocol.Layout` typealias (M2 D4); Swift requires the declaring module to be
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
    public var layout: Layout
    public init(name: String, symbol: String = "square.grid.2x2", layout: Layout = .maximize) { self.name = name; self.symbol = symbol; self.layout = layout }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        layout = try c.decodeIfPresent(Layout.self, forKey: .layout) ?? .maximize
    }
}

public enum KeybindingPreset: String, Codable, Sendable { case fn, ctrlAlt = "ctrl-alt" }
public enum RailSide: String, Codable, Sendable { case left, right }

/// How the tab bar spends its width.
/// - `fit`: each tab is as wide as its content, packed left. One tab sits at the left edge.
/// - `equal`: every tab takes 1/n of the bar and centres its content, the way Safari does.
public enum TabSizing: String, Codable, Sendable { case fit, equal }

public enum HighlightColor {
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
    public var defaultLayout: Layout = .maximize
    public var axTimeoutMs: Int = 1000
    public var refreshIntervalMs: Int = 2000
    public var startAtLogin: Bool = false
    public var panelWidth: Double = 48
    public var panelHeight: Double = 34
    public var railSide: RailSide = .left
    public var tabSizing: TabSizing = .fit
    public var highlightMs: Int = 600
    public var launcherURL: String = "raycast://"
    public var showPanels: Bool = true
    public var highlightColor: String = "system"
    /// Both panels' material tint and how opaque they are. "system" means the stock vibrancy
    /// material; a hex colour replaces it. One pair for both surfaces — split them only if the
    /// rail and bar ever need to differ.
    public var panelColor: String = "system"
    public var panelOpacity: Double = 1
    public var workspaces: [WorkspaceSeed] = []
    public var ephemeral: [AppRule] = Config.defaultEphemeral
    public var float: [AppRule] = []
    public var ignore: [AppRule] = []
    /// chord -> command, *added* to the defaults. Hand-edited, additive, and cannot unbind.
    public var keybindings: [String: String] = [:]
    /// command -> chord, *replacing* the default for that command. This is what the settings
    /// window writes: picking a new chord has to stop the old one working, or every rebind
    /// silently leaves a second way in.
    public var keybindingOverrides: [String: String] = [:]
    /// bundle-id → category, for the apps the built-in table and `LSApplicationCategoryType`
    /// both get wrong. Any table of this kind is permanently incomplete; this is the knob.
    public var appCategories: [String: AppCategory] = [:]

    public static let defaultEphemeral = [AppRule(bundleId: "com.apple.systempreferences"), AppRule(bundleId: "com.apple.calculator")]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case keybindingPreset = "keybinding-preset", gap, defaultLayout = "default-layout", axTimeoutMs = "ax-timeout-ms",
             refreshIntervalMs = "refresh-interval-ms", startAtLogin = "start-at-login", workspaces = "workspace",
             ephemeral, float, ignore, keybindings,
             panelWidth = "panel-width", panelHeight = "panel-height", railSide = "rail-side", tabSizing = "tab-sizing",
             highlightMs = "highlight-ms", launcherURL = "launcher-url", showPanels = "show-panels",
             highlightColor = "highlight-color", appCategories = "app-categories",
             panelColor = "panel-color", panelOpacity = "panel-opacity",
             keybindingOverrides = "keybinding-overrides"
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        keybindingPreset = try c.decodeIfPresent(KeybindingPreset.self, forKey: .keybindingPreset) ?? .fn
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 8
        defaultLayout = try c.decodeIfPresent(Layout.self, forKey: .defaultLayout) ?? .maximize
        axTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .axTimeoutMs) ?? 1000
        refreshIntervalMs = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMs) ?? 2000
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        panelWidth = try c.decodeIfPresent(Double.self, forKey: .panelWidth) ?? 48
        panelHeight = try c.decodeIfPresent(Double.self, forKey: .panelHeight) ?? 34
        railSide = try c.decodeIfPresent(RailSide.self, forKey: .railSide) ?? .left
        tabSizing = try c.decodeIfPresent(TabSizing.self, forKey: .tabSizing) ?? .fit
        highlightMs = try c.decodeIfPresent(Int.self, forKey: .highlightMs) ?? 600
        launcherURL = try c.decodeIfPresent(String.self, forKey: .launcherURL) ?? "raycast://"
        showPanels = try c.decodeIfPresent(Bool.self, forKey: .showPanels) ?? true
        if let raw = try c.decodeIfPresent(String.self, forKey: .highlightColor) {
            guard let n = HighlightColor.normalize(raw) else {
                throw DecodingError.dataCorruptedError(forKey: .highlightColor, in: c, debugDescription: "highlight-color must be \"system\" or #RRGGBB")
            }
            highlightColor = n
        } else { highlightColor = "system" }
        if let raw = try c.decodeIfPresent(String.self, forKey: .panelColor) {
            guard let n = HighlightColor.normalize(raw) else {
                throw DecodingError.dataCorruptedError(forKey: .panelColor, in: c, debugDescription: "panel-color must be \"system\" or #RRGGBB")
            }
            panelColor = n
        } else { panelColor = "system" }
        // Clamped rather than refused: an out-of-range opacity is a typo, not a reason to reject
        // the whole config and fall back to defaults the user never asked for.
        panelOpacity = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .panelOpacity) ?? 1))
        appCategories = try c.decodeIfPresent([String: AppCategory].self, forKey: .appCategories) ?? [:]
        workspaces = try c.decodeIfPresent([WorkspaceSeed].self, forKey: .workspaces) ?? []
        ephemeral = try c.decodeIfPresent([AppRule].self, forKey: .ephemeral) ?? Config.defaultEphemeral
        float = try c.decodeIfPresent([AppRule].self, forKey: .float) ?? []
        ignore = try c.decodeIfPresent([AppRule].self, forKey: .ignore) ?? []
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
        highlight-ms = \(highlightMs)
        launcher-url = \(q(launcherURL))
        show-panels = \(showPanels)
        highlight-color = \(q(highlightColor))

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
        rules("ephemeral", ephemeral); rules("float", float); rules("ignore", ignore)
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

    /// Spec §7.3 rule 0: config wins over heuristics. Order: ephemeral, float, ignore.
    public func kindOverride(bundleID: String?, title: String) -> WindowKind? {
        if ephemeral.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .ephemeral }
        if float.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .float }
        if ignore.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .ignore }
        return nil
    }
}
