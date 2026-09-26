import Testing
import Foundation
import Darwin
import SpacialShellProtocol
@testable import SpacialShellKit

/// #117 (G36): the subscribe stream — the pure snapshot diff, its wire encoding, and a socket
/// round trip including the slow-client drop.
@Suite struct ShellEventsTests {
    static let ws1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let ws2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let a = WindowRef(id: 1, pid: 10), b = WindowRef(id: 2, pid: 10)

    /// One display, two workspaces; `windows` maps each window to its workspace and title.
    static func snapshot(generation: UInt64 = 1, active: UUID = ws1,
                         windows: [(WindowRef, UUID, String)] = [], focus: WindowRef? = nil) -> ShellSnapshot {
        let rows = windows.map { w, ws, title in
            ShellSnapshot.WindowRow(window: w, pid: w.pid, workspaceId: ws, title: title, appName: "Terminal",
                                    bundleID: "com.x", isFocused: w == focus, isVisibleUnderLayout: ws == active,
                                    isFloating: false, isHidden: false)
        }
        let workspaces = [(ws1, "one"), (ws2, "two")].map { id, name in
            ShellSnapshot.WorkspaceRow(id: id, name: name, symbol: "terminal", layout: .maximize, pinned: false,
                                       isActive: id == active, windowCount: rows.filter { $0.workspaceId == id }.count,
                                       isTrailingEmpty: false)
        }
        let screen = ShellSnapshot.ScreenRow(
            display: "D1", frame: nil, visibleFrame: nil, isMain: true, isFocused: true, isCoveredByFullscreen: false,
            insets: EdgeInsetsDTO(top: 0, left: 0, right: 0, bottom: 0), activeWorkspaceId: active,
            workspaces: workspaces, windows: rows)
        return ShellSnapshot(
            v: IPCProtocol.version, generation: generation, screens: [screen],
            focus: .init(screen: "D1", window: focus), zen: false, capabilities: WireState.capabilities,
            locked: false,
            chrome: .init(panelWidth: 0, panelHeight: 0, railSide: "left", launcherURL: "", showPanels: true))
    }

    // MARK: diff (pure)

    @Test func nothingChangedMeansNoEvents() {
        let s = Self.snapshot(windows: [(a, Self.ws1, "zsh")], focus: a)
        var later = s; later.generation = 9
        #expect(ShellEvents.diff(from: s, to: later).isEmpty)
    }

    @Test func adoptionAndCloseAreEvents() throws {
        let before = Self.snapshot(windows: [(a, Self.ws1, "zsh")])
        let after = Self.snapshot(windows: [(b, Self.ws1, "vim")])
        let events = ShellEvents.diff(from: before, to: after)
        // One in, one out: the workspace's count is unchanged, so no `workspaces-changed`.
        try #require(events.map(\.event) == ["window-adopted", "window-closed"])
        #expect(events.allSatisfy { $0.v == IPCProtocol.version })
        let adopted = events[0].data
        #expect(adopted["display"]?.stringValue == "D1")
        #expect(adopted["window"]?["title"]?.stringValue == "vim")
        #expect(adopted["window"]?["window"]?["id"]?.intValue == 2)
        #expect(events[1].data["window"]?["id"]?.intValue == 1 && events[1].data["pid"]?.intValue == 10)
    }

    @Test func switchingWorkspaceAndFocusComeInOrder() throws {
        let before = Self.snapshot(windows: [(a, Self.ws1, "zsh"), (b, Self.ws2, "vim")], focus: a)
        let after = Self.snapshot(active: Self.ws2, windows: [(a, Self.ws1, "zsh"), (b, Self.ws2, "vim")], focus: b)
        let events = ShellEvents.diff(from: before, to: after)
        // `isVisibleUnderLayout` flips too, but that is not an event of its own.
        try #require(events.map(\.event) == ["workspace-activated", "workspaces-changed", "focus-changed"])
        let activated = events[0].data
        #expect(activated["workspace"]?.uuidValue == Self.ws2 && activated["previous"]?.uuidValue == Self.ws1)
        #expect(activated["name"]?.stringValue == "two")
        let focus = events[2].data
        #expect(focus["window"]?["id"]?.intValue == 2 && focus["title"]?.stringValue == "vim")
        #expect(focus["workspaceId"]?.uuidValue == Self.ws2 && focus["display"]?.stringValue == "D1")
    }

    @Test func focusLostOmitsTheWindow() throws {
        let before = Self.snapshot(windows: [(a, Self.ws1, "zsh")], focus: a)
        let after = Self.snapshot(windows: [(a, Self.ws1, "zsh")], focus: nil)
        let events = ShellEvents.diff(from: before, to: after)
        try #require(events.map(\.event) == ["focus-changed"])
        #expect(events[0].data["window"] == nil && events[0].data["title"] == nil)
    }

    @Test func movesAndTitleChanges() throws {
        let before = Self.snapshot(windows: [(a, Self.ws1, "zsh")])
        let after = Self.snapshot(windows: [(a, Self.ws2, "zsh — ~/code")])
        let events = ShellEvents.diff(from: before, to: after)
        try #require(events.map(\.event) == ["workspaces-changed", "window-moved", "window-title-changed"])
        #expect(events[1].data["from"]?.uuidValue == Self.ws1 && events[1].data["to"]?.uuidValue == Self.ws2)
        #expect(events[2].data["title"]?.stringValue == "zsh — ~/code")
    }

