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
    case toggleShellUI                     // Zen mode: hide/show the shell panels
    case focusScreen(Neighbor)
    case moveWindowToScreen(Neighbor)
    case toggleFloat
    case openSettings

    // Shell-UI verbs (M2 design §Decisions: distinct base names, payloads Hashable). The keyboard
    // verbs above are relative to the focused screen; a panel click or IPC call names its target
    // outright — the rail on a second screen must work without moving focus there first.
    case focusWorkspaceID(UUID)            // rail click; workspace by id, wherever it lives
    case focusWindowRef(WindowRef)         // tab click / overview selection
    case setWorkspaceLayout(UUID, Layout)  // layout switcher; targets that workspace directly
    case closeWindowRef(WindowRef)         // tab close button
    case toggleOverview                    // overview/launcher overlay; app-layer surface, not a World mutation
}

public enum Effect: Sendable, Equatable {
    case focus(WindowRef)
    case close(WindowRef)
    case relayout
}
