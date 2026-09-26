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
    /// The row itself, in order. The rail draws one icon per distinct app and derives the
    /// workspace's category from them; both need the apps, not just how many there are. Resolving
    /// a `pid` to a name, an icon or a bundle id stays on the platform side, as it does for tabs.
    public let windows: [WindowRef]
    public let isActive: Bool
    public let isPinned: Bool
    public let isTrailingEmpty: Bool // the always-there way down (invariant 4); drawn as "+"
    public init(id: UUID, index: Int, name: String, symbol: String, windowCount: Int,
                windows: [WindowRef] = [], isActive: Bool, isPinned: Bool, isTrailingEmpty: Bool) {
        self.id = id; self.index = index; self.name = name; self.symbol = symbol
        self.windowCount = windowCount; self.windows = windows
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
    public let isOffSpace: Bool      // on another native Space (#55): no tiling slot; a click goes there
    /// The window's title (#110), from the snapshot feed. Empty when it has none or none is known
    /// yet; the tab then shows the app name, as it did before titles.
    public let title: String
    public init(ref: WindowRef, isFocused: Bool, isFloating: Bool, isHidden: Bool, isFullscreen: Bool = false,
                isOffSpace: Bool = false, title: String = "") {
        self.ref = ref; self.isFocused = isFocused; self.isFloating = isFloating; self.isHidden = isHidden
        self.isFullscreen = isFullscreen; self.isOffSpace = isOffSpace; self.title = title
    }
}

/// #10: one layout as the popover and the ⋯ menu list it.
public struct LayoutChoice: Identifiable, Equatable, Sendable {
    /// Where it comes from: the ⋯ menu's sections, and whether the editor offers Duplicate
    /// (built-in), Reset (config.toml) or Delete (drawn).
    public enum Origin: Equatable, Sendable { case builtin, file, drawn }
    public let def: LayoutDef
    public let origin: Origin
    public let onBar: Bool
    public var id: LayoutID { def.id }
    public init(def: LayoutDef, origin: Origin, onBar: Bool) { self.def = def; self.origin = origin; self.onBar = onBar }
}

public struct ScreenShellState: Equatable, Sendable {
    public let display: DisplayID
    public let isFocusedScreen: Bool
    public let rail: [WorkspaceRailItem]     // top→bottom, same order as Screen.workspaces
    public let tabs: [WindowTabItem]         // left→right, the active workspace's row
    public let layout: LayoutID              // the active workspace's layout, as stored
    /// Design §8: set when `layout` does not resolve (a deleted or mistyped layout) and the shell
    /// is drawing the fallback — "layout "code-3" is missing — using maximize". Nil otherwise.
    public let layoutWarning: String?
    /// The layout actually drawn: `layout`, or its fallback when it does not resolve. The switcher
    /// highlights this one, badged when `layoutWarning` is set.
    public let shownLayout: LayoutID
    /// #10: every layout, catalogue order — the popover's rows and the ⋯ menu's items.
    public let layouts: [LayoutChoice]
    /// The bar set, in order (design §7).
    public let bar: [LayoutID]
    /// `default-layout`, which "Set as default" writes.
    public let defaultLayout: LayoutID
    /// The rail tray (#73): windows no tab brings back on its own, in `ShellUI.tray(in:)` order.
    /// The same list on every display — hidden windows and popups are the user's, not a screen's.
    public let tray: [WindowRef]
    public init(display: DisplayID, isFocusedScreen: Bool, rail: [WorkspaceRailItem],
                tabs: [WindowTabItem], layout: LayoutID, layouts catalogue: LayoutCatalogue = .builtins,
                tray: [WindowRef] = []) {
        self.display = display; self.isFocusedScreen = isFocusedScreen
        self.rail = rail; self.tabs = tabs; self.layout = layout; self.tray = tray
        layoutWarning = catalogue.warning(for: layout)
        shownLayout = catalogue.resolve(layout).def.id
        layouts = catalogue.all.map { d in
            LayoutChoice(def: d, origin: d.isBuiltin ? .builtin : catalogue.fileIDs.contains(d.id) ? .file : .drawn,
                         onBar: catalogue.bar.contains(d.id))
        }
        bar = catalogue.bar
        defaultLayout = catalogue.fallback
    }

