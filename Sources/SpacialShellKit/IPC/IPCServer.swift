import Foundation
import Darwin
import OpenTelemetryApi
import SpacialShellProtocol
import os

/// v0 control socket: one NDJSON `IPCRequest` per line, one `IPCResponse` back, over a unix
/// socket at `IPCProtocol.defaultSocketPath()` (0600). Enough for `spacialctl` and Raycast.
/// ponytail: blocking write(2) for replies, unconditional stale unlink — replaced by the full M2
/// IPCServer (SnapshotHub, NWListener) when Tasks 9–13 land.
///
/// #117: `subscribe` turns a connection into an event stream — an ok reply, one `shell` baseline
/// event (the full snapshot), then only the typed deltas `ShellEvents.diff` finds per publish.
/// Back-pressure: subscriber sockets are non-blocking with a large send buffer; a write that would
/// block or lands short drops the subscriber (deltas cannot be coalesced, and a torn line is
/// useless). It reconnects and gets a fresh baseline. The store only ever enqueues.
public final class IPCServer: @unchecked Sendable {
    private static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "ipc")
    private let path: String
    private let handle: @Sendable (IPCRequest) async -> IPCResponse
    private let queue = DispatchQueue(label: "sh.emu.SpacialShell.ipc")
    private var listenFD: Int32 = -1
    private var acceptSource: (any DispatchSourceRead)?
    private var readers: [Int32: (source: any DispatchSourceRead, framer: LineFramer)] = [:]
    private var subscribers: Set<Int32> = []
    /// The last snapshot `publish` accepted: the next diff's base and a new subscriber's baseline.
    private var lastSnapshot: ShellSnapshot?
    /// Kernel buffer per subscriber — the whole queue a slow client gets before it is dropped.
    private let subscriberSendBuffer: Int32

    public init(path: String = IPCProtocol.defaultSocketPath(), subscriberSendBuffer: Int32 = 1 << 20,
         handle: @escaping @Sendable (IPCRequest) async -> IPCResponse) {
        self.path = path
        self.subscriberSendBuffer = subscriberSendBuffer
        self.handle = handle
    }

    public func start() throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let ok = path.utf8CString.withUnsafeBufferPointer { src -> Bool in
            guard src.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
            withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyMemory(from: UnsafeRawBufferPointer(src)) }
            return true
        }
        guard ok else { close(fd); throw POSIXError(.ENAMETOOLONG) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let e = errno; close(fd); throw POSIXError(.init(rawValue: e) ?? .EIO)
        }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.resume()
        acceptSource = source
        Self.log.info("ipc listening at \(self.path, privacy: .public)")
    }

    public func stop() {
        queue.sync {
            acceptSource?.cancel(); acceptSource = nil
            for (fd, r) in readers { r.source.cancel(); close(fd) }
            readers = [:]
            subscribers = []
            if listenFD >= 0 { close(listenFD); listenFD = -1 }
            unlink(path)
        }
    }

    // MARK: queue only

    private func acceptOne() {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readSome(fd) }
        source.setCancelHandler { close(fd) }
        // The registration is what makes the connection live: `readSome` and `send` both refuse
        // fds they don't know. (Regression guard: an "autofix" once deleted this line while adding
        // SO_NOSIGPIPE above, which turned every spacialctl call into an eternal hang —
        // `IPCServerTests.roundTrip` pins it, with a recv timeout so the failure is loud.)
        readers[fd] = (source, LineFramer())
        source.resume()
    }

    private func readSome(_ fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 8192)
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { return dropConnection(fd) }
        guard var entry = readers[fd] else { return }
        let outcome = entry.framer.push(Data(buf[0..<n]))
        readers[fd] = entry
        guard case .lines(let lines) = outcome else { return dropConnection(fd) }
        for line in lines {
            let request = try? IPCCodec.decoder.decode(IPCRequest.self, from: line)
            if let request, request.cmd == "subscribe" { subscribe(fd, id: request.id); continue }
            Task { [handle] in
                // #83: one root span per request. `cmd` is one of a handful of verbs; the args
                // (a command name at most) are not recorded.
                let span = Telemetry.tracer().spanBuilder(spanName: "ipc.request").setNoParent().startSpan()
                span.setAttribute(key: "ipc.cmd", value: request?.cmd ?? "invalid")
                let response: IPCResponse =
                    if let request { await handle(request) } else { .failure(id: 0, "invalid request") }
                span.end()
                self.send(response, to: fd)
            }
        }
    }

    private nonisolated func send(_ response: IPCResponse, to fd: Int32) {
        guard let data = try? IPCCodec.line(response) else { return }
        queue.async {
            guard self.readers[fd] != nil else { return }
            if self.subscribers.contains(fd) { return self.writeOrDrop(data, to: fd) }
            _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        }
    }

    private func dropConnection(_ fd: Int32) {
        subscribers.remove(fd)
        readers.removeValue(forKey: fd)?.source.cancel()
    }

    // MARK: subscribe (#117)

    /// Called with every snapshot the store publishes; returns at once. Stale or repeated
    /// generations are ignored, so a late hop cannot rewind the diff base.
    public func publish(_ snapshot: ShellSnapshot) {
        queue.async {
            if let last = self.lastSnapshot, snapshot.generation <= last.generation { return }
            let previous = self.lastSnapshot
            self.lastSnapshot = snapshot
            guard let previous, !self.subscribers.isEmpty else { return }
            var data = Data()
            for event in ShellEvents.diff(from: previous, to: snapshot) {
                if let line = try? IPCCodec.line(event) { data.append(line) }
            }
            guard !data.isEmpty else { return }
            for fd in self.subscribers { self.writeOrDrop(data, to: fd) }
        }
    }

    private func subscribe(_ fd: Int32, id: Int) {
        let span = Telemetry.tracer().spanBuilder(spanName: "ipc.request").setNoParent().startSpan()
        span.setAttribute(key: "ipc.cmd", value: "subscribe")
        defer { span.end() }
        guard readers[fd] != nil, !subscribers.contains(fd) else { return }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var size = subscriberSendBuffer
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout.size(ofValue: size)))
        subscribers.insert(fd)
        var data = (try? IPCCodec.line(IPCResponse.ok(id: id))) ?? Data()
        if let last = lastSnapshot, let line = try? IPCCodec.line(ShellEvents.baseline(last)) { data.append(line) }
        writeOrDrop(data, to: fd)
    }

    /// Never blocks: the fd is non-blocking, and anything short of the whole buffer drops the client.
    private func writeOrDrop(_ data: Data, to fd: Int32) {
        let n = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if n != data.count {
            Self.log.info("ipc subscriber dropped (slow or gone)")
            dropConnection(fd)
        }
    }
}
