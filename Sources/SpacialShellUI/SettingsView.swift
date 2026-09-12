import AppKit
import SwiftUI
import SpacialShellKit

/// The settings window's contents: a sidebar of panes over the knobs the shell actually reads.
///
/// Everything here edits `SettingsOverrides`, never `config.toml` — see `Settings` for why. That
/// is not an implementation detail the user should have to infer, so a knob the file has set and
/// the window has overridden says so, and offers the way back.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general = "General", appearance = "Appearance", layout = "Layout"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintpalette"
            case .layout: "square.grid.2x2"
            }
        }
    }

    /// What `config.toml` says, before any override — the baseline a "Reset" returns you to.
    let file: Config
    @Binding var overrides: SettingsOverrides
    let openConfigFile: () -> Void

    @State private var pane: Pane = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: Binding(get: { pane }, set: { pane = $0 ?? pane })) { p in
                Label(p.rawValue, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch pane {
                    case .general: general
                    case .appearance: appearance
                    case .layout: layout
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
            }
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    // MARK: panes

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("General", "Anything set here wins over config.toml. The file is never written.")
            row("Rail side", overridden: overrides.railSide != nil) {
                Picker("", selection: binding(\.railSide, default: file.railSide)) {
                    Text("Left").tag(RailSide.left); Text("Right").tag(RailSide.right)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
            } reset: { overrides.railSide = nil }

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("config.toml").font(.system(size: 12, weight: .semibold))
                Text("The file is the source of truth for everything this window does not override, and it is the only place to set keybindings, workspace seeds and app rules.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Open config.toml…", action: openConfigFile)
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Appearance", "Colour and opacity of the workspace rail and the window tab bar.")
            row("Panel opacity", overridden: overrides.panelOpacity != nil) {
                HStack(spacing: 8) {
                    Slider(value: binding(\.panelOpacity, default: file.panelOpacity), in: 0.2...1)
                        .frame(width: 170)
                    Text(String(format: "%.0f%%", (overrides.panelOpacity ?? file.panelOpacity) * 100))
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                }
            } reset: { overrides.panelOpacity = nil }

            row("Panel colour", overridden: overrides.panelColor != nil) {
                HStack(spacing: 8) {
                    ColorPicker("", selection: colorBinding).labelsHidden()
                    Button("System") { overrides.panelColor = "system" }
                        .disabled((overrides.panelColor ?? file.panelColor) == "system")
                }
            } reset: { overrides.panelColor = nil }
        }
    }

    private var layout: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Layout", "Panel sizes and the gap between tiled windows.")
            row("Rail width", overridden: overrides.panelWidth != nil) {
                stepper(binding(\.panelWidth, default: file.panelWidth), range: 36...320, suffix: "pt")
            } reset: { overrides.panelWidth = nil }

            row("Tab bar height", overridden: overrides.panelHeight != nil) {
                stepper(binding(\.panelHeight, default: file.panelHeight), range: 24...80, suffix: "pt")
            } reset: { overrides.panelHeight = nil }

            row("Window gap", overridden: overrides.gap != nil) {
                stepper(binding(\.gap, default: file.gap), range: 0...64, suffix: "pt")
            } reset: { overrides.gap = nil }

            row("Tab sizing", overridden: overrides.tabSizing != nil) {
                Picker("", selection: binding(\.tabSizing, default: file.tabSizing)) {
                    Text("Fit").tag(TabSizing.fit); Text("Equal").tag(TabSizing.equal)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
            } reset: { overrides.tabSizing = nil }
        }
    }

    // MARK: pieces

    private func header(_ title: String, _ blurb: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(blurb).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One knob. `overridden` is shown rather than hidden: a value that disagrees with the file
    /// the user is also editing by hand is confusing precisely when it is invisible.
    private func row(_ label: String, overridden: Bool,
                     @ViewBuilder control: () -> some View,
                     reset: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 12)).frame(width: 120, alignment: .leading)
            control()
            if overridden {
                Button("Use file", action: reset)
                    .font(.system(size: 11))
                    .help("Stop overriding this and use whatever config.toml says")
            }
            Spacer(minLength: 0)
        }
    }

    private func stepper(_ value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack(spacing: 6) {
            Slider(value: value, in: range).frame(width: 170)
            Text("\(Int(value.wrappedValue))\(suffix)")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
        }
    }

    /// Reads through to the file when unset, and writing always creates the override — which is
    /// exactly what moving a slider means.
    private func binding<V>(_ key: WritableKeyPath<SettingsOverrides, V?>, default fallback: V) -> Binding<V> {
        Binding(get: { overrides[keyPath: key] ?? fallback },
                set: { overrides[keyPath: key] = $0 })
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                guard let rgba = HighlightColor.rgba(overrides.panelColor ?? file.panelColor) else { return .gray }
                return Color(.sRGB, red: rgba.0, green: rgba.1, blue: rgba.2, opacity: 1)
            },
            set: { new in
                guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
                overrides.panelColor = String(format: "#%02X%02X%02X",
                                              Int(c.redComponent * 255), Int(c.greenComponent * 255),
                                              Int(c.blueComponent * 255))
            })
    }
}
