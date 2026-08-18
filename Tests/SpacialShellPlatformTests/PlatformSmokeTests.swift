import Testing
@testable import SpacialShellPlatform

@Suite struct PlatformSmokeTests {
    // The `SpacialShellPlatform.kitVersion` placeholder was removed together with
    // Sources/SpacialShellPlatform/Platform.swift. Task 15 replaces this file with the
    // AX-dump classifier corpus test.
    @Test func moduleCompiles() { #expect(Bool(true)) }
}
