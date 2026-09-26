import AppKit
import SwiftUI
import SpacialShellKit

extension View {
    /// Every rail and tab-bar button (#93). The panels are non-activating and never key, so no
    /// control in them may take keyboard focus: with Full Keyboard Access on, a layout button drew
    /// the focus ring anyway. Out of the key-view loop, and no focus effect if one is drawn regardless.
    func panelButton() -> some View {
        buttonStyle(.plain).focusable(false).focusEffectDisabled()
    }

    /// #121: vertical scrolling over this view, as discrete steps (-1 back, +1 forward; see
    /// `ScrollStepper`). Sideways scrolling passes through, so a scroll view inside keeps it.
    /// `action` is re-read on every render, so each step sees the state the last one produced.
    func onScrollStep(_ action: @escaping (Int) -> Void) -> some View {
        modifier(ScrollSteps(action: action))
    }
}

/// SwiftUI on macOS 14 has no scroll-wheel callback for an arbitrary view, so this watches the
/// app's own scroll events (a local monitor, installed only while the pointer is over the view)
/// and takes those aimed at the window the pointer entered.
private struct ScrollSteps: ViewModifier {
    let action: (Int) -> Void
    @State private var catcher = ScrollCatcher()

    func body(content: Content) -> some View {
        catcher.action = action
        return content
            .contentShape(Rectangle())
            .onHover { catcher.hovering($0) }
            .onDisappear { catcher.hovering(false) }
    }
}

@MainActor
private final class ScrollCatcher {
    var action: (Int) -> Void = { _ in }
    private var stepper = ScrollStepper()
    private var monitor: Any?
    private weak var window: NSWindow?

    func hovering(_ inside: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard inside else { return }
        // The window under the pointer now. A hover can stick past a screen edge; checking the
        // event's window keeps a stuck one from taking scrolls meant for, say, the settings window.
        let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
        window = NSApp.window(withWindowNumber: number)
        stepper = ScrollStepper()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let (dx, dy) = (Double(event.scrollingDeltaX), Double(event.scrollingDeltaY))
            let phase: ScrollStepper.Phase =
                !event.momentumPhase.isEmpty ? .momentum
                : event.phase.contains(.began) ? .began
                : event.phase.contains(.changed) ? .changed
                : event.phase.isEmpty ? .none
                : .ended          // .ended, .cancelled, .mayBegin, .stationary: nothing to add
            let number = event.windowNumber
            let swallow = MainActor.assumeIsolated { self?.handle(dx: dx, dy: dy, phase: phase, window: number) ?? false }
            return swallow ? nil : event
        }
    }

    private func handle(dx: Double, dy: Double, phase: ScrollStepper.Phase, window number: Int) -> Bool {
        guard let window, window.windowNumber == number, let step = stepper.feed(dx: dx, dy: dy, phase: phase) else { return false }
        if step != 0 { action(step) }
        return true
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
