import Foundation

public enum Vertical: Sendable, Hashable { case up, down }
public enum Horizontal: Sendable, Hashable { case left, right }
public enum Neighbor: Sendable, Hashable { case prev, next }

public enum Command: Sendable, Hashable {
    case focusWorkspace(Vertical)
    case focusWorkspaceIndex(Int)          // 1-based; Fn+0 → 10
    case focusWindow(Horizontal)
    case closeFocusedWindow
    case moveWindow(Horizontal)
    case moveWindowToWorkspace(Vertical)
    case cycleLayout
    case toggleShellUI                     // reserved; no-op in M1
    case focusScreen(Neighbor)
    case moveWindowToScreen(Neighbor)
    case toggleFloat
}

public enum Effect: Sendable, Equatable {
    case focus(WindowRef)
    case close(WindowRef)
    case relayout
}
