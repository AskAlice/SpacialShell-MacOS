import Foundation
import CoreGraphics
import SpacialShellProtocol

// Moved to SpacialShellProtocol (M2 D4) so `spacialctl` and the IPC server can share these types
// without linking the model. Typealiases keep every M1 call site (`WindowRef(id:pid:)`, …)
// compiling unchanged.
public typealias DisplayID = SpacialShellProtocol.DisplayID
public typealias WindowID = SpacialShellProtocol.WindowID
public typealias WindowRef = SpacialShellProtocol.WindowRef
public typealias LayoutID = SpacialShellProtocol.LayoutID

public enum WindowKind: String, Codable, Sendable { case tile, float, ephemeral, ignore }

public struct Workspace: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var layout: LayoutID
    public var windows: [WindowRef]      // ordered left→right; tiled + floating
    public var floating: Set<WindowRef>
    public var anchor: WindowRef?         // last focused window here; maximize/split anchor
    public var pinned: Bool               // never reaped when empty (config seed / user-named)
    /// Held open while empty because the state file says windows belong here — set by
    /// `PersistedState.restore` for a workspace some app was in when we quit, cleared by
    /// `normalize()` as soon as a window lands. Without it the reaper would delete the workspace
    /// between restore and the first snapshot, and the apps would have nowhere to return to.
    public var reserved: Bool
    /// #74: the category this row was made for by category routing — how the next app of that
    /// category finds it, wherever a drag has since moved it. Nil for every row routing did not
    /// make, and for every row in a state file older than #74.
    public var category: AppCategory?
    /// #113: sizes the user gave this row's layouts, by `Resize.Page.key` (a drawn layout's id, a
    /// built-in's `id#tiles`). Empty = every layout as designed; `balance` empties it.
    /// Persisted by `PersistedState`, not here: the keys below leave it out so a `Workspace` written
    /// before #113 still decodes.
    public var portions: [String: Portions] = [:]
    /// #114: how many columns `split` shows here (`SplitView.columns`, default 2). Persisted by
    /// `PersistedState`, left out of the keys below like `portions`.
    public var splitColumns: Int = SplitView.defaultColumns
    /// #114: the first window of split's sliding view. A hint, not a rule: `slideViews()` keeps it
    /// in step with the anchor, and the engine clamps it so the focused window is always in view.
    public var splitStart: WindowRef?
    enum CodingKeys: String, CodingKey { case id, name, symbol, layout, windows, floating, anchor, pinned, reserved, category }
    public init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2", layout: LayoutID,
                windows: [WindowRef] = [], floating: Set<WindowRef> = [], anchor: WindowRef? = nil,
                pinned: Bool = false, reserved: Bool = false, category: AppCategory? = nil,
                portions: [String: Portions] = [:], splitColumns: Int = SplitView.defaultColumns) {
        self.id = id; self.name = name; self.symbol = symbol; self.layout = layout
        self.windows = windows; self.floating = floating; self.anchor = anchor
        self.pinned = pinned; self.reserved = reserved; self.category = category
        self.portions = portions; self.splitColumns = splitColumns
    }

    /// #114: split's view of `row` (this workspace's tiled windows), for the engine.
    public func split(in row: [WindowRef]) -> SplitView {
        SplitView(columns: splitColumns, start: splitStart.flatMap { row.firstIndex(of: $0) } ?? 0)
    }
    public var isEmpty: Bool { windows.isEmpty }
}

public struct Screen: Codable, Equatable, Sendable {
    public let display: DisplayID
    public var rect: CGRect?             // nil = whole display visibleFrame
    public var workspaces: [Workspace]   // top→bottom
    public var activeIndex: Int
    /// #106: the workspace that was active here before the current one — where Fn+N on the active
    /// workspace goes back to. Set by `World.remember`, cleared by `normalize()` once it is gone.
    public var previous: UUID?
    public init(display: DisplayID, rect: CGRect? = nil, workspaces: [Workspace], activeIndex: Int, previous: UUID? = nil) {
        self.display = display; self.rect = rect; self.workspaces = workspaces; self.activeIndex = activeIndex
        self.previous = previous
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
    public var ignored: Set<WindowRef>         // popups / unmanageable
    public var hidden: Set<WindowRef>          // minimized or app-hidden; keep slot, skip layout+nav
    /// Native fullscreen (spec §4.3, amended 2026-09-14): keeps its slot and its tab and stays
    /// reachable by nav, but macOS owns its frame — skipped by layout and never parked.
    public var fullscreen: Set<WindowRef> = []
    /// On another native Space (#55): same deal as `fullscreen` — keeps its slot and its tab, but
    /// no frame write can show it, so layout skips it and it is never framed or parked.
    public var offSpace: Set<WindowRef> = []
    /// #128: the placeholder tabs, by the ref each holds in its row (`WindowRef.isPlaceholder`).
    /// A key here is in exactly one workspace's `windows`, never focused, never an anchor, never
    /// tiled — see `Placeholder`.
    public var placeholders: [WindowRef: Placeholder] = [:]
    /// #129 (material-shell P17): pinned tabs — live windows or placeholders. A pinned window that
    /// closes leaves a placeholder in its slot instead of its tab disappearing, and a pinned
    /// placeholder cannot be closed until it is unpinned. Every member is placed in a row.
    public var pinnedTabs: Set<WindowRef> = []
    public var parents: [WindowRef: WindowRef] // dialog → owner
    public var defaultLayout: LayoutID
    /// Zen mode (M2 design ruling): true hides the shell panels and gives their edges back to the
    /// layout. Lives in the model because the layout rect depends on it — the reconciler reads it
    /// via `ShellInsets(config:hidden:)`, so a toggle is an ordinary command → relayout round
    /// trip. Persisted in `state.json` (`PersistedState.zen`) so it survives relaunch.
    public var zen: Bool
    public init(screens: [DisplayID: Screen], screenOrder: [DisplayID], focus: Focus,
                ephemeral: Set<WindowRef>, ignored: Set<WindowRef>, hidden: Set<WindowRef>,
                parents: [WindowRef: WindowRef], defaultLayout: LayoutID, zen: Bool = false) {
        self.screens = screens; self.screenOrder = screenOrder; self.focus = focus
        self.ephemeral = ephemeral; self.ignored = ignored; self.hidden = hidden
        self.parents = parents; self.defaultLayout = defaultLayout; self.zen = zen
    }
}
