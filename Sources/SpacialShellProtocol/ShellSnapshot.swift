import Foundation

// NOT YET EMITTED: this is the M2 T8 wire contract; the store still publishes the v1 `WireState`.
// Codec-tested here so the shape is frozen before the feed lands — nothing produces it yet.

/// The one wire shape published to the UI, the IPC subscribers, and the state-saver — spec
/// "Snapshot" decision: rows for **all** workspaces on a screen (not just the active one),
/// `WindowRow.workspaceId` nil for an ephemeral visitor.
public struct ShellSnapshot: Codable, Sendable, Equatable {

    public struct WorkspaceRow: Codable, Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var symbol: String
        public var layout: Layout
        public var pinned: Bool
        public var isActive: Bool
        public var windowCount: Int
        public var isTrailingEmpty: Bool

        public init(
            id: UUID, name: String, symbol: String, layout: Layout, pinned: Bool, isActive: Bool,
            windowCount: Int, isTrailingEmpty: Bool
        ) {
            self.id = id; self.name = name; self.symbol = symbol; self.layout = layout
            self.pinned = pinned; self.isActive = isActive; self.windowCount = windowCount
            self.isTrailingEmpty = isTrailingEmpty
        }
    }

    public struct WindowRow: Codable, Sendable, Equatable {
        public var window: WindowRef        // { id, pid }
        public var pid: Int32               // duplicated flat for scripting convenience
        /// nil = ephemeral visitor (no workspace membership).
        public var workspaceId: UUID?
        public var title: String
        public var appName: String
        public var bundleID: String?
        public var isFocused: Bool
        /// The layout would show it. Hidden → false; floating → true; tiled → the layout gives
        /// slot i a frame. Not "is on screen right now" — a display can be missing mid-hot-plug.
        public var isVisibleUnderLayout: Bool
        public var isFloating: Bool
        public var isHidden: Bool

        public init(
            window: WindowRef, pid: Int32, workspaceId: UUID?, title: String, appName: String,
            bundleID: String?, isFocused: Bool, isVisibleUnderLayout: Bool, isFloating: Bool,
            isHidden: Bool
        ) {
            self.window = window; self.pid = pid; self.workspaceId = workspaceId
            self.title = title; self.appName = appName; self.bundleID = bundleID
            self.isFocused = isFocused; self.isVisibleUnderLayout = isVisibleUnderLayout
            self.isFloating = isFloating; self.isHidden = isHidden
        }
    }

    public struct ScreenRow: Codable, Sendable, Equatable {
        public var display: DisplayID
        public var frame: RectDTO?          // nil while the display is absent from the topology
        public var visibleFrame: RectDTO?
        public var isMain: Bool
        public var isFocused: Bool
        public var isCoveredByFullscreen: Bool
        public var insets: EdgeInsetsDTO
        public var activeWorkspaceId: UUID?
        public var workspaces: [WorkspaceRow]
        /// Rows for **all** workspaces of this screen, not only the active one.
        public var windows: [WindowRow]

        public init(
            display: DisplayID, frame: RectDTO?, visibleFrame: RectDTO?, isMain: Bool,
            isFocused: Bool, isCoveredByFullscreen: Bool, insets: EdgeInsetsDTO,
            activeWorkspaceId: UUID?, workspaces: [WorkspaceRow], windows: [WindowRow]
        ) {
            self.display = display; self.frame = frame; self.visibleFrame = visibleFrame
            self.isMain = isMain; self.isFocused = isFocused
            self.isCoveredByFullscreen = isCoveredByFullscreen; self.insets = insets
            self.activeWorkspaceId = activeWorkspaceId; self.workspaces = workspaces
            self.windows = windows
        }
    }

    public struct FocusRow: Codable, Sendable, Equatable {
        public var screen: DisplayID
        public var window: WindowRef?
        public init(screen: DisplayID, window: WindowRef?) {
            self.screen = screen; self.window = window
        }
    }

    public struct ChromeRow: Codable, Sendable, Equatable {
        public var panelWidth: Double
        public var panelHeight: Double
        public var railSide: String
        public var launcherURL: String
        public var showPanels: Bool
        public init(
            panelWidth: Double, panelHeight: Double, railSide: String,
            launcherURL: String, showPanels: Bool
        ) {
            self.panelWidth = panelWidth; self.panelHeight = panelHeight; self.railSide = railSide
            self.launcherURL = launcherURL
            self.showPanels = showPanels
        }
    }

    public var v: Int                       // == IPCProtocol.version
    public var generation: UInt64           // monotonic per publish; subscribers drop stale
    public var screens: [ScreenRow]         // in world.screenOrder
    public var focus: FocusRow
    public var zen: Bool
    public var capabilities: [String]
    public var locked: Bool
    public var chrome: ChromeRow

    public init(
        v: Int, generation: UInt64, screens: [ScreenRow], focus: FocusRow, zen: Bool,
        capabilities: [String], locked: Bool, chrome: ChromeRow
    ) {
        self.v = v; self.generation = generation; self.screens = screens; self.focus = focus
        self.zen = zen; self.capabilities = capabilities
        self.locked = locked; self.chrome = chrome
    }

    /// Equality ignoring `generation` — the publisher's dedupe key.
    public func isEquivalent(to other: ShellSnapshot) -> Bool {
        var lhs = self
        var rhs = other
        lhs.generation = 0
        rhs.generation = 0
        return lhs == rhs
    }
}
