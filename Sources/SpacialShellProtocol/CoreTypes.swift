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

/// A layout's identity (#9, custom grid layouts design §2/§4.1): any string, never a closed set.
/// It encodes as the bare string, byte-for-byte what the `Layout` enum wrote, so every existing
/// `config.toml`, `state.json` and wire payload loads unchanged — and a string no build has seen
/// decodes too, instead of rejecting the whole file. Whether an id *means* anything is decided
/// late, by Kit's `LayoutCatalogue`. The static members keep `== .maximize` call sites compiling.
public struct LayoutID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    /// #9 bridge from the enum (tests use it since #10 moved the switcher onto the catalogue);
    /// goes with the enum in #11.
    public init(_ layout: Layout) { rawValue = layout.rawValue }
    public init(from d: Decoder) throws { rawValue = try d.singleValueContainer().decode(String.self) }
    public func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(rawValue) }
    public static let maximize: LayoutID = "maximize", split: LayoutID = "split",
                      column: LayoutID = "column", half: LayoutID = "half", grid: LayoutID = "grid"
}

/// The five built-ins as a closed set. Since #10 only Kit's `BuiltinLayout` uses it; storage
/// speaks `LayoutID` and the switcher the catalogue. Removed by #11.
public enum Layout: String, Codable, CaseIterable, Sendable {
    case maximize, split, column, half, grid
    public var next: Layout {
        let all = Layout.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
