import Testing
import Foundation
@testable import SpacialShellProtocol

@Suite struct JSONValueTests {
    @Test func roundTripsEveryCase() throws {
        let cases: [JSONValue] = [
            .null,
            .bool(true), .bool(false),
            .int(42), .int(-7), .int(0),
            .double(3.5), .double(-0.25),
            .string(""), .string("hello \"world\"\nwith a newline"),
            .array([.int(1), .string("two"), .null, .bool(false)]),
            .object(["a": .int(1), "b": .array([.string("x")]), "c": .object(["nested": .null])]),
        ]
        for value in cases {
            let data = try IPCCodec.encoder.encode(value)
            let decoded = try IPCCodec.decoder.decode(JSONValue.self, from: data)
            #expect(decoded == value, "round-trip failed for \(value)")
        }
    }

    @Test func encodingAnEncodableRoundTripsToTheSameShape() throws {
        struct Point: Encodable { let x: Int; let y: String }
        let value = try JSONValue(encoding: Point(x: 1, y: "two"))
        #expect(value == .object(["x": .int(1), "y": .string("two")]))
    }

    @Test func decodeToATypeReconstructsIt() throws {
        struct Point: Decodable, Equatable { let x: Int; let y: String }
        let value = JSONValue.object(["x": .int(1), "y": .string("two")])
        let decoded = try value.decode(Point.self)
        #expect(decoded == Point(x: 1, y: "two"))
    }

    @Test func typedAccessors() {
        let obj = JSONValue.object(["name": .string("alice"), "age": .int(9), "ok": .bool(true)])
        #expect(obj["name"]?.stringValue == "alice")
        #expect(obj["age"]?.intValue == 9)
        #expect(obj["ok"]?.boolValue == true)
        #expect(obj["missing"] == nil)
        #expect(JSONValue.string("not an object")["x"] == nil)

        let id = UUID()
        let idValue = JSONValue.string(id.uuidString)
        #expect(idValue.uuidValue == id)
        #expect(JSONValue.string("not-a-uuid").uuidValue == nil)
    }
}

@Suite struct IPCMessageTests {
    @Test func requestRoundTrips() throws {
        let req = IPCRequest(id: 3, cmd: "focus-workspace", args: ["id": .string("abc"), "index": .int(2)])
        let data = try IPCCodec.encoder.encode(req)
        let decoded = try IPCCodec.decoder.decode(IPCRequest.self, from: data)
        #expect(decoded == req)
    }

    @Test func responseOkOmitsError() throws {
        let res = IPCResponse.ok(id: 1, data: .string("done"))
        #expect(res.ok == true)
        #expect(res.error == nil)
        let data = try IPCCodec.encoder.encode(res)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["error"] == nil)
        let decoded = try IPCCodec.decoder.decode(IPCResponse.self, from: data)
        #expect(decoded == res)
    }

    @Test func responseFailureCarriesMessage() throws {
        let res = IPCResponse.failure(id: 5, "unknown workspace")
        #expect(res.ok == false)
        #expect(res.error == "unknown workspace")
        #expect(res.data == nil)
        let data = try IPCCodec.encoder.encode(res)
        let decoded = try IPCCodec.decoder.decode(IPCResponse.self, from: data)
        #expect(decoded == res)
    }

    @Test func eventRoundTrips() throws {
        let event = IPCEvent(v: IPCProtocol.version, event: "shell", data: .object(["zen": .bool(true)]))
        let data = try IPCCodec.encoder.encode(event)
        let decoded = try IPCCodec.decoder.decode(IPCEvent.self, from: data)
        #expect(decoded == event)
    }
}

@Suite struct IPCCodecTests {
    @Test func lineNeverContainsAnInteriorNewline() throws {
        let req = IPCRequest(id: 1, cmd: "x", args: ["note": .string("line one\nline two\r\nline three")])
        let line = try IPCCodec.line(req)
        #expect(line.last == 0x0A)
        let interior = line.dropLast()
        #expect(!interior.contains(0x0A))
    }

