import Foundation

/// v0 `spacialctl state` payload — workspaces only, no window rows.
/// ponytail: superseded by ShellSnapshot (M2 Task 8), which adds titles/appNames/chrome.
public struct WireState: Codable, Equatable, Sendable {
    public struct WorkspaceDTO: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String, symbol: String, layout: String
        public var pinned: Bool, isActive: Bool
        public var windowCount: Int
    }
    public struct ScreenDTO: Codable, Equatable, Sendable {
        public var display: String
        public var isFocused: Bool
        public var activeIndex: Int
        public var workspaces: [WorkspaceDTO]
    }
    public var v: Int = 1
    public var capabilities: [String] = ["run"]
    public var screens: [ScreenDTO]

    public init(world: World) {
        screens = world.screenOrder.compactMap { id in
            guard let s = world.screens[id] else { return nil }
            return ScreenDTO(
                display: id, isFocused: id == world.focus.screen, activeIndex: s.activeIndex,
                workspaces: s.workspaces.enumerated().map { i, ws in
                    WorkspaceDTO(id: ws.id, name: ws.name, symbol: ws.symbol, layout: ws.layout.rawValue,
                                 pinned: ws.pinned, isActive: i == s.activeIndex, windowCount: ws.windows.count)
                })
        }
    }
}
