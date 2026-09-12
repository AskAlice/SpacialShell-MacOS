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
            tabs: [], layout: .split)
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
}
