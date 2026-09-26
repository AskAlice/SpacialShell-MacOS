import Foundation
import CoreGraphics
import SpacialShellProtocol

/// M2 T8 / M3 B2 (#110): the one published shape, derived purely from the model and the store's
/// side tables. `WorldStore` builds it on every publish; the panels read titles from it.
extension ShellSnapshot {
    /// `titles` and `appNames` are the store's tables — the model is spatial and carries neither.
    /// A window with no title yet gets "" (the UI falls back to the app name).
    public init(world: World, generation: UInt64, displays: [DisplayInfo], config: Config,
                layouts: LayoutCatalogue, titles: [WindowRef: String], appNames: [Int32: String],
                bundleIDs: [WindowRef: String], locked: Bool) {
        let byID = Dictionary(displays.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let insets = ShellInsets(config: config, hidden: world.zen)
        func row(_ w: WindowRef, workspace: UUID?, visible: Bool, floating: Bool) -> WindowRow {
            WindowRow(window: w, pid: w.pid, workspaceId: workspace, title: titles[w] ?? "",
                      appName: appNames[w.pid] ?? "", bundleID: bundleIDs[w],
                      isFocused: world.focus.window == w, isVisibleUnderLayout: visible,
                      isFloating: floating, isHidden: world.hidden.contains(w))
        }
        // A visitor has no workspace: it is listed on its owner's screen, else the focused one.
        let owners = Dictionary(world.screenOrder.flatMap { d in
            world.screens[d]?.workspaces.flatMap { $0.windows.map { ($0, d) } } ?? []
        }, uniquingKeysWith: { a, _ in a })
        let visitors = Dictionary(grouping: world.ephemeral.sorted { $0.id < $1.id }) {
            world.parents[$0].flatMap { owners[$0] } ?? world.focus.screen
        }
        let screens: [ScreenRow] = world.screenOrder.compactMap { d in
            guard let screen = world.screens[d] else { return nil }
            let info = byID[d]
            let windows = screen.workspaces.flatMap { ws -> [WindowRow] in
                let tiled = world.tiled(in: ws)
                let focused = ws.anchor.flatMap { tiled.firstIndex(of: $0) } ?? 0
                // A unit-free rect big enough that no zone floor engages: "would the layout show
                // it", not "is it on screen now" — right mid-hot-plug too.
                let frames = LayoutEngine.frames(layouts.resolve(ws.layout).def, count: tiled.count, focused: focused,
                                                 in: CGRect(x: 0, y: 0, width: 100_000, height: 100_000), gap: 0,
                                                 split: ws.split(in: tiled))
                return ws.windows.map { w in
                    let floating = ws.floating.contains(w)
                    let visible = world.hidden.contains(w) ? false
                        : floating ? true
                        : tiled.firstIndex(of: w).map { frames.indices.contains($0) && frames[$0] != nil } ?? false
                    return row(w, workspace: ws.id, visible: visible, floating: floating)
                }
            } + (visitors[d] ?? []).map { row($0, workspace: nil, visible: !world.hidden.contains($0), floating: true) }
            return ScreenRow(
                display: d, frame: info.map { RectDTO($0.frame) }, visibleFrame: info.map { RectDTO($0.visibleFrame) },
                isMain: info?.isMain ?? false, isFocused: world.focus.screen == d,
                isCoveredByFullscreen: world.showsFullscreenSpace(d),
                insets: EdgeInsetsDTO(top: insets.top, left: insets.left, right: insets.right, bottom: insets.bottom),
                activeWorkspaceId: screen.active.id,
                workspaces: screen.workspaces.enumerated().map { i, ws in
                    WorkspaceRow(id: ws.id, name: ws.name, symbol: ws.symbol, layout: ws.layout, pinned: ws.pinned,
                                 isActive: i == screen.activeIndex, windowCount: ws.windows.count,
                                 isTrailingEmpty: i == screen.workspaces.count - 1 && ws.isEmpty && !ws.pinned)
                },
                windows: windows)
        }
        self.init(
            v: IPCProtocol.version, generation: generation, screens: screens,
            focus: FocusRow(screen: world.focus.screen, window: world.focus.window),
            zen: world.zen, capabilities: WireState.capabilities, locked: locked,
            chrome: ChromeRow(panelWidth: config.panelWidth, panelHeight: config.panelHeight,
                              railSide: config.railSide.rawValue, launcherURL: config.launcherURL,
                              showPanels: config.showPanels))
    }

    /// Every window's title, for the panels. Empty titles are left out, so a lookup miss and an
    /// untitled window read the same: fall back to the app name.
    public var titles: [WindowRef: String] {
        Dictionary(screens.flatMap(\.windows).filter { !$0.title.isEmpty }.map { ($0.window, $0.title) },
                   uniquingKeysWith: { a, _ in a })
    }
}
