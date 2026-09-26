import Foundation
import SpacialShellProtocol

/// #115 (G14): how a rail tile is drawn — material-shell's `panel-icon-style`.
/// - `app`: up to four of the row's apps as a 2x2 icon grid (the M2 tile, and the default).
/// - `category`: the workspace's category glyph, so a web row reads as a globe wherever it sits.
/// - `hybrid`: the category glyph with the row's top apps beneath it.
public enum RailIconStyle: String, Codable, Sendable, CaseIterable { case app, category, hybrid }

extension AppCategory {
    /// The glyph a category draws on the rail (#115) — the same symbols the workspace menu's
    /// "Set symbol" offers for these kinds of work, so choosing one by hand and letting the
    /// category choose look the same.
    public var symbol: String {
        switch self {
        case .web: "globe"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .terminal: "terminal"
        case .communication: "bubble.left.and.bubble.right"
        case .media: "play.rectangle"
        case .design: "paintbrush"
        case .productivity: "doc.text"
        case .utilities: "wrench.and.screwdriver"
        }
    }
}

/// What one rail tile draws: the pure half of #115. Apps are pids; the view resolves them to icons
/// (`AppMetaCache`), as it does for tabs. `category` is the one whose colour tints the glyph.
public enum RailTileFace: Equatable, Sendable {
    /// The trailing empty workspace: "+".
    case plus
    /// One glyph fills the tile.
    case symbol(String, category: AppCategory?)
    /// Up to four apps, first-seen order.
    case apps([Int32])
    /// The glyph over the row's top apps (at most `RailTile.hybridApps`).
    case hybrid(String, category: AppCategory?, apps: [Int32])
}

public enum RailTile {
    /// The app grid's 2x2.
    public static let maxApps = 4
    /// Hybrid's row under the glyph: two icons fit a 32 pt tile beside the window count.
    public static let hybridApps = 2
    /// `Workspace`'s default glyph. A row still carrying it has had no glyph chosen for it.
    public static let defaultSymbol = "square.grid.2x2"

    /// One pid per app, in the order the row first mentions it — how the app grid reads, left to
    /// right, like the tab bar.
    public static func distinctApps(_ windows: [WindowRef]) -> [Int32] {
        var seen: Set<Int32> = []
        return windows.compactMap { seen.insert($0.pid).inserted ? $0.pid : nil }
    }

    /// The row's apps by how many windows each has here, most first; ties keep first-seen order.
    /// material-shell orders its tile icons the same way (P3).
    public static func topApps(_ windows: [WindowRef]) -> [Int32] {
        let order = distinctApps(windows)
        var counts: [Int32: Int] = [:]
        for w in windows { counts[w.pid, default: 0] += 1 }
        return order.enumerated().sorted { a, b in
            let (ca, cb) = (counts[a.element]!, counts[b.element]!)
            return ca != cb ? ca > cb : a.offset < b.offset
        }.map(\.element)
    }

    /// The category a row is drawn as: its own (#112 "Set category", or routing's), else the one
    /// its apps add up to. Nil when neither says anything.
    public static func category(of item: WorkspaceRailItem, categoryOf: (Int32) -> AppCategory?) -> AppCategory? {
        item.category ?? AppCategories.summarise(distinctApps(item.windows).map(categoryOf))
    }

    /// What `item` draws in `style`.
    ///
    /// The glyph, for `category` and `hybrid`: a symbol someone chose (a `[[workspace]]` seed or
    /// "Set symbol") wins, since choosing the glyph is exactly what they did; then the category's.
    /// A row with neither — no category known, no glyph chosen — falls back to its apps, because
    /// the default grid glyph on every such tile would say nothing at all.
    public static func face(for item: WorkspaceRailItem, style: RailIconStyle,
                            categoryOf: (Int32) -> AppCategory?) -> RailTileFace {
        if item.isTrailingEmpty { return .plus }
        let apps = distinctApps(item.windows)
        let category = category(of: item, categoryOf: categoryOf)
        let glyph = item.symbol != defaultSymbol ? item.symbol : category?.symbol
        switch style {
        case .app:
            return apps.isEmpty ? .symbol(item.symbol, category: category) : .apps(Array(apps.prefix(maxApps)))
        case .category:
            if let glyph { return .symbol(glyph, category: category) }
            return apps.isEmpty ? .symbol(item.symbol, category: nil) : .apps(Array(apps.prefix(maxApps)))
        case .hybrid:
            guard let glyph else {
                return apps.isEmpty ? .symbol(item.symbol, category: nil) : .apps(Array(apps.prefix(maxApps)))
            }
            if apps.isEmpty { return .symbol(glyph, category: category) }
            return .hybrid(glyph, category: category, apps: Array(topApps(item.windows).prefix(hybridApps)))
        }
    }
}
