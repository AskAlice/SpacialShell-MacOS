import Testing
import Foundation
import Darwin
import SpacialShellProtocol
@testable import SpacialShellKit

@Suite struct IPCServerTests {
    /// Full round-trip over a real unix socket: connect, one request per line, one response back.
    @Test func roundTrip() async throws {
        let path = "/tmp/spacialshell-test-\(UUID().uuidString.prefix(8)).sock"
        let server = IPCServer(path: path) { request in
            request.cmd == "ping"
                ? .ok(id: request.id, data: .object(["pong": .bool(true)]))
                : .failure(id: request.id, "unknown cmd")
        }
        try server.start()
        defer { server.stop() }

        @Sendable func askBlocking(_ request: IPCRequest) throws -> IPCResponse {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            defer { close(fd) }
            // A server that accepts but never answers (the readers-registration regression) must
            // fail this test in seconds, not hang it: the recv timeout turns silence into n <= 0,
            // which `#require(n > 0)` reports.
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            path.utf8CString.withUnsafeBufferPointer { src in
                withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyMemory(from: UnsafeRawBufferPointer(src)) }
            }
            let rc = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            #expect(rc == 0)
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

        func ask(_ request: IPCRequest) async throws -> IPCResponse { try await offPool { try askBlocking(request) } }

        let ok = try await ask(IPCRequest(id: 7, cmd: "ping"))
        #expect(ok.ok && ok.id == 7 && ok.data?["pong"]?.boolValue == true)
        let bad = try await ask(IPCRequest(id: 8, cmd: "nope"))
        #expect(!bad.ok && bad.error == "unknown cmd")
    }
}

/// Runs a blocking call (a socket `read`) on a GCD thread. Blocking a cooperative-pool thread
/// instead can starve the task that has to answer it: on a 3-core CI runner the server's reply
/// then waits out the 5 s receive timeout and the round-trip tests fail.
func offPool<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { done in
        DispatchQueue.global().async { done.resume(with: Result { try body() }) }
    }
}
