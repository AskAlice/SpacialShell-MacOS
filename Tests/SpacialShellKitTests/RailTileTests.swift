import Testing
import Foundation
@testable import SpacialShellKit

/// #115 (G14): what a rail tile draws in each `rail-icon-style`, and the config keys behind it.
@Suite struct RailTileTests {
    // pid → category, as `AppMetaCache` would resolve it: 1 Safari (web), 2 Terminal, 3 an app
    // nobody can place.
    static func categoryOf(_ pid: Int32) -> AppCategory? { [1: .web, 2: .terminal][pid] }

    static func item(_ pids: [Int32], symbol: String = RailTile.defaultSymbol, category: AppCategory? = nil,
                     trailing: Bool = false) -> WorkspaceRailItem {
        WorkspaceRailItem(id: UUID(), index: 0, name: "Workspace", symbol: symbol, windowCount: pids.count,
                          windows: pids.enumerated().map { WindowRef(id: WindowID($0.offset + 1), pid: $0.element) },
                          isActive: false, isPinned: false, isTrailingEmpty: trailing, category: category)
    }

    func face(_ item: WorkspaceRailItem, _ style: RailIconStyle) -> RailTileFace {
        RailTile.face(for: item, style: style, categoryOf: Self.categoryOf)
    }

    /// `app` is the M2 tile, unchanged: up to four apps, first-seen order; an empty row its glyph.
    @Test func appStyleIsTheIconGrid() {
        #expect(face(Self.item([2, 1, 2, 4, 5, 6]), .app) == .apps([2, 1, 4, 5]))
        #expect(face(Self.item([], symbol: "globe"), .app) == .symbol("globe", category: nil))
        #expect(face(Self.item([], trailing: true), .app) == .plus)
        #expect(face(Self.item([], trailing: true), .category) == .plus)
        #expect(face(Self.item([], trailing: true), .hybrid) == .plus)
    }

    /// `category`: the row's own category (#112's "Set category") wins over the one its apps add up to.
    @Test func categoryStyleDrawsTheCategoryGlyph() {
        #expect(face(Self.item([1, 1, 2]), .category) == .symbol("globe", category: .web))
        #expect(face(Self.item([1, 1, 2], category: .coding), .category)
                == .symbol("chevron.left.forwardslash.chevron.right", category: .coding))
        // A pinned row with no windows yet still reads as what it is for.
        #expect(face(Self.item([], category: .terminal), .category) == .symbol("terminal", category: .terminal))
    }

    /// A glyph someone chose — a `[[workspace]]` seed, "Set symbol" — beats the category's; the
    /// category still picks the colour.
    @Test func aChosenSymbolBeatsTheCategoryGlyph() {
        #expect(face(Self.item([1], symbol: "star"), .category) == .symbol("star", category: .web))
        #expect(face(Self.item([1, 2], symbol: "star"), .hybrid) == .hybrid("star", category: .web, apps: [1, 2]))
    }

    /// No category known and no glyph chosen: the apps, not a meaningless default glyph.
    @Test func anUnplaceableRowFallsBackToItsApps() {
        #expect(face(Self.item([3, 4]), .category) == .apps([3, 4]))
        #expect(face(Self.item([3, 4]), .hybrid) == .apps([3, 4]))
        #expect(face(Self.item([]), .category) == .symbol(RailTile.defaultSymbol, category: nil))
    }

    /// `hybrid`: the glyph over the row's top two apps, most windows first.
    @Test func hybridDrawsTheGlyphOverTheTopApps() {
        #expect(face(Self.item([1, 2, 2, 3, 3, 3]), .hybrid) == .hybrid("globe", category: .web, apps: [3, 2]))
        #expect(face(Self.item([1]), .hybrid) == .hybrid("globe", category: .web, apps: [1]))
        #expect(face(Self.item([], category: .web), .hybrid) == .symbol("globe", category: .web))
    }

    @Test func topAppsCountWindowsAndKeepFirstSeenOnTies() {
        func refs(_ pids: [Int32]) -> [WindowRef] { pids.enumerated().map { WindowRef(id: WindowID($0.offset), pid: $0.element) } }
        #expect(RailTile.topApps(refs([5, 6, 6, 7, 7])) == [6, 7, 5])
        #expect(RailTile.topApps(refs([9, 8])) == [9, 8])
        #expect(RailTile.distinctApps(refs([5, 6, 5, 7])) == [5, 6, 7])
    }

    @Test func everyCategoryHasItsOwnGlyph() {
        let glyphs = AppCategory.allCases.map(\.symbol)
        #expect(Set(glyphs).count == glyphs.count)
    }

    // MARK: config

    @Test func railIconStyleDefaultsToAppAndParses() throws {
        #expect(try Config.parse(toml: "").railIconStyle == .app)
        for style in RailIconStyle.allCases {
            let c = try Config.parse(toml: "rail-icon-style = \"\(style.rawValue)\"")
            #expect(c.railIconStyle == style)
        }
        #expect(throws: (any Error).self) { try Config.parse(toml: #"rail-icon-style = "icons""#) }
    }

    @Test func categoryColorsParseAndNormalise() throws {
        let toml = """
        [category-colors]
        web = "#3478f6"
        terminal = "30D158"
        """
        let c = try Config.parse(toml: toml)
        #expect(c.categoryColors == [.web: "#3478F6", .terminal: "#30D158"])
        #expect(Config.unknownKeys(toml: toml).isEmpty)
        #expect(try Config.parse(toml: "").categoryColors.isEmpty)
    }

    /// A category name nothing knows is a warning (#133), not a rejection; a bad colour rejects,
    /// as a bad `panel-color` does.
    @Test func categoryColorsTyposWarnAndBadColoursReject() throws {
        let toml = "[category-colors]\nwebb = \"#3478F6\"\nmedia = \"#FF375F\"\n"
        #expect(try Config.parse(toml: toml).categoryColors == [.media: "#FF375F"])
        #expect(Config.unknownKeys(toml: toml) == ["category-colors.webb"])
        #expect(throws: (any Error).self) { try Config.parse(toml: "[category-colors]\nweb = \"blue\"\n") }
        #expect(throws: (any Error).self) { try Config.parse(toml: "[category-colors]\nweb = \"system\"\n") }
    }

    @Test func theSettingsWindowOverridesTheStyle() {
        var file = Config(); file.railIconStyle = .category
        #expect(Settings.effective(config: file, overrides: SettingsOverrides()).railIconStyle == .category)
        var gui = SettingsOverrides(); gui.railIconStyle = .hybrid
        #expect(Settings.effective(config: file, overrides: gui).railIconStyle == .hybrid)
    }
}
