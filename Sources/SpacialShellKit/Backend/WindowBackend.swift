import Foundation
import CoreGraphics

public struct DisplayInfo: Equatable, Sendable, Hashable {
    public let id: DisplayID
    public let frame: CGRect          // top-left origin, y-down, global
    public let visibleFrame: CGRect   // minus menu bar and Dock
    public let isMain: Bool
    public init(id: DisplayID, frame: CGRect, visibleFrame: CGRect, isMain: Bool) {
        self.id = id; self.frame = frame; self.visibleFrame = visibleFrame; self.isMain = isMain
    }
}
