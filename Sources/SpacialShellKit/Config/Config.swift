import Foundation
import TOMLDecoder

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

public struct Config: Codable, Equatable, Sendable {
    public var keybindingPreset: KeybindingPreset = .fn
    public var gap: Double = 8
    public var defaultLayout: Layout = .maximize
    public var axTimeoutMs: Int = 1000
    public var refreshIntervalMs: Int = 2000
    public var startAtLogin: Bool = false
    public var workspaces: [WorkspaceSeed] = []
    public var ephemeral: [AppRule] = Config.defaultEphemeral
    public var float: [AppRule] = []
    public var ignore: [AppRule] = []
    public var keybindings: [String: String] = [:]

    public static let defaultEphemeral = [AppRule(bundleId: "com.apple.systempreferences"), AppRule(bundleId: "com.apple.calculator")]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case keybindingPreset = "keybinding-preset", gap, defaultLayout = "default-layout", axTimeoutMs = "ax-timeout-ms",
             refreshIntervalMs = "refresh-interval-ms", startAtLogin = "start-at-login", workspaces = "workspace",
             ephemeral, float, ignore, keybindings
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        keybindingPreset = try c.decodeIfPresent(KeybindingPreset.self, forKey: .keybindingPreset) ?? .fn
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 8
        defaultLayout = try c.decodeIfPresent(Layout.self, forKey: .defaultLayout) ?? .maximize
        axTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .axTimeoutMs) ?? 1000
        refreshIntervalMs = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMs) ?? 2000
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        workspaces = try c.decodeIfPresent([WorkspaceSeed].self, forKey: .workspaces) ?? []
        ephemeral = try c.decodeIfPresent([AppRule].self, forKey: .ephemeral) ?? Config.defaultEphemeral
        float = try c.decodeIfPresent([AppRule].self, forKey: .float) ?? []
        ignore = try c.decodeIfPresent([AppRule].self, forKey: .ignore) ?? []
        keybindings = try c.decodeIfPresent([String: String].self, forKey: .keybindings) ?? [:]
    }

    public static func parse(toml: String) throws -> Config { try TOMLDecoder().decode(Config.self, from: toml) }
    public static func load(from url: URL) throws -> Config { try parse(toml: String(contentsOf: url, encoding: .utf8)) }

    /// Spec §7.3 rule 0: config wins over heuristics. Order: ephemeral, float, ignore.
    public func kindOverride(bundleID: String?, title: String) -> WindowKind? {
        if ephemeral.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .ephemeral }
        if float.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .float }
        if ignore.contains(where: { $0.matches(bundleID: bundleID, title: title) }) { return .ignore }
        return nil
    }
}
