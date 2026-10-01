import AppKit
import Foundation
import Testing
import SpacialShellKit
import SpacialShellProtocol
@testable import SpacialShellUI

/// #201: one window menu wherever a window appears — a tab, a sidebar card's preview, a workspace
/// tile's per-window submenu. Built, never shown: nothing here orders a window on screen.
@MainActor
@Suite struct WindowMenuTests {
    let w = WindowRef(id: 1, pid: 1)
    let here = UUID(), there = UUID()

    func rail() -> [WorkspaceRailItem] {
        [WorkspaceRailItem(id: here, index: 0, name: "Web", symbol: "globe", windowCount: 1, windows: [w],
                           isActive: true, isPinned: false, isTrailingEmpty: false),
         WorkspaceRailItem(id: there, index: 1, name: "Code", symbol: "terminal", windowCount: 0,
                           isActive: false, isPinned: false, isTrailingEmpty: false)]
    }
    func info(floating: Bool = false, pinned: Bool = false, placeholder: Bool = false) -> RailMenu.WindowInfo {
        RailMenu.WindowInfo(ref: placeholder ? WindowRef(id: 9, pid: -5) : w, title: "Pull requests",
                            isFloating: floating, isPinned: pinned, isPlaceholder: placeholder)
    }
    func titles(_ m: NSMenu) -> [String] { m.items.filter { !$0.isSeparatorItem }.map(\.title) }

    @Test func aTiledWindowsMenu() {
        let m = RailMenu.window(info(), rail: rail(), metaFor: { _ in AppMeta(name: "Brave", icon: nil, bundleID: nil, category: nil) }, send: { _ in })
        #expect(titles(m) == ["Switch to Window", "Move to Workspace", "Move App to Workspace",
                              "Float", "Pin", "Hide App", "Close Window", "Quit App"])
        let move = m.items.first { $0.title == "Move to Workspace" }!.submenu!
        #expect(move.items.map(\.title) == ["Code (2)"], "not the row it is in")
    }

    @Test func floatingAndPinnedFlipTheirItems() {
        let m = RailMenu.window(info(floating: true, pinned: true), rail: rail(), metaFor: { _ in AppMeta(name: "Brave", icon: nil, bundleID: nil, category: nil) }, send: { _ in })
        #expect(titles(m).contains("Tile") && titles(m).contains("Unpin"))
    }

    /// #128: a placeholder has no window: Open and Close only.
    @Test func aPlaceholderOpensOrCloses() {
        let m = RailMenu.window(info(placeholder: true), rail: rail(), metaFor: { _ in AppMeta(name: "Brave", icon: nil, bundleID: nil, category: nil) }, send: { _ in })
        #expect(titles(m) == ["Open", "Close"])
    }

    /// A tile's menu leads with its windows, each a submenu holding that window's menu.
    @Test func aTileListsItsWindowsAsSubmenus() {
        let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 2), c = WindowRef(id: 3, pid: 3)
        let tile = WorkspaceRailItem(id: here, index: 0, name: "Web", symbol: "globe", windowCount: 3, windows: [a, b, c],
                                     isActive: true, isPinned: false, isTrailingEmpty: false)
        let m = RailMenu.workspace(tile, layouts: [], categories: [], rail: [tile],
                                   windowInfo: { RailMenu.WindowInfo(ref: $0, title: "w\($0.id)", isFloating: false,
                                                                     isPinned: false, isPlaceholder: false) },
                                   metaFor: { _ in AppMeta(name: "App", icon: nil, bundleID: nil, category: nil) }, send: { _ in })
        let windows = m.items.prefix { !$0.isSeparatorItem }
        #expect(windows.map(\.title) == ["Windows", "w1", "w2", "w3"])
        #expect(windows.dropFirst().allSatisfy { $0.submenu?.items.first?.title == "Switch to Window" })
        #expect(titles(m).contains("Set layout") && titles(m).contains("Remove workspace"))
    }
}
