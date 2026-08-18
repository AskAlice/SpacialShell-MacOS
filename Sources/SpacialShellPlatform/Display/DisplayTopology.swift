import AppKit
import CoreGraphics
import SpacialShellKit

/// Spec §7.8. The one place NSScreen's bottom-left, y-up geometry becomes the top-left, y-down
/// geometry everything else (AX, `Layout`, `World`) speaks. Rebuilt on every access: NSScreen
/// caches nothing useful across a hot-plug, and a stale topology places windows off-screen.
enum DisplayTopology {
    /// NSScreen (bottom-left, y-up) → AX (top-left, y-down). `mainHeight` is the height of the
    /// screen whose frame origin is (0,0) — the origin both coordinate systems share.
    static func flip(_ r: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Spec §7.8: identity is the display's UUID, which survives unplug/replug, not the
    /// `CGDirectDisplayID` (recycled) and not the top-left point (moves when you rearrange).
    static func uuid(for screen: NSScreen) -> DisplayID {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            // Deviation from the brief, which force-casts: a missing `NSScreenNumber` must not
            // crash the window manager. The frame is a unique-enough stand-in — screens never
            // overlap — and it keeps every id non-empty.
            return "display-at-\(Int(screen.frame.minX)),\(Int(screen.frame.minY))"
        }
        guard let cf = CGDisplayCreateUUIDFromDisplayID(num)?.takeRetainedValue() else { return "display-\(num)" }
        return CFUUIDCreateString(nil, cf) as String
    }

    /// Spec §7.8: main = the screen at origin (0,0), never `NSScreen.main` — that one follows the
    /// key window and lies inside activation callbacks (AeroSpace's note).
    @MainActor static func current() -> [DisplayInfo] {
        let screens = NSScreen.screens
        let main = screens.first { $0.frame.origin == .zero } ?? screens.first
        let h = main?.frame.height ?? 0
        return screens.map { s in
            DisplayInfo(
                id: uuid(for: s),
                frame: flip(s.frame, mainHeight: h),
                visibleFrame: flip(s.visibleFrame, mainHeight: h),
                isMain: s === main,
            )
        }
    }
}