    @Test func lineEndsInExactlyOneNewlineByte() throws {
        let line = try IPCCodec.line(IPCResponse.ok(id: 1))
        #expect(line.suffix(1) == Data([0x0A]))
    }

    @Test func encoderNeverPrettyPrintsAndSortsKeys() throws {
        let data = try IPCCodec.encoder.encode(IPCRequest(id: 1, cmd: "a", args: [:]))
        let s = String(decoding: data, as: UTF8.self)
        #expect(!s.contains("\n"))
        #expect(s == #"{"args":{},"cmd":"a","id":1}"#)
    }
}

@Suite struct LineFramerTests {
    @Test func oneLineDeliveredAcrossThreeChunks() {
        var framer = LineFramer()
        #expect(framer.push(Data("{\"a\":".utf8)) == .lines([]))
        #expect(framer.push(Data("1}".utf8)) == .lines([]))
        let outcome = framer.push(Data("\n".utf8))
        #expect(outcome == .lines([Data("{\"a\":1}".utf8)]))
    }

    @Test func twoLinesInOneChunk() {
        var framer = LineFramer()
        let outcome = framer.push(Data("one\ntwo\n".utf8))
        #expect(outcome == .lines([Data("one".utf8), Data("two".utf8)]))
    }

    @Test func trailingPartialLineIsHeldBack() {
        var framer = LineFramer()
        let outcome = framer.push(Data("complete\nincomplete".utf8))
        #expect(outcome == .lines([Data("complete".utf8)]))
        let next = framer.push(Data(" now\n".utf8))
        #expect(next == .lines([Data("incomplete now".utf8)]))
    }

    @Test func crlfIsTolerated() {
        var framer = LineFramer()
        let outcome = framer.push(Data("hello\r\nworld\r\n".utf8))
        #expect(outcome == .lines([Data("hello".utf8), Data("world".utf8)]))
    }

    @Test func overflowAtExactlyMaxLineBytesPlusOne() {
        var framer = LineFramer(maxLineBytes: 8)
        // No newline yet: exactly maxLineBytes bytes must NOT overflow.
        let atLimit = framer.push(Data(repeating: 0x41, count: 8))
        #expect(atLimit == .lines([]))
        // One more byte (still no newline) crosses maxLineBytes -> overflow.
        let overflow = framer.push(Data([0x41]))
        #expect(overflow == .overflow)
    }
}

@Suite struct IPCProtocolTests {
    @Test func defaultSocketPathFitsInSunPath() {
        let path = IPCProtocol.defaultSocketPath()
        #expect(path.utf8.count < 104)
    }

    @Test func constants() {
        #expect(IPCProtocol.version == 1)
        #expect(IPCProtocol.maxRequestBytes == 64 * 1024)
        #expect(IPCProtocol.socketFileName == "spacialshell.sock")
    }
}

/// #9: `LayoutID` encodes exactly as the `Layout` enum did, so nothing on disk or on the wire
/// changes, and decodes strings no build has seen instead of throwing. The enum was
/// `String`-backed, so its encoding was the bare case name; #11 retired it, and the pre-#9
/// fixtures in the Kit tests hold the bytes it wrote.
@Suite struct LayoutIDCodecTests {
    @Test func builtinsEncodeByteForByteAsTheEnum() throws {
        for l in ["maximize", "split", "column", "half", "grid"] {
            let id = LayoutID(rawValue: l)
            #expect(try JSONEncoder().encode(id) == JSONEncoder().encode(l))
            #expect(try JSONEncoder().encode([id]) == JSONEncoder().encode([l]))
            #expect(try JSONDecoder().decode(LayoutID.self, from: JSONEncoder().encode(l)) == id)
        }
        #expect(LayoutID.maximize.rawValue == "maximize" && LayoutID.grid.rawValue == "grid")
    }

    @Test func anUnseenIdDecodes() throws {
        #expect(try JSONDecoder().decode(LayoutID.self, from: Data(#""code-3""#.utf8)) == "code-3")
    }
}
