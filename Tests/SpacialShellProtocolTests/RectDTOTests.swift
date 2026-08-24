import Testing
import Foundation
import CoreGraphics
@testable import SpacialShellProtocol

@Suite struct RectDTOTests {
    @Test func roundTripsThroughCGRect() {
        let r = CGRect(x: 12.5, y: -3, width: 640, height: 480.25)
        let dto = RectDTO(r)
        #expect(dto.cgRect == r)
        #expect(dto.x == 12.5 && dto.y == -3 && dto.width == 640 && dto.height == 480.25)
    }

    @Test func memberwiseInitMatchesCGRectInit() {
        let dto = RectDTO(x: 1, y: 2, width: 3, height: 4)
        #expect(dto == RectDTO(CGRect(x: 1, y: 2, width: 3, height: 4)))
    }

    @Test func goldenJSONKeysAreExactlyXYWidthHeightSorted() throws {
        let dto = RectDTO(x: 1, y: 2, width: 3, height: 4)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(dto)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json == #"{"height":4,"width":3,"x":1,"y":2}"#)
    }

    @Test func roundTripsThroughJSON() throws {
        let dto = RectDTO(x: 1.5, y: 2.5, width: 3.5, height: 4.5)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(dto)
        let decoded = try decoder.decode(RectDTO.self, from: data)
        #expect(decoded == dto)
    }

    @Test func edgeInsetsDTOZeroIsAllZero() {
        let z = EdgeInsetsDTO.zero
        #expect(z.top == 0 && z.left == 0 && z.right == 0 && z.bottom == 0)
    }

    @Test func edgeInsetsDTORoundTripsThroughJSON() throws {
        let insets = EdgeInsetsDTO(top: 1, left: 2, right: 3, bottom: 4)
        let data = try JSONEncoder().encode(insets)
        let decoded = try JSONDecoder().decode(EdgeInsetsDTO.self, from: data)
        #expect(decoded == insets)
    }
}
