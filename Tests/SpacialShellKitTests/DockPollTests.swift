import Testing
import SpacialShellKit

/// #212: which Dock items a poll between full reads asks. Running apps' items, plus one other as
/// the edge anchor, so every lift in the sample is measured against frames read together.
@Suite struct DockPollTests {
    @Test func asksTheRunningAppsPlusOneAnchor() {
        let paths: [String?] = ["/Applications/Mail.app", "/Applications/Notes.app", nil, "/System/Applications/Finder.app"]
        let running: [String: [Int32]] = ["/Applications/Mail.app": [10], "/System/Applications/Finder.app": [20, 21]]
        #expect(DockPoll.live(paths, running: running) == [0, 1, 3])
    }

    @Test func anAppThatHasQuitIsNotAskedForItsOwnSake() {
        // A path still in the map with no pids left marks nothing; it is only the anchor here.
        #expect(DockPoll.live(["/Applications/Mail.app", "/Applications/Notes.app"],
                              running: ["/Applications/Mail.app": []]) == [0])
    }

    @Test func everythingRunningNeedsNoAnchor() {
        #expect(DockPoll.live(["/a.app", "/b.app"], running: ["/a.app": [1], "/b.app": [2]]) == [0, 1])
    }

    @Test func nothingRunningAsksOnlyTheAnchor() {
        #expect(DockPoll.live(["/Applications/Mail.app", nil], running: [:]) == [0])
        #expect(DockPoll.live([], running: [:]).isEmpty)
    }
}
