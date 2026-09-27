import Foundation
import SpacialShellProtocol

/// What kind of work an app is for, as the rail labels a workspace.
///
/// macOS cannot answer this on its own. `LSApplicationCategoryType` is the only system-provided
/// answer and it is neither complete nor, for this purpose, correct: measured over a real
/// /Applications folder, 103 of 190 apps declare the key at all, Chrome and Brave declare nothing,
/// and Safari, Firefox and Tor all declare `public.app-category.productivity` — so "web browsing"
/// is simply not derivable from it. Hence a curated table first, the system key only as a coarse
/// fallback, and a config override for everything both of them get wrong.
public enum AppCategory: String, Codable, CaseIterable, Sendable {
    case web, coding, terminal, communication, media, design, productivity, utilities

    /// What the rail draws. Deliberately lowercase — it sits under an icon strip, not in a title.
    public var label: String {
        switch self {
        case .web: "web browsing"
        case .coding: "coding"
        case .terminal: "terminal"
        case .communication: "communication"
        case .media: "media"
        case .design: "design"
        case .productivity: "productivity"
        case .utilities: "utilities"
        }
    }
}

public enum AppCategories {
    /// Bundle ids we answer for directly. Not exhaustive and never will be — that is what
    /// `app-categories` in the config is for. Kept to apps whose category the system key gets
    /// outright wrong (every browser) or does not express at all (every terminal).
    public static let table: [String: AppCategory] = [
        // Browsers — the whole reason the system key cannot be trusted.
        "com.apple.Safari": .web,
        "com.google.Chrome": .web,
        "com.google.Chrome.canary": .web,
        "com.brave.Browser": .web,
        "com.brave.Browser.nightly": .web,
        "com.brave.Browser.origin": .web,
        "org.mozilla.firefox": .web,
        "org.mozilla.com.zilla.firefox": .web,
        "org.torproject.torbrowser": .web,
        "com.microsoft.edgemac": .web,
        "com.operasoftware.Opera": .web,
        "company.thebrowser.Browser": .web,          // Arc
        "com.vivaldi.Vivaldi": .web,

        // Terminals — macOS has no terminal category at all.
        "com.apple.Terminal": .terminal,
        "com.googlecode.iterm2": .terminal,
        "dev.warp.Warp-Stable": .terminal,
        "com.mitchellh.ghostty": .terminal,
        "co.zeit.hyper": .terminal,
        "net.kovidgoyal.kitty": .terminal,
        "io.alacritty": .terminal,
        "com.github.wez.wezterm": .terminal,

        // Editors and IDEs. `developer-tools` covers these, but it also covers chat clients that
        // mislabel themselves, so naming them is what keeps "coding" meaning coding.
        "com.microsoft.VSCode": .coding,
        "com.microsoft.VSCodeInsiders": .coding,
        "com.apple.dt.Xcode": .coding,
        "com.jetbrains.intellij": .coding,
        "com.jetbrains.pycharm": .coding,
        "com.sublimetext.4": .coding,
        "com.sublimetext.3": .coding,
        "dev.zed.Zed": .coding,
        "com.todesktop.230313mzl4w4u92": .coding,    // Cursor
        "com.google.android.studio": .coding,
        "com.axosoft.gitkraken": .coding,
        "com.github.GitHubClient": .coding,

        // Chat. Several of these claim `developer-tools` or `business`.
        "com.tinyspeck.slackmacgap": .communication,
        "com.hnc.Discord": .communication,
        "org.whispersystems.signal-desktop": .communication,
        "ru.keepcoder.Telegram": .communication,
        "desktop.WhatsApp": .communication,
        "com.apple.MobileSMS": .communication,
        "us.zoom.xos": .communication,
        "com.microsoft.teams2": .communication,

        // Media and design.
        "org.videolan.vlc": .media,
        "com.spotify.client": .media,
        "io.mpv": .media,
        // The user's order puts these together after media (#74). Apple files Finder under no
        // category and System Settings under utilities only sometimes, so they are stated here.
        "com.apple.finder": .utilities,
        "com.apple.systempreferences": .utilities,
        "com.apple.Music": .media,
        "com.figma.Desktop": .design,
        "com.canva.CanvaDesktop": .design,
        "org.blenderfoundation.blender": .design,
        "com.adobe.Photoshop": .design,
    ]

    /// `LSApplicationCategoryType` → us. Coarse on purpose: this tier only runs for apps the table
    /// has never heard of, where a rough answer beats none. `developer-tools` maps to `coding`
    /// knowing full well that some chat apps claim it — the table catches the ones that matter.
    static func fromSystem(_ ls: String) -> AppCategory? {
        switch ls.replacingOccurrences(of: "public.app-category.", with: "") {
        case "developer-tools": .coding
        case "productivity", "business", "finance", "education", "reference": .productivity
        case "social-networking": .communication
        case "music", "video", "entertainment", "photography": .media
        case "graphics-design": .design
        case "utilities": .utilities
        default: nil
        }
    }

    /// Precedence: the user's override, then our table, then the system's own key, then nothing.
    /// "Nothing" is a real answer — an unlabelled workspace beats a confidently wrong label.
    public static func category(bundleID: String?, systemCategory: String? = nil,
                                overrides: [String: AppCategory] = [:]) -> AppCategory? {
        guard let bundleID else { return systemCategory.flatMap(fromSystem) }
        if let o = overrides[bundleID] { return o }
        if let t = table[bundleID] { return t }
        return systemCategory.flatMap(fromSystem)
    }

    /// The one category that best describes a workspace holding these apps: the most common one,
    /// ties broken by whichever appeared first in the row. A workspace with a browser and two
    /// editors is a coding workspace; the label follows the weight of what is actually in it.
    public static func summarise(_ categories: [AppCategory?]) -> AppCategory? {
        let known = categories.compactMap { $0 }
        guard !known.isEmpty else { return nil }
        var counts: [AppCategory: Int] = [:]
        for c in known { counts[c, default: 0] += 1 }
        let best = counts.values.max()!
        return known.first { counts[$0] == best }
    }
}

// MARK: - #183: what a workspace row is called

extension AppCategories {
    /// The category a row is drawn as: its own (#112 "Set category", or routing's #74), else the
    /// one its apps add up to. Nil when neither says anything.
    public static func rowCategory(_ own: AppCategory?, windows: [WindowRef],
                                   categoryOf: (Int32) -> AppCategory?) -> AppCategory? {
        own ?? summarise(RailTile.distinctApps(windows).map(categoryOf))
    }

    /// The title a row goes by wherever it has room for one: the spatial view's label and the
    /// rail's hover card, which must never disagree. Its category, capitalised ("Web browsing"),
    /// else the stored name; the trailing empty row is "New workspace". No row number: the
    /// spatial view draws that on its own, and the card sits beside the tile it describes.
    public static func rowTitle(name: String, category: AppCategory?, isTrailingEmpty: Bool) -> String {
        if isTrailingEmpty { return "New workspace" }
        guard let label = category?.label else { return name }
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}
