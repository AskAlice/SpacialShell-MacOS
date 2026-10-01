import Testing
import Foundation
@testable import SpacialShellProtocol

/// `spacialctl`'s command line → the request it puts on the wire (#131 adds `focus-workspace`,
/// `quit` and `call`; the older subcommands must send exactly what they always did).
@Suite struct SpacialCtlCommandLineTests {
    func req(_ args: String...) -> IPCRequest? { SpacialCtlCommandLine.request(args) }

    @Test func existingSubcommandsAreUnchanged() {
        #expect(req("version") == IPCRequest(id: 1, cmd: "version"))
        #expect(req("state") == IPCRequest(id: 1, cmd: "state"))
        #expect(req("subscribe") == IPCRequest(id: 1, cmd: "subscribe"))
        #expect(req("run", "focus-workspace-2") == IPCRequest(id: 1, cmd: "run", args: ["command": .string("focus-workspace-2")]))
        #expect(req("run", "switch", "42") == IPCRequest(id: 1, cmd: "run", args: ["command": .string("switch 42")]))
        #expect(req("set-layout", "grid") == IPCRequest(id: 1, cmd: "set-layout", args: ["layout": .string("grid")]))
        #expect(req("set-layout", "grid", "--workspace", "W") ==
                IPCRequest(id: 1, cmd: "set-layout", args: ["layout": .string("grid"), "workspace": .string("W")]))
        // #198: "change-layout" is the name it goes by; it sends the same request.
        #expect(req("change-layout", "grid") == req("set-layout", "grid"))
        #expect(req("change-layout", "grid", "--workspace", "W") == req("set-layout", "grid", "--workspace", "W"))
    }

    /// #199: a window by app and/or title, with `--index N` or `--first` for several.
    @Test func focusWindowByAppAndTitle() {
        #expect(req("focus-window", "--app", "brave", "--title", "pull requests") ==
                IPCRequest(id: 1, cmd: "focus-window", args: ["app": .string("brave"), "title": .string("pull requests")]))
        #expect(req("focus-window", "--title", "zsh", "--index", "2") ==
                IPCRequest(id: 1, cmd: "focus-window", args: ["title": .string("zsh"), "index": .int(2)]))
        #expect(req("focus-window", "--app", "brave", "--first") ==
                IPCRequest(id: 1, cmd: "focus-window", args: ["app": .string("brave"), "first": .bool(true)]))
        #expect(req("focus-window") == nil)                                  // nothing to find it by
        #expect(req("focus-window", "--index", "2") == nil)
        #expect(req("focus-window", "--app") == nil)                         // a flag without its value
        #expect(req("focus-window", "--app", "x", "--index", "zero") == nil)
        #expect(req("focus-window", "--app", "x", "--color", "red") == nil)
    }

    @Test func focusWorkspaceAndQuit() {
        let id = UUID().uuidString
        #expect(req("focus-workspace", id) == IPCRequest(id: 1, cmd: "focus-workspace", args: ["workspace": .string(id)]))
        // Not validated here: the daemon's "unknown workspace" is the one answer for a bad id.
        #expect(req("focus-workspace", "nope")?.args["workspace"] == .string("nope"))
        #expect(req("quit") == IPCRequest(id: 1, cmd: "quit"))
        #expect(req("reload") == IPCRequest(id: 1, cmd: "reload"))   // #194
    }

    /// #196
    @Test func karabinerRulesPrintsOrWrites() {
        #expect(req("karabiner-rules") == IPCRequest(id: 1, cmd: "karabiner-rules"))
        #expect(req("karabiner-rules", "--write") == IPCRequest(id: 1, cmd: "karabiner-rules", args: ["write": .bool(true)]))
        #expect(req("karabiner-rules", "--force") == nil)
    }

    @Test func callSendsAnyVerbWithItsArgs() {
        #expect(req("call", "version") == IPCRequest(id: 1, cmd: "version"))
        let sent = req("call", "move-window", #"{"window":{"id":42,"pid":501},"workspace":"W","follow":false}"#)
        #expect(sent == IPCRequest(id: 1, cmd: "move-window", args: [
            "window": .object(["id": .int(42), "pid": .int(501)]), "workspace": .string("W"), "follow": .bool(false),
        ]))
    }

    @Test func usageErrors() {
        #expect(req() == nil)
        #expect(req("teleport") == nil)
        #expect(req("run") == nil)
        #expect(req("focus-workspace") == nil)
        #expect(req("focus-workspace", "a", "b") == nil)
        #expect(req("call") == nil)
        #expect(req("call", "x", "not json") == nil)
        #expect(req("call", "x", "[1,2]") == nil)          // args are an object
        #expect(req("set-layout", "grid", "--screen", "D") == nil)
    }

    /// What each subcommand sends survives the codec unchanged.
    @Test func requestsRoundTripTheWire() throws {
        for args in [["quit"], ["focus-workspace", UUID().uuidString], ["call", "set-category", #"{"workspace":"W","category":null}"#]] {
            let request = try #require(SpacialCtlCommandLine.request(args))
            let line = try IPCCodec.line(request)
            #expect(line.last == 0x0A && line.dropLast().firstIndex(of: 0x0A) == nil)
            #expect(try IPCCodec.decoder.decode(IPCRequest.self, from: line) == request)
        }
    }
}
