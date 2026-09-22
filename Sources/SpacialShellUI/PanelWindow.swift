import AppKit

/// The chrome-less overlay both panels live in. Non-activating: a click on a rail or a tab must
/// not steal key status from the window the user is working in — the click's whole point is to
/// change focus through the model, not through AppKit.
/// Not `final`: `HighlightPanel` (T20) is the same furniture with two changes — click-through and
/// one level higher — and inheriting keeps the non-activating, never-key configuration in one place
/// rather than copied into a second window class that must stay in step with it.
class PanelWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating                       // above the tiled windows it describes
        backgroundColor = .clear                // the SwiftUI material is the only background
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Hover is a real interaction here (the rail's workspace previews), and a window that
        // can never become key has to ask for pointer movement explicitly.
        acceptsMouseMovedEvents = true
        // One native Space per display (README): the panels simply stay put everywhere, and stay
        // out of Mission Control's and ⌘Tab's way as far as macOS lets a window opt out. No
        // `.fullScreenAuxiliary`: another app's native fullscreen Space gets the whole display.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
    }

    // Never key, never main: the shell is furniture, not a window you are "in".
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
