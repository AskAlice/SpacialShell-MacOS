import AppKit
import SwiftUI
import Foundation
import SpacialShellKit
import SpacialShellProtocol
@testable import SpacialShellUI

/// The story catalog — Storybook for the shell. One entry per interesting state of each view,
/// rendered at the view's true geometry. Every story is (a) image-snapshotted in light and dark
/// and (b) run through `LayoutLint` (no overlapping text, nothing escaping its container).
/// Adding a UI state? Add its story here and it is covered by both, and becomes PR-media source.
@MainActor
struct Story {
    let name: String
    let size: CGSize?          // nil = use the view's fitting size
    let view: AnyView
    /// Stories that model a condition the design knows it does not handle yet (e.g. tab overflow
    /// before T19's "+N" badge). Their lint runs under `withKnownIssue` so the gap is recorded
    /// without a red suite; remove the flag when the handling lands.
    var knownOverflow: Bool = false
    /// The story's ideal width legitimately exceeds its container because its text truncates —
    /// which is handling, not a gap, and the opposite of `knownOverflow`. `fittingSize` reports
    /// the untruncated ideal, so LayoutLint's must-fit check cannot tell the two apart; this says
    /// which one it is. The escape check still runs, so real clipping is still caught.
    var truncates: Bool = false
}

/// An `NSMenu` drawn as the system draws it — section headers, separators, a check on the current
/// item, template glyphs — from the menu's own items, so the story shows what `LayoutMenu` built.
struct MenuPreview: View {
    let menu: NSMenu
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(menu.items.enumerated()), id: \.offset) { _, item in
                if item.isSeparatorItem {
                    Divider().padding(.vertical, 5).padding(.horizontal, 6)
                } else if item.isSectionHeader {
                    Text(item.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 2)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                            .opacity(item.state == .on ? 1 : 0).frame(width: 12)
                        if let image = item.image { Image(nsImage: image).renderingMode(.template).frame(width: 18) }
                        else { Color.clear.frame(width: 18, height: 1) }
                        Text(item.title).font(.system(size: 13))
                        if item.hasSubmenu {
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 22)
                }
            }
        }
        .padding(5)
        .frame(width: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.regularMaterial))
    }
}

@MainActor
enum Stories {
    // MARK: fixtures

