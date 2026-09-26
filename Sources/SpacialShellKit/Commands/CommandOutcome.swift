import Foundation
import SpacialShellProtocol

/// #109, M2 ruling "Error channel": why a command could not run. A failure means the command named
/// something that is not there (or the store refused it); a command that is valid but has nothing
/// to do is a `CommandReport.noop`, not an error.
public enum CommandError: Error, Sendable, Hashable, CustomStringConvertible {
    /// A 1-based index (`focus-workspace-9` on a three-row display) or a workspace id.
    case unknownWorkspace(String)
    case unknownWindow(WindowRef)
    case noFocusedWindow
    case unknownScreen
    /// Spec §7.7: the screen is locked; the store makes no model changes.
    case locked

    /// Stable, kebab-case: the IPC reply's `error` code.
    public var code: String {
        switch self {
        case .unknownWorkspace: "unknown-workspace"
        case .unknownWindow: "unknown-window"
        case .noFocusedWindow: "no-focused-window"
        case .unknownScreen: "unknown-screen"
        case .locked: "locked"
        }
    }

    public var description: String {
        switch self {
        case .unknownWorkspace(let w): "unknown workspace \(w)"
        case .unknownWindow(let r): "window \(r.id) not found"
        case .noFocusedWindow: "no focused window"
        case .unknownScreen: "no focused screen"
        case .locked: "the screen is locked"
        }
    }
}

/// What `WorldStore.run` reports back: hotkeys ignore it, `spacialctl run` prints it.
public enum CommandReport: Sendable, Hashable {
    case done
    case noop(String)
    case failed(CommandError)

    /// The IPC `run` reply: `data.outcome` is always there (`ok` / `noop` / `failed`); a no-op adds
    /// `reason`, a failure is `ok: false` with the message in `error` and its code in `data.error`.
    public func response(id: Int) -> IPCResponse {
        switch self {
        case .done: .ok(id: id, data: .object(["outcome": .string("ok")]))
        case .noop(let reason): .ok(id: id, data: .object(["outcome": .string("noop"), "reason": .string(reason)]))
        case .failed(let e):
            IPCResponse(id: id, v: IPCProtocol.version, ok: false,
                        data: .object(["outcome": .string("failed"), "error": .string(e.code)]),
                        error: e.description)
        }
    }
}

/// `CommandRunner.run`'s result: the next world, the effects, and the report.
public struct CommandOutcome: Sendable, Equatable {
    public var world: World
    public var effects: [Effect]
    public var report: CommandReport
}
