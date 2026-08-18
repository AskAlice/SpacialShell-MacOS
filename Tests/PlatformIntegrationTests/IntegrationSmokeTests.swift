import Testing
import SpacialShellKit
import SpacialShellPlatform
@Suite struct IntegrationSmokeTests {
    @Test func kitAndPlatformVersionsMatch() {
        #expect(SpacialShellPlatform.kitVersion == SpacialShellKit.version)
    }
}
