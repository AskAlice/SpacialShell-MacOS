import Foundation
import SpacialShellProtocol

/// What a request handler gives `IPCServer`: the reply, and anything that must wait until the
/// reply is on the wire. `quit` needs that: the termination gate stops the server, and a reply
/// sent after that point would never arrive. `afterSend` runs on the server's queue, so it must
/// hand off (as `route(.quit)` does, to the gate's queue) rather than call `stop()` itself.
public struct IPCReply: Sendable {
    public var response: IPCResponse
    public var afterSend: (@Sendable () -> Void)?
    public init(_ response: IPCResponse, afterSend: (@Sendable () -> Void)? = nil) {
        self.response = response; self.afterSend = afterSend
    }
}

/// Why an id-addressed verb was not run. `badArgs` is the caller's mistake (a missing or ill-typed
/// argument): `ok: false` and a message naming it. `failed` names something that is not there: the
/// same B1 reply (#109) the store gives, so a malformed id and a well-formed stale one look alike.
public enum IPCRefusal: Error, Equatable, Sendable {
    case badArgs(String)
    case failed(CommandError)

    public func response(id: Int) -> IPCResponse {
        switch self {
        case .badArgs(let message): .failure(id: id, message)
        case .failed(let error): CommandReport.failed(error).response(id: id)
        }
    }
}

/// The control socket's verb table (#131, M3 B8). The handler `AppRuntime` gives `IPCServer`, kept
/// here so the table can be tested and `capabilities` can be built from it rather than kept in step
/// by hand. `subscribe` is the one verb the server answers itself: it changes what the connection is.
///
/// The id-addressed verbs are the shell's own ones (a rail click, a tab drag) given wire names. They
/// name their target outright, so they work on any display without moving focus first. The store
/// checks every id inside `CommandRunner`, so a race with a keystroke ends in a clean
/// `unknown-workspace` / `unknown-window` error, never a different target.
public struct IPCDispatch: Sendable {
    public var version: String
    public var wireState: @Sendable () async -> WireState
    /// `WorldStore.run`: model commands, awaited so a `state` straight after sees their effect.
    public var run: @Sendable (Command) async -> CommandReport
    /// The app-layer route (#88): overview, settings, the layout surfaces, quit.
    public var route: @Sendable (Command) -> Void
    /// #139: the settings window's "Reset saved state…", by another door; returns what happened.
    public var resetState: @Sendable () async -> String
    /// #196: `write` false, the Karabiner rules file as JSON; true, it is written and the reply
    /// says where. Throws what went wrong.
    public var karabinerRules: @Sendable (_ write: Bool) async throws -> JSONValue

    public init(version: String, wireState: @escaping @Sendable () async -> WireState,
                run: @escaping @Sendable (Command) async -> CommandReport,
                route: @escaping @Sendable (Command) -> Void,
                resetState: @escaping @Sendable () async -> String = { "not running" },
                karabinerRules: @escaping @Sendable (Bool) async throws -> JSONValue = { _ in .null }) {
        self.version = version; self.wireState = wireState; self.run = run; self.route = route
        self.resetState = resetState; self.karabinerRules = karabinerRules
    }

    /// The verbs `handle` answers, plus `subscribe`. Order is the wire's: older verbs first.
    public static let verbs: [String] = ["run", "state", "version", "subscribe", "set-layout", "quit", "reset-state", "karabiner-rules", "reload"] + idVerbs.keys.sorted()

    public func handle(_ request: IPCRequest) async -> IPCReply {
        let id = request.id
        switch request.cmd {
        case "version":
            return IPCReply(.ok(id: id, data: .object(["version": .string(version)])))
        case "state":
            return IPCReply(.ok(id: id, data: (try? JSONValue(encoding: await wireState())) ?? .null))
        case "run":
            let name = request.args["command"]?.stringValue ?? ""
            guard let command = KeyBindings.command(named: name)
            else { return IPCReply(.failure(id: id, "unknown command \"\(name)\"")) }
            // #88: exactly like a hotkey. App-layer commands go to their controllers (the store
            // would drop them). #109: the reply carries the store's report.
            if command.isAppLayer { route(command); return IPCReply(CommandReport.done.response(id: id)) }
            return IPCReply(await run(command).response(id: id))
        case "set-layout":
            // #10, design §6: refuses an id the catalogue does not know (spacialctl exits 1).
            switch await wireState().setLayout(request.args["layout"]?.stringValue,
                                               workspace: request.args["workspace"]?.stringValue) {
            case .success(let command): return IPCReply(await run(command).response(id: id))
            case .failure(let refusal): return IPCReply(.failure(id: id, refusal.message))
            }
        case "reset-state":
            return IPCReply(.ok(id: id, data: .object(["message": .string(await resetState())])))
        case "karabiner-rules":
            do { return IPCReply(.ok(id: id, data: try await karabinerRules(request.args["write"]?.boolValue == true))) }
            catch { return IPCReply(.failure(id: id, error.localizedDescription)) }
        case "quit":
            // Through the termination gate, like the rail's Quit (spec §7.4), but only once the
            // reply is written: the gate's first step stops this server.
            return IPCReply(CommandReport.done.response(id: id)) { [route] in route(.quit) }
        case "reload":
            // #194: the same, then the bundle starts again.
            return IPCReply(CommandReport.done.response(id: id)) { [route] in route(.reload) }
        default:
            switch Self.command(for: request) {
            case nil: return IPCReply(.failure(id: id, "unknown cmd \(request.cmd)"))
            case .failure(let refusal)?: return IPCReply(refusal.response(id: id))
            case .success(let command)?: return IPCReply(await run(command).response(id: id))
            }
        }
    }

