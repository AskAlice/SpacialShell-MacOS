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
        case general = "General", appearance = "Appearance", layout = "Layout", keys = "Keybindings"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintpalette"
            case .layout: "square.grid.2x2"
            case .keys: "keyboard"
            }
        }
    }

    /// What `config.toml` says, before any override — the baseline a "Reset" returns you to.
    let file: Config
    @Binding var overrides: SettingsOverrides
    /// Where the running build actually reads the file from. Worth showing, not just opening: a
    /// sandboxed build reads it inside its container, where nobody would think to look and no
    /// dotfile symlink points — see docs/config.md.
    let configPath: String
    let openConfigFile: () -> Void

    @State private var pane: Pane = .general
    /// The command currently listening for a chord, if any. One at a time: two recorders would
    /// both swallow the same keystroke.
    @State private var recording: String?

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
                    case .keys: keys
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
            row("Modifier", overridden: overrides.keybindingPreset != nil) {
                Picker("", selection: binding(\.keybindingPreset, default: file.keybindingPreset)) {
                    Text("fn").tag(KeybindingPreset.fn); Text("\u{2303}\u{2325}").tag(KeybindingPreset.ctrlAlt)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
            } reset: { overrides.keybindingPreset = nil }

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
                Text(configPath)
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var keys: some View {
        let effective = Settings.effective(config: file, overrides: overrides)
        return VStack(alignment: .leading, spacing: 14) {
            header("Keybindings", "Click a chord and press the keys you want. Escape cancels. A chord needs at least one of fn, \u{2303}, \u{2325} or \u{2318} \u{2014} a bare key would be swallowed everywhere.")
            if effective.keybindingPreset == .fn {
                Text("Note: some keyboards cannot produce the fn modifier at all \u{2014} a virtual HID device such as Karabiner's re-emits your keys without it, because Apple handles fn in hardware. If fn chords never fire, switch the modifier to \u{2303}\u{2325} under General.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
            }
            ForEach(Self.commandOrder, id: \.0) { name, label in
                keyRow(name: name, label: label, config: effective)
            }
        }
    }

    private func keyRow(name: String, label: String, config: Config) -> some View {
        let bound = KeyBindings.commandNames[name].flatMap { CheatSheet.primaryDisplay(for: $0, config: config) }
        let isOverridden = (overrides.keybindingOverrides?[name] ?? nil) != nil
        return HStack(spacing: 12) {
            Text(label).font(.system(size: 12)).frame(width: 190, alignment: .leading)
            Button {
                recording = recording == name ? nil : name
            } label: {
                Text(recording == name ? "Press keys\u{2026}" : (bound ?? "unbound"))
                    .font(.system(size: 11).monospacedDigit())
                    .frame(width: 120)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(recording == name ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                                                : AnyShapeStyle(.quaternary.opacity(0.5))))
            }
            .buttonStyle(.plain)
            .overlay {
                if recording == name {
                    ChordRecorder(onCapture: { chord in
                        var m = overrides.keybindingOverrides ?? [:]
                        m[name] = KeyBindings.serialize(chord)
                        overrides.keybindingOverrides = m
                        recording = nil
                    }, onCancel: { recording = nil })
                    .frame(width: 0, height: 0)
                }
            }
            if isOverridden {
                Button("Use file") {
                    var m = overrides.keybindingOverrides ?? [:]
                    m.removeValue(forKey: name)
                    overrides.keybindingOverrides = m.isEmpty ? nil : m
                }
                .font(.system(size: 11))
                .help("Stop overriding this and use whatever config.toml and the preset say")
            }
            Spacer(minLength: 0)
        }
    }

    /// Grouped the way the cheat sheet groups them, so the two surfaces read the same.
    static let commandOrder: [(String, String)] = [
        ("focus-workspace-up", "Focus workspace up"), ("focus-workspace-down", "Focus workspace down"),
        ("focus-window-left", "Focus window left"), ("focus-window-right", "Focus window right"),
        ("move-window-left", "Move window left"), ("move-window-right", "Move window right"),
        ("move-window-up", "Move window to workspace up"), ("move-window-down", "Move window to workspace down"),
        ("focus-screen-prev", "Focus previous screen"), ("focus-screen-next", "Focus next screen"),
        ("move-window-to-screen-prev", "Move window to previous screen"),
        ("move-window-to-screen-next", "Move window to next screen"),
        ("cycle-layout", "Cycle layout"), ("toggle-float", "Toggle float"),
        ("close-window", "Close window"), ("toggle-shell-ui", "Toggle Zen mode"),
        ("toggle-overview", "Open overview"), ("open-settings", "Open settings"),
    ]

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
