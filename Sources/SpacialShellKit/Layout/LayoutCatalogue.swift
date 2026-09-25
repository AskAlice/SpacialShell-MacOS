import Foundation
import os
import SpacialShellProtocol

// Layouts as data (#9, the "expand" step of docs/superpowers/specs/2026-09-25-custom-grid-layouts-design.md).
// Only the id crosses the Protocol boundary; the definitions and their geometry live here.

/// The five layouts that are code, not data: each is a function of the window count (and
/// `maximize`/`split` of the focus), which no fixed zone list can express (design §5).
/// ponytail: backed by the Protocol enum until #11 makes it a Kit enum of its own.
public typealias BuiltinLayout = SpacialShellProtocol.Layout

/// One drawn zone, as a unit rect: `0…1`, origin top-left, y-down (M1 §3.2's AX convention). The
/// workspace rect it maps onto changes with the display, insets, Zen and the gap (design §4.2).
public struct LayoutZone: Codable, Hashable, Sendable {
    public var x, y, w, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }

    /// Clamped into the unit square; nil when nothing is left of it (or it was never a number).
    /// A hand-edited config may be wrong without disarming the file (M1 §9).
    var clamped: LayoutZone? {
        guard [x, y, w, h].allSatisfy(\.isFinite) else { return nil }
        let cx = min(max(x, 0), 1), cy = min(max(y, 0), 1)
        // In range, the numbers pass through untouched: recomputing `(x + w) − x` is not `w` in
        // floating point (2/3 + 1/3 − 2/3 is 0.33333333333333337), and a saved layout must decode
        // to exactly what was saved (#10's Copy as TOML and settings.json round-trips).
        let cw = x >= 0 && x + w <= 1 ? w : min(x + w, 1) - cx
        let ch = y >= 0 && y + h <= 1 ? h : min(y + h, 1) - cy
        let z = LayoutZone(x: cx, y: cy, w: cw, h: ch)
        return z.w > 1e-6 && z.h > 1e-6 ? z : nil
    }
}

public struct LayoutDef: Codable, Hashable, Sendable, Identifiable {
    public enum Body: Hashable, Sendable { case builtin(BuiltinLayout), zones([LayoutZone]) }
    public var id: LayoutID
    /// What the switcher, the menu, the tooltip and the Hint show.
    public var name: String
    /// SF Symbol; nil means "draw the zones" (the #10 switcher does that).
    public var symbol: String?
    public var body: Body
    public var isBuiltin: Bool { if case .builtin = body { true } else { false } }

    public init(id: LayoutID, name: String, symbol: String? = nil, body: Body) {
        self.id = id; self.name = name; self.symbol = symbol; self.body = body
    }

    /// The five, in cycle order, with the symbols the switcher has always drawn.
    public static let builtins: [LayoutDef] = [
        LayoutDef(id: .maximize, name: "Maximize", symbol: "rectangle", body: .builtin(.maximize)),
        LayoutDef(id: .split, name: "Split", symbol: "rectangle.split.2x1", body: .builtin(.split)),
        LayoutDef(id: .column, name: "Column", symbol: "rectangle.split.3x1", body: .builtin(.column)),
        LayoutDef(id: .half, name: "Half", symbol: "rectangle.lefthalf.filled", body: .builtin(.half)),
        LayoutDef(id: .grid, name: "Grid", symbol: "square.grid.2x2", body: .builtin(.grid)),
    ]

