import Testing
@testable import SpacialShellKit
@Suite struct SmokeTests {
    @Test func versionIsSet() { #expect(SpacialShellKit.version == "0.1.0") }
}
