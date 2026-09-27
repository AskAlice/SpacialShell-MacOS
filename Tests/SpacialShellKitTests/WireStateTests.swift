import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

@Suite struct WireStateTests {
    @Test func reflectsWorld() throws {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .column)
        w.adopt(WindowRef(id: 1, pid: 1), kind: .tile, on: "D1")
        w.adopt(WindowRef(id: 2, pid: 1), kind: .tile, on: "D1")
        let s = WireState.test(world: w)
        #expect(s.screens.map(\.display) == ["D1", "D2"])
        #expect(s.screens[0].isFocused && !s.screens[1].isFocused)
        #expect(s.screens[0].workspaces[0].windowCount == 2)
        #expect(s.screens[0].workspaces[0].isActive)
        #expect(s.screens[0].workspaces[0].layout == "column")
        let json = try JSONValue(encoding: s)          // wire round-trip
        #expect(try json.decode(WireState.self) == s)
    }
}
