import Testing
import Foundation
@testable import SpacialShellKit

/// #171, #166: one `CommandEnvironment` goes through every command and every recursion unchanged,
/// and a command that hands off to another reports the one it handed off to's reason.
@Suite struct CommandEnvironmentTests {
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), ghost = WindowRef(id: 99, pid: 9)
    func world(_ layout: LayoutID = .split) -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: layout)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        return w
    }
    func report(_ c: Command, _ w: World) -> CommandReport { CommandRunner.run(c, on: w, in: .test()).report }

    /// #166's acceptance: the reason is set inside the recursion and still reaches the report.
    @Test func aRecursedCommandsReasonReachesTheReport() {
        let w = world()
        #expect(report(.recoverWindow(ghost), w) == .failed(.unknownWindow(ghost)), "recoverWindow → focusWindowRef")
        #expect(report(.adjustSplitColumns(-1), w) == .noop("split already shows 2 columns"),
                "adjustSplitColumns → setSplitColumns")
        #expect(report(.resizeWindow(.width, grow: true), w) == .done, "resizeWindow → setPortions")
    }

    /// The command `resizeWindow` hands off to (line 413 before #171) says why it did nothing.
    @Test func setPortionsSaysWhyItDidNothing() {
        let w = world(), id = w.screens["D1"]!.active.id, other = UUID()
        #expect(report(.setPortions(other, key: "split#2", Portions(x: [0.3])), w) == .failed(.unknownWorkspace(other.uuidString)))
        #expect(report(.setPortions(id, key: "split#2", nil), w) == .noop("the tiles are already that size"))
    }

    /// Built from the config the store holds: what a command reads from config comes from here.
    @Test func theStoreBuildsItFromConfigLayoutsAndDisplays() {
        var config = Config()
        config.workspaceWrap = true
        config.categoryOrder = [.web]
        let d = [DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                             visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600), isMain: true)]
        let env = CommandEnvironment(config: config, layouts: .builtins, displays: d)
        #expect(env == CommandEnvironment(layouts: .builtins, displays: d, workspaceWrap: true, categoryOrder: [.web]))
    }
}
