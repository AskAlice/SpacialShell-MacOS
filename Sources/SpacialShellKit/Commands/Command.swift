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

    // Shell-UI verbs (M2). The keyboard verbs above are relative to the focused screen; a panel
    // click names its target outright — the rail on a second screen must work without moving
    // focus there first.
    case activateWorkspace(DisplayID, Int) // rail click; 0-based index into that screen's stack
    case selectWindow(WindowRef)           // tab click
    case setLayout(DisplayID, Layout)      // layout switcher; applies to that screen's active workspace
    case closeWindow(WindowRef)            // tab close button
}

public enum Effect: Sendable, Equatable {
    case focus(WindowRef)
    case close(WindowRef)
    case relayout
}
