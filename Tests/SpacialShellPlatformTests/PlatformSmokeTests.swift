import Testing
@testable import SpacialShellPlatform
@Suite struct PlatformSmokeTests {
    @Test func kitVersionIsSet() { #expect(SpacialShellPlatform.kitVersion == "0.1.0") }
}
