import AppKit

/// The overview/launcher's window: Spotlight-shaped. Unlike `PanelWindow` it *does* become key —
/// the search field needs typing — but stays `.nonactivatingPanel`, so taking key does not
/// activate SpacialShell or reorder anyone's windows. Esc and clicking outside both dismiss.
final class OverviewPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)   // above the shell panels
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc lands here from anywhere in the view hierarchy.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// Clicking anywhere else takes key status away; a launcher that lingers after that is stale.
    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }
}