    /// Design §7: the bar set, then the layout on screen when it is not in the set, so the bar
    /// always shows what is active.
    public var switcher: [LayoutChoice] {
        let byID = Dictionary(layouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (bar + (bar.contains(shownLayout) ? [] : [shownLayout])).compactMap { byID[$0] }
    }

    /// The ⋯ menu: built-ins, then config.toml's, then drawn ones; empty sections left out.
    public var menuSections: [(title: String, items: [LayoutChoice])] {
        [("Built-in", LayoutChoice.Origin.builtin), ("From config.toml", .file), ("Drawn", .drawn)].compactMap { title, origin in
            let items = layouts.filter { $0.origin == origin }
            return items.isEmpty ? nil : (title, items)
        }
    }

    /// A tab dropped on this bar's empty end (#32). The bar names its own destination: a window
    /// from another row moves into this bar's workspace (without following, #95); one already in
    /// it goes to the end.
    public func endOfRowDrop(_ ref: WindowRef) -> Command {
        guard !tabs.contains(where: { $0.ref == ref }), let ws = rail.first(where: \.isActive) else {
            return .moveWindowRefBefore(ref, nil)
        }
        return .moveWindowRefToWorkspace(ref, ws.id, follow: false)
    }

    /// A rail tile dropped on another tile of this rail (#75) lands just before it, like a tab in
    /// the bar; dropping on "+" puts it last. Nil for a no-op, or for a workspace from another
    /// display's rail: reordering stays within one display.
    public func railReorder(_ workspace: UUID, before target: UUID) -> Command? {
        guard let i = rail.firstIndex(where: { $0.id == workspace }),
              let j = rail.firstIndex(where: { $0.id == target }) else { return nil }
        let to = j > i ? j - 1 : j     // an index into the stack with the dragged tile removed
        return to == i ? nil : .moveWorkspace(workspace, toIndex: to)
    }
}

public enum ShellUI {
    /// Nil when the world does not know this display (mid hot-plug); the caller just skips it.
    /// `titles` is the snapshot feed's (`ShellSnapshot.titles`): the model carries no titles.
    public static func state(for display: DisplayID, in world: World,
                             layouts: LayoutCatalogue = .builtins,
                             titles: [WindowRef: String] = [:]) -> ScreenShellState? {
        guard let screen = world.screens[display] else { return nil }
        let rail = screen.workspaces.enumerated().map { i, ws in
            WorkspaceRailItem(
                id: ws.id, index: i, name: ws.name, symbol: ws.symbol,
                windowCount: ws.windows.count,
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
                isFullscreen: world.fullscreen.contains(w),
                isOffSpace: world.offSpace.contains(w),
                title: titles[w] ?? "")
        }
        return ScreenShellState(
            display: display,
            isFocusedScreen: world.focus.screen == display,
            rail: rail, tabs: tabs, layout: active.layout, layouts: layouts, tray: tray(in: world))
    }

    /// #73: what the rail tray lists — every hidden (minimized or ⌘H) window, then every popup
    /// (`ephemeral`), each in rail order: displays left→right, workspaces top→bottom, rows
    /// left→right. A popup has no place of its own, so it sorts by its owner's (`parents`), and
    /// one with no placed owner goes last, by id, so the list does not shuffle between renders.
    /// `ignored` windows are not listed: the shell does not manage them, so it does not offer them.
    public static func tray(in world: World) -> [WindowRef] {
        let placed = world.screenOrder.flatMap { world.screens[$0]?.workspaces.flatMap(\.windows) ?? [] }
        let rank = Dictionary(placed.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func key(_ r: WindowRef) -> (Int, WindowID) { (world.parents[r].flatMap { rank[$0] } ?? .max, r.id) }
        return placed.filter(world.hidden.contains) + world.ephemeral.sorted { key($0) < key($1) }
    }

    /// #29: whether `display` shows the dimmed cheat sheet behind its empty workspace. Only the
    /// focused display (one sheet, where the user is looking), only while its active workspace has
    /// no windows, and not on a fullscreen Space (#72). Zen deliberately does not hide it.
    public static func showsEmptyCheatSheet(_ display: DisplayID, in world: World, config: Config) -> Bool {
        guard config.emptyCheatsheet, world.focus.screen == display, let screen = world.screens[display] else { return false }
        return screen.active.isEmpty && !world.showsFullscreenSpace(display)
    }
}
