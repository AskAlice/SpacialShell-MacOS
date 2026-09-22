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
        // Pinned, not defaulted: this test is about the inset arithmetic, so it must not move
        // when `panel-width`'s or `panel-margin`'s default does. ConfigTests owns the defaults.
        var c = Config(); c.railSide = .left; c.panelWidth = 48; c.panelHeight = 34; c.panelMargin = 10
        let i = ShellInsets(config: c, hidden: false)
        // The cards float: every edge gives up the margin, the two carrying a card give up the
        // card on top of it.
        #expect(i.top == 44 && i.left == 58 && i.right == 10 && i.bottom == 10)
        #expect(i.apply(to: CGRect(x: 0, y: 0, width: 1000, height: 700)) == CGRect(x: 58, y: 44, width: 932, height: 646))
    }
    @Test func rightRailInsets() {
        var c = Config(); c.railSide = .right; c.panelWidth = 48; c.panelHeight = 34; c.panelMargin = 10
        let i = ShellInsets(config: c, hidden: false)
        #expect(i.top == 44 && i.left == 10 && i.right == 58 && i.bottom == 10)
        #expect(i.apply(to: CGRect(x: 0, y: 0, width: 1000, height: 700)) == CGRect(x: 10, y: 44, width: 932, height: 646))
    }
    @Test func hiddenIsZero() {
        #expect(ShellInsets(config: Config(), hidden: true) == .zero)
    }
    @Test func showPanelsFalseIsZero() {
        var c = Config(); c.showPanels = false
        #expect(ShellInsets(config: c, hidden: false) == .zero)
    }
}
