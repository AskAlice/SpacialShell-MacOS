import Foundation
import CoreGraphics

/// Pure derivation of what the shell panels draw, one value per screen. The app layer renders it
/// and never looks inside `World` itself; anything the panels need that is not spatial (app names,
/// icons, materials) is resolved on the platform side by `pid`.

public struct WorkspaceRailItem: Identifiable, Equatable, Sendable {
    public let id: UUID              // Workspace.id — stable across reorders and renames
    public let index: Int            // 0-based position in the screen's stack
    public let name: String
    public let symbol: String        // SF Symbol name (config seed or default)
    public let windowCount: Int      // all windows in the row, hidden ones included
    /// The row's layout, so the tile can draw its *shape* — a schematic from `LayoutEngine`, never
    /// a capture, so it needs no Screen Recording permission and costs nothing to draw.
    public let layout: Layout
    /// The row itself, in order. The rail draws one icon per distinct app and derives the
    /// workspace's category from them; both need the apps, not just how many there are. Resolving
    /// a `pid` to a name, an icon or a bundle id stays on the platform side, as it does for tabs.
    public let windows: [WindowRef]
    public let isActive: Bool
    public let isPinned: Bool
    public let isTrailingEmpty: Bool // the always-there way down (invariant 4); drawn as "+"
    public init(id: UUID, index: Int, name: String, symbol: String, windowCount: Int,
                layout: Layout, windows: [WindowRef] = [],
                isActive: Bool, isPinned: Bool, isTrailingEmpty: Bool) {
        self.id = id; self.index = index; self.name = name; self.symbol = symbol
        self.windowCount = windowCount; self.windows = windows; self.layout = layout
        self.isActive = isActive; self.isPinned = isPinned
        self.isTrailingEmpty = isTrailingEmpty
    }
}

public struct WindowTabItem: Identifiable, Equatable, Sendable {
    public var id: WindowRef { ref }
    public let ref: WindowRef
    public let isFocused: Bool
    public let isFloating: Bool      // keeps its row index but no tiling slot; drawn with a pin
    public let isHidden: Bool        // minimized or app-hidden; drawn dimmed, click is a no-op
    public let isFullscreen: Bool    // native fullscreen: no tiling slot; a click returns to its Space
    public init(ref: WindowRef, isFocused: Bool, isFloating: Bool, isHidden: Bool, isFullscreen: Bool = false) {
        self.ref = ref; self.isFocused = isFocused; self.isFloating = isFloating; self.isHidden = isHidden
        self.isFullscreen = isFullscreen
    }
}

public struct ScreenShellState: Equatable, Sendable {
    public let display: DisplayID
    public let isFocusedScreen: Bool
    public let rail: [WorkspaceRailItem]     // top→bottom, same order as Screen.workspaces
    public let tabs: [WindowTabItem]         // left→right, the active workspace's row
    public let layout: Layout                // the active workspace's layout
    public init(display: DisplayID, isFocusedScreen: Bool, rail: [WorkspaceRailItem],
                tabs: [WindowTabItem], layout: Layout) {
        self.display = display; self.isFocusedScreen = isFocusedScreen
        self.rail = rail; self.tabs = tabs; self.layout = layout
    }
}

public enum ShellUI {
    /// Nil when the world does not know this display (mid hot-plug); the caller just skips it.
    public static func state(for display: DisplayID, in world: World) -> ScreenShellState? {
        guard let screen = world.screens[display] else { return nil }
        let rail = screen.workspaces.enumerated().map { i, ws in
            WorkspaceRailItem(
                id: ws.id, index: i, name: ws.name, symbol: ws.symbol,
                windowCount: ws.windows.count,
                layout: ws.layout,
                windows: ws.windows,
                isActive: i == screen.activeIndex,
                isPinned: ws.pinned,
                isTrailingEmpty: i == screen.workspaces.count - 1 && ws.isEmpty && !ws.pinned)
        }
        let active = screen.active
        let tabs = active.windows.map { w in
            WindowTabItem(
                ref: w,
                isFocused: world.focus.window == w,
                isFloating: active.floating.contains(w),
                isHidden: world.hidden.contains(w),
                isFullscreen: world.fullscreen.contains(w))
        }
        return ScreenShellState(
            display: display,
            isFocusedScreen: world.focus.screen == display,
            rail: rail, tabs: tabs, layout: active.layout)
    }
}
