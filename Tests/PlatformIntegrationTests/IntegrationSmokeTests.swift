import Testing
import SpacialShellKit
import SpacialShellPlatform

@Suite struct IntegrationSmokeTests {
    @Test func kitAndPlatformLinkTogether() {
        #expect(SpacialShellKit.version == "0.1.0")
    }
}
