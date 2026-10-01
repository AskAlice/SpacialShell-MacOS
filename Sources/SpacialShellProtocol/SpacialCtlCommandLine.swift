import Foundation

/// `spacialctl`'s argument grammar: a command line → the one request it sends, or nil for a usage
/// error (exit 2). Pure, so the wire each subcommand produces is tested without a socket.
public enum SpacialCtlCommandLine {
    public static let usage = """
    usage: spacialctl [--socket PATH] <subcommand>
      version              daemon version
      state                spatial model as JSON
      run <command-name>   run a bound command, e.g. `run focus-workspace-2`; a command that
                           fails (unknown workspace, no focused window, ...) exits 1
      set-layout <id> [--workspace <uuid>]
                           set a workspace's layout (default: the focused one); unknown ids exit 1
      focus-workspace <uuid>
                           switch to a workspace by id, on whichever display holds it; an unknown
                           id exits 1
      quit                 quit the shell the way the rail menu does: every window is put back
      reload               quit as above, then start the same SpacialShell.app again
      reset-state          delete the saved state (state.json); the windows stay where they are,
                           nothing more is saved, and the next launch starts fresh
      call <cmd> [<json-object>]
                           send any socket verb with its args, e.g.
                           call move-window '{"window":{"id":42,"pid":501},"workspace":"<uuid>"}'
      karabiner-rules [--write]
                           SpacialShell's hotkeys as a Karabiner-Elements rules file (JSON), so they
                           work in password fields; --write saves it to Karabiner's
                           assets/complex_modifications/spacialshell.json
      subscribe            stream events, one JSON object per line: a `shell` snapshot first, then
                           only changes (workspace-activated, focus-changed, window-adopted, ...)
    """

    public static func request(_ args: [String]) -> IPCRequest? {
        switch args.first {
        case "version": return IPCRequest(id: 1, cmd: "version")
        case "state": return IPCRequest(id: 1, cmd: "state")
        case "subscribe": return IPCRequest(id: 1, cmd: "subscribe")
        case "quit": return IPCRequest(id: 1, cmd: "quit")
        case "reload": return IPCRequest(id: 1, cmd: "reload")   // #194
        case "reset-state": return IPCRequest(id: 1, cmd: "reset-state")   // #139
        case "karabiner-rules" where args.count == 1: return IPCRequest(id: 1, cmd: "karabiner-rules")   // #196
        case "karabiner-rules" where args == ["karabiner-rules", "--write"]:
            return IPCRequest(id: 1, cmd: "karabiner-rules", args: ["write": .bool(true)])
        // #109: extra words are passed through, so `run switch 42` is the daemon's clear "unknown command".
        case "run" where args.count >= 2:
            return IPCRequest(id: 1, cmd: "run", args: ["command": .string(args.dropFirst().joined(separator: " "))])
        case "set-layout" where args.count == 2:
            return IPCRequest(id: 1, cmd: "set-layout", args: ["layout": .string(args[1])])
        case "set-layout" where args.count == 4 && args[2] == "--workspace":
            return IPCRequest(id: 1, cmd: "set-layout", args: ["layout": .string(args[1]), "workspace": .string(args[3])])
        // #131: passed through unparsed — an id that is not a UUID is the daemon's "unknown workspace".
        case "focus-workspace" where args.count == 2:
            return IPCRequest(id: 1, cmd: "focus-workspace", args: ["workspace": .string(args[1])])
        case "call" where args.count == 2:
            return IPCRequest(id: 1, cmd: args[1])
        case "call" where args.count == 3:
            guard case .object(let object)? = try? IPCCodec.decoder.decode(JSONValue.self, from: Data(args[2].utf8))
            else { return nil }
            return IPCRequest(id: 1, cmd: args[1], args: object)
        default: return nil
        }
    }
}
