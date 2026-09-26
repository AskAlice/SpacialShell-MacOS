import Testing
import Foundation
import CoreGraphics
@testable import SpacialShellKit

/// #126 (G35): the Dock's badges and bounces, turned into "this app wants attention".
@Suite struct AttentionTests {
    // A bottom Dock of 44 pt items resting on y = 1440…1484 (AX: y down). Mail (pid 10), Slack
    // (pid 20, two instances' worth: 20 and 21), Notes (30).
    static func item(_ pids: [Int32], x: CGFloat, lift: CGFloat = 0, badge: String? = nil, size: CGFloat = 44) -> DockItemSample {
        DockItemSample(pids: pids, frame: CGRect(x: x, y: 1484 - size - lift, width: size, height: size), badge: badge)
    }
    static func dock(mail: CGFloat = 0, slack: CGFloat = 0, mailBadge: String? = nil, edge: DockEdge = .bottom) -> DockSample {
        DockSample(edge: edge, items: [item([10], x: 100, lift: mail, badge: mailBadge),
                                       item([20, 21], x: 150, lift: slack), item([30], x: 200)])
    }

    @Test func liftsAreMeasuredFromTheSharedEdge() {
        #expect(AttentionTracker.lifts(Self.dock(slack: 52)) == [0, 52, 0])
        // Magnification grows an icon away from the edge, not off it: not a lift.
        let magnified = DockSample(edge: .bottom, items: [Self.item([10], x: 100, size: 88), Self.item([20], x: 190)])
        #expect(AttentionTracker.lifts(magnified) == [0, 0])
        let left = DockSample(edge: .left, items: [DockItemSample(pids: [1], frame: CGRect(x: 0, y: 0, width: 44, height: 44)),
                                                   DockItemSample(pids: [2], frame: CGRect(x: 30, y: 50, width: 44, height: 44))])
        #expect(AttentionTracker.lifts(left) == [0, 30])
        let right = DockSample(edge: .right, items: [DockItemSample(pids: [1], frame: CGRect(x: 1000, y: 0, width: 44, height: 44)),
                                                     DockItemSample(pids: [2], frame: CGRect(x: 970, y: 50, width: 44, height: 44))])
        #expect(AttentionTracker.lifts(right) == [0, 30])
    }

    /// A bounce marks every instance of the app, holds across the ~2 s gap between bounces, and
    /// goes once the Dock stops.
    @Test func aBounceMarksTheAppUntilTheDockStops() {
        var t = AttentionTracker()
        t.feed(Self.dock(), now: 0)
        #expect(t.wanting(now: 0).isEmpty)
        t.feed(Self.dock(slack: 40), now: 1)
        #expect(t.wanting(now: 1) == [20, 21])
        t.feed(Self.dock(), now: 2.5)                       // between bounces
        #expect(t.wanting(now: 2.5) == [20, 21])
        t.feed(Self.dock(), now: 4.5)                       // stopped: no lift for longer than the hold
        #expect(t.wanting(now: 4.5).isEmpty)
    }

    /// Layout jitter is not a bounce.
    @Test func aSmallShiftIsNotABounce() {
        var t = AttentionTracker()
        t.feed(Self.dock(slack: 3), now: 0)
        #expect(t.wanting(now: 0).isEmpty)
    }

    /// Focusing the app clears the mark; the bounce landing just after is not a new request.
    @Test func focusClearsABounce() {
        var t = AttentionTracker()
        t.feed(Self.dock(mail: 40), now: 0)
        t.focus(10, now: 0.5)
        #expect(t.wanting(now: 0.5).isEmpty)
        t.feed(Self.dock(mail: 20), now: 0.75)              // still coming down
        t.focus(30, now: 1)
        #expect(t.wanting(now: 1).isEmpty)
        t.feed(Self.dock(mail: 40), now: 3)                 // a new request, after the settle
        #expect(t.wanting(now: 3) == [10])
    }

    /// The Dock speaks per app, not per instance: focusing one instance clears only that one, and
    /// another still asking keeps its mark while the Dock bounces.
    @Test func focusingOneInstanceLeavesTheOther() {
        var t = AttentionTracker()
        t.feed(Self.dock(slack: 40), now: 0)
        t.focus(20, now: 0.5)
        #expect(t.wanting(now: 0.5) == [21])
    }

    /// A badge marks until the app is focused; the same badge is then seen, a new value is news,
    /// and a badge that goes away takes its mark (and what was seen) with it.
    @Test func aBadgeMarksUntilSeenAndAgainWhenItChanges() {
        var t = AttentionTracker()
        t.feed(Self.dock(mailBadge: "3"), now: 0)
        #expect(t.wanting(now: 0) == [10])
        t.focus(10, now: 1)
        #expect(t.wanting(now: 1).isEmpty)
        t.feed(Self.dock(mailBadge: "4"), now: 2)          // arrives while Mail is in front: seen
        t.focus(30, now: 3)
        #expect(t.wanting(now: 3).isEmpty)
        t.feed(Self.dock(mailBadge: "5"), now: 4)
        #expect(t.wanting(now: 4) == [10])
        t.feed(Self.dock(), now: 5)
        #expect(t.wanting(now: 5).isEmpty)
        t.feed(Self.dock(mailBadge: "5"), now: 6)          // back again: news again
        #expect(t.wanting(now: 6) == [10])
    }

    /// The focused app is never marked: you are already looking at it.
    @Test func theFocusedAppIsNeverMarked() {
        var t = AttentionTracker()
        t.focus(10, now: 0)
        t.feed(Self.dock(mail: 40, mailBadge: "1"), now: 5)
        #expect(t.wanting(now: 5).isEmpty)
    }

    // MARK: view-state

    @Test func railTileAndTabsCarryTheMark() {
        let s = ScreenID.d
        let mail = WindowRef(id: 1, pid: 10), notes = WindowRef(id: 2, pid: 30), slack = WindowRef(id: 3, pid: 20)
        let world = World(
            screens: [s: Screen(display: s, workspaces: [
                Workspace(name: "A", layout: .split, windows: [mail, notes]),
                Workspace(name: "B", layout: .maximize, windows: [slack]),
                Workspace(name: "C", layout: .maximize)], activeIndex: 0)],
            screenOrder: [s], focus: Focus(screen: s, window: notes),
            ephemeral: [], ignored: [], hidden: [], parents: [:], defaultLayout: .maximize)
        let state = ShellUI.state(for: s, in: world, attention: [20, 10])!
        #expect(state.rail.map(\.wantsAttention) == [true, true, false])
        #expect(state.tabs.map(\.wantsAttention) == [true, false])
        #expect(ShellUI.state(for: s, in: world)!.rail.allSatisfy { !$0.wantsAttention })
    }

    // MARK: config

    @Test func dockAttentionDefaultsOnAndRoundTrips() throws {
        #expect(try Config.parse(toml: "").dockAttention)
        let off = try Config.parse(toml: "dock-attention = false")
        #expect(!off.dockAttention)
        #expect(try !Config.parse(toml: off.render()).dockAttention)
        #expect(Config.unknownKeys(toml: "dock-attention = false").isEmpty)
        var gui = SettingsOverrides(); gui.dockAttention = true
        #expect(Settings.effective(config: off, overrides: gui).dockAttention)
    }
}

private enum ScreenID { static let d: DisplayID = "D1" }
