import Foundation
import CoreGraphics
import SpacialShellProtocol

// Moved to SpacialShellProtocol (M2 D4) so `spacialctl` and the IPC server can share these types
// without linking the model. Typealiases keep every M1 call site (`WindowRef(id:pid:)`,
// `Layout.allCases`, …) compiling unchanged.
public typealias DisplayID = SpacialShellProtocol.DisplayID
public typealias WindowID = SpacialShellProtocol.WindowID
public typealias WindowRef = SpacialShellProtocol.WindowRef
public typealias Layout = SpacialShellProtocol.Layout

public enum WindowKind: String, Codable, Sendable { case tile, float, ephemeral, ignore }

public struct Workspace: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var layout: Layout
    public var windows: [WindowRef]      // ordered left→right; tiled + floating
    public var floating: Set<WindowRef>
    public var anchor: WindowRef?         // last focused window here; maximize/split anchor
    public var pinned: Bool               // never reaped when empty (config seed / user-named)
    /// Held open while empty because the state file says windows belong here — set by
    /// `PersistedState.restore` for a workspace some app was in when we quit, cleared by
    /// `normalize()` as soon as a window lands. Without it the reaper would delete the workspace
    /// between restore and the first snapshot, and the apps would have nowhere to return to.
    public var reserved: Bool
    public init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2", layout: Layout,
                windows: [WindowRef] = [], floating: Set<WindowRef> = [], anchor: WindowRef? = nil,
                pinned: Bool = false, reserved: Bool = false) {
        self.id = id; self.name = name; self.symbol = symbol; self.layout = layout
        self.windows = windows; self.floating = floating; self.anchor = anchor
        self.pinned = pinned; self.reserved = reserved
    }
    public var isEmpty: Bool { windows.isEmpty }
}

public struct Screen: Codable, Equatable, Sendable {
    public let display: DisplayID
    public var rect: CGRect?             // nil = whole display visibleFrame
    public var workspaces: [Workspace]   // top→bottom
    public var activeIndex: Int
    public init(display: DisplayID, rect: CGRect? = nil, workspaces: [Workspace], activeIndex: Int) {
        self.display = display; self.rect = rect; self.workspaces = workspaces; self.activeIndex = activeIndex
    }
    public var active: Workspace {
        get { workspaces[activeIndex] }
        set { workspaces[activeIndex] = newValue }
    }
}

public struct Focus: Codable, Equatable, Sendable {
    public var screen: DisplayID
    public var window: WindowRef?
    public init(screen: DisplayID, window: WindowRef?) { self.screen = screen; self.window = window }
}

public struct World: Codable, Equatable, Sendable {
    public var screens: [DisplayID: Screen]
    public var screenOrder: [DisplayID]        // left→right, top→bottom
    public var focus: Focus
    public var ephemeral: Set<WindowRef>       // visitors: no workspace, never parked
    public var ignored: Set<WindowRef>         // popups / fullscreen / unmanageable
    public var hidden: Set<WindowRef>          // minimized or app-hidden; keep slot, skip layout+nav
    public var parents: [WindowRef: WindowRef] // dialog → owner
    public var defaultLayout: Layout
    /// Zen mode (M2 design ruling): true hides the shell panels and gives their edges back to the
    /// layout. Lives in the model because the layout rect depends on it — the reconciler reads it
    /// via `ShellInsets(config:hidden:)`, so a toggle is an ordinary command → relayout round
    /// trip. Persisted in `state.json` (`PersistedState.zen`) so it survives relaunch.
    public var zen: Bool
    public init(screens: [DisplayID: Screen], screenOrder: [DisplayID], focus: Focus,
                ephemeral: Set<WindowRef>, ignored: Set<WindowRef>, hidden: Set<WindowRef>,
                parents: [WindowRef: WindowRef], defaultLayout: Layout, zen: Bool = false) {
        self.screens = screens; self.screenOrder = screenOrder; self.focus = focus
        self.ephemeral = ephemeral; self.ignored = ignored; self.hidden = hidden
        self.parents = parents; self.defaultLayout = defaultLayout; self.zen = zen
    }
}
