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

/// NOT YET EMITTED: the subscribe/push channel is M2 T12; no server constructs this yet.
public struct IPCEvent: Codable, Sendable, Equatable {
    public var v: Int
    public var event: String
    public var data: JSONValue
    public init(v: Int, event: String, data: JSONValue) {
        self.v = v; self.event = event; self.data = data
    }
}
