import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct GeometryTests {
    @Test func flipIsSelfInverse() {
        let r = CGRect(x: 100, y: 200, width: 300, height: 400)
        #expect(Geometry.flip(Geometry.flip(r, mainHeight: 1080), mainHeight: 1080) == r)
    }
    @Test func flipSecondaryAboveAndBelowPrimary() {
        // main 1920×1080 at (0,0). Above: NSScreen y=1080..2160 → AX y = 1080-2160 = -1080
        let above = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        #expect(Geometry.flip(above, mainHeight: 1080) == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        #expect(Geometry.flip(Geometry.flip(above, mainHeight: 1080), mainHeight: 1080) == above)
        // Below: NSScreen y=-1440..0 → AX y = 1080-0 = 1080
        let below = CGRect(x: 2560, y: -1440, width: 2560, height: 1440)
        #expect(Geometry.flip(below, mainHeight: 1080) == CGRect(x: 2560, y: 1080, width: 2560, height: 1440))
        #expect(Geometry.flip(Geometry.flip(below, mainHeight: 1080), mainHeight: 1080) == below)
    }
    @Test func leftRailInsets() {
        var c = Config(); c.railSide = .left
        let i = ShellInsets(config: c, hidden: false)
        #expect(i.top == 34 && i.left == 48 && i.right == 0 && i.bottom == 0)
        #expect(i.apply(to: CGRect(x: 0, y: 0, width: 1000, height: 700)) == CGRect(x: 48, y: 34, width: 952, height: 666))
    }
    @Test func rightRailInsets() {
        var c = Config(); c.railSide = .right
        let i = ShellInsets(config: c, hidden: false)
        #expect(i.top == 34 && i.left == 0 && i.right == 48 && i.bottom == 0)
        #expect(i.apply(to: CGRect(x: 0, y: 0, width: 1000, height: 700)) == CGRect(x: 0, y: 34, width: 952, height: 666))
    }
    @Test func hiddenIsZero() {
        #expect(ShellInsets(config: Config(), hidden: true) == .zero)
    }
    @Test func showPanelsFalseIsZero() {
        var c = Config(); c.showPanels = false
        #expect(ShellInsets(config: c, hidden: false) == .zero)
    }
}
