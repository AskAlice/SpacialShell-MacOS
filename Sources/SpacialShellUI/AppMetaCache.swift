import AppKit
import SpacialShellKit
import SpacialShellProtocol

/// What the shell draws for an app that the model cannot know: resolved from a window's pid.
struct AppMeta {
    let name: String
    let icon: NSImage?
    let bundleID: String?
    /// Nil means "we genuinely do not know" — the rail leaves the workspace unlabelled rather
    /// than guessing. See `AppCategories` for why macOS cannot answer this on its own.
    let category: AppCategory?
}

/// Name + icon by pid, cached: `NSRunningApplication` lookups are not free and the panels
/// re-render on every world change. Dead pids leave stale entries; they are unreachable once
/// their windows leave the world, and the map stays small (one entry per app, not per window).
@MainActor
public final class AppMetaCache {
    public init() {}

    private var cache: [Int32: AppMeta] = [:]
    private var overrides: [String: AppCategory] = [:]

    /// Config overrides change what a cached entry's category should be, so the cache is dropped
    /// when they do — it is one entry per running app, so rebuilding it costs nothing worth saving.
    public func update(config: Config) {
        guard config.appCategories != overrides else { return }
        overrides = config.appCategories
        cache.removeAll()
    }

    /// #128: placeholder pid → bundle id. A placeholder has no process to ask, so its icon and
    /// name come from the installed app with that bundle id instead.
    private var placeholderBundles: [Int32: String] = [:]

    /// #128: the placeholders the world holds now. A placeholder pid is derived from its bundle id,
    /// so an entry never changes meaning; new ones are simply added.
    public func note(placeholders: [SpacialShellProtocol.WindowRef: Placeholder]) {
        for (ref, p) in placeholders where placeholderBundles[ref.pid] != p.bundleID {
            placeholderBundles[ref.pid] = p.bundleID
            cache[ref.pid] = nil
        }
    }

    func meta(for pid: Int32) -> AppMeta {
        if let m = cache[pid] { return m }
        if pid < 0 { return placeholderMeta(pid) }
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleID = app?.bundleIdentifier
        let m = AppMeta(
            name: app?.localizedName ?? "App",
            icon: app?.icon,
            bundleID: bundleID,
            category: AppCategories.category(bundleID: bundleID,
                                             systemCategory: Self.systemCategory(of: app),
                                             overrides: overrides))
        cache[pid] = m
        return m
    }

    /// #128: an app that is not running, by bundle id: the installed app's name and icon, or —
    /// uninstalled since it was saved — the bundle id's last component and no icon.
    private func placeholderMeta(_ pid: Int32) -> AppMeta {
        let bundleID = placeholderBundles[pid]
        let url = bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        let bundle = url.flatMap(Bundle.init(url:))
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url?.deletingPathExtension().lastPathComponent
            ?? bundleID?.split(separator: ".").last.map(String.init) ?? "App"
        let m = AppMeta(name: name, icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) }, bundleID: bundleID,
                        category: AppCategories.category(
                            bundleID: bundleID,
                            systemCategory: bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
                            overrides: overrides))
        if bundleID != nil { cache[pid] = m }
        return m
    }

    /// `LSApplicationCategoryType` out of the app's own Info.plist. Only 54% of a real
    /// /Applications folder declares it, which is exactly why it is the fallback tier and not
    /// the answer.
    private static func systemCategory(of app: NSRunningApplication?) -> String? {
        guard let url = app?.bundleURL, let bundle = Bundle(url: url) else { return nil }
        return bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
    }
}
