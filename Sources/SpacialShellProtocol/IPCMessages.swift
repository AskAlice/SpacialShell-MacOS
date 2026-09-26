import Foundation
import Darwin

public enum IPCProtocol {
    public static let version = 1
    public static let maxRequestBytes = 64 * 1024
    public static let socketFileName = "spacialshell.sock"

    /// `~/Library/Application Support/SpacialShell/spacialshell.sock`, or
    /// `/tmp/spacialshell-<uid>.sock` when that would exceed `sun_path`'s 104 bytes.
    public static func defaultSocketPath() -> String {
        let preferred = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpacialShell/\(socketFileName)")
            .path
        return preferred.utf8.count < 104 ? preferred : "/tmp/spacialshell-\(getuid()).sock"
    }
}

public struct IPCRequest: Codable, Sendable, Equatable {
    public var id: Int
    public var cmd: String
    public var args: [String: JSONValue]
    public init(id: Int, cmd: String, args: [String: JSONValue] = [:]) {
        self.id = id; self.cmd = cmd; self.args = args
    }
}

public struct IPCResponse: Codable, Sendable, Equatable {
    public var id: Int
    public var v: Int
    public var ok: Bool
    public var data: JSONValue?
    public var error: String?

    public init(id: Int, v: Int, ok: Bool, data: JSONValue? = nil, error: String? = nil) {
        self.id = id; self.v = v; self.ok = ok; self.data = data; self.error = error
    }

    public static func ok(id: Int, data: JSONValue? = nil) -> IPCResponse {
        IPCResponse(id: id, v: IPCProtocol.version, ok: true, data: data)
    }

    public static func failure(id: Int, _ message: String) -> IPCResponse {
        IPCResponse(id: id, v: IPCProtocol.version, ok: false, error: message)
    }
}

/// One line of a `subscribe` stream (#117): `event` names the change, `data` its payload.
/// See docs/ipc.md for the event table. Distinguished from an `IPCResponse` by having `event`.
public struct IPCEvent: Codable, Sendable, Equatable {
    public var v: Int
    public var event: String
    public var data: JSONValue
    public init(v: Int, event: String, data: JSONValue) {
        self.v = v; self.event = event; self.data = data
    }
}

/// #109: what `spacialctl` prints for a reply and the code it exits with — 0 ok, 1 the daemon
/// returned an error. A `run` reply (`data.outcome`) prints nothing when the command ran, the
/// reason on stderr when it was a no-op (still 0: nothing went wrong), and the error when it failed.
public struct CLIOutput: Equatable, Sendable {
    public var code: Int32
    public var stdout: String?
    public var stderr: String?
    public init(code: Int32, stdout: String? = nil, stderr: String? = nil) {
        self.code = code; self.stdout = stdout; self.stderr = stderr
    }
}

extension IPCResponse {
    public var cliOutput: CLIOutput {
        guard ok else { return CLIOutput(code: 1, stderr: "spacialctl: \(error ?? "unknown error")") }
        switch data?["outcome"]?.stringValue {
        case "ok": return CLIOutput(code: 0)
        case "noop": return CLIOutput(code: 0, stderr: "spacialctl: nothing to do: \(data?["reason"]?.stringValue ?? "no-op")")
        default:
            guard let data, let out = try? IPCCodec.encoder.encode(data) else { return CLIOutput(code: 0) }
            return CLIOutput(code: 0, stdout: String(decoding: out, as: UTF8.self))
        }
    }
}
