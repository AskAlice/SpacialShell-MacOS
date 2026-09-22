import AppKit
import SwiftUI
import SpacialShellKit

/// The focus ring: a persistent accent stroke around the focused window, drawn at the frame the
/// reconciler is *about* to tile it at, so it lands before the window does (M2 design, Motion).
/// One per display, sized to the display's visible frame, and never in the way of a click.
final class HighlightPanel: PanelWindow {
    override init() {
        super.init()
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }
}

struct FocusRingView: View {
    /// The ring's frame in this view's own top-left coordinates, nil = no ring.
    let frame: CGRect?
    let color: Color
    /// nil animates nothing (`highlight-ms = 0`).
    let animation: Animation?

    static let lineWidth: CGFloat = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let f = frame {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color, lineWidth: Self.lineWidth)
                    .frame(width: f.width, height: f.height)
                    .offset(x: f.minX, y: f.minY)
                    .animation(animation, value: f)
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
    }

    /// `highlight-color` → the stroke; "system" is the accent.
    static func color(for config: Config) -> Color {
        if let (r, g, b, a) = HighlightColor.rgba(config.highlightColor) {
            return Color(red: r, green: g, blue: b, opacity: a)
        }
        return .accentColor
    }

    static func animation(for config: Config) -> Animation? {
        config.highlightMs > 0 ? .spring(duration: Double(config.highlightMs) / 1000) : nil
    }
}
