import AppKit
import CoreGraphics
import ScreenCaptureKit
import SpacialShellKit
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
                       longSide: CGFloat) async -> [WindowID: CGImage] {
        guard !refs.isEmpty, ScreenRecordingAccess.isGranted else { return [:] }
        // onScreenWindowsOnly: false — a window in an inactive workspace is parked in a corner
        // sliver, and an inactive workspace is exactly the one worth previewing.
        guard let content = await CaptureGate.listing({
            try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        }) else { return [:] }

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

        var out: [WindowID: CGImage] = [:]
        for ref in refs {
            if Task.isCancelled { break }
            guard let cgID = captureIDs[ref.id], let window = candidates[cgID] else { continue }
            let size = window.frame.size
            guard size.width > 0, size.height > 0 else { continue }

            let config = SCStreamConfiguration()
            let scale = min(1, longSide / max(size.width, size.height))
            config.width = max(1, Int((size.width * scale).rounded()))
            config.height = max(1, Int((size.height * scale).rounded()))
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            guard let cgImage = await CaptureGate.image({
                try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            }) else { continue }
            out[ref.id] = cgImage
        }
        return out
    }
}

/// #90: the last downscaled picture of every window, so the rail hover card draws in its first
/// frame. The policy (LRU, the cap, staleness, eviction) is `ThumbnailCache` in Kit; this holds the
/// pixels. Fed by #77's switch pictures via `ingest`, the hover's own refresh via `add`, and #142's
/// background preload and refresh (`ThumbnailRefresher`), which skips what those keep fresh.
@MainActor
final class WindowThumbnails {
    static let shared = WindowThumbnails()
    /// Pixels on the long side: sharp in the card's 148 pt grid tile on Retina and close enough in
    /// the one-window 304 pt frame; 256 looked soft there. The cap in `ThumbnailCache` bounds memory.
    nonisolated static let longSide: CGFloat = 400
    private var cache = ThumbnailCache<CGImage>()

    func image(for id: WindowID) -> NSImage? {
        cache.image(for: id).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }
    func isStale(_ id: WindowID) -> Bool { cache.isStale(id) }
    func taken(_ id: WindowID) -> ContinuousClock.Instant? { cache.taken(id) }
    /// Every window the store still knows; the rest have closed.
    func retain(_ live: Set<WindowID>) { cache.retain(live) }

    /// Fire and forget: the one-line hook for pictures taken for something else. Returns at once;
    /// the downscale runs at utility priority, off the main actor.
    func ingest(_ images: some Sequence<(key: WindowID, value: CGImage)>) {
        let batch = Array(images), taken = ContinuousClock.now
        Task { await add(batch, taken: taken) }
    }

    func add(_ images: [(key: WindowID, value: CGImage)], taken: ContinuousClock.Instant) async {
        guard !images.isEmpty else { return }
        let small = await Task.detached(priority: .utility) {
            images.compactMap { e in Self.downscale(e.value).map { (e.key, $0) } }
        }.value
        for (id, image) in small { cache.insert(image, for: id, taken: taken) }
    }

    /// `longSide` pixels on the long side, in the source's own colour space (sRGB if that is not
    /// an RGB space a bitmap context can draw into). Nil rather than the full-size original on
    /// failure, so the cache's memory bound holds.
    nonisolated static func downscale(_ image: CGImage) -> CGImage? {
        let long = CGFloat(max(image.width, image.height))
        guard long > longSide else { return image }
        let s = longSide / long
        let w = max(1, Int((CGFloat(image.width) * s).rounded())), h = max(1, Int((CGFloat(image.height) * s).rounded()))
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}

/// Window titles for the rail tray (#73), read from AX when the tray opens. The model keeps none —
/// a title changes with every tab switch in a browser, and nothing spatial depends on it — so like
/// a preview it is fetched per open and dropped with the card. `nonisolated async`, so it runs off
/// the main actor: an AX read to a hung app blocks for its messaging timeout. A window AX will not
/// name is simply absent, and the row keeps the app's name instead.
enum WindowTitles {
    static func titles(for refs: [SpacialShellProtocol.WindowRef]) async -> [WindowID: String] {
        var out: [WindowID: String] = [:]
        for ref in refs {
            if Task.isCancelled { break }
            guard let element = WindowIdentities.element(for: ref.id) else { continue }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
                  let title = value as? String, !title.isEmpty else { continue }
            out[ref.id] = title
        }
        return out
    }
}

/// #199: a window's thumbnail as a PNG on disk, for clients outside the shell (Raycast's Switch to
/// Window… shows it beside the list). Taken now when missing or stale, then written to
/// `~/Library/Caches/sh.emu.SpacialShell/previews/<id>.png`, overwritten each time.
// ponytail: one file per window, never pruned; a closed window's PNG lingers in Caches until the
// next preview of that id overwrites it or macOS purges the cache. Prune on `retain` if it matters.
public enum WindowPreviewFile {
    public struct NoPicture: LocalizedError {
        public var errorDescription: String? {
            "no picture of that window (it may not be capturable, or Screen Recording is not granted)"
        }
    }

    @MainActor
    public static func write(_ ref: SpacialShellProtocol.WindowRef) async throws -> String {
        let thumbs = WindowThumbnails.shared
        if thumbs.isStale(ref.id) {
            let taken = ContinuousClock.now
            let images = await WindowPreviewCapture.images(for: [ref], longSide: WindowThumbnails.longSide)
            await thumbs.add(Array(images), taken: taken)
        }
        guard let image = thumbs.image(for: ref.id),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else { throw NoPicture() }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sh.emu.SpacialShell/previews", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(ref.id).png")
        try png.write(to: file, options: .atomic)
        return file.path
    }
}
