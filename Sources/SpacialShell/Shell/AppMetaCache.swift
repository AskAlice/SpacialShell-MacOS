import AppKit

/// What the shell draws for an app that the model cannot know: resolved from a window's pid.
struct AppMeta {
    let name: String
    let icon: NSImage?
}

/// Name + icon by pid, cached: `NSRunningApplication` lookups are not free and the panels
/// re-render on every world change. Dead pids leave stale entries; they are unreachable once
/// their windows leave the world, and the map stays small (one entry per app, not per window).
@MainActor
final class AppMetaCache {
    private var cache: [Int32: AppMeta] = [:]

    func meta(for pid: Int32) -> AppMeta {
        if let m = cache[pid] { return m }
        let app = NSRunningApplication(processIdentifier: pid)
        let m = AppMeta(name: app?.localizedName ?? "App", icon: app?.icon)
        cache[pid] = m
        return m
    }
}
