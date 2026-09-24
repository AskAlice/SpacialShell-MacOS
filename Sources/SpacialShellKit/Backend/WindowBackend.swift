import Foundation
import CoreGraphics

public struct DisplayInfo: Equatable, Sendable, Hashable {
    public let id: DisplayID
    public let frame: CGRect          // top-left origin, y-down, global
    public let visibleFrame: CGRect   // minus menu bar and Dock
    public let isMain: Bool
    public init(id: DisplayID, frame: CGRect, visibleFrame: CGRect, isMain: Bool) {
        self.id = id; self.frame = frame; self.visibleFrame = visibleFrame; self.isMain = isMain
    }
}

public struct AppInfo: Equatable, Sendable, Hashable {
    public let pid: Int32
    public let bundleID: String?
    public let isHidden: Bool
    public init(pid: Int32, bundleID: String?, isHidden: Bool) { self.pid = pid; self.bundleID = bundleID; self.isHidden = isHidden }
}

public struct WindowSnapshot: Equatable, Sendable {
    public let ref: WindowRef
    public let frame: CGRect
    public let title: String
    public let bundleID: String?
    public let kind: WindowKind          // platform heuristic; Kit applies config overrides on top
    public let parent: WindowRef?
    public let isMinimized: Bool
    public let isFullscreen: Bool
    /// False for a window macOS has on another native Space (#55): alive, but not in the app's
    /// `kAXWindowsAttribute`, which lists only the Spaces on screen. A `var` so a replayed
    /// observation can be brought up to date without re-reading the window.
    public var onActiveSpace: Bool
    public init(ref: WindowRef, frame: CGRect, title: String, bundleID: String?, kind: WindowKind, parent: WindowRef?, isMinimized: Bool, isFullscreen: Bool,
                onActiveSpace: Bool = true) {
        self.ref = ref; self.frame = frame; self.title = title; self.bundleID = bundleID; self.kind = kind
        self.parent = parent; self.isMinimized = isMinimized; self.isFullscreen = isFullscreen
        self.onActiveSpace = onActiveSpace
    }
}

/// Full observation of reality. The store diffs it against the model. Spec §7.6.
public struct Snapshot: Equatable, Sendable {
    public var displays: [DisplayInfo]
    public var apps: [AppInfo]
    public var windows: [WindowSnapshot]
    public var focused: WindowRef?
    public var loginwindowFrontmost: Bool
    public init(displays: [DisplayInfo], apps: [AppInfo], windows: [WindowSnapshot], focused: WindowRef?, loginwindowFrontmost: Bool = false) {
        self.displays = displays; self.apps = apps; self.windows = windows; self.focused = focused; self.loginwindowFrontmost = loginwindowFrontmost
    }
}

public enum BackendEvent: Sendable, Equatable {
    case snapshot(Snapshot)
    /// macOS brought an app to the front (⌘Tab, the Dock, a click, `open`). Distinct from
    /// `focusChanged`, which only ever names a *window*: an app whose windows are all parked or
    /// minimized becomes frontmost with no focused window at all, so the shell heard nothing and
    /// left the user with a menu bar naming an app they could not see (#56, #57).
    case appActivated(pid: Int32)
    case windowMoved(WindowRef, CGRect)
    case windowResized(WindowRef, CGRect)
    case focusChanged(WindowRef?)
    /// A human just pressed a key or a mouse button (#28): the hotkey tap's keyDown — ⌘Tab
    /// included — or the global mouse monitors (button down, left drag). It carries no time: the store stamps it on
    /// arrival, and because it travels the same stream as `appActivated` and `focusChanged`, it is
    /// always seen before the focus change it caused.
    case humanInput
    case screenLocked
    case screenUnlocked
}

public enum BackendError: Error, Equatable, Sendable { case notFound, timeout, ax(Int32) }

public protocol WindowBackend: Sendable {
    func currentSnapshot() async -> Snapshot
    func setFrame(_ ref: WindowRef, _ frame: CGRect) async -> Result<Void, BackendError>
    func setPosition(_ ref: WindowRef, _ origin: CGPoint) async -> Result<Void, BackendError>
    func raise(_ ref: WindowRef) async -> Result<Void, BackendError>
    func close(_ ref: WindowRef) async -> Result<Void, BackendError>
    /// Put a window into, or take it out of, native macOS fullscreen (`AXFullScreen`). Used to
    /// leave fullscreen before a workspace switch on that display (#49); the shell never *enters*
    /// fullscreen on the user's behalf.
    func setFullscreen(_ ref: WindowRef, _ on: Bool) async -> Result<Void, BackendError>
    /// Bring a minimized or app-hidden window back (#48): clear `AXMinimized`, and unhide its app
    /// if ⌘H put it away. The shell never hides windows itself; this only undoes what the user or
    /// the app did, so that a tab click can deliver the window it names.
    func unhide(_ ref: WindowRef) async -> Result<Void, BackendError>
    var events: AsyncStream<BackendEvent> { get }
}
