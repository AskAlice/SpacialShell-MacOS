import Foundation
import CoreGraphics

public typealias DisplayID = String   // CGDisplayCreateUUIDFromDisplayID string
public typealias WindowID = UInt32    // CGWindowID

public struct WindowRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public let id: WindowID
    public let pid: Int32
    public init(id: WindowID, pid: Int32) { self.id = id; self.pid = pid }
    public var description: String { "w\(id)@\(pid)" }
}

public enum Layout: String, Codable, CaseIterable, Sendable {
    case maximize, split, column, half, grid
    public var next: Layout {
        let all = Layout.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

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
    public init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2", layout: Layout,
                windows: [WindowRef] = [], floating: Set<WindowRef> = [], anchor: WindowRef? = nil, pinned: Bool = false) {
        self.id = id; self.name = name; self.symbol = symbol; self.layout = layout
        self.windows = windows; self.floating = floating; self.anchor = anchor; self.pinned = pinned
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
    public init(screens: [DisplayID: Screen], screenOrder: [DisplayID], focus: Focus,
                ephemeral: Set<WindowRef>, ignored: Set<WindowRef>, hidden: Set<WindowRef>,
                parents: [WindowRef: WindowRef], defaultLayout: Layout) {
        self.screens = screens; self.screenOrder = screenOrder; self.focus = focus
        self.ephemeral = ephemeral; self.ignored = ignored; self.hidden = hidden
        self.parents = parents; self.defaultLayout = defaultLayout
    }
}
