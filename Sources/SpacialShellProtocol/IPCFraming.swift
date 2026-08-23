import Foundation

/// Newline-delimited JSON. `JSONEncoder` with `[.sortedKeys]` (never `.prettyPrinted`) cannot
/// emit a bare newline — string contents escape it as the two characters `\n`.
public struct LineFramer: Sendable {
    private let maxLineBytes: Int
    private var buffer = Data()

    public init(maxLineBytes: Int = IPCProtocol.maxRequestBytes) {
        self.maxLineBytes = maxLineBytes
    }

    public enum Outcome: Sendable, Equatable { case lines([Data]), overflow }

    /// Appends `chunk` and returns whatever complete lines that produced. `.overflow` once the
    /// buffer passes `maxLineBytes` with no newline — unrecoverable, the caller must close.
    public mutating func push(_ chunk: Data) -> Outcome {
        buffer.append(chunk)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            var line = buffer[..<nl]
            if line.last == 0x0D { line.removeLast() }
            lines.append(Data(line))
            buffer.removeSubrange(...nl)
        }
        return buffer.count > maxLineBytes ? .overflow : .lines(lines)
    }
}

public enum IPCCodec {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    public static let decoder = JSONDecoder()

    public static func line<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }
}
