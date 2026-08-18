import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct FakeBackendTests {
    @Test func recordsWritesAndUpdatesFrames() async {
        let r = WindowRef(id: 1, pid: 1)
        let b = FakeBackend(snapshot: Snapshot(displays: [], apps: [], windows: [WindowSnapshot(ref: r, frame: CGRect(x: 0, y: 0, width: 10, height: 10), title: "", bundleID: nil, kind: .tile, parent: nil, isMinimized: false, isFullscreen: false)], focused: nil))
        _ = await b.setPosition(r, CGPoint(x: 5, y: 5))
        #expect(await b.frames[r] == CGRect(x: 5, y: 5, width: 10, height: 10))
        #expect(await b.calls == [.setPosition(r, CGPoint(x: 5, y: 5))])
    }
}
