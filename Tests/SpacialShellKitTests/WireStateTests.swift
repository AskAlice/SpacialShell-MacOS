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

    /// #198/#199: a workspace carries the title it goes by everywhere (#183: its category,
    /// capitalised, else its name) and each window its title and app name, so a client can name
    /// rows and find a window by app and title.
    @Test func carriesTitlesAndAppNames() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let tab = WindowRef(id: 1, pid: 7)
        w.adopt(tab, kind: .tile, on: "D1")
        let s = WireState.test(world: w, bundleIDs: [tab: "com.x.browser"], titles: [tab: "Pull requests"],
                               appNames: [7: "Brave Origin"], categoryOverrides: ["com.x.browser": .web])
        let ws = s.screens[0].workspaces[0]
        #expect(ws.title == "Web browsing")
        #expect(ws.windows[0].title == "Pull requests" && ws.windows[0].appName == "Brave Origin")
        #expect(s.screens[0].workspaces.last?.title == "New workspace", "the trailing empty row")
    }
}

