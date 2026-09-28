import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellPlatform
import SpacialShellProtocol

/// Owns the overview/launcher overlay. Toggled by `toggle-overview` (`Fn+Tab`), which AppRuntime
/// routes here instead of the store — opening a search box is not a model mutation. Selections
/// re-enter the ordinary pipeline: a window cell sends `.focusWindowRef`, an app cell launches via
/// `NSWorkspace` and the new window is adopted by the store like any other window that appears.
@MainActor
public final class OverviewController {
    private let panel = OverviewPanel()
    private var host: NSHostingView<OverviewView>?
    private let appMeta: AppMetaCache
    private let send: @Sendable (Command) -> Void
    private var world: World?
    private var titles: [SpacialShellProtocol.WindowRef: String] = [:]
    private var isOpen = false
    /// URL → item, kept across opens; the directory listing is cheap, the icon loads are not.
    private var appCache: [URL: OverviewAppItem] = [:]

    private static let panelSize = NSSize(width: 640, height: 440)
    private static let appDirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                                  NSHomeDirectory() + "/Applications"]

    public init(appMeta: AppMetaCache, send: @escaping @Sendable (Command) -> Void) {
        self.appMeta = appMeta
        self.send = send
        panel.onDismiss = { [weak self] in self?.close() }
    }

    public func update(world: World, snapshot: ShellSnapshot) {
        self.world = world
        titles = snapshot.titles
    }

    public func toggle() {
        isOpen ? close() : open()
    }

    private func open() {
        guard let world else { return }
        isOpen = true
        let windows = windowItems(world)
        let thumbs = WindowThumbnails.shared
        let view = OverviewView(
            windows: windows,
            apps: installedApps(),
            thumbnails: Self.thumbnails(for: windows),
            onSelectWindow: { [weak self] ref in
                self?.close(restoreFocus: false)   // the selection is the focus; a restore could race it
                self?.send(.focusWindowRef(ref))
            },
            onLaunchApp: { [weak self] url in
                self?.close(restoreFocus: false)   // the launched app takes focus when its window adopts
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            })
        // A fresh hosting view per open: state (query text, scroll) must not leak between opens,
        // and a fresh identity is also what re-fires `onAppear`, which focuses the search field.
        let host = NSHostingView(rootView: view)
        self.host = host
        panel.contentView = host

        // Centred in the upper half of the focused screen, Spotlight-style. NSScreen coordinates
        // (bottom-left y-up) — the overview never touches AX geometry.
        let screen = NSScreen.screens.first { DisplayTopology.uuid(for: $0) == world.focus.screen }
            ?? NSScreen.main ?? NSScreen.screens.first
        if let vf = screen?.visibleFrame {
            let s = Self.panelSize
            panel.setFrame(NSRect(x: vf.midX - s.width / 2, y: vf.minY + vf.height * 0.62 - s.height / 2,
                                  width: s.width, height: s.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)

        // #189: after the first frame is drawn from the cache, take what is missing or stale, a
        // few windows at a time, and swap each batch's pictures in as it lands. A landing from an
        // earlier open only re-reads the cache for what is on screen now.
        ThumbnailRefresher.shared.refresh(
            ThumbnailRefresh.onOverview(windows.map(\.ref), in: world, isStale: thumbs.isStale)) { [weak self] in
            guard let self, self.isOpen, let host = self.host else { return }
            host.rootView.thumbnails = Self.thumbnails(for: host.rootView.windows)
        }
    }

    /// The cached picture of every window that has one. A placeholder (#128) has no window, and its
    /// id is its own, so a picture cached under the same number belongs to some real window.
    private static func thumbnails(for windows: [OverviewWindowItem]) -> [SpacialShellProtocol.WindowRef: NSImage] {
        var out: [SpacialShellProtocol.WindowRef: NSImage] = [:]
        for item in windows where !item.ref.isPlaceholder {
            out[item.ref] = WindowThumbnails.shared.image(for: item.ref.id)
        }
        return out
    }

    private func close(restoreFocus: Bool = true) {
        guard isOpen else { return }
        isOpen = false
        // #189: the open's captures are left to finish (a few windows, once; they stay in the
        // cache). `cancelRefresh` would cancel whichever request is current, maybe the spatial view's.
        panel.orderOut(nil)   // fires resignKey → onDismiss → this method; the flag above ends the loop
        panel.contentView = nil
        host = nil
        // Taking key focus for the search field took it from whoever had it; on a plain dismissal
        // hand it back to the window the model says is focused, so the overview leaves no trace.
        // Skipped when a selection follows — its own focus command must not race a restore.
        if restoreFocus, let f = world?.focus.window {
            send(.focusWindowRef(f))
        }
    }

    // MARK: - Data

    private func windowItems(_ world: World) -> [OverviewWindowItem] {
        var out: [OverviewWindowItem] = []
        for (n, sid) in world.screenOrder.enumerated() {
            guard let screen = world.screens[sid] else { continue }
            for ws in screen.workspaces {
                for w in ws.windows {
                    let meta = appMeta.meta(for: w.pid)
                    let place = world.screenOrder.count > 1 ? "\(ws.name) · screen \(n + 1)" : ws.name
                    out.append(OverviewWindowItem(ref: w, name: titles[w] ?? meta.name, app: meta.name, detail: place, icon: meta.icon))
                }
            }
        }
        for w in world.ephemeral {
            let meta = appMeta.meta(for: w.pid)
            out.append(OverviewWindowItem(ref: w, name: titles[w] ?? meta.name, app: meta.name, detail: "visitor", icon: meta.icon))
        }
        return out
    }

    private func installedApps() -> [OverviewAppItem] {
        var out: [URL: OverviewAppItem] = [:]
        let fm = FileManager.default
        for dir in Self.appDirs {
            let urls = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                    includingPropertiesForKeys: nil,
                                                    options: .skipsHiddenFiles)) ?? []
            for url in urls where url.pathExtension == "app" {
                if let cached = appCache[url] { out[url] = cached; continue }
                let name = url.deletingPathExtension().lastPathComponent
                let item = OverviewAppItem(url: url, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
                appCache[url] = item
                out[url] = item
            }
        }
        return out.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
