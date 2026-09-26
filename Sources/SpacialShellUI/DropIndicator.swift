import AppKit
import SwiftUI

/// #108: the tile a dragged window would swap with — the active-tab treatment (18 % accent fill)
/// with an accent edge, so it reads over any window content.
struct DropTargetView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 3))
    }
}

/// #113: the border between two tiles under the pointer, or in the hand — a solid accent bar in
/// the gap, so the edge you can drag is the edge you see.
struct BorderTargetView: View {
    var body: some View {
        Capsule(style: .continuous).fill(Color.accentColor)
    }
}

/// Owns the click-through panel `DropTargetView` lives in. `WorldStore` aims it at a tile
/// (top-left global) or nil; it fades in, glides between tiles and fades out in 180 ms — instant
/// under Reduce Motion. #113 reuses it, with `BorderTargetView`, for the resize border.
@MainActor
public final class DropIndicator {
    private let panel: PanelWindow

    public convenience init() { self.init(DropTargetView()) }

    /// #113: the border highlight.
    public static func border() -> DropIndicator { DropIndicator(BorderTargetView()) }

    init<V: View>(_ view: V) {
        let p = PanelWindow()
        p.ignoresMouseEvents = true      // the drag's mouse-up must reach whatever is underneath
        p.contentView = NSHostingView(rootView: view)
        p.alphaValue = 0
        panel = p
    }

    public func show(_ frame: CGRect?) {
        let instant = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = instant ? 0 : 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            guard let frame else { panel.animator().alphaValue = 0; return }
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            let rect = NSRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
            if panel.alphaValue == 0 || instant {
                panel.setFrame(rect, display: true)
            } else {
                panel.animator().setFrame(rect, display: true)
            }
            panel.orderFrontRegardless()
            panel.animator().alphaValue = 1
        }
    }
}
