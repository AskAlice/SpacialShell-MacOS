import SwiftUI
import SpacialShellKit

extension View {
    /// Every rail and tab-bar button (#93). The panels are non-activating and never key, so no
    /// control in them may take keyboard focus: with Full Keyboard Access on, a layout button drew
    /// the focus ring anyway. Out of the key-view loop, and no focus effect if one is drawn regardless.
    func panelButton() -> some View {
        buttonStyle(.plain).focusable(false).focusEffectDisabled()
    }
}

/// What the rail and the tab bar are painted with.
///
/// Both panels take this rather than hardcoding `.thinMaterial`, which is what they did while
/// `panel-color` and `panel-opacity` were parsed, persisted, editable in the settings window, and
/// read by absolutely nothing.
///
/// "system" keeps the stock vibrancy material — the default, and the only option that tracks the
/// desktop behind it. A hex colour replaces the material outright: you cannot tint a material and
/// still have it behave like one, and a flat colour that honestly looks flat beats a muddy blend
/// that looks like a bug.
struct PanelChrome: View {
    let color: String        // "system" or #RRGGBB / #RRGGBBAA
    let opacity: Double      // 0...1, multiplied into whichever of the two is used

    init(config: Config) {
        self.color = config.panelColor
        self.opacity = config.panelOpacity
    }

    init(color: String, opacity: Double) {
        self.color = color
        self.opacity = opacity
    }

    var body: some View {
        if let (r, g, b, a) = HexColor.rgba(color) {
            Color(.sRGB, red: r, green: g, blue: b, opacity: a * opacity)
        } else {
            Rectangle().fill(.thinMaterial).opacity(opacity)
        }
    }
}
