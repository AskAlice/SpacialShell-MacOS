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
    enum CodingKeys: String, CodingKey, CaseIterable { case bundleId = "bundle-id", titleRegex = "title-regex" }
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
    enum CodingKeys: String, CodingKey, CaseIterable { case name, symbol, layout }
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

/// What a tab shows (#116). `full` is the app icon and the window title; `name` drops the icon;
/// `icon` drops the title, for crowded rows. The title is always in the tab's tooltip.
public enum TabStyle: String, Codable, Sendable, CaseIterable { case full, name, icon }

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

/// #148: tracing, exported over OTLP/HTTP. Off unless `enabled` and a token are both present; the
/// app target owns everything past parsing.
public struct TelemetryConfig: Codable, Equatable, Sendable {
    public var enabled = false
    /// The OTLP base URL; `/v1/traces` is appended.
    public var endpoint = ""
    public var user = ""
    public var token = ""
    public init() {}
    enum CodingKeys: String, CodingKey, CaseIterable { case enabled, endpoint, user, token }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
    }

    /// Where traces go and with which headers — or nil, which means register nothing and send
    /// nothing. `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_HEADERS` override the table;
    /// `enabled` does not, so off stays off whatever the environment says. Headers from the
    /// environment replace the Basic auth, and count as the credential.
    public func export(env: [String: String]) -> (url: URL, headers: [String: String])? {
        guard enabled else { return nil }
        var headers = Self.parseHeaders(env["OTEL_EXPORTER_OTLP_HEADERS"] ?? "")
        if headers.isEmpty {
            guard !token.isEmpty else { return nil }
            headers["Authorization"] = "Basic " + Data("\(user):\(token)".utf8).base64EncodedString()
        }
        var base = env["OTEL_EXPORTER_OTLP_ENDPOINT"].flatMap { $0.isEmpty ? nil : $0 } ?? endpoint
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/v1/traces"), url.scheme == "https" || url.scheme == "http", url.host != nil
        else { return nil }
        return (url, headers)
    }

    /// The OTel spec's `key=value,key=value`, values percent-encoded. Hand-rolled because the
    /// exporter's own parser splits on every `=` (dropping a base64 value's padding) and does not
    /// decode, so Grafana's documented `Authorization=Basic%20…` never arrived.
    static func parseHeaders(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let key = pair[..<eq].trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, let v = value.removingPercentEncoding, !v.isEmpty { out[key] = v }
        }
        return out
    }
}

public struct Config: Decodable, Equatable, Sendable {
    public var keybindingPreset: KeybindingPreset = .fn
    public var gap: Double = 8
    /// #124 (M4 G11): the space between the row and the screen edge, when it should differ from
    /// `gap` (material-shell's `screen-gap`). Nil follows `gap`; `outerGap` is what applies.
    public var screenGap: Double?
    public var outerGap: Double { screenGap ?? gap }
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
    public var tabStyle: TabStyle = .full
    /// #115 (G14): what a rail tile draws — its apps, its category's glyph, or both.
    public var railIconStyle: RailIconStyle = .app
    /// #115: a colour per category, tinting that category's glyph on the rail. Hex only, like
    /// `panel-color`; a category left out keeps the stock secondary glyph.
    public var categoryColors: [AppCategory: String] = [:]
    /// #126 (G35): mirror the Dock's badges and bounces as a mark on the rail tile and the tab of
    /// the app asking for attention. Off stops the Dock poll altogether.
    public var dockAttention: Bool = true
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
    /// #138 (G34): bundle ids or process names of window managers that fight SpacialShell over the
    /// same windows; one running raises a warning. Replaces the default list; `[]` turns it off.
    public var otherWindowManagers: [String] = OtherWindowManagers.defaults
    /// #139 (G31): read `state.json` at launch and keep it written. Off: neither, and the file is
    /// left as it is. See `StatePersistence`.
    public var persistState: Bool = true
    /// Switching is motion (#64, ruled in #65): windows slide as screenshot proxies when the Screen
    /// Recording grant is present, and are placed instantly without it or with this off.
    public var animations: Bool = true
    /// #140 (G13): re-tiles move too — a layout change, a swap, a window opening or closing next to
    /// the others — sliding and scaling from the old frames to the new over ~250 ms. Off by default:
    /// the VM measurement met the 80 ms capture budget only in 8 of 10 re-tiles at 8 windows, so a
    /// re-tile whose capture overruns it is placed instantly, as a switch is. Only with `animations`.
    public var animateRetile: Bool = false
    /// #29: an empty workspace on the focused display shows the cheat sheet, dimmed, as its
    /// background, so a fresh screen answers "what can I press?" without holding anything.
    public var emptyCheatsheet: Bool = true
    /// #96: the rail hides off its edge like the Dock, its inset goes, and rows tile into its
    /// width; the pointer at that edge slides it back in over the windows without re-tiling.
    public var railAutohide: Bool = false
    /// #107: a keyboard or command focus change to another display takes the pointer with it, to
    /// the centre of the newly focused window (or of the display, when its row is empty).
    public var pointerWarp: Bool = true
    /// #120 (G3): Fn+W on the first workspace goes to the last non-empty one, and Fn+S on the last
    /// non-empty one goes to the first. Off by default: the ends of the stack stay ends.
    public var workspaceWrap: Bool = false
    /// #141 (G27): trackpad swipes navigate like Fn+W/A/S/D — up/down a workspace, left/right a
    /// window, one step per swipe, content following the fingers as natural scrolling does.
    public var gestures: Bool = true
    /// #141: how many fingers a swipe takes, exactly. Clamped to 3…5: two fingers is scrolling.
    public var gestureFingers: Int = 3
    /// #141: swipe the way the keys point instead (swipe left runs Fn+A, swipe up Fn+W).
    public var gestureInvert: Bool = false
    /// #160: four-finger swipes change the layout — up/down cycle it, right/left widen/narrow the
    /// focused tile. Only while `gestures` is on, and off when `gesture-fingers` is 4 (navigation
    /// keeps its fingers). See `SwipeBindings`.
    public var gestureLayout: Bool = true
    public static let gestureFingerRange = 3...5
    /// #135 (G28): resting the pointer on another tiled or floating window focuses it, as a click
    /// on its tab would. Opt-in (#24): off, focus moves only by click, key, swipe or command.
    public var focusFollowsMouse: Bool = false
    /// #135: how long the pointer has to rest on a window before it takes focus. Clamped to
    /// `FocusFollowsMouse.delayRangeMs`.
    public var focusFollowsMouseDelayMs: Int = FocusFollowsMouse.defaultDelayMs
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
    /// #10: the ids `config.toml` itself defines. Set when the file is decoded and never written;
    /// `Settings.effective` keeps it, so the ⋯ menu can tell a file layout from a drawn one and
    /// the editor offers Reset (a file layout) rather than Delete (a drawn one).
    public var fileLayoutIDs: Set<LayoutID> = []
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
    public var telemetry = TelemetryConfig()

