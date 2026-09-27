import Testing
import Foundation
import CoreGraphics
@testable import SpacialShellKit

/// #132 (M3 B9): the spatialisation view's state, camera and triggers.
@Suite struct SpatialViewTests {
    let d: DisplayID = "D1"
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 2), c = WindowRef(id: 3, pid: 3)
    let e = WindowRef(id: 4, pid: 4), f = WindowRef(id: 5, pid: 5)

    /// Row 0: split, three windows, focus on the third (so the view shows b, c). Row 1: maximize,
    /// e floating and f tiled. Row 2: the trailing empty one.
    func world() -> World {
        var split = Workspace(name: "Code", layout: .split, windows: [a, b, c], anchor: c, category: .coding)
        split.splitStart = b
        return World(
            screens: [d: Screen(display: d, workspaces: [
                split,
                Workspace(name: "Web", layout: .maximize, windows: [e, f], floating: [e], anchor: f),
                Workspace(name: "Workspace", layout: .maximize)], activeIndex: 1)],
            screenOrder: [d], focus: Focus(screen: d, window: f),
            ephemeral: [], ignored: [], hidden: [], parents: [:], defaultLayout: .maximize)
    }

    func state() throws -> SpatialState {
        try #require(SpatialView.state(for: d, in: world(), layouts: .builtins, titles: [c: "main.swift"],
                                       viewport: CGSize(width: 1600, height: 1000), gap: 0))
    }

    @Test func everyRowIsAMiniDesktopInStackOrder() throws {
        let s = try state()
        #expect(s.rows.map(\.name) == ["Code", "Web", "Workspace"])
        #expect(s.rows.map(\.isActive) == [false, true, false])
        #expect(s.rows.map(\.isTrailingEmpty) == [false, false, true])
        #expect(s.activeIndex == 1)
        #expect(s.aspect == 1.6)
        #expect(s.rows[0].category == .coding)
    }

    /// Chips sit where the row's layout frames its windows, in unit coordinates; the rest of the
    /// row (off split's view, floating) is beside the desktop, not on it.
    @Test func chipsAreTheLayoutsFramesAndTheRestWaitsBeside() throws {
        let s = try state()
        let code = s.rows[0]
        #expect(code.chips.map(\.ref) == [b, c])
        #expect(code.chips.map(\.frame) == [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)])
        #expect(code.chips.map(\.title) == ["", "main.swift"])
        #expect(code.offscreen == [a])
        let web = s.rows[1]
        #expect(web.chips.map(\.ref) == [f] && web.chips[0].frame == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(web.chips[0].isFocused)
        #expect(web.offscreen == [e])
        #expect(web.windows == [f, e])
        #expect(s.rows[2].chips.isEmpty && s.rows[2].offscreen.isEmpty)
    }

    @Test func noViewportNoState() {
        #expect(SpatialView.state(for: d, in: world(), layouts: .builtins, viewport: .zero) == nil)
        #expect(SpatialView.state(for: "elsewhere", in: world(), layouts: .builtins, viewport: CGSize(width: 10, height: 10)) == nil)
    }

    /// The camera centres the active row; moving a row moves it by exactly one row and a gap.
    @Test func theCameraCentresTheActiveRow() {
        #expect(SpatialView.cameraOffset(active: 0, rowHeight: 200, spacing: 20, viewHeight: 1000) == 400)
        #expect(SpatialView.cameraOffset(active: 1, rowHeight: 200, spacing: 20, viewHeight: 1000) == 180)
        #expect(SpatialView.cameraOffset(active: 3, rowHeight: 200, spacing: 20, viewHeight: 1000) == -260)
    }

    @Test func holdingTheWorkspaceKeysOpensIt() {
        #expect(SpatialView.opensOnHold(.focusWorkspace(.up)) && SpatialView.opensOnHold(.focusWorkspace(.down)))
        #expect(SpatialView.opensOnHold(.moveWindowToWorkspace(.down)))
        #expect(!SpatialView.opensOnHold(.focusWindow(.left)) && !SpatialView.opensOnHold(.cycleLayout))
    }

    /// A held-open view lands when the preset's modifier goes, not when W is let go.
    @Test func itStaysWhileTheModifierIsHeld() {
        #expect(SpatialView.isHeld([.maskSecondaryFn], preset: .fn))
        #expect(SpatialView.isHeld([.maskSecondaryFn, .maskShift], preset: .fn))
        #expect(!SpatialView.isHeld([], preset: .fn))
        #expect(SpatialView.isHeld([.maskControl, .maskAlternate], preset: .ctrlAlt))
        #expect(!SpatialView.isHeld([.maskControl], preset: .ctrlAlt))
    }

    /// Fn+Z (⌃⌥Z on ctrl-alt), app-layer, a no-op in the model, and on the cheat sheet.
    @Test func toggleIsABoundAppLayerCommand() throws {
        #expect(KeyBindings.table(for: Config())[try #require(KeyBindings.parse("fn-z"))] == .toggleSpatialView)
        var ctrlAlt = Config(); ctrlAlt.keybindingPreset = .ctrlAlt
        #expect(KeyBindings.table(for: ctrlAlt)[try #require(KeyBindings.parse("ctrl-alt-z"))] == .toggleSpatialView)
        #expect(KeyBindings.command(named: "toggle-spatial-view") == .toggleSpatialView)
        #expect(Command.toggleSpatialView.isAppLayer)
        // The runner normalises any world it is given, so the no-op is judged against the overview's.
        let before = world()
        let out = CommandRunner.run(.toggleSpatialView, on: before, in: .test())
        #expect(out.world == CommandRunner.run(.toggleOverview, on: before, in: .test()).world && out.effects.isEmpty)
        #expect(CheatSheet.rows(for: Config()).contains { $0.commandName == "toggle-spatial-view" && $0.chords == ["Fn+Z"] })
    }
}