    static func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        return image
    }

    static let meta: (Int32) -> AppMeta = { pid in
        let names: [Int32: String] = [
            1: "Safari", 2: "Notes", 3: "Terminal", 4: "Mail",
            5: "A Very Long Application Name That Must Truncate", 6: "X",
        ]
        let colors: [NSColor] = [.systemBlue, .systemYellow, .systemGray, .systemTeal, .systemPink, .systemGreen]
        // Real bundle ids, so the stories go through the same table the shell does: Safari is
        // `web` only because the table overrules the `productivity` it declares about itself.
        let bundles: [Int32: String] = [
            1: "com.apple.Safari", 2: "com.apple.Notes", 3: "com.apple.Terminal",
            4: "com.apple.mail", 5: "com.microsoft.VSCode", 6: "com.hnc.Discord",
        ]
        let bundle = bundles[pid]
        return AppMeta(name: names[pid] ?? "App \(pid)", icon: swatch(colors[Int(pid - 1) % colors.count]),
                       bundleID: bundle,
                       category: AppCategories.category(bundleID: bundle,
                                                        systemCategory: "public.app-category.productivity"))
    }

    /// A stand-in for a captured window: a landscape swatch, so the miniature has an aspect
    /// ratio the card has to letterbox like a real screenshot.
    static func shot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 320, height: 200))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 320, height: 200).fill()
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSRect(x: 0, y: 170, width: 320, height: 30).fill()
        image.unlockFocus()
        return image
    }

    static func rail(_ items: [WorkspaceRailItem], tray: [SpacialShellProtocol.WindowRef] = []) -> ScreenShellState {
        ScreenShellState(display: "D1", isFocusedScreen: true, rail: items, tabs: [], layout: .split, tray: tray)
    }
    /// `pids` are the apps actually in the row — the rail draws one icon each and derives the
    /// category label from them, so a story without pids is a workspace of unknown apps.
    static func railItem(_ i: Int, name: String, symbol: String, count: Int, pids: [Int32] = [],
                         active: Bool = false, pinned: Bool = false, trailing: Bool = false) -> WorkspaceRailItem {
        WorkspaceRailItem(id: UUID(), index: i, name: name, symbol: symbol, windowCount: count,
                          windows: pids.map { WindowRef(id: WindowID($0) * 10, pid: $0) },
                          isActive: active, isPinned: pinned, isTrailingEmpty: trailing)
    }
    static func tabs(_ items: [WindowTabItem], layout: SpacialShellProtocol.LayoutID = .split,
                     layouts: LayoutCatalogue = .builtins) -> ScreenShellState {
        ScreenShellState(display: "D1", isFocusedScreen: true,
                         rail: [railItem(0, name: "Web", symbol: "globe", count: items.count, active: true)],
                         tabs: items, layout: layout, layouts: layouts)
    }

    /// #10: the approved mockup's catalogue — one layout from config.toml, two drawn in the editor.
    static func customLayouts(bar extra: [SpacialShellProtocol.LayoutID] = []) -> LayoutCatalogue {
        func drawn(_ id: SpacialShellProtocol.LayoutID, _ name: String, _ z: [(Double, Double, Double, Double)]) -> LayoutDef {
            LayoutDef(id: id, name: name, body: .zones(z.map { LayoutZone(x: $0.0, y: $0.1, w: $0.2, h: $0.3) }))
        }
        var c = Config()
        c.layouts = [drawn("wide-4", "Ultrawide four", [(0, 0, 0.25, 1), (0.25, 0, 0.5, 1), (0.75, 0, 0.25, 0.5), (0.75, 0.5, 0.25, 0.5)]),
                     drawn("code-3", "Code, three", [(0, 0, 0.625, 1), (0.625, 0, 0.375, 0.5), (0.625, 0.5, 0.375, 0.5)]),
                     drawn("focus-c", "Focus centre", [(0, 0, 0.25, 1), (0.25, 0, 0.5, 1), (0.75, 0, 0.25, 1)])]
        c.fileLayoutIDs = ["wide-4"]
        c.layoutBar += extra
        return LayoutCatalogue(config: c)
    }

    /// The code-3 of the walkthrough's step 6: a 2×2, the left column merged, the splitter at 60 %.
    static var codeThree: GridEditor {
        var e = GridEditor(preset: .grid2x2)
        e.merge(0, 2)
        if let v = e.splitters.first(where: { $0.axis == .vertical }) { e.move(v, to: 0.6) }
        e.setName("Code, three")
        e.setID("code-3")
        return e
    }
    /// `window` distinguishes several windows of one app — tabs are keyed by their ref.
    static func tab(_ pid: Int32, window: Int = 0, focused: Bool = false, floating: Bool = false, hidden: Bool = false,
                    fullscreen: Bool = false, offSpace: Bool = false, title: String = "") -> WindowTabItem {
        WindowTabItem(ref: WindowRef(id: WindowID(pid) * 10 + WindowID(window) * 1000, pid: pid),
                      isFocused: focused, isFloating: floating, isHidden: hidden, isFullscreen: fullscreen,
                      isOffSpace: offSpace, title: title)
    }

    static let railGeometry = CGSize(width: 48, height: 800)
    static let barGeometry = CGSize(width: 1200, height: 34)

    // MARK: catalog

    static var all: [Story] {
        var out: [Story] = []
        func add(_ name: String, _ size: CGSize?, _ v: some View,
                 knownOverflow: Bool = false, truncates: Bool = false) {
            out.append(Story(name: name, size: size, view: AnyView(v),
                             knownOverflow: knownOverflow, truncates: truncates))
        }
        let send: (Command) -> Void = { _ in }

        // Rail
        add("rail-default", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 3, pids: [5, 3, 5]),
                         railItem(1, name: "Web", symbol: "globe", count: 2, pids: [1, 1], active: true),
                         railItem(2, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send))
        add("rail-pinned-empty", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Chat", symbol: "bubble.left.and.bubble.right", count: 0, pinned: true),
                         railItem(1, name: "Web", symbol: "globe", count: 1, pids: [1], active: true),
                         railItem(2, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send))
        // Five distinct apps in one row: four icons then "+1", and a category label that has to
        // pick one answer out of a mixed row.
        add("rail-many-apps", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Everything", symbol: "square.grid.2x2", count: 6,
                                  pids: [5, 3, 1, 6, 4, 2], active: true),
                         railItem(1, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send))
        // #75: "Chat" mid-drag over "Code" — the insertion line in the gap above where it lands.
        let reorder = [railItem(0, name: "Code", symbol: "terminal", count: 3, pids: [5, 3, 5]),
                       railItem(1, name: "Web", symbol: "globe", count: 2, pids: [1, 1], active: true),
                       railItem(2, name: "Chat", symbol: "bubble.left.and.bubble.right", count: 1, pids: [6]),
                       railItem(3, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]
        add("rail-reorder-insertion", railGeometry, ScreenPanelView(
            state: rail(reorder), launcherURL: "raycast://", metaFor: meta, send: send,
            dropTarget: reorder[0].id, reordering: reorder[2].id))
        // No cog on a secondary display — one way into settings, not one per monitor.
        add("rail-secondary-screen", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 1, pids: [5], active: true),
                         railItem(1, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send))
        add("rail-twelve-workspaces", railGeometry, ScreenPanelView(
            state: rail((0..<11).map { railItem($0, name: "Workspace \($0 + 1)", symbol: "square.grid.2x2",
                                               count: ($0 * 3) % 7, pids: [Int32($0 % 6) + 1], active: $0 == 4) }
                        + [railItem(11, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send),
            knownOverflow: true)   // 12 rows can exceed a short rail; overflow handling is unbuilt

        // Rail hover card — what a tile says when you point at it. The fixtures stand in for
        // ScreenCaptureKit frames: the card is a pure view, so the stories cover every state
        // including the one no test machine can reach (a granted Screen Recording capture).
        func preview(_ pid: Int32, image: NSImage?) -> WindowPreviewItem {
            let m = meta(pid)
            return WindowPreviewItem(ref: WindowRef(id: WindowID(pid) * 10, pid: pid),
                                     name: m.name, icon: m.icon, image: image)
        }
        add("rail-hover-previews", nil, RailHoverCard(
            title: "Code (1)", subtitle: "3 windows · coding",
            content: .previews([preview(5, image: shot(.systemPink)),
                                preview(3, image: shot(.systemGray)),
                                preview(1, image: shot(.systemBlue))]),
            onGrantAccess: {}), truncates: true)
        // #90: the first frame of a hover — thumbnails from the cache, at the cache's downscaled
        // size, and the icon placeholder only for the window the shell has never seen.
        func cached(_ color: NSColor) -> NSImage? {
            shot(color).cgImage(forProposedRect: nil, context: nil, hints: nil)
                .flatMap(WindowThumbnails.downscale).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
        add("rail-hover-cached", nil, RailHoverCard(
            title: "Code (1)", subtitle: "3 windows · coding",
            content: .previews([preview(5, image: cached(.systemPink)),
                                preview(3, image: cached(.systemGray)),
                                preview(1, image: nil)]),
            onGrantAccess: {}), truncates: true)
        // One window gets the big frame; the capture has not landed yet on the second tile, so
        // this also covers the icon placeholder.
        add("rail-hover-one-window", nil, RailHoverCard(
            title: "Web (2)", subtitle: "1 window · web browsing",
            content: .previews([preview(1, image: shot(.systemBlue))]),
            onGrantAccess: {}))
        // More than the card draws, plus a name that has to truncate under its miniature.
        add("rail-hover-overflow", nil, RailHoverCard(
            title: "Everything (1)", subtitle: "8 windows · coding",
            content: .previews((0..<8).map { preview(Int32($0 % 6) + 1, image: $0 < 4 ? shot(.systemTeal) : nil) }),
            onGrantAccess: {}), truncates: true)
        // The state every Mac without the grant is in — never blank boxes.
        add("rail-hover-needs-screen-recording", nil, RailHoverCard(
            title: "Code (1)", subtitle: "3 windows · coding",
            content: .needsScreenRecording, onGrantAccess: {}))
        add("rail-hover-empty", nil, RailHoverCard(
            title: "Chat (1)", subtitle: "0 windows",
            content: .message("Nothing here yet. Drop a tab on this tile, or open something from the launcher."),
            onGrantAccess: {}))
        add("rail-hover-new-workspace", nil, RailHoverCard(
            title: "New workspace", subtitle: nil,
            content: .message("Opens a new workspace — or drop a tab here to move its window into one."),
            onGrantAccess: {}))

        // #73: the tray — hidden windows and popups, counted, pinned above the cog.
        let hiddenAway: [SpacialShellProtocol.WindowRef] = [WindowRef(id: 20, pid: 2), WindowRef(id: 40, pid: 4),
                                                            WindowRef(id: 60, pid: 6)]
        add("rail-tray", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 3, pids: [5, 3, 5]),
                         railItem(1, name: "Web", symbol: "globe", count: 2, pids: [1, 1], active: true),
                         railItem(2, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)],
                        tray: hiddenAway),
            launcherURL: "raycast://", metaFor: meta, send: send))
        // …and its list: icon + title rows, a title that has to truncate, one AX would not name
        // (the app's name stands in), and a popup.
        func row(_ pid: Int32, _ title: String?) -> WindowPreviewItem {
            let m = meta(pid)
            return WindowPreviewItem(ref: WindowRef(id: WindowID(pid) * 10, pid: pid), name: title ?? m.name,
                                     icon: m.icon, image: nil)
        }
        add("rail-tray-open", nil, RailHoverCard(
            title: "Hidden windows and popups", subtitle: "4 windows · click one to bring it back",
            content: .windows([row(2, "Shopping list"),
                               row(4, "Re: the quarterly numbers, and a subject line long enough that it has to truncate"),
                               row(6, nil),
                               row(1, "Downloads")]),
            onGrantAccess: {}), truncates: true)

        // #109: the error channel — a badge on the cog (the worst severity), and the list its
        // hover opens. Warnings only on the rail, so the story shows the triangle; the card mixes.
        add("rail-problems", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 2, pids: [5, 3], active: true),
                         railItem(1, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send,
            problems: [.screenRecordingMissing]))
        let problems: [Problem] = [
            .configInvalid("unknown key \"gapp\" on line 12"),
            .screenRecordingMissing,
            .axWriteFailing(app: "us.zoom.xos"),
            .telemetryFailing(host: "otel.example.com"),
        ]
        add("rail-problems-open", nil, RailHoverCard(
            title: "\(problems.count) problems", subtitle: "Each clears itself once it is fixed",
            content: .problems(problems), onGrantAccess: {}))

        // #130 (M3 B7): the first-launch grant wait — a window, not a silent hang — fresh, and
        // once a stale TCC row is the likelier story.
        add("grant-wait", nil, GrantWaitView(wait: GrantWait(elapsed: .seconds(4)), openSettings: {}, quit: {}))
        add("grant-wait-stale", nil, GrantWaitView(wait: GrantWait(elapsed: .seconds(47)), openSettings: {}, quit: {}))
        // …and the alert a failed hotkey tap opens, with the socket's queued behind it.
        add("problem-alert", nil, ProblemAlertView(
            problem: .hotkeysInactive("the event tap could not be created"), queued: 1, dismiss: { _ in }))
        // #138: another window manager is running — a warning the user may keep, so it offers
        // "Don't warn again".
        add("problem-alert-other-wm", nil, ProblemAlertView(
            problem: .otherWindowManager(entry: "com.knollsoft.Rectangle", name: "Rectangle"), queued: 0,
            dismiss: { _ in }))

        // panel-color / panel-opacity actually reaching the panels. These existed as config keys,
        // as persisted values and as settings-window controls while nothing read them, so the
        // point of these two stories is that a tinted panel is *visibly* tinted.
        add("rail-tinted", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 2, pids: [5, 3], active: true),
                         railItem(1, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta,
            chrome: PanelChrome(color: "#9D0B7F", opacity: 0.9), send: send))
        add("bar-tinted", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true), tab(3)]), metaFor: meta, sizing: .fit,
            chrome: PanelChrome(color: "#9D0B7F", opacity: 0.9), send: send))

        // Tab bar
        add("bar-one-tab", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true)], layout: .maximize), metaFor: meta, sizing: .fit, send: send))
        add("bar-five-tabs", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true), tab(2), tab(3), tab(4), tab(6)]), metaFor: meta, sizing: .fit, send: send))
        add("bar-long-names", barGeometry, WorkspacePanelView(
            state: tabs([tab(5, focused: true), tab(5), tab(5), tab(5)]), metaFor: meta, sizing: .fit, send: send), truncates: true)
        // #110: window titles. Two Terminal windows told apart by title; Notes has no title yet and
        // shows its app name, as every tab did before the feed.
        add("bar-titles", barGeometry, WorkspacePanelView(
            state: tabs([tab(3, focused: true, title: "~/code/spacial-shell — zsh"),
                         tab(3, window: 1, title: "~/Downloads — zsh"),
                         tab(1, title: "Pull requests · AskAlice/SpacialShell-MacOS"), tab(2)]),
            metaFor: meta, sizing: .fit, send: send))
        // #116: the same row as `bar-titles` in the other two tab styles.
        for style in [TabStyle.name, .icon] {
            add("bar-style-\(style.rawValue)", barGeometry, WorkspacePanelView(
                state: tabs([tab(3, focused: true, title: "~/code/spacial-shell — zsh"),
                             tab(3, window: 1, title: "~/Downloads — zsh"),
                             tab(1, title: "Pull requests · AskAlice/SpacialShell-MacOS"), tab(2)]),
                metaFor: meta, sizing: .fit, style: style, send: send))
        }
        // A title longer than the 220 pt tab ceiling truncates in the middle, keeping both ends.
        add("bar-long-title", barGeometry, WorkspacePanelView(
            state: tabs([tab(4, focused: true,
                             title: "Re: Quarterly planning — the long thread everyone was copied on (37 messages)"),
                         tab(1, title: "developer.apple.com/documentation/applicationservices/axuielement_h/1462085-axuielementcopyattributevalue"),
                         tab(3, title: "zsh")]),
            metaFor: meta, sizing: .fit, send: send), truncates: true)
        add("bar-floating-hidden", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true), tab(2, floating: true), tab(3, hidden: true), tab(4)]),
            metaFor: meta, sizing: .fit, send: send))
        add("bar-fullscreen", barGeometry, WorkspacePanelView(
            state: tabs([tab(3, focused: true), tab(1, fullscreen: true), tab(4)]),
            metaFor: meta, sizing: .fit, send: send))
        // #55: on another Space, beside the two states it must not be mistaken for.
        add("bar-off-space", barGeometry, WorkspacePanelView(
            state: tabs([tab(3, focused: true), tab(1, offSpace: true), tab(2, hidden: true), tab(4, fullscreen: true)]),
            metaFor: meta, sizing: .fit, send: send))
        // Tab overflow (#14), at 800 pt: the tab row gets 628 pt, and each tab at its 88 pt floor
        // costs 91 with spacing (+16 for the focused tab's close button, +8 end-of-row gap). Six tabs
        // (570) squeeze toward the floor and still fit; seven (661) are past it and the row scrolls;
        // twenty scroll to keep the focused tab in view.
        func row(_ n: Int, focus: Int) -> ScreenShellState {
            tabs((1...n).map { tab(Int32(($0 % 6) + 1), window: $0, focused: $0 == focus) }, layout: .column)
        }
        let narrowBar = CGSize(width: 800, height: 34)
        add("bar-six-tabs-at-floor", narrowBar, WorkspacePanelView(
            state: row(6, focus: 1), metaFor: meta, sizing: .fit, send: send))
        add("bar-seven-tabs-scrolls", narrowBar, WorkspacePanelView(
            state: row(7, focus: 1), metaFor: meta, sizing: .fit, send: send))
        add("bar-twenty-tabs", narrowBar, WorkspacePanelView(
            state: row(20, focus: 1), metaFor: meta, sizing: .fit, send: send))
        add("bar-twenty-tabs-focus-last", narrowBar, WorkspacePanelView(
            state: row(20, focus: 20), metaFor: meta, sizing: .fit, send: send))

        // Layouts (#10). The bar: the set, plus the active layout from outside it, then ⋯ and the cog.
        add("bar-layouts-custom", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true), tab(3)], layout: "focus-c", layouts: customLayouts(bar: ["code-3"])),
            metaFor: meta, sizing: .fit, send: send))
        // Design §8: the workspace holds a deleted layout; the fallback is highlighted and badged.
        add("bar-layout-missing", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true)], layout: "code-3"), metaFor: meta, sizing: .fit, send: send))
        // The cog's popover: every layout by name, the current one checked, Show-on-bar switches.
        add("layout-popover", nil, LayoutPopoverView(
            state: tabs([tab(1, focused: true)], layout: .maximize, layouts: customLayouts()), send: send))
        // The ⋯ menu — the real NSMenu the bar pops up, drawn item by item (a menu cannot be
        // snapshotted closed, and an open one is a separate process's window).
        add("layout-menu", nil, MenuPreview(menu: LayoutMenu.make(
            tabs([tab(1, focused: true)], layout: "code-3", layouts: customLayouts(bar: ["code-3"])),
            send: send, editLayouts: {})))
        // #111: the rail's app menu (no clock, #24 P4). #112: a tile's right-click menu, and its
        // "Set category" and "Set symbol" submenus — a row routing made for web, checked.
        add("rail-app-menu", nil, MenuPreview(menu: RailMenu.app(send: send)))
        let webRow = WorkspaceRailItem(id: UUID(), index: 0, name: "Workspace", symbol: "globe", windowCount: 2,
                                       windows: [], isActive: true, isPinned: false, isTrailingEmpty: false,
                                       category: .web, layout: .split)
        let workspaceMenu = RailMenu.workspace(webRow, layouts: tabs([]).layouts,
                                               categories: Config.defaultCategoryOrder, send: send)
        add("rail-workspace-menu", nil, MenuPreview(menu: workspaceMenu))
        add("rail-workspace-menu-category", nil, MenuPreview(menu: workspaceMenu.items[0].submenu!))
        add("rail-workspace-menu-symbol", nil, MenuPreview(menu: workspaceMenu.items[1].submenu!))
        add("rail-workspace-menu-layout", nil, MenuPreview(menu: workspaceMenu.items[2].submenu!))
        // #127: a tab's right-click menu (a floating tab, so "Tile"), and "Move to workspace":
        // every other row on the display, by category or name, then "+" as "New workspace".
        let tabMenu = RailMenu.tab(tab(3, floating: true), rail: [
            railItem(0, name: "Workspace", symbol: "globe", count: 2, active: true),
            WorkspaceRailItem(id: UUID(), index: 1, name: "Workspace", symbol: "terminal", windowCount: 1,
                              isActive: false, isPinned: false, isTrailingEmpty: false, category: .terminal),
            railItem(2, name: "Workspace", symbol: "square.grid.2x2", count: 1),
            railItem(3, name: "Workspace", symbol: "plus", count: 0, trailing: true),
        ], metaFor: meta, send: send)
        add("tab-menu", nil, MenuPreview(menu: tabMenu))
        add("tab-menu-move", nil, MenuPreview(menu: tabMenu.items[3].submenu!))
        // The editor, at the walkthrough's step 6; an existing drawn layout (Delete); a built-in
        // (read-only, Duplicate to edit).
        add("layout-editor", LayoutEditorView.size, LayoutEditorView(mode: .edit(codeThree)))
        add("layout-editor-existing", LayoutEditorView.size, LayoutEditorView(
            mode: .edit(GridEditor(editing: customLayouts()["code-3"]!)!),
            removal: .delete(warning: GridEditor.deleteWarning(usage: 3, fallback: .maximize)), taken: ["code-3"]))
        add("layout-editor-builtin", LayoutEditorView.size, LayoutEditorView(
            mode: .readOnly(LayoutDef.builtins[1], canDuplicate: true)))

        // Overview
        let windows = [
            // #110: cells show the window title; Notes has none and falls back to its app name.
            OverviewWindowItem(ref: WindowRef(id: 10, pid: 1), name: "Start Page", app: "Safari", detail: "Web",
                               icon: swatch(.systemBlue)),
            OverviewWindowItem(ref: WindowRef(id: 20, pid: 2), name: "Notes", app: "Notes", detail: "Web",
                               icon: swatch(.systemYellow)),
            OverviewWindowItem(ref: WindowRef(id: 30, pid: 3), name: "~/code/spacial-shell — zsh", app: "Terminal",
                               detail: "Code", icon: swatch(.systemGray)),
            OverviewWindowItem(ref: WindowRef(id: 40, pid: 5),
                               name: "A Very Long Application Name That Must Truncate",
                               app: "A Very Long Application Name That Must Truncate",
                               detail: "a workspace with a very long name", icon: swatch(.systemPink)),
        ]
        let apps = ["Mail", "Files", "Music", "Calendar", "Photos",
                    "A Very Long Application Name That Must Truncate"].enumerated().map { i, n in
            OverviewAppItem(url: URL(fileURLWithPath: "/Applications/\(n).app"), name: n,
                            icon: swatch([.systemTeal, .systemGreen, .systemOrange, .systemRed, .systemPurple, .systemBrown][i]))
        }
        add("overview-results", CGSize(width: 640, height: 440),
            OverviewView(windows: windows, apps: apps, onSelectWindow: { _ in }, onLaunchApp: { _ in }))
        add("overview-empty", CGSize(width: 640, height: 440),
            OverviewView(windows: [], apps: [], onSelectWindow: { _ in }, onLaunchApp: { _ in }))

        // Cheat sheet (fitting size — the panel sizes itself)
        add("cheatsheet-fn", nil,
            CheatSheetView(groups: CheatSheetController.grouped(CheatSheet.rows(for: Config()))))
        var ctrlAlt = Config(); ctrlAlt.keybindingPreset = .ctrlAlt
        add("cheatsheet-ctrl-alt", nil,
            CheatSheetView(groups: CheatSheetController.grouped(CheatSheet.rows(for: ctrlAlt))))
        // #29: the passive background behind an empty workspace — same sheet, dimmed.
        add("cheatsheet-empty-workspace", nil,
            CheatSheetView(groups: CheatSheetController.grouped(CheatSheet.rows(for: Config())), dimmed: true))
        // #87: fitted to a 1024 pt display. The sheets above are wider than that; these wrap to fit
        // — the Fn sheet the whole width, the empty-workspace one the area beside the 48 pt rail.
        // Fitting size, as the panel sizes itself; `cheatSheetWrapsToFitItsArea` checks the width.
        add("cheatsheet-fn-1024", nil,
            CheatSheetView.fitting(CheatSheetController.grouped(CheatSheet.rows(for: Config())), in: 1024).view)
        add("cheatsheet-empty-workspace-1024", nil,
            CheatSheetView.fitting(CheatSheetController.grouped(CheatSheet.rows(for: Config())),
                                   dimmed: true, in: 1024 - 48).view)

        // #108: the tile a dragged window would swap with, at a half-split tile's size.
        add("drop-target", CGSize(width: 480, height: 320), DropTargetView())

        // The settings window's General pane, with #138's silenced warnings and the way back.
        var silenced = SettingsOverrides()
        silenced.silence("other-wm:com.knollsoft.Rectangle")
        silenced.silence("other-wm:yabai")
        add("settings-general", nil, SettingsView(
            file: Config(), overrides: .constant(silenced), configPath: "~/.config/spacial-shell/config.toml",
            openConfigFile: {}, checkForUpdates: nil, standalone: .general))

        return out
    }
}
