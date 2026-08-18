import Testing
import Foundation
@testable import SpacialShellPlatform

@Suite struct DisplayTopologyTests {
    @Test func flipConvertsBottomLeftToTopLeft() {
        // main 1000x700; NSScreen visibleFrame y=0 h=675 (dock 0, menu bar 25) → top-left y = 700-675 = 25
        #expect(DisplayTopology.flip(CGRect(x: 0, y: 0, width: 1000, height: 675), mainHeight: 700) == CGRect(x: 0, y: 25, width: 1000, height: 675))
        // a display above main: NSScreen frame y=700..1400 → top-left y = 700-1400 = -700
        #expect(DisplayTopology.flip(CGRect(x: 0, y: 700, width: 1000, height: 700), mainHeight: 700) == CGRect(x: 0, y: -700, width: 1000, height: 700))
    }
    @Test @MainActor func currentReturnsAtLeastOneDisplayWithUUID() {
        let d = DisplayTopology.current()
        #expect(!d.isEmpty && d.contains(where: \.isMain) && d.allSatisfy { !$0.id.isEmpty })
    }
}
