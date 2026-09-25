import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ConfigTests {
    @Test func emptyTomlGivesDefaults() throws {
        let c = try Config.parse(toml: "")
        #expect(c.keybindingPreset == .fn && c.gap == 8 && c.defaultLayout == .maximize && c.axTimeoutMs == 1000 && c.refreshIntervalMs == 2000)
        #expect(c.panelWidth == 48 && c.panelHeight == 34 && c.railSide == .left && c.launcherURL == "raycast://" && c.showPanels)
        // #70: System Settings is a window you work in, not a visitor — only Calculator by default.
        #expect(c.ephemeral.map(\.bundleId) == ["com.apple.calculator"])
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
        launcher-url = "raycast://extensions/foo"
        show-panels = false
        """)
        #expect(c.panelWidth == 64 && c.panelHeight == 40 && c.railSide == .right)
        #expect(c.launcherURL == "raycast://extensions/foo" && !c.showPanels)
    }
    /// #60: the focus ring was removed, but config files written before then still carry its keys.
    /// Unknown keys are ignored, so they must load rather than fail.
    @Test func removedFocusRingKeysStillLoad() throws {
        let c = try Config.parse(toml: """
        focus-ring = true
        highlight-ms = 300
        highlight-color = "#FF0000"
        gap = 4
        """)
        #expect(c.gap == 4)
    }
    @Test func unknownRailSideRejects() {
        #expect(throws: (any Error).self) { try Config.parse(toml: #"rail-side = "middle""#) }
    }
}
