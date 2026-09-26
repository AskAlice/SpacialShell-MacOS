import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

/// #131 (M3 B8): the socket's verb table — id-addressed verbs, `quit`, `focus-workspace` by id,
/// and `capabilities` naming exactly what is answered. Pure: the store is `CommandRunner` over a
/// world held here, the app layer a recorder.
@Suite struct IPCDispatchTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), c = WindowRef(id: 3, pid: 2)

    /// D1 holds [a b] and twelve pinned rows (so index 11+ exists); D2 holds [c].
    func world() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .column)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1"); w.adopt(c, kind: .tile, on: "D2")
        for i in 2...12 {
            let rows = w.screens["D1"]!.workspaces.count
            w.screens["D1"]!.workspaces.insert(Workspace(name: "W\(i)", layout: .column, pinned: true), at: rows - 1)
        }
        w.focus = Focus(screen: "D1", window: a)
        return w
    }

    final class Harness: @unchecked Sendable {
        private let lock = NSLock()
        private var _world: World
        private var _routed: [Command] = []
        init(_ world: World) { _world = world }
        var world: World { lock.withLock { _world } }
        var routed: [Command] { lock.withLock { _routed } }

        var dispatch: IPCDispatch {
            IPCDispatch(
                version: "test",
                wireState: { WireState(world: self.world) },
                run: { command in
                    self.lock.withLock {
                        let outcome = CommandRunner.run(command, on: self._world)
                        self._world = outcome.world
                        return outcome.report
                    }
                },
                route: { command in self.lock.withLock { self._routed.append(command) } })
        }
    }

    func request(_ cmd: String, _ args: [String: JSONValue] = [:]) -> IPCRequest { IPCRequest(id: 5, cmd: cmd, args: args) }
    func window(_ r: WindowRef) -> JSONValue { .object(["id": .int(Int(r.id)), "pid": .int(Int(r.pid))]) }

    // MARK: - command mapping

    @Test func everyIdVerbMapsToItsShellCommand() throws {
        let ws = UUID(), onto = WindowRef(id: 9, pid: 4)
        let expected: [(String, [String: JSONValue], Command)] = [
            ("focus-workspace", ["workspace": .string(ws.uuidString)], .focusWorkspaceID(ws)),
            ("focus-window", ["window": window(a)], .focusWindowRef(a)),
            ("close-window", ["window": window(a)], .closeWindowRef(a)),
            ("toggle-float", ["window": window(a)], .toggleFloatRef(a)),
            ("recover-window", ["window": window(a)], .recoverWindow(a)),
            ("move-window", ["window": window(a), "workspace": .string(ws.uuidString)],
             .moveWindowRefToWorkspace(a, ws, follow: true)),
            ("move-window", ["window": window(a), "workspace": .string(ws.uuidString), "follow": .bool(false)],
             .moveWindowRefToWorkspace(a, ws, follow: false)),
            ("move-window-before", ["window": window(a), "before": window(onto)], .moveWindowRefBefore(a, onto)),
            ("move-window-before", ["window": window(a)], .moveWindowRefBefore(a, nil)),
            ("move-window-before", ["window": window(a), "before": .null], .moveWindowRefBefore(a, nil)),
            ("move-app", ["window": window(a), "workspace": .string(ws.uuidString)], .moveAppRefToWorkspace(a, ws)),
            ("swap-window", ["window": window(a), "onto": window(onto)], .dropWindow(a, onto: onto)),
            ("move-workspace", ["workspace": .string(ws.uuidString), "index": .int(2)], .moveWorkspace(ws, toIndex: 2)),
            ("remove-workspace", ["workspace": .string(ws.uuidString)], .removeWorkspace(ws)),
            ("set-symbol", ["workspace": .string(ws.uuidString), "symbol": .string("star")], .setWorkspaceSymbol(ws, "star")),
            ("set-category", ["workspace": .string(ws.uuidString), "category": .string("coding")],
             .setWorkspaceCategory(ws, .coding)),
            ("set-category", ["workspace": .string(ws.uuidString), "category": .null], .setWorkspaceCategory(ws, nil)),
            ("set-split-columns", ["workspace": .string(ws.uuidString), "columns": .int(3)], .setSplitColumns(ws, 3)),
        ]
        for (cmd, args, command) in expected {
            #expect(IPCDispatch.command(for: request(cmd, args)) == .success(command), "\(cmd) \(args)")
        }
        // Every id verb is covered above.
        #expect(Set(expected.map(\.0)) == Set(IPCDispatch.idVerbs.keys))
        #expect(IPCDispatch.command(for: request("state")) == nil)
    }

    /// Args arrive through JSON: the mapping sees what the wire decodes, not a hand-built tree.
    @Test func argsSurviveTheWire() throws {
        let ws = UUID()
        let line = Data(#"{"id":3,"cmd":"move-window","args":{"window":{"id":42,"pid":501},"workspace":"\#(ws.uuidString)","follow":false}}"#.utf8)
        let decoded = try IPCCodec.decoder.decode(IPCRequest.self, from: line)
        #expect(IPCDispatch.command(for: decoded) == .success(.moveWindowRefToWorkspace(WindowRef(id: 42, pid: 501), ws, follow: false)))
        #expect(try IPCCodec.decoder.decode(IPCRequest.self, from: IPCCodec.line(decoded)) == decoded)
    }

    @Test func aMissingOrIllTypedArgumentIsNamed() {
        func refusal(_ cmd: String, _ args: [String: JSONValue]) -> IPCRefusal? {
            if case .failure(let r)? = IPCDispatch.command(for: request(cmd, args)) { return r }
            return nil
        }
        #expect(refusal("focus-workspace", [:]) == .badArgs("focus-workspace needs workspace (a workspace id from `state`)"))
        #expect(refusal("focus-workspace", ["workspace": .int(3)]) == .badArgs("focus-workspace needs workspace (a workspace id from `state`)"))
        #expect(refusal("focus-window", [:]) == .badArgs(#"focus-window needs window {"id": <window id>, "pid": <pid>}"#))
        #expect(refusal("focus-window", ["window": .object(["id": .int(-1), "pid": .int(1)])]) != nil)
        #expect(refusal("swap-window", ["window": window(a)]) == .badArgs(#"swap-window needs onto {"id": <window id>, "pid": <pid>}"#))
        let ws = JSONValue.string(UUID().uuidString)
        #expect(refusal("move-window", ["window": window(a), "workspace": ws, "follow": .string("yes")])
                == .badArgs("move-window: follow must be true or false"))
        #expect(refusal("set-split-columns", ["workspace": ws]) == .badArgs("set-split-columns needs columns (an integer)"))
        #expect(refusal("set-symbol", ["workspace": ws, "symbol": .string("")]) == .badArgs("set-symbol needs symbol (a string)"))
        // A forgotten category must not clear one: only an explicit null does.
        #expect(refusal("set-category", ["workspace": ws])?.isBadArgs == true)
        #expect(refusal("set-category", ["workspace": ws, "category": .string("games")])?.isBadArgs == true)
    }

    /// B1 (#109): an id that names nothing is `unknown-workspace`, whether it is malformed or stale.
    @Test func anUnknownWorkspaceIdIsTheB1Error() async throws {
        let h = Harness(world())
        let stale = UUID().uuidString
        for id in ["not-a-uuid", stale] {
            let reply = await h.dispatch.handle(request("focus-workspace", ["workspace": .string(id)])).response
            #expect(!reply.ok && reply.id == 5)
            #expect(reply.data?["outcome"]?.stringValue == "failed")
            #expect(reply.data?["error"]?.stringValue == "unknown-workspace")
            #expect(reply.error == "unknown workspace \(id)")
            #expect(reply.cliOutput.code == 1)
        }
        let ghost = await h.dispatch.handle(request("focus-window", ["window": window(WindowRef(id: 77, pid: 7))])).response
        #expect(ghost.data?["error"]?.stringValue == "unknown-window")
    }

    // MARK: - focus-workspace: any row, any display

    /// The Raycast `switch` bug (de-gap-analysis §C): past 10 there was no `focus-workspace-N`, and
    /// only the focused display's rows were reachable. By id, both are.
    @Test func focusWorkspaceReachesRowElevenAndUpAndOtherDisplays() async throws {
        let h = Harness(world())
        let twelfth = h.world.screens["D1"]!.workspaces[11].id
        let reply = await h.dispatch.handle(request("focus-workspace", ["workspace": .string(twelfth.uuidString)])).response
        #expect(reply.ok && reply.data?["outcome"]?.stringValue == "ok")
        #expect(h.world.screens["D1"]!.activeIndex == 11)

        let other = h.world.screens["D2"]!.workspaces[0].id
        _ = await h.dispatch.handle(request("focus-workspace", ["workspace": .string(other.uuidString)]))
        #expect(h.world.focus.screen == "D2" && h.world.focus.window == c)
    }

    // MARK: - quit

    @Test func quitRepliesFirstAndRoutesThroughTheGateAfter() async throws {
        let h = Harness(world())
        let reply = await h.dispatch.handle(request("quit"))
        #expect(reply.response.ok && reply.response.data?["outcome"]?.stringValue == "ok")
        #expect(h.routed.isEmpty)                  // nothing yet: the reply is not on the wire
        let after = try #require(reply.afterSend)
        after()
        #expect(h.routed == [.quit])
        #expect(!KeyBindings.commandNames.keys.contains("quit"))   // not a hotkey, not `run quit`
    }

    @Test func runStillRoutesAppLayerCommandsAndRunsModelOnes() async throws {
        let h = Harness(world())
        let overview = await h.dispatch.handle(request("run", ["command": .string("toggle-overview")])).response
        #expect(overview.ok && h.routed == [.toggleOverview])
        let right = await h.dispatch.handle(request("run", ["command": .string("focus-window-right")])).response
        #expect(right.ok && h.world.focus.window == b)
        let bad = await h.dispatch.handle(request("run", ["command": .string("nope")])).response
        #expect(!bad.ok && bad.error == "unknown command \"nope\"")
    }

    // MARK: - capabilities

    /// `capabilities` is exactly the verbs answered plus the payload features: every listed verb
    /// gets an answer other than "unknown cmd", and an unlisted one gets exactly that.
    @Test func capabilitiesAreTruthful() async throws {
        let caps = WireState.capabilities
        #expect(Set(caps) == Set(IPCDispatch.verbs + WireState.features))
        #expect(caps.count == Set(caps).count)
        let h = Harness(world())
        for verb in IPCDispatch.verbs where verb != "subscribe" {   // `subscribe`: IPCServer's own (IPCServerTests)
            let reply = await h.dispatch.handle(request(verb)).response
            #expect(reply.error?.hasPrefix("unknown cmd") != true, "\(verb) is listed but not answered")
        }
        let unknown = await h.dispatch.handle(request("teleport")).response
        #expect(!unknown.ok && unknown.error == "unknown cmd teleport")
        #expect(!caps.contains("teleport"))
        // The state payload carries the same list the snapshot feed does.
        #expect(WireState(world: world()).capabilities == caps)
    }

    @Test func versionAndStateAnswer() async throws {
        let h = Harness(world())
        let version = await h.dispatch.handle(request("version")).response
        #expect(version.data?["version"]?.stringValue == "test")
        let state = await h.dispatch.handle(request("state")).response
        let decoded = try #require(state.data).decode(WireState.self)
        #expect(decoded.screens.count == 2 && decoded.capabilities.contains("focus-workspace"))
    }
}

extension IPCRefusal {
    var isBadArgs: Bool { if case .badArgs = self { true } else { false } }
}
