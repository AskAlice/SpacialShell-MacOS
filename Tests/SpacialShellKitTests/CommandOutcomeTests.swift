import Testing
import Foundation
import Darwin
import SpacialShellProtocol
@testable import SpacialShellKit

/// #109: the command-error half of the error channel — what a command reports, what the IPC
/// `run` reply carries, and what `spacialctl` prints and exits with.
@Suite struct CommandOutcomeTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), ghost = WindowRef(id: 99, pid: 9)
    func base() -> World {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        return w   // focus a on D1[0]; D1 has rows [a b] and the trailing "+"
    }
    func report(_ c: Command, _ w: World? = nil) -> CommandReport { CommandRunner.run(c, on: w ?? base()).report }

    @Test func aCommandThatRanIsDone() {
        #expect(report(.focusWindow(.right)) == .done)
        #expect(report(.focusWorkspaceIndex(2)) == .done)
        #expect(report(.cycleLayout) == .done)
    }

    @Test func namingSomethingThatIsNotThereFails() {
        #expect(report(.focusWorkspaceIndex(9)) == .failed(.unknownWorkspace("9")))
        let id = UUID()
        #expect(report(.focusWorkspaceID(id)) == .failed(.unknownWorkspace(id.uuidString)))
        #expect(report(.setWorkspaceLayout(id, .grid)) == .failed(.unknownWorkspace(id.uuidString)))
        #expect(report(.focusWindowRef(ghost)) == .failed(.unknownWindow(ghost)))
        #expect(report(.dropWindow(ghost, onto: a)) == .failed(.unknownWindow(ghost)))
        #expect(report(.moveWindowToWorkspaceIndex(0)) == .failed(.unknownWorkspace("0")))
    }

    @Test func aFocusCommandWithNothingFocusedFails() {
        var w = base(); w.focus.window = nil
        #expect(report(.closeFocusedWindow, w) == .failed(.noFocusedWindow))
        #expect(report(.toggleFloat, w) == .failed(.noFocusedWindow))
        #expect(report(.moveWindowToWorkspace(.down), w) == .failed(.noFocusedWindow))
    }

    @Test func aValidCommandWithNothingToDoIsANoopWithItsReason() {
        #expect(report(.focusWorkspace(.up)) == .noop("already on the top workspace"))
        #expect(report(.focusWorkspaceIndex(1)) == .noop("already on workspace 1"))
        #expect(report(.moveWindow(.left)) == .noop("already at the left edge"))
        #expect(report(.moveWindowRefBefore(b, nil)) == .noop("the tab is already there"))
        #expect(report(.toggleOverview) == .noop("nothing to do"))   // app-layer: the model's fallback
    }

    @Test func aFailureChangesNothingAndApplyIsTheSameShim() {
        let w0 = base()   // one world: `base()` mints fresh workspace ids
        let o = CommandRunner.run(.focusWorkspaceIndex(9), on: w0)
        #expect(o.world == w0 && o.effects.isEmpty)
        let (w, e) = CommandRunner.apply(.focusWindow(.right), to: w0)
        let r = CommandRunner.run(.focusWindow(.right), on: w0)
        #expect(w == r.world && e == r.effects)
    }

    // MARK: - the IPC reply

    @Test func replyShapeCarriesTheOutcome() {
        #expect(CommandReport.done.response(id: 3) == .ok(id: 3, data: .object(["outcome": .string("ok")])))
        let noop = CommandReport.noop("already on workspace 1").response(id: 4)
        #expect(noop.ok && noop.data?["outcome"]?.stringValue == "noop"
                && noop.data?["reason"]?.stringValue == "already on workspace 1")
        let failed = CommandReport.failed(.unknownWorkspace("42")).response(id: 5)
        #expect(!failed.ok && failed.id == 5 && failed.error == "unknown workspace 42")
        #expect(failed.data?["outcome"]?.stringValue == "failed" && failed.data?["error"]?.stringValue == "unknown-workspace")
    }

    @Test func spacialctlExitsNonZeroOnlyOnFailure() {
        #expect(CommandReport.done.response(id: 1).cliOutput == CLIOutput(code: 0))
        #expect(CommandReport.noop("only one display").response(id: 1).cliOutput
                == CLIOutput(code: 0, stderr: "spacialctl: nothing to do: only one display"))
        #expect(CommandReport.failed(.unknownWorkspace("42")).response(id: 1).cliOutput
                == CLIOutput(code: 1, stderr: "spacialctl: unknown workspace 42"))
        #expect(IPCResponse.failure(id: 1, "unknown command \"switch 42\"").cliOutput
                == CLIOutput(code: 1, stderr: "spacialctl: unknown command \"switch 42\""))
        // Non-`run` replies still print their data.
        #expect(IPCResponse.ok(id: 1, data: .object(["version": .string("1")])).cliOutput
                == CLIOutput(code: 0, stdout: #"{"version":"1"}"#))
    }

    /// The reply survives the wire: a real socket, a handler that runs the command.
    @Test func runReplyRoundTripsOverTheSocket() async throws {
        let path = "/tmp/spacialshell-test-\(UUID().uuidString.prefix(8)).sock"
        let world = base()
        let server = IPCServer(path: path) { request in
            let name = request.args["command"]?.stringValue ?? ""
            guard let command = KeyBindings.commandNames[name] else { return .failure(id: request.id, "unknown command \"\(name)\"") }
            return CommandRunner.run(command, on: world).report.response(id: request.id)
        }
        try server.start()
        defer { server.stop() }

        func ask(_ command: String) throws -> IPCResponse {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            defer { close(fd) }
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            path.utf8CString.withUnsafeBufferPointer { src in
                withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyMemory(from: UnsafeRawBufferPointer(src)) }
            }
            let rc = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            try #require(rc == 0)
            let line = try IPCCodec.line(IPCRequest(id: 1, cmd: "run", args: ["command": .string(command)]))
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

        #expect(try ask("focus-workspace-2").cliOutput.code == 0)
        let unknown = try ask("focus-workspace-9")
        #expect(unknown.cliOutput == CLIOutput(code: 1, stderr: "spacialctl: unknown workspace 9"))
        #expect(try ask("switch 42").cliOutput.code == 1)
        #expect(try ask("focus-workspace-up").cliOutput.stderr == "spacialctl: nothing to do: already on the top workspace")
    }
}

extension WorldStoreTests {
    /// #109: the store hands the runner's report back, refuses while locked, and a failed
    /// command reaches neither the model nor the backend (the M2 ruling: no reconcile on error).
    @Test func runReportsItsOutcome() async {
        let (store, be) = await make(snap([win(a), win(b)], focused: a))
        await be.reset()
        let before = await store.world
        #expect(await store.run(.focusWorkspaceIndex(7)) == .failed(.unknownWorkspace("7")))
        #expect(await store.world == before)
        #expect(await be.calls.isEmpty)
        #expect(await store.run(.focusWindow(.right)) == .done)
        await store.apply(.screenLocked)
        #expect(await store.run(.focusWindow(.right)) == .failed(.locked))
    }
}
