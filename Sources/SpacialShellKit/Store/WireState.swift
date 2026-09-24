import Foundation

/// `spacialctl state` payload — workspaces, and since v2 the windows in them.
/// ponytail: superseded by ShellSnapshot (M2 Task 8), which adds titles/appNames/chrome.
public struct WireState: Codable, Equatable, Sendable {
    /// One managed window, as the model sees it (#57). Counts alone could not answer the question
    /// that mattered — *which* window is where, and is it parked — so diagnosing a window that
    /// holds focus while sitting off-screen meant reading the window server instead of asking the
    /// shell. `isParked` and `frame` are the store's own view, not AX's: when they disagree with
    /// reality, that disagreement is the bug.
    public struct WindowDTO: Codable, Equatable, Sendable {
        public var id: WindowID
        public var pid: Int32
        public var bundleID: String?
        public var isFocused: Bool
        public var isFloating: Bool
        public var isHidden: Bool
        public var isFullscreen: Bool
        public var isOffSpace: Bool
        public var isParked: Bool
        public var frame: [Double]?      // x, y, w, h — the last frame the backend observed
    }
    public struct WorkspaceDTO: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String, symbol: String, layout: String
        public var pinned: Bool, isActive: Bool
        public var windowCount: Int
        public var windows: [WindowDTO]
    }
    public struct ScreenDTO: Codable, Equatable, Sendable {
        public var display: String
        public var isFocused: Bool
        public var activeIndex: Int
        public var workspaces: [WorkspaceDTO]
    }
    public var v: Int = 2
    public var capabilities: [String] = ["run", "state", "version", "window-rows"]
    public var screens: [ScreenDTO]

    /// `bundleIDs`, `parked` and `observed` are the store's side tables; a caller without them
    /// still gets every workspace, just with anonymous windows.
    public init(world: World, bundleIDs: [WindowRef: String] = [:],
                parked: Set<WindowRef> = [], observed: [WindowRef: CGRect] = [:]) {
        screens = world.screenOrder.compactMap { id in
            guard let s = world.screens[id] else { return nil }
            return ScreenDTO(
                display: id, isFocused: id == world.focus.screen, activeIndex: s.activeIndex,
                workspaces: s.workspaces.enumerated().map { i, ws in
                    WorkspaceDTO(id: ws.id, name: ws.name, symbol: ws.symbol, layout: ws.layout.rawValue,
                                 pinned: ws.pinned, isActive: i == s.activeIndex, windowCount: ws.windows.count,
                                 windows: ws.windows.map { w in
                                     WindowDTO(id: w.id, pid: w.pid, bundleID: bundleIDs[w],
                                               isFocused: world.focus.window == w,
                                               isFloating: ws.floating.contains(w),
                                               isHidden: world.hidden.contains(w),
                                               isFullscreen: world.fullscreen.contains(w),
                                               isOffSpace: world.offSpace.contains(w),
                                               isParked: parked.contains(w),
                                               frame: observed[w].map { [$0.minX, $0.minY, $0.width, $0.height] })
                                 })
                })
        }
    }
}