    /// An id-addressed request as the command it runs; nil when `cmd` is not one of them. Pure: it
    /// checks the arguments' shape, and the store checks that what they name exists.
    public static func command(for request: IPCRequest) -> Result<Command, IPCRefusal>? {
        guard let make = idVerbs[request.cmd] else { return nil }
        do { return .success(try make(Args(verb: request.cmd, values: request.args))) }
        catch let refusal as IPCRefusal { return .failure(refusal) }
        catch { return .failure(.badArgs("\(request.cmd): \(error)")) }
    }

    /// Wire name → command. Windows are `{"id": <CGWindowID>, "pid": <pid>}`, as in `state` and the
    /// event stream; workspaces are the uuid strings `state` lists.
    static let idVerbs: [String: @Sendable (Args) throws -> Command] = [
        "focus-workspace": { .focusWorkspaceID(try $0.workspace()) },
        "focus-window": { .focusWindowRef(try $0.window()) },
        "close-window": { .closeWindowRef(try $0.window()) },
        "toggle-float": { .toggleFloatRef(try $0.window()) },
        "recover-window": { .recoverWindow(try $0.window()) },
        "move-window": { a in
            .moveWindowRefToWorkspace(try a.window(), try a.workspace(), follow: try a.bool("follow") ?? true)
        },
        "move-window-before": { .moveWindowRefBefore(try $0.window(), try $0.window("before", optional: true)) },
        "move-app": { .moveAppRefToWorkspace(try $0.window(), try $0.workspace()) },
        "swap-window": { .dropWindow(try $0.window(), onto: try $0.window("onto")) },
        "move-workspace": { .moveWorkspace(try $0.workspace(), toIndex: try $0.int("index")) },
        "remove-workspace": { .removeWorkspace(try $0.workspace()) },
        "set-symbol": { .setWorkspaceSymbol(try $0.workspace(), try $0.string("symbol")) },
        "set-category": { .setWorkspaceCategory(try $0.workspace(), try $0.category()) },
        "set-split-columns": { .setSplitColumns(try $0.workspace(), try $0.int("columns")) },
    ]

    /// Typed reads of one request's args; every miss is a `badArgs` naming the argument.
    struct Args {
        let verb: String
        let values: [String: JSONValue]

        func workspace() throws -> UUID {
            guard let text = values["workspace"]?.stringValue
            else { throw IPCRefusal.badArgs("\(verb) needs workspace (a workspace id from `state`)") }
            guard let id = UUID(uuidString: text) else { throw IPCRefusal.failed(.unknownWorkspace(text)) }
            return id
        }

        func window(_ key: String = "window") throws -> WindowRef {
            guard let window = try window(key, optional: false) else { throw IPCRefusal.badArgs("\(verb) needs \(key)") }
            return window
        }

        /// Absent or null is nil when `optional`; anything else must be `{"id": n, "pid": n}`.
        func window(_ key: String, optional: Bool) throws -> WindowRef? {
            let value = values[key]
            if optional, value == nil || value == .null { return nil }
            guard let id = value?["id"]?.intValue.flatMap(WindowID.init(exactly:)),
                  let pid = value?["pid"]?.intValue.flatMap(Int32.init(exactly:))
            else { throw IPCRefusal.badArgs("\(verb) needs \(key) {\"id\": <window id>, \"pid\": <pid>}") }
            return WindowRef(id: id, pid: pid)
        }

        func int(_ key: String) throws -> Int {
            guard let n = values[key]?.intValue else { throw IPCRefusal.badArgs("\(verb) needs \(key) (an integer)") }
            return n
        }

        func string(_ key: String) throws -> String {
            guard let s = values[key]?.stringValue, !s.isEmpty
            else { throw IPCRefusal.badArgs("\(verb) needs \(key) (a string)") }
            return s
        }

        func bool(_ key: String) throws -> Bool? {
            guard let value = values[key], value != .null else { return nil }
            guard let b = value.boolValue else { throw IPCRefusal.badArgs("\(verb): \(key) must be true or false") }
            return b
        }

        /// Required, so a forgotten argument cannot clear a category: `null` clears it.
        func category() throws -> AppCategory? {
            let known = AppCategory.allCases.map(\.rawValue).joined(separator: ", ")
            guard let value = values["category"]
            else { throw IPCRefusal.badArgs("\(verb) needs category (one of \(known), or null to clear)") }
            if value == .null { return nil }
            guard let name = value.stringValue, let category = AppCategory(rawValue: name)
            else { throw IPCRefusal.badArgs("unknown category \(value.stringValue.map { "\"\($0)\"" } ?? "value") (known: \(known))") }
            return category
        }
    }
}
