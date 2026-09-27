import AppKit
import ImageIO
import os
import SpacialShellKit
import SpacialShellPlatform
import SpacialShellProtocol

/// #179: what hides everything but the peeked window while a rail preview is peeked.
///
/// An opaque panel over the peeked window's display — its desktop picture, or the window
/// background colour until (or where) the picture cannot be read — ordered directly below the
/// peeked window (`order(.below, relativeTo:)` its window-server number). Every other window is
/// covered where it is, never moved, and the shell's own panels, a level above, stay in front.
/// It takes the clicks that land on it: a click on what looks like the desktop must not reach a
/// window nobody can see.
///
/// Driven by the model, not the pointer: `update(peek:display:)` runs on every publish, so
/// whatever ends the peek — leaving the preview, a hotkey, a switch, the window closing — takes
/// the backdrop with it. That publish comes after the pass that placed and raised the window, so
/// its frame is settled by the time its window-server number is looked up; and each publish
/// orders the backdrop under it again, in case a raise since has gone over it.
@MainActor
final class PeekBackdrop {
    private static let log = Logger(subsystem: "sh.emu.SpacialShell", category: "peek")
    private let panel = BackdropPanel()
    private let picture = NSView()
    /// The peek the backdrop is for, and once it is found, the window-server number it sits under.
    private var target: (ref: SpacialShellProtocol.WindowRef, display: DisplayID, number: CGWindowID?)?
    private var lookup: Task<Void, Never>?
    /// Desktop pictures, decoded at their display's size, by file.
    private var pictures: [URL: CGImage] = [:]
    /// The number is matched on the window's frame, and a window just placed can take a moment to
    /// reach the window list there: this many tries, this far apart, before giving up.
    private static let lookupTries = 5
    private static let lookupInterval = Duration.milliseconds(60)

    init() {
        picture.wantsLayer = true
        picture.layer?.contentsGravity = .resizeAspectFill
        picture.layer?.masksToBounds = true
        panel.contentView = picture
    }

    /// `peek` is `World.peek`; `display` the display its row is on.
    func update(peek: SpacialShellProtocol.WindowRef?, display: DisplayID?) {
        guard let peek, let display else { hide(); return }
        if let t = target, t.ref == peek, t.display == display {
            if let n = t.number { panel.order(.below, relativeTo: Int(n)) }   // found: keep it just under
            return                                                            // still looking
        }
        // A swap to another preview keeps the backdrop up meanwhile (the new window is raised over
        // it already), so nothing behind flashes between the two; another display starts over.
        if target?.display != display { hide() }
        lookup?.cancel()
        guard let screen = NSScreen.screens.first(where: { DisplayTopology.uuid(for: $0) == display }) else { hide(); return }
        target = (peek, display, nil)
        let size = CGSize(width: screen.frame.width * screen.backingScaleFactor, height: screen.frame.height * screen.backingScaleFactor)
        let url = NSWorkspace.shared.desktopImageURL(for: screen)
        lookup = Task { [weak self] in
            // Off the main actor: the lookup reads the window's AX attributes and copies the window
            // list, and a hung app must not freeze the shell's panels with it.
            var number: CGWindowID?
            for attempt in 1...Self.lookupTries {
                number = await Task.detached { WindowIdentities.captureID(for: peek.id) }.value
                if number != nil || Task.isCancelled { break }
                if attempt < Self.lookupTries { try? await Task.sleep(for: Self.lookupInterval) }
            }
            guard let self, !Task.isCancelled, self.target?.ref == peek else { return }
            guard let number else {
                // Without its number the backdrop cannot go under it, and covering the window itself
                // would be worse than covering nothing: the peek shows the window, just not alone.
                Self.log.notice("peek backdrop: no window-server number for \(peek.id, privacy: .public)")
                return
            }
            self.target?.number = number
            self.picture.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            self.picture.layer?.contents = url.flatMap { self.pictures[$0] }
            self.panel.setFrame(screen.frame, display: false)
            self.panel.order(.below, relativeTo: Int(number))
            guard let url, self.pictures[url] == nil else { return }
            let image = await Task.detached { Self.decode(url, fitting: size) }.value
            guard !Task.isCancelled, self.target?.ref == peek, let image else { return }
            self.pictures[url] = image
            self.picture.layer?.contents = image
        }
    }

    func hide() {
        lookup?.cancel(); lookup = nil
        guard target != nil else { return }
        target = nil
        panel.orderOut(nil)
        picture.layer?.contents = nil
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

/// Normal level, so it can sit directly under another app's window; opaque, never key, and out of
/// Mission Control's and ⌘Tab's way like the rest of the shell's furniture.
private final class BackdropPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .normal
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
