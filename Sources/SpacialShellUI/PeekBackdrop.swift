import AppKit
import ImageIO
import SpacialShellKit
import SpacialShellPlatform
import SpacialShellProtocol

/// #179: what shows the peeked window, alone, while a rail preview is peeked.
///
/// An opaque panel over the peeked window's display: its desktop picture (or the window
/// background colour until, or where, the picture cannot be read), and on it a picture of the
/// peeked window at `PeekPreview.frame`, where clicking the preview would put it. It sits above
/// every ordinary window and below the shell's own panels, so the rail and the card stay in front.
///
/// #222: the real window used to be centred, resized and raised under it without activating its
/// app. macOS only orders a window above another app's windows when its own app activates, and
/// activating would take the keyboard from the focused window, so it stayed under the frontmost
/// app and the peek showed nothing; and when it did show, it was not where a click would put
/// it. Now nothing moves: the cached thumbnail shows at once, then a fresh full-size capture.
///
/// It takes the clicks that land on it: a click on what looks like the desktop must not reach a
/// window nobody can see. Driven by the store (`onPeek`), not the pointer, so whatever ends the
/// peek (leaving the preview, a hotkey, a switch, the window closing) takes the backdrop with it.
@MainActor
final class PeekBackdrop {
    private let panel = BackdropPanel()
    private let picture = NSView()
    /// The peeked window's picture, on the desktop picture.
    private let shot = CALayer()
    private var shown: PeekPreview?
    private var capture: Task<Void, Never>?
    /// Desktop pictures, decoded at their display's size, by file.
    private var pictures: [URL: CGImage] = [:]

    init() {
        picture.wantsLayer = true
        picture.layer?.contentsGravity = .resizeAspectFill
        picture.layer?.masksToBounds = true
        shot.contentsGravity = .resizeAspect
        shot.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        picture.layer?.addSublayer(shot)
        panel.contentView = picture
    }

    func update(_ preview: PeekPreview?) {
        guard preview != shown else { return }
        guard let preview,
              let screen = NSScreen.screens.first(where: { DisplayTopology.uuid(for: $0) == preview.display }),
              let primary = NSScreen.screens.first else { hide(); return }
        let swap = shown?.display == preview.display   // another preview: keep the backdrop up meanwhile
        shown = preview
        capture?.cancel()
        // Top-left global → this panel's bottom-left local.
        let f = preview.frame
        let slot = CGRect(x: f.minX - screen.frame.minX, y: primary.frame.maxY - f.maxY - screen.frame.minY,
                          width: f.width, height: f.height)
        let url = NSWorkspace.shared.desktopImageURL(for: screen)
        if !swap {
            picture.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            picture.layer?.contents = url.flatMap { pictures[$0] }
        }
        // Until the fresh picture lands: the card's thumbnail, scaled up. Soft, but the right window.
        show(WindowThumbnails.shared.image(for: preview.window.id)?.cgImage(forProposedRect: nil, context: nil, hints: nil), in: slot)
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
        let size = CGSize(width: screen.frame.width * screen.backingScaleFactor, height: screen.frame.height * screen.backingScaleFactor)
        let longSide = max(slot.width, slot.height) * screen.backingScaleFactor
        capture = Task { [weak self] in
            // The desktop picture decodes beside the capture, not before it: a large wallpaper
            // must not hold the window's own picture back.
            async let desktop: CGImage? = if let url, self?.pictures[url] == nil {
                await Task.detached { Self.decode(url, fitting: size) }.value
            } else { nil }
            let fresh = await WindowPreviewCapture.images(for: [preview.window], longSide: longSide)[preview.window.id]
            guard !Task.isCancelled, let self, self.shown == preview else { return }
            if let fresh { self.show(fresh, in: slot) }
            if let url, let image = await desktop, !Task.isCancelled, self.shown == preview {
                self.pictures[url] = image
                self.picture.layer?.contents = image
            }
        }
    }

    /// The window's picture, aspect-fitted into `slot` (panel coordinates).
    private func show(_ image: CGImage?, in slot: CGRect) {
        shot.contents = image
        guard let image, image.width > 0, image.height > 0 else { shot.frame = .zero; return }
        let scale = min(slot.width / CGFloat(image.width), slot.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        shot.frame = CGRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2,
                            width: size.width, height: size.height).integral
    }

    func hide() {
        capture?.cancel(); capture = nil
        guard shown != nil else { return }
        shown = nil
        panel.orderOut(nil)
        picture.layer?.contents = nil
        shot.contents = nil
    }

    /// The desktop picture decoded once, no larger than its display: a 6K wallpaper file is not
    /// decoded at full size to be drawn at screen size.
    private nonisolated static func decode(_ url: URL, fitting size: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Above every ordinary window and below the shell's panels (`.floating`); opaque, never key, and
/// out of Mission Control's and ⌘Tab's way like the rest of the shell's furniture.
private final class BackdropPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
