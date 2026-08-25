import Foundation

/// A dynamically-typed JSON value — the shape of `IPCRequest.args` / `IPCResponse.data` /
/// `IPCEvent.data`, none of which have a schema the protocol layer can see ahead of time.
public enum JSONValue: Codable, Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Round-trips `value` through the wire encoder/decoder into a `JSONValue` tree.
    public init<T: Encodable>(encoding value: T) throws {
        let data = try IPCCodec.encoder.encode(value)
        self = try IPCCodec.decoder.decode(JSONValue.self, from: data)
    }

    /// Round-trips this tree back out to a concrete `Decodable` type.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try IPCCodec.encoder.encode(self)
        return try IPCCodec.decoder.decode(T.self, from: data)
    }

    // MARK: Typed accessors used by the dispatcher

    public subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .int(let value) = self { return value }
        if case .double(let value) = self, value.truncatingRemainder(dividingBy: 1) == 0 {
            return Int(value)
        }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var uuidValue: UUID? {
        if case .string(let value) = self { return UUID(uuidString: value) }
        return nil
    }
}
