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

    /// System Settings only resizes vertically, so AX calls it a dialog; the default `[[tile]]`
    /// rule puts it in its row anyway, and a file's own `[[tile]]` replaces the default.
    @Test func systemSettingsTilesByDefault() throws {
        #expect(Config().kindOverride(bundleID: "com.apple.systempreferences", title: "") == .tile)
        let c = try Config.parse(toml: "[[tile]]\nbundle-id = \"com.example.x\"\n")
        #expect(c.kindOverride(bundleID: "com.example.x", title: "") == .tile)
        #expect(c.kindOverride(bundleID: "com.apple.systempreferences", title: "") == nil)
    }

    // MARK: #83 telemetry

    static let telemetryToml = """
    [telemetry]
    enabled = true
    endpoint = "https://otlp.example.net/otlp/"
    user = "123456"
    token = "not-a-real-token"
    """

    @Test func telemetryDefaultsToOffAndSendsNothing() throws {
        let t = try Config.parse(toml: "").telemetry
        #expect(t == TelemetryConfig() && !t.enabled)
        #expect(t.export(env: [:]) == nil)
        // Off stays off whatever the environment says.
        #expect(t.export(env: ["OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318",
                               "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Basic%20eA=="]) == nil)
        // On, but no credential anywhere: still nothing.
        var noToken = try Config.parse(toml: Self.telemetryToml).telemetry
        noToken.token = ""
        #expect(noToken.export(env: [:]) == nil)
    }

    @Test func telemetryTableParsesAndExportsWithBasicAuth() throws {
        let t = try Config.parse(toml: Self.telemetryToml).telemetry
        #expect(t.enabled && t.endpoint == "https://otlp.example.net/otlp/" && t.user == "123456" && t.token == "not-a-real-token")
        let target = try #require(t.export(env: [:]))
        #expect(target.url.absoluteString == "https://otlp.example.net/otlp/v1/traces")
        #expect(target.headers == ["Authorization": "Basic " + Data("123456:not-a-real-token".utf8).base64EncodedString()])
    }

    @Test func telemetryEnvironmentOverridesEndpointAndHeaders() throws {
        let t = try Config.parse(toml: Self.telemetryToml).telemetry
        let target = try #require(t.export(env: ["OTEL_EXPORTER_OTLP_ENDPOINT": "http://127.0.0.1:4318",
                                                 "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Basic%20dTp0==, X-Scope = a%2Cb"]))
        #expect(target.url.absoluteString == "http://127.0.0.1:4318/v1/traces")
        // Percent-decoded, and a base64 value keeps its padding.
        #expect(target.headers == ["Authorization": "Basic dTp0==", "X-Scope": "a,b"])
    }

    @Test func renderNeverWritesTheToken() throws {
        let c = try Config.parse(toml: Self.telemetryToml)
        let out = c.render()
        #expect(!out.contains("not-a-real-token") && !out.contains("token"))
        let back = try Config.parse(toml: out).telemetry
        #expect(back.enabled && back.endpoint == c.telemetry.endpoint && back.user == c.telemetry.user && back.token.isEmpty)
    }

    /// #89: `[[tile]]` promotes only standard windows. System Settings' "Quit & Reopen" alert is
    /// not one; tiling it made it a tab that pushed the main Settings window aside.
    @Test func tileRuleSkipsAlertsAndSheets() {
        let c = Config()
        #expect(c.kindOverride(bundleID: "com.apple.systempreferences", title: "Privacy", standard: true) == .tile)
        #expect(c.kindOverride(bundleID: "com.apple.systempreferences", title: "", standard: false) == nil)
    }
}
