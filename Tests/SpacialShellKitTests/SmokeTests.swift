import Foundation
import Testing
@testable import SpacialShellKit
@Suite struct SmokeTests {
    /// Tests run loose (no `.app`), so they see the fallback.
    @Test func versionIsSet() { #expect(SpacialShellKit.version == SpacialShellKit.fallbackVersion) }

    // #191: `spacialctl version` reports the running release.
    @Test func anAppBundlesVersionWins() {
        let app = URL(fileURLWithPath: "/Applications/SpacialShell.app")
        #expect(SpacialShellKit.version(bundleURL: app, shortVersion: "0.4.0") == "0.4.0")
    }

    @Test func withNoBundleTheFallbackIsUsed() {
        let loose = URL(fileURLWithPath: "/tmp/.build/debug")
        #expect(SpacialShellKit.version(bundleURL: loose, shortVersion: "9.9.9") == SpacialShellKit.fallbackVersion)
        let app = URL(fileURLWithPath: "/Applications/SpacialShell.app")
        #expect(SpacialShellKit.version(bundleURL: app, shortVersion: nil) == SpacialShellKit.fallbackVersion)
        #expect(SpacialShellKit.version(bundleURL: app, shortVersion: "") == SpacialShellKit.fallbackVersion)
    }
}
