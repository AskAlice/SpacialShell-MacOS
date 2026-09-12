import AppKit
import CoreGraphics
import ScreenCaptureKit
import SpacialShellPlatform
import SpacialShellProtocol

/// One window as the rail's hover card draws it: what it is, and — once the capture lands — what
/// it currently looks like. `image` is nil while the shot is in flight and stays nil for a window
/// ScreenCaptureKit would not hand over, so the card always has a name and an icon to fall back on.
struct WindowPreviewItem: Identifiable {
    let ref: SpacialShellProtocol.WindowRef
    let name: String
    let icon: NSImage?
    var image: NSImage?
    var id: SpacialShellProtocol.WindowRef { ref }
}

/// The second TCC grant (Accessibility moves windows; this one reads their pixels).
///
/// `CGPreflightScreenCaptureAccess` is the check that matters, because without the grant capture
/// does not *fail* — ScreenCaptureKit hands back a frame of desktop wallpaper, which as an empty
/// grey box in the hover card is indistinguishable from a window that happens to be blank. So the
/// card asks this first and says so, rather than drawing nothing and letting the user guess.
enum ScreenRecordingAccess {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompt, then open the pane. The request is what puts SpacialShell in the list at all — the
    /// Screen Recording pane shows apps that have asked — and the grant only takes effect on the
    /// next launch, which is why the card says "then restart" instead of pretending to poll.
    static func request() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum WindowPreviewCapture {
    /// One `SCScreenshotManager` frame per window, in the order given. Per hover, never a stream:
    /// an `SCStream` would keep a capture session (and its power cost) alive for as long as the
    /// rail exists, to show something nobody is looking at.
    ///
    /// The filter is `desktopIndependentWindow`, so each shot contains exactly one window and
    /// structurally cannot contain the rail that is drawing the preview. Our own pid is dropped
    /// from the candidate map too, so a stale `WindowRef` can never resolve onto a shell panel.
    ///
    /// Cancellation is checked between windows: sweeping down the rail starts and abandons a
    /// capture per tile, and the abandoned ones must stop at the next boundary rather than run on.
    static func images(for refs: [SpacialShellProtocol.WindowRef],
                       pixelHeight: CGFloat) async -> [WindowID: NSImage] {
        guard !refs.isEmpty, ScreenRecordingAccess.isGranted else { return [:] }
        // onScreenWindowsOnly: false — a window in an inactive workspace is parked in a corner
        // sliver, and an inactive workspace is exactly the one worth previewing.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: false) else { return [:] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var candidates: [CGWindowID: SCWindow] = [:]
        for window in content.windows where window.owningApplication?.processID != ownPID {
            candidates[window.windowID] = window
        }
        // Since #18 `ref.id` is minted by SpacialShell, not a window-server handle, so it cannot
        // index `SCWindow.windowID` directly any more. `captureIDs` does the public match, and
        // returns nothing for a window it cannot pin down — in which case the card falls back to
        // the name and icon it already has. A missing thumbnail is the whole cost.
        let captureIDs = WindowIdentities.captureIDs(for: refs.map(\.id))

        var out: [WindowID: NSImage] = [:]
        for ref in refs {
            if Task.isCancelled { break }
            guard let cgID = captureIDs[ref.id], let window = candidates[cgID] else { continue }
            let size = window.frame.size
            guard size.width > 0, size.height > 0 else { continue }

            let config = SCStreamConfiguration()
            let scale = min(1, pixelHeight / size.height)
            config.width = max(1, Int((size.width * scale).rounded()))
            config.height = max(1, Int((size.height * scale).rounded()))
            config.showsCursor = false
            guard let cgImage = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: config) else { continue }
            out[ref.id] = NSImage(cgImage: cgImage,
                                  size: NSSize(width: config.width, height: config.height))
        }
        return out
    }
}
