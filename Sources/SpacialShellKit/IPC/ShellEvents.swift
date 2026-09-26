import Foundation
import SpacialShellProtocol

/// #117 (G36): what changed between two published snapshots, as the typed `IPCEvent`s a
/// `subscribe` connection streams. Pure: the IPC queue runs it once per publish, never the store.
///
/// Additive to the wire: `v` stays `IPCProtocol.version`; a client ignores event names it does not
/// know. Titles ride along (the panels show them, and the socket is 0600, user-owned); telemetry
/// never sees them — no span is opened here.
public enum ShellEvents {
    /// The baseline a new subscriber gets once, before any delta: the full snapshot.
    public static func baseline(_ snapshot: ShellSnapshot) -> IPCEvent {
        event("shell", snapshot)
    }

    /// Order: workspaces, then windows, then focus — a bar that redraws on `focus-changed` already
    /// knows the window it points at.
    public static func diff(from old: ShellSnapshot, to new: ShellSnapshot) -> [IPCEvent] {
        var events: [IPCEvent] = []
        let oldScreens = Dictionary(old.screens.map { ($0.display, $0) }, uniquingKeysWith: { a, _ in a })
        for screen in new.screens {
            let before = oldScreens[screen.display]
            if before?.activeWorkspaceId != screen.activeWorkspaceId, let id = screen.activeWorkspaceId {
                let ws = screen.workspaces.first { $0.id == id }
                events.append(event("workspace-activated", Activated(
                    display: screen.display, workspace: id, name: ws?.name, symbol: ws?.symbol,
                    previous: before?.activeWorkspaceId)))
            }
            if before?.workspaces != screen.workspaces {
                events.append(event("workspaces-changed", WorkspacesChanged(
                    display: screen.display, workspaces: screen.workspaces)))
            }
        }

        let oldRows = rows(old), newRows = rows(new)
        for (display, row) in newRows.values.sorted(by: { $0.row.window.id < $1.row.window.id }) {
            guard let (oldDisplay, was) = oldRows[row.window] else {
                events.append(event("window-adopted", Located(display: display, window: row)))
                continue
            }
            if was.workspaceId != row.workspaceId || oldDisplay != display {
                events.append(event("window-moved", Moved(
                    window: row.window, from: was.workspaceId, to: row.workspaceId,
                    fromDisplay: oldDisplay, display: display)))
            }
            if was.title != row.title {
                events.append(event("window-title-changed", Titled(window: row.window, title: row.title)))
            }
        }
        for (_, row) in oldRows.values.sorted(by: { $0.row.window.id < $1.row.window.id })
        where newRows[row.window] == nil {
            events.append(event("window-closed", Closed(window: row.window, pid: row.pid)))
        }

        if old.focus != new.focus {
            let row = new.focus.window.flatMap { newRows[$0]?.row }
            events.append(event("focus-changed", Focus(
                display: new.focus.screen, window: new.focus.window, workspaceId: row?.workspaceId,
                title: row?.title, appName: row?.appName, bundleID: row?.bundleID)))
        }
        return events
    }

    // MARK: payloads (encoded with sorted keys, nil fields omitted)

    struct Activated: Encodable { let display: DisplayID, workspace: UUID, name: String?, symbol: String?, previous: UUID? }
    struct WorkspacesChanged: Encodable { let display: DisplayID, workspaces: [ShellSnapshot.WorkspaceRow] }
    struct Located: Encodable { let display: DisplayID, window: ShellSnapshot.WindowRow }
    struct Moved: Encodable { let window: WindowRef, from: UUID?, to: UUID?, fromDisplay: DisplayID, display: DisplayID }
    struct Titled: Encodable { let window: WindowRef, title: String }
    struct Closed: Encodable { let window: WindowRef, pid: Int32 }
    struct Focus: Encodable {
        let display: DisplayID, window: WindowRef?, workspaceId: UUID?, title: String?, appName: String?, bundleID: String?
    }

    private static func rows(_ s: ShellSnapshot) -> [WindowRef: (display: DisplayID, row: ShellSnapshot.WindowRow)] {
        Dictionary(s.screens.flatMap { screen in screen.windows.map { ($0.window, (screen.display, $0)) } },
                   uniquingKeysWith: { a, _ in a })
    }

    private static func event<T: Encodable>(_ name: String, _ payload: T) -> IPCEvent {
        IPCEvent(v: IPCProtocol.version, event: name, data: (try? JSONValue(encoding: payload)) ?? .null)
    }
}
