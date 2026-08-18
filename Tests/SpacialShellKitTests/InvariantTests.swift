import Testing
import Foundation
@testable import SpacialShellKit

@Suite struct InvariantTests {
    static let a = WindowRef(id: 1, pid: 100)
    static let b = WindowRef(id: 2, pid: 100)

    func world(_ wss: [[WindowRef]], active: Int = 0) -> World {
        let ws = wss.map { Workspace(name: "W", layout: .maximize, windows: $0) }
        return World(
            screens: ["D1": Screen(display: "D1", rect: nil, workspaces: ws, activeIndex: active)],
            screenOrder: ["D1"], focus: Focus(screen: "D1", window: nil),
            ephemeral: [], ignored: [], hidden: [], parents: [:], defaultLayout: .maximize)
    }

    @Test func validWorldHasNoViolations() {
        #expect(world([[Self.a], []]).invariantViolations().isEmpty)
    }
    @Test func lastWorkspaceMustBeEmpty() {
        #expect(!world([[Self.a]]).invariantViolations().isEmpty)
    }
    @Test func windowInTwoWorkspacesIsViolation() {
        #expect(world([[Self.a], [Self.a], []]).invariantViolations().contains { $0.contains("and") })
    }
    @Test func emptyNonTrailingNonActiveIsViolation() {
        #expect(!world([[Self.a], [], []], active: 0).invariantViolations().isEmpty)
    }
    @Test func emptyActiveIsAllowed() {
        #expect(world([[], [Self.a], []], active: 0).invariantViolations().isEmpty)
    }
    @Test func pinnedEmptyIsAllowed() {
        var w = world([[Self.a], [], []], active: 0)
        w.screens["D1"]!.workspaces[1].pinned = true
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func focusMustBeInActiveWorkspaceOrEphemeral() {
        var w = world([[Self.a], [Self.b], []], active: 0)
        w.focus.window = Self.b
        #expect(!w.invariantViolations().isEmpty)
        w.focus.window = Self.a
        #expect(w.invariantViolations().isEmpty)
    }
    @Test func layoutNextCycles() {
        #expect(Layout.maximize.next == .split)
        #expect(Layout.grid.next == .maximize)
    }
}
