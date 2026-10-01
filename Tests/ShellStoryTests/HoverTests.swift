import Testing
import AppKit
import SwiftUI
@testable import SpacialShellUI
@testable import SpacialShellKit

/// Does hovering a rail tile actually reach us?
///
/// The rail lives in a borderless, non-activating `NSPanel` that can never become key, in an
/// `LSUIElement` app. The tab drag failed silently under exactly those conditions — not because of
/// the panel, as it turned out, but the question was only settled by asking the view hierarchy
/// rather than by reading the code. Same technique here.
///
/// SwiftUI's `.onHover` is an `NSTrackingArea` underneath. A hierarchy with no tracking area can
/// never receive a mouse-entered event, so a failure here is conclusive in the unhappy direction.
/// It cannot prove a real pointer lands one; that needs a human.
@MainActor
@Suite(.serialized) struct HoverTests {
    let meta: (Int32) -> AppMeta = { _ in
        AppMeta(name: "App", icon: nil, bundleID: "com.apple.Safari", category: .web)
    }

    func railState() -> ScreenShellState {
        ScreenShellState(
            display: "D1", isFocusedScreen: true,
            rail: [WorkspaceRailItem(id: UUID(), index: 0, name: "Code", symbol: "terminal",
                                     windowCount: 1, windows: [WindowRef(id: 1, pid: 1)],
                                     isActive: true, isPinned: false, isTrailingEmpty: false)],
            tabs: [], layout: .split, layouts: .builtins)
    }

    func trackingAreaCount(_ v: NSView) -> Int {
        v.trackingAreas.count + v.subviews.reduce(0) { $0 + trackingAreaCount($1) }
    }

    func mount(in window: NSWindow) -> NSView {
        let host = NSHostingView(rootView: ScreenPanelView(
            state: railState(), launcherURL: "raycast://", metaFor: meta, send: { _ in }))
        host.frame = NSRect(x: 0, y: 0, width: 48, height: 800)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Tracking areas are installed via updateTrackingAreas once the view is in a window.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return host
    }

