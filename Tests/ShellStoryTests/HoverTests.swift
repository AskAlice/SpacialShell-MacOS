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
        let hover = RailHoverController(send: { sent.commands.append($0) })
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
        let hover = RailHoverController(send: { sent.commands.append($0) }, peekDwell: Self.dwell)
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
}
