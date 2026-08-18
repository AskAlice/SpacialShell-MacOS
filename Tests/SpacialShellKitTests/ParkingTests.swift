import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct ParkingTests {
    let main = DisplayInfo(id: "M", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055), isMain: true)
    let right = DisplayInfo(id: "R", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: 1920, y: 25, width: 1920, height: 1055), isMain: false)
    let below = DisplayInfo(id: "B", frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 1080, width: 1920, height: 1080), isMain: false)

    @Test func singleDisplayParksBottomRight() { #expect(Parking.corner(for: main, among: [main]) == .bottomRight) }
    @Test func displayToTheRightPushesParkingToBottomLeft() { #expect(Parking.corner(for: main, among: [main, right]) == .bottomLeft) }
    @Test func rightDisplayItselfParksBottomRight() { #expect(Parking.corner(for: right, among: [main, right]) == .bottomRight) }
    @Test func bottomRightOriginLeavesOnePixelSliver() {
        let o = Parking.origin(windowSize: CGSize(width: 800, height: 600), visibleFrame: main.visibleFrame, corner: .bottomRight, sliver: 1)
        #expect(o == CGPoint(x: 1919, y: 1079))
    }
    @Test func bottomLeftOriginLeavesOnePixelColumn() {
        let o = Parking.origin(windowSize: CGSize(width: 800, height: 600), visibleFrame: main.visibleFrame, corner: .bottomLeft, sliver: 1)
        #expect(o == CGPoint(x: -799, y: 1079))
    }
    @Test func zeroSliverForZoom() {
        let o = Parking.origin(windowSize: CGSize(width: 800, height: 600), visibleFrame: main.visibleFrame, corner: .bottomRight, sliver: 0)
        #expect(o == CGPoint(x: 1920, y: 1080))
    }
}