    // MARK: encoding

    @Test func anEventIsOneSortedLine() throws {
        let events = ShellEvents.diff(from: Self.snapshot(), to: Self.snapshot(windows: [(a, Self.ws1, "a\nb")]))
        let line = try IPCCodec.line(try #require(events.last))
        #expect(line.filter { $0 == 0x0A }.count == 1 && line.last == 0x0A)   // the title's newline is escaped
        let text = String(decoding: line, as: UTF8.self)
        #expect(text.hasPrefix(#"{"data":"#) && text.contains(#""event":"window-adopted","v":1}"#))
        #expect(try IPCCodec.decoder.decode(IPCEvent.self, from: line.dropLast()) == events.last)
        // The baseline is the whole snapshot, decodable as one.
        let baseline = ShellEvents.baseline(Self.snapshot(generation: 4))
        #expect(baseline.event == "shell")
        #expect(try baseline.data.decode(ShellSnapshot.self).generation == 4)
    }

    // MARK: socket

    final class Client {
        let fd: Int32
        var framer = LineFramer(maxLineBytes: 1 << 22)
        var queued: [Data] = []
        init(path: String, receiveBuffer: Int32? = nil) throws {
            fd = socket(AF_UNIX, SOCK_STREAM, 0)
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            if var size = receiveBuffer {
                _ = setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
            }
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
            try #require(rc == 0)
        }
        deinit { close(fd) }
        func send(_ request: IPCRequest) throws {
            let line = try IPCCodec.line(request)
            _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        }
        /// The next line, or nil on EOF / timeout.
        func next() -> Data? {
            var buf = [UInt8](repeating: 0, count: 65536)
            while queued.isEmpty {
                let n = read(fd, &buf, buf.count)
                guard n > 0, case .lines(let lines) = framer.push(Data(buf[0..<n])) else { return nil }
                queued = lines
            }
            return queued.removeFirst()
        }
        func event() throws -> IPCEvent { try IPCCodec.decoder.decode(IPCEvent.self, from: try #require(next())) }
    }

    static func server(sendBuffer: Int32 = 1 << 20) throws -> (IPCServer, String) {
        let path = "/tmp/spacialshell-test-\(UUID().uuidString.prefix(8)).sock"
        let server = IPCServer(path: path, subscriberSendBuffer: sendBuffer) { request in
            request.cmd == "ping" ? .ok(id: request.id, data: .string("pong")) : .failure(id: request.id, "unknown cmd")
        }
        try server.start()
        return (server, path)
    }

    @Test func subscribeStreamsABaselineThenOnlyChanges() throws {
        let (server, path) = try Self.server()
        defer { server.stop() }
        server.publish(Self.snapshot(generation: 1, windows: [(a, Self.ws1, "zsh")], focus: a))

        let sub = try Client(path: path)
        try sub.send(IPCRequest(id: 3, cmd: "subscribe"))
        let reply = try IPCCodec.decoder.decode(IPCResponse.self, from: try #require(sub.next()))
        #expect(reply.ok && reply.id == 3)
        let baseline = try sub.event()
        let base = try baseline.data.decode(ShellSnapshot.self)
        #expect(baseline.event == "shell" && base.generation == 1)

        // A stale generation is ignored; a repeat of the same state sends nothing; a real change sends its delta.
        server.publish(Self.snapshot(generation: 0, windows: [], focus: nil))
        server.publish(Self.snapshot(generation: 2, windows: [(a, Self.ws1, "zsh")], focus: a))
        server.publish(Self.snapshot(generation: 3, windows: [(a, Self.ws1, "zsh")], focus: nil))
        let focus = try sub.event()
        #expect(focus.event == "focus-changed" && focus.data["window"] == nil)

        // Other connections still get plain request/response while a subscriber is open.
        let plain = try Client(path: path)
        try plain.send(IPCRequest(id: 4, cmd: "ping"))
        let pong = try IPCCodec.decoder.decode(IPCResponse.self, from: try #require(plain.next()))
        #expect(pong.data?.stringValue == "pong")
    }

    @Test func aSlowSubscriberIsDroppedNotWaitedFor() throws {
        let (server, path) = try Self.server(sendBuffer: 8192)
        defer { server.stop() }
        let many = (1...200).map { i in WindowRef(id: WindowID(i), pid: 10) }
        let long = String(repeating: "x", count: 1024)
        server.publish(Self.snapshot(generation: 1))

        let sub = try Client(path: path, receiveBuffer: 8192)
        try sub.send(IPCRequest(id: 1, cmd: "subscribe"))
        // Never read while ~200 KB per publish is produced: the server must not block (this test
        // would hang) and must not buffer without bound — it closes the connection.
        for g in 2...20 {
            server.publish(Self.snapshot(generation: UInt64(g), windows: many.map { ($0, Self.ws1, "\(g)\(long)") }))
        }
        var lines = 0
        while sub.next() != nil { lines += 1 }
        var byte: UInt8 = 0
        #expect(read(sub.fd, &byte, 1) == 0)                  // EOF, not the 5 s timeout
        #expect(lines < 19 * 200)                             // it did not get everything
    }
}
