import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ConfigTests {
    @Test func emptyTomlGivesDefaults() throws {
        let c = try Config.parse(toml: "")
        #expect(c.keybindingPreset == .fn && c.gap == 8 && c.defaultLayout == .maximize && c.axTimeoutMs == 1000 && c.refreshIntervalMs == 2000)
        #expect(c.panelWidth == 112 && c.panelHeight == 48 && c.panelMargin == 12 && c.railSide == .left && c.highlightMs == 600 && c.launcherURL == "raycast://" && c.showPanels)
        #expect(c.ephemeral.map(\.bundleId) == ["com.apple.systempreferences", "com.apple.calculator"])
        #expect(c.workspaces.isEmpty)
    }
    @Test func parsesEverything() throws {
        let c = try Config.parse(toml: """
        keybinding-preset = "ctrl-alt"
        gap = 4
        default-layout = "half"
        ax-timeout-ms = 500
        refresh-interval-ms = 1000
        start-at-login = true
        [[workspace]]
        name = "Code"
        symbol = "terminal"
        layout = "half"
        [[float]]
        bundle-id = "com.apple.iphonesimulator"
        [[ignore]]
        bundle-id = "com.example.x"
        title-regex = "^Picture in Picture$"
        [keybindings]
        "fn-shift-g" = "toggle-float"
        """)
        #expect(c.keybindingPreset == .ctrlAlt && c.gap == 4 && c.defaultLayout == .half && c.startAtLogin)
        #expect(c.workspaces == [WorkspaceSeed(name: "Code", symbol: "terminal", layout: .half)])
        #expect(c.float == [AppRule(bundleId: "com.apple.iphonesimulator", titleRegex: nil)])
        #expect(c.ignore.first?.titleRegex == "^Picture in Picture$")
        #expect(c.keybindings == ["fn-shift-g": "toggle-float"])
    }
    @Test func kindOverrideChecksRulesInOrder() throws {
        let c = try Config.parse(toml: """
        [[float]]
        bundle-id = "com.x"
        [[ignore]]
        bundle-id = "com.x"
        title-regex = "PiP"
        """)
        #expect(c.kindOverride(bundleID: "com.x", title: "Main") == .float)
        #expect(c.kindOverride(bundleID: "com.x", title: "PiP") == .float)   // float is checked before ignore, so float wins
        #expect(c.kindOverride(bundleID: "com.apple.calculator", title: "") == .ephemeral)
        #expect(c.kindOverride(bundleID: "com.other", title: "") == nil)
    }
    @Test func invalidTomlThrows() {
        #expect(throws: (any Error).self) { try Config.parse(toml: "gap = ") }
    }
    @Test func panelKeysRoundTrip() throws {
        let c = try Config.parse(toml: """
        panel-width = 64
        panel-height = 40
        rail-side = "right"
        highlight-ms = 300
        launcher-url = "raycast://extensions/foo"
        show-panels = false
        """)
        #expect(c.panelWidth == 64 && c.panelHeight == 40 && c.railSide == .right)
        #expect(c.highlightMs == 300 && c.launcherURL == "raycast://extensions/foo" && !c.showPanels)
    }
    @Test func unknownRailSideRejects() {
        #expect(throws: (any Error).self) { try Config.parse(toml: #"rail-side = "middle""#) }
    }
}
