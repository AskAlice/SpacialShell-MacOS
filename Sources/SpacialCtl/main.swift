import Darwin
import Foundation
import SpacialShellProtocol

// spacialctl — one-shot NDJSON client for the SpacialShell control socket.
// Exit codes: 0 ok · 1 daemon returned an error · 2 usage · 3 daemon not reachable.

let usage = """
usage: spacialctl [--socket PATH] <subcommand>
  version              daemon version
  state                spatial model as JSON
  run <command-name>   run a bound command, e.g. `run focus-workspace-2`; a command that
                       fails (unknown workspace, no focused window, ...) exits 1
  set-layout <id> [--workspace <uuid>]
                       set a workspace's layout (default: the focused one); unknown ids exit 1
"""

var args = Array(CommandLine.arguments.dropFirst())
var socketPath = IPCProtocol.defaultSocketPath()
if args.first == "--socket", args.count >= 2 { socketPath = args[1]; args.removeFirst(2) }

let request: IPCRequest
switch args.first {
case "version": request = IPCRequest(id: 1, cmd: "version")
case "state": request = IPCRequest(id: 1, cmd: "state")
// #109: extra words are passed through, so `run switch 42` is the daemon's clear "unknown command".
case "run" where args.count >= 2:
    request = IPCRequest(id: 1, cmd: "run", args: ["command": .string(args.dropFirst().joined(separator: " "))])
case "set-layout" where args.count == 2: request = IPCRequest(id: 1, cmd: "set-layout", args: ["layout": .string(args[1])])
case "set-layout" where args.count == 4 && args[2] == "--workspace":
    request = IPCRequest(id: 1, cmd: "set-layout", args: ["layout": .string(args[1]), "workspace": .string(args[3])])
default:
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("spacialctl: \(message)\n".utf8))
    exit(code)
}

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { die("socket() failed", code: 3) }
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
socketPath.utf8CString.withUnsafeBufferPointer { src in
    guard src.count <= MemoryLayout.size(ofValue: addr.sun_path) else { die("socket path too long", code: 2) }
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyMemory(from: UnsafeRawBufferPointer(src)) }
}
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else { die("SpacialShell is not running (\(socketPath))", code: 3) }

guard let line = try? IPCCodec.line(request) else { die("encode failed", code: 2) }
_ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }

var framer = LineFramer()
var responseLine: Data?
var buf = [UInt8](repeating: 0, count: 8192)
while responseLine == nil {
    let n = read(fd, &buf, buf.count)
    guard n > 0 else { die("connection closed", code: 3) }
    guard case .lines(let lines) = framer.push(Data(buf[0..<n])) else { die("response too large", code: 3) }
    responseLine = lines.first
}
close(fd)

guard let response = try? IPCCodec.decoder.decode(IPCResponse.self, from: responseLine!) else {
    die("bad response", code: 3)
}
let output = response.cliOutput
if let err = output.stderr { FileHandle.standardError.write(Data((err + "\n").utf8)) }
if let out = output.stdout { print(out) }
exit(output.code)