    /// The control. If this fails, hover is wired wrongly in a way that has nothing to do with
    /// the panel, and the panel result below means nothing.
    @Test func railInAnOrdinaryWindowInstallsTrackingAreas() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 48, height: 800),
                         styleMask: [.titled], backing: .buffered, defer: false)
        #expect(trackingAreaCount(mount(in: w)) > 0)
    }

    /// The real question: the same view in the window the shell actually uses.
    @Test func railInAPanelWindowInstallsTrackingAreas() {
        let panel = PanelWindow()
        panel.setFrame(NSRect(x: 0, y: 0, width: 48, height: 800), display: false)
        let n = trackingAreaCount(mount(in: panel))
        #expect(n > 0, "a rail with no tracking area can never receive a hover")
    }

    /// A tracking area is not enough on its own: an `NSWindow` only routes mouse-moved events when
    /// it is asked to, and a never-key panel is exactly the case where the default is unhelpful.
    @Test func thePanelAcceptsMouseMovedEvents() {
        #expect(PanelWindow().acceptsMouseMovedEvents)
    }

    /// #51: a preview click is a tab click — `.focusWindowRef`, which activates the window's
    /// workspace and focuses its tab — and the card does not outlive the switch it caused.
    @Test func clickingAPreviewFocusesItsWindowAndClosesTheCard() {
        final class Sent: @unchecked Sendable { var commands: [Command] = [] }
        let sent = Sent()
        let hover = RailHoverController(send: { sent.commands.append($0) }, present: { _ in })
        let item = railState().rail[0]
        hover.show(item: item, tile: NSRect(x: 0, y: 400, width: 48, height: 48), railSide: .left,
                   bounds: NSRect(x: 0, y: 0, width: 1440, height: 900), metaFor: meta)
        #expect(hover.shownWorkspace == item.id)

        hover.select(WindowRef(id: 1, pid: 1))

        #expect(sent.commands == [.focusWindowRef(WindowRef(id: 1, pid: 1))])
        #expect(hover.shownWorkspace == nil)
    }

    final class Sent: @unchecked Sendable { var commands: [Command] = [] }
    static let dwell = Duration.milliseconds(40)
    func settle() async { try? await Task.sleep(for: Self.dwell * 3) }
    func shownCard(_ sent: Sent) -> (RailHoverController, WorkspaceRailItem) {
        let hover = RailHoverController(send: { sent.commands.append($0) }, peekDwell: Self.dwell, present: { _ in })
        let item = railState().rail[0]
        hover.show(item: item, tile: NSRect(x: 0, y: 400, width: 48, height: 48), railSide: .left,
                   bounds: NSRect(x: 0, y: 0, width: 1440, height: 900), metaFor: meta)
        return (hover, item)
    }

    /// #179: resting on a preview rings it at once and peeks its window after the dwell; leaving it
    /// ends the peek after the same dwell.
    @Test func restingOnAPreviewHighlightsItThenPeeksItsWindow() async {
        let sent = Sent()
        let (hover, _) = shownCard(sent)
        let x = WindowRef(id: 1, pid: 1)
        hover.previewHovered(x, inside: true)
        #expect(hover.peekState.highlighted == x)
        #expect(sent.commands.isEmpty, "nothing moves before the dwell")
        await settle()
        #expect(sent.commands == [.peek(x)])
        hover.previewHovered(x, inside: false)
        #expect(hover.peekState.highlighted == nil)
        await settle()
        #expect(sent.commands == [.peek(x), .peek(nil)])
    }

    /// Crossing the card fires nothing; moving to another preview swaps the peek directly.
    @Test func crossingPreviewsSwapsThePeekWithoutRestoringInBetween() async {
        let sent = Sent()
        let (hover, _) = shownCard(sent)
        let x = WindowRef(id: 1, pid: 1), y = WindowRef(id: 2, pid: 2), z = WindowRef(id: 3, pid: 3)
        hover.previewHovered(x, inside: true); hover.previewHovered(x, inside: false)
        hover.previewHovered(y, inside: true); hover.previewHovered(y, inside: false)
        #expect(sent.commands.isEmpty, "a sweep across the card peeks nothing")
        hover.previewHovered(z, inside: true)
        await settle()
        #expect(sent.commands == [.peek(z)])
        hover.previewHovered(z, inside: false)
        hover.previewHovered(y, inside: true)
        hover.previewHovered(z, inside: false)   // a late exit from the one already left
        await settle()
        #expect(sent.commands == [.peek(z), .peek(y)], "a swap, with no .peek(nil) in between")
        #expect(hover.peekState.highlighted == y)
    }

    /// The card going ends the peek at once; a click focuses the window and sends nothing after it.
    @Test func closingTheCardEndsThePeekAndAClickLeavesTheWindowFocused() async {
        let sent = Sent()
        let (hover, _) = shownCard(sent)
        let x = WindowRef(id: 1, pid: 1)
        hover.previewHovered(x, inside: true)
        await settle()
        hover.hideNow()
        #expect(sent.commands == [.peek(x), .peek(nil)])

        let clicked = Sent()
        let (again, _) = shownCard(clicked)
        again.previewHovered(x, inside: true)
        await settle()
        again.select(x)
        await settle()
        #expect(clicked.commands == [.peek(x), .focusWindowRef(x)])
        #expect(again.peekState.highlighted == nil && again.peekState.peeking == nil)
    }

    /// Commands reach the store in separate tasks, so a `.peek` can land after the click that
    /// should have ended it (and a `.peek(nil)` sent while locked is refused): a published peek the
    /// card no longer wants, and is not about to ask for, is ended.
    @Test func aPeekTheCardNoLongerWantsIsEnded() async {
        let sent = Sent()
        let (hover, _) = shownCard(sent)
        let x = WindowRef(id: 1, pid: 1), y = WindowRef(id: 2, pid: 2)
        hover.previewHovered(x, inside: true)
        await settle()
        hover.modelPeeked(x)                      // wanted
        hover.previewHovered(x, inside: false); hover.previewHovered(y, inside: true)
        hover.modelPeeked(x)                      // y's peek is on its way
        #expect(sent.commands == [.peek(x)])
        await settle()
        hover.select(y)
        hover.modelPeeked(y)                      // the late `.peek(y)`, after the click
        #expect(sent.commands == [.peek(x), .peek(y), .focusWindowRef(y), .peek(nil)])
        hover.modelPeeked(nil)
        #expect(sent.commands.count == 4)
    }

    // MARK: - #182: the card never outlives the pointer

    /// A pointer, a clock and a rail the test moves by hand.
    final class Stage {
        var pointer = CGPoint(x: 24, y: 424)   // on the tile
        var clock = ContinuousClock.now
        var rail: CGRect? = CGRect(x: 0, y: 0, width: 48, height: 900)
    }

    func shownCard(_ stage: Stage, _ item: WorkspaceRailItem) -> RailHoverController {
        let hover = RailHoverController(send: { _ in }, pointer: { stage.pointer }, now: { stage.clock }, present: { _ in })
        hover.railFrame = { stage.rail }
        hover.show(item: item, tile: NSRect(x: 0, y: 400, width: 48, height: 48), railSide: .left,
                   bounds: NSRect(x: 0, y: 0, width: 1440, height: 900), metaFor: meta)
        #expect(hover.shownWorkspace == item.id)
        return hover
    }

    /// No tile reports an exit once it is gone: the re-render itself has to take the card away.
    @Test func theCardGoesWhenItsWorkspaceLeavesTheRail() {
        let stage = Stage()
        let state = railState()
        let hover = shownCard(stage, state.rail[0])

        hover.railChanged(state)   // an unrelated re-render keeps it
        #expect(hover.shownWorkspace == state.rail[0].id)

        hover.railChanged(ScreenShellState(display: "D1", isFocusedScreen: true, rail: [], tabs: [],
                                           layout: .split, layouts: .builtins))
        #expect(hover.shownWorkspace == nil)
    }

    /// #203: a window closing (or opening) in the shown row keeps the card, which follows it.
    @Test func theCardFollowsItsRowWhenAWindowCloses() {
        let stage = Stage()
        let item = railState().rail[0]
        let hover = shownCard(stage, item)
        let fewer = WorkspaceRailItem(id: item.id, index: item.index, name: item.name, symbol: item.symbol,
                                      windowCount: max(0, item.windowCount - 1), windows: Array(item.windows.dropLast()),
                                      isActive: item.isActive, isPinned: false, isTrailingEmpty: false)
        hover.railChanged(ScreenShellState(display: "D1", isFocusedScreen: true, rail: [fewer], tabs: [],
                                           layout: .split, layouts: .builtins))
        #expect(hover.shownWorkspace == item.id, "same row, one window fewer: still shown")
    }

    /// Still there but at another row: the card would sit beside some other tile.
    @Test func theCardGoesWhenItsWorkspaceMoves() {
        let stage = Stage()
        let item = railState().rail[0]
        let hover = shownCard(stage, item)
        let moved = WorkspaceRailItem(id: item.id, index: 1, name: item.name, symbol: item.symbol,
                                      windowCount: 1, windows: item.windows,
                                      isActive: true, isPinned: false, isTrailingEmpty: false)
        let above = WorkspaceRailItem(id: UUID(), index: 0, name: "Web", symbol: "globe", windowCount: 0,
                                      isActive: false, isPinned: false, isTrailingEmpty: false)
        hover.railChanged(ScreenShellState(display: "D1", isFocusedScreen: true, rail: [above, moved], tabs: [],
                                           layout: .split, layouts: .builtins))
        #expect(hover.shownWorkspace == nil)
    }

    /// The pointer left rail and card without any exit being delivered — across a screen edge, or
    /// faster than SwiftUI noticed. The card goes once the grace is up, not before.
    @Test func theCardGoesOnceThePointerHasBeenOffRailAndCardForTheGrace() {
        let stage = Stage()
        let hover = shownCard(stage, railState().rail[0])

        stage.pointer = CGPoint(x: 900, y: 100)
        hover.checkPointer()
        #expect(hover.shownWorkspace != nil, "the grace covers the gap between tile and card")
        stage.clock += .milliseconds(100)
        hover.checkPointer()
        #expect(hover.shownWorkspace != nil)
        stage.clock += .milliseconds(100)
        hover.checkPointer()
        #expect(hover.shownWorkspace == nil)
    }

    /// On the rail, or back on it within the grace, the card stays — the tile's own exit decides.
    @Test func theCardStaysWhileThePointerIsOnTheRail() {
        let stage = Stage()
        let hover = shownCard(stage, railState().rail[0])

        stage.pointer = CGPoint(x: 900, y: 100)
        hover.checkPointer()
        stage.clock += .milliseconds(100)
        stage.pointer = CGPoint(x: 24, y: 700)   // back on the rail, on another row
        hover.checkPointer()
        stage.clock += .seconds(1)
        hover.checkPointer()
        #expect(hover.shownWorkspace != nil)
    }

    /// An auto-hiding rail that slid away is not "on the rail" any more, however still the pointer.
    @Test func aRailThatIsGoneDoesNotHoldTheCard() {
        let stage = Stage()
        let hover = shownCard(stage, railState().rail[0])

        stage.rail = nil
        hover.checkPointer()
        stage.clock += .milliseconds(200)
        hover.checkPointer()
        #expect(hover.shownWorkspace == nil)
    }
}
