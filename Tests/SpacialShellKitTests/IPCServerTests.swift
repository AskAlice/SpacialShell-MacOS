import Testing
import Foundation
import Darwin
import SpacialShellProtocol
@testable import SpacialShellKit

@Suite struct IPCServerTests {
    /// Full round-trip over a real unix socket: connect, one request per line, one response back.
    @Test func roundTrip() async throws {
        let path = testSocketPath()
        let server = IPCServer(path: path) { request in
            request.cmd == "ping"
                ? .ok(id: request.id, data: .object(["pong": .bool(true)]))
                : .failure(id: request.id, "unknown cmd")
        }
        try server.start()
        defer { server.stop() }

        let ok = try await ask(path, IPCRequest(id: 7, cmd: "ping"))
        #expect(ok.ok && ok.id == 7 && ok.data?["pong"]?.boolValue == true)
        let bad = try await ask(path, IPCRequest(id: 8, cmd: "nope"))
        #expect(!bad.ok && bad.error == "unknown cmd")
    }

    // MARK: - #131: one shell per socket

    /// Probe before unlink: a second server on a live socket refuses, and the first keeps it.
    @Test func aSecondServerRefusesALiveSocket() async throws {
        let path = testSocketPath()
        let first = IPCServer(path: path) { .ok(id: $0.id, data: .string("first")) }
        try first.start()
        defer { first.stop() }
        #expect(IPCServer.isAnswering(path: path))

        let second = IPCServer(path: path) { .ok(id: $0.id, data: .string("second")) }
        #expect(throws: IPCServerError.alreadyRunning(path)) { try second.start() }
        let reply = try await ask(path, IPCRequest(id: 1, cmd: "who"))
        #expect(reply.data?.stringValue == "first")
    }

    /// A socket file nobody listens on (the shell crashed) is stale: replaced, not refused.
    @Test func aStaleSocketFileIsReplaced() async throws {
        let path = testSocketPath()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = unixAddress(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        try #require(bound == 0)
        close(fd)   // bound, never listening: the file stays behind
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(!IPCServer.isAnswering(path: path))

        let server = IPCServer(path: path) { .ok(id: $0.id) }
        try server.start()
        defer { server.stop() }
        #expect(try await ask(path, IPCRequest(id: 2, cmd: "x")).ok)
    }

    @Test func nothingAtThePathIsNotAnswering() {
        #expect(!IPCServer.isAnswering(path: testSocketPath()))
    }

    /// `quit`'s shape: the reply's after-step stops the server (the termination gate's first move).
    /// The reply still arrives, because the after-step runs only once it is written.
    @Test func theReplyLandsBeforeItsAfterStep() async throws {
        let path = testSocketPath()
        let box = ServerBox()
        let server = IPCServer(path: path, reply: { request in
            IPCReply(.ok(id: request.id, data: .string("bye"))) {
                // As the gate does it: another queue, never the IPC queue it runs on.
                DispatchQueue.global().async { box.server?.stop() }
            }
        })
        box.server = server
        try server.start()
        defer { server.stop() }

        let reply = try await ask(path, IPCRequest(id: 4, cmd: "quit"))
        #expect(reply.ok && reply.id == 4 && reply.data?.stringValue == "bye")
        // Then the server is gone: its socket file is unlinked.
        let deadline = Date().addingTimeInterval(5)
        while FileManager.default.fileExists(atPath: path), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}

final class ServerBox: @unchecked Sendable { var server: IPCServer? }

/// A short, unique path: `sun_path` is 104 bytes and suites run in parallel.
func testSocketPath() -> String { "/tmp/spacialshell-test-\(UUID().uuidString.prefix(8)).sock" }

func unixAddress(_ path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    path.utf8CString.withUnsafeBufferPointer { src in
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyMemory(from: UnsafeRawBufferPointer(src)) }
    }
    return addr
}

/// One request, one reply, over a fresh connection — off the cooperative pool.
func ask(_ path: String, _ request: IPCRequest) async throws -> IPCResponse {
    try await offPool { try askBlocking(path, request) }
}

func askBlocking(_ path: String, _ request: IPCRequest) throws -> IPCResponse {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    // A server that accepts but never answers (the readers-registration regression) must fail the
    // test in bounded time, not hang it: the recv timeout turns silence into n <= 0, which
    // `#require(n > 0)` reports.
    var tv = socketTestReceiveTimeout
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var addr = unixAddress(path)
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    try #require(rc == 0)
    let line = try IPCCodec.line(request)
    _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    var framer = LineFramer(), buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fd, &buf, buf.count)
        try #require(n > 0)
        if case .lines(let lines) = framer.push(Data(buf[0..<n])), let first = lines.first {
            return try IPCCodec.decoder.decode(IPCResponse.self, from: first)
        }
    }
}

/// Runs a blocking call (a socket `read`) on a GCD thread. Blocking a cooperative-pool thread
/// instead can starve the task that has to answer it: on a 3-core CI runner the server's reply
/// then waits out the receive timeout and the round-trip tests fail.
func offPool<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { done in
        DispatchQueue.global().async { done.resume(with: Result { try body() }) }
    }
}
