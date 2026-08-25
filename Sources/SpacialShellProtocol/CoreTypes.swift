import Foundation

// Moved verbatim from SpacialShellKit's Model.swift (M1) so `spacialctl`, the Raycast extension,
// and the IPC server can share this vocabulary without linking the model, the reconciler, or
// TOMLDecoder. Kit keeps `public typealias` shims so every M1 call site keeps compiling.
// See docs/superpowers/plans/2026-08-19-m2-appendix-b-ipc-cli.md D4.

public typealias DisplayID = String   // CGDisplayCreateUUIDFromDisplayID string
public typealias WindowID = UInt32    // CGWindowID

public struct WindowRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public let id: WindowID
    public let pid: Int32
    public init(id: WindowID, pid: Int32) { self.id = id; self.pid = pid }
    public var description: String { "w\(id)@\(pid)" }
}

public enum Layout: String, Codable, CaseIterable, Sendable {
    case maximize, split, column, half, grid
    public var next: Layout {
        let all = Layout.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