    /// Decision 2026-09-24 (#70): System Settings used to be here, and so never got a tab — but it
    /// is a window you work in, not a visitor. Calculator is the one app that really is a popup.
    public static let defaultEphemeral = [AppRule(bundleId: "com.apple.calculator")]
    public static let defaultTile = [AppRule(bundleId: "com.apple.systempreferences")]
    /// Every built-in, in the order Fn+Space cycles them. Decision 2026-09-26 (#123): `ratio`
    /// joins the default ring, sixth, after `grid` — it shipped off the bar, and the user ruled a
    /// built-in you can only reach from the popover is one nobody finds.
    public static let defaultLayoutBar: [LayoutID] = [.maximize, .split, .column, .half, .grid, .ratio]
    public static let defaultCategoryOrder: [AppCategory] = [.web, .terminal, .coding, .media, .utilities]

    public init() {}

    /// Decodes over the defaults, one `Config.keys` entry at a time: a key the file leaves out
    /// keeps its property's initial value.
    public init(from d: Decoder) throws {
        self.init()
        let c = try d.container(keyedBy: ConfigKey.Name.self)
        for key in Config.keys { try key.decode(&self, c) }
        fileLayoutIDs = Set(layouts.map(\.id))
    }

    public static func parse(toml: String) throws -> Config { try TOMLDecoder().decode(Config.self, from: toml) }
    public static func load(from url: URL) throws -> Config { try parse(toml: String(contentsOf: url, encoding: .utf8)) }

    /// #133: keys the file sets that nothing reads, a typo or a key since removed (#60's
    /// `focus-ring`). Decoding skips them, so the file still loads and reload stays armed; this
    /// names them so the app can warn. A table's keys are dotted (`telemetry.tokn`), each named
    /// once however many `[[float]]` blocks repeat it, sorted: the parser keeps neither source
    /// order nor positions, so there is no line number to give either. `[keybindings]`,
    /// `[keybinding-overrides]` and `[app-categories]` are free-form maps: any key there is data.
    public static func unknownKeys(toml: String) -> [String] {
        guard let root = try? TOMLTable(source: toml) else { return [] }
        var out: [String] = []
        for key in root.keys {
            guard knownKeys.contains(key) else { out.append(key); continue }
            guard let known = knownSubkeys[key] else { continue }
            let blocks: [TOMLTable]
            if let t = try? root.table(forKey: key) { blocks = [t] }
            else if let a = try? root.array(forKey: key) { blocks = (0..<a.count).compactMap { try? a.table(atIndex: $0) } }
            else { blocks = [] }
            for sub in blocks.flatMap(\.keys) where !known.contains(sub) && !out.contains("\(key).\(sub)") {
                out.append("\(key).\(sub)")
            }
        }
        return out.sorted()
    }

    /// What `unknownKeys` accepts: every key's name, and each table's own keys.
    private static let knownKeys = Set(keys.map(\.name))
    private static let knownSubkeys = Dictionary(keys.compactMap { k in k.subkeys.map { (k.name, $0) } },
                                                 uniquingKeysWith: { first, _ in first })

    /// Spec §7.3 rule 0: config wins over heuristics. Order: ephemeral, float, ignore, tile.
    /// `standard` is the window's AX subrole being `AXStandardWindow`: `[[tile]]` only ever promotes
    /// an app's main window, never its alerts or sheets (#89).
    public func kindOverride(bundleID: String?, title: String, standard: Bool = true) -> WindowKind? {
        if ephemeral.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .ephemeral }
        if float.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .float }
        if ignore.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .ignore }
        if standard, tile.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .tile }
        return nil
    }
}