    /// The TOML shape of design §3.3, and the same keys in `settings.json`:
    /// `{ id, name, symbol?, zones = [{x, y, w, h}, …] }`. A built-in is written as `builtin = "…"`
    /// only so the type round-trips; neither store ever holds one (a user layout cannot shadow one).
    enum CodingKeys: String, CodingKey { case id, name, symbol, zones, builtin }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(LayoutID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id.rawValue
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        if let b = try c.decodeIfPresent(BuiltinLayout.self, forKey: .builtin) { body = .builtin(b); return }
        let raw = try c.decode([LayoutZone].self, forKey: .zones)
        let zones = raw.compactMap(\.clamped)
        if zones.count < raw.count {
            let (name, dropped) = (id.rawValue, raw.count - zones.count)
            LayoutCatalogue.log.error("layout \"\(name, privacy: .public)\": dropped \(dropped, privacy: .public) degenerate zone(s)")
        }
        guard !zones.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .zones, in: c, debugDescription: "layout \"\(id.rawValue)\" has no usable zones")
        }
        body = .zones(zones)
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(symbol, forKey: .symbol)
        switch body {
        case .builtin(let b): try c.encode(b, forKey: .builtin)
        case .zones(let z): try c.encode(z, forKey: .zones)
        }
    }

    /// The `[[layout]]` block of design §3.3: what the editor's Copy as TOML puts on the pasteboard
    /// and what `Config.render` writes. Nil for a built-in, which no file ever defines.
    public var toml: String? {
        guard case .zones(let zones) = body else { return nil }
        let q = Config.quote
        var o = "[[layout]]\nid = \(q(id.rawValue))\nname = \(q(name))\n"
        if let s = symbol { o += "symbol = \(q(s))\n" }
        return o + "zones = [\n" + zones.map { "  { x = \($0.x), y = \($0.y), w = \($0.w), h = \($0.h) },\n" }.joined() + "]\n"
    }

    /// `settings.json` over `config.toml`, per id, the GUI winning (design §3.1) — the rule
    /// `keybindingOverrides` already follows. File order first, then layouts only the GUI has.
    public static func merge(file: [LayoutDef], gui: [LayoutDef]) -> [LayoutDef] {
        let byID = Dictionary(gui.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let fileIDs = Set(file.map(\.id))
        var seen: Set<LayoutID> = []
        return (file.map { byID[$0.id] ?? $0 } + gui.filter { !fileIDs.contains($0.id) })
            .filter { seen.insert($0.id).inserted }
    }

    /// Decodes a list one entry at a time, dropping (and logging) the ones that do not decode:
    /// one bad zone must not lose twenty drawn layouts (design §3.2).
    static func lossy<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> [LayoutDef]? {
        try c.decodeIfPresent([Lossy].self, forKey: key).map { $0.compactMap(\.def) }
    }
    private struct Lossy: Decodable {
        let def: LayoutDef?
        init(from d: Decoder) throws {
            do { def = try LayoutDef(from: d) } catch {
                LayoutCatalogue.log.error("layout entry skipped: \(String(describing: error), privacy: .public)")
                def = nil
            }
        }
    }
}

/// Every layout the shell knows, built from the effective config and nowhere else (design §4.1).
public struct LayoutCatalogue: Sendable, Equatable {
    static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "layouts")
    /// The bar set's cap (Q4: a fixed 8, so Fn+Space stays a short ring).
    public static let maxBar = 8

    /// Built-ins first, then the user's layouts in merged order.
    public let all: [LayoutDef]
    /// What `cycleLayout` rings through: ordered, ≤ 8, only ids that resolve.
    public let bar: [LayoutID]
    /// `default-layout`: the second link of the resolve chain.
    public let fallback: LayoutID
    /// #10: which user layouts `config.toml` defines; the rest were drawn in the editor.
    public let fileIDs: Set<LayoutID>

    public init(config: Config) {
        fileIDs = config.fileLayoutIDs
        let builtinIDs = Set(LayoutDef.builtins.map(\.id))
        var user: [LayoutDef] = []
        for def in config.layouts {
            if builtinIDs.contains(def.id) || def.isBuiltin {
                Self.log.error("layout \"\(def.id.rawValue, privacy: .public)\" ignored: built-in layouts cannot be redefined")
            } else { user.append(def) }
        }
        all = LayoutDef.builtins + user
        let known = Set(all.map(\.id))
        var seen: Set<LayoutID> = []
        bar = Array(config.layoutBar.filter { known.contains($0) && seen.insert($0).inserted }.prefix(Self.maxBar))
        fallback = config.defaultLayout
    }

    public static let builtins = LayoutCatalogue(config: Config())

    public subscript(id: LayoutID) -> LayoutDef? { all.first { $0.id == id } }

    /// Never nothing to draw: the id, else `default-layout`, else maximize (design §2, §8).
    /// `resolved` is false when the id itself is unknown — a deleted or mistyped layout, which the
    /// workspace keeps so that restoring the layout restores the workspace.
    public func resolve(_ id: LayoutID) -> (def: LayoutDef, resolved: Bool) {
        if let d = self[id] { return (d, true) }
        return (self[fallback] ?? LayoutDef.builtins[0], false)
    }

    /// #10: what a workspace holding `id` will draw once `id` is deleted — the resolve chain's next
    /// link, `default-layout`, unless that is `id` itself or missing too. The delete sheet names it.
    public func fallback(afterDeleting id: LayoutID) -> LayoutID {
        fallback != id && self[fallback] != nil ? fallback : LayoutDef.builtins[0].id
    }

    /// `cycleLayout`: the next id round the bar; from outside the bar, its start.
    public func next(after id: LayoutID) -> LayoutID {
        guard let first = bar.first else { return id }
        guard let i = bar.firstIndex(of: id) else { return first }
        return bar[(i + 1) % bar.count]
    }

    /// The warning the switcher shows for a workspace whose layout does not resolve; nil when it does.
    public func warning(for id: LayoutID) -> String? {
        let (def, ok) = resolve(id)
        return ok ? nil : "layout \"\(id.rawValue)\" is missing — using \(def.id.rawValue)"
    }
}

extension World {
    /// #10: how many workspaces hold `id` — what the delete sheet counts (design §8.6).
    public func workspaces(using id: LayoutID) -> Int {
        screens.values.reduce(0) { $0 + $1.workspaces.filter { $0.layout == id }.count }
    }
}
