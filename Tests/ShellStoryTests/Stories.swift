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

    static func rail(_ items: [WorkspaceRailItem]) -> ScreenShellState {
        ScreenShellState(display: "D1", isFocusedScreen: true, rail: items, tabs: [], layout: .split)
    }
    /// `pids` are the apps actually in the row — the rail draws one icon each and derives the
    /// category label from them, so a story without pids is a workspace of unknown apps.
    static func railItem(_ i: Int, name: String, symbol: String, count: Int, pids: [Int32] = [],
                         active: Bool = false, pinned: Bool = false, trailing: Bool = false) -> WorkspaceRailItem {
        WorkspaceRailItem(id: UUID(), index: i, name: name, symbol: symbol, windowCount: count,
                          windows: pids.map { WindowRef(id: WindowID($0) * 10, pid: $0) },
                          isActive: active, isPinned: pinned, isTrailingEmpty: trailing)
    }
    static func tabs(_ items: [WindowTabItem], layout: SpacialShellProtocol.Layout = .split) -> ScreenShellState {
        ScreenShellState(display: "D1", isFocusedScreen: true,
                         rail: [railItem(0, name: "Web", symbol: "globe", count: items.count, active: true)],
                         tabs: items, layout: layout)
    }
    static func tab(_ pid: Int32, focused: Bool = false, floating: Bool = false, hidden: Bool = false) -> WindowTabItem {
        WindowTabItem(ref: WindowRef(id: WindowID(pid) * 10, pid: pid),
                      isFocused: focused, isFloating: floating, isHidden: hidden)
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
        add("bar-floating-hidden", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true), tab(2, floating: true), tab(3, hidden: true), tab(4)]),
            metaFor: meta, sizing: .fit, send: send))
        add("bar-twenty-tabs", CGSize(width: 800, height: 34), WorkspacePanelView(
            state: tabs((1...20).map { tab(Int32(($0 % 6) + 1), focused: $0 == 1) }, layout: .column),
            metaFor: meta, sizing: .fit, send: send),
            knownOverflow: true)   // no "+N" badge yet (T19); the squeeze is the point of the story

        // Overview
        let windows = [
            OverviewWindowItem(ref: WindowRef(id: 10, pid: 1), name: "Safari", detail: "Web", icon: swatch(.systemBlue)),
            OverviewWindowItem(ref: WindowRef(id: 20, pid: 2), name: "Notes", detail: "Web", icon: swatch(.systemYellow)),
            OverviewWindowItem(ref: WindowRef(id: 30, pid: 3), name: "Terminal", detail: "Code", icon: swatch(.systemGray)),
            OverviewWindowItem(ref: WindowRef(id: 40, pid: 5),
                               name: "A Very Long Application Name That Must Truncate",
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

        return out
    }
}
