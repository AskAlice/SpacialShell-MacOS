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
        case general = "General", appearance = "Appearance", layout = "Layout", workspaces = "Workspaces"
        case keys = "Keybindings"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintpalette"
            case .layout: "square.grid.2x2"
            case .workspaces: "rectangle.stack"
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
    /// #58: Sparkle's check, from the app target. `nil` when there is no updater (a loose dev build,
    /// or no signing key yet), and the row is not shown.
    let checkForUpdates: (() -> Void)?

    @State private var pane: Pane = .general
    /// The command currently listening for a chord, if any. One at a time: two recorders would
    /// both swallow the same keystroke.
    @State private var recording: String?

    /// Stories only: one pane's contents on their own. `NavigationSplitView` does not draw into an
    /// offscreen bitmap, so the snapshot tests render the pane without the sidebar around it.
    var standalone: Pane? = nil

    var body: some View {
        if let standalone {
            content(standalone).frame(width: 520, alignment: .leading).padding(22)
                .background(Color(nsColor: .windowBackgroundColor))
        } else {
            NavigationSplitView {
                List(Pane.allCases, selection: Binding(get: { pane }, set: { pane = $0 ?? pane })) { p in
                    Label(p.rawValue, systemImage: p.symbol).tag(p)
                }
                .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
            } detail: {
                ScrollView {
                    content(pane)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                }
            }
            .frame(minWidth: 620, minHeight: 420)
        }
    }

    private func content(_ pane: Pane) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            switch pane {
            case .general: general
            case .appearance: appearance
            case .layout: layout
            case .workspaces: workspaces
            case .keys: keys
            }
        }
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

            row("Pointer follows focus", overridden: overrides.pointerWarp != nil) {
                Toggle("", isOn: binding(\.pointerWarp, default: file.pointerWarp)).labelsHidden()
            } reset: { overrides.pointerWarp = nil }

            // #135: opt-in; `focus-follows-mouse-delay-ms` is file-only.
            row("Focus follows mouse", overridden: overrides.focusFollowsMouse != nil) {
                Toggle("", isOn: binding(\.focusFollowsMouse, default: file.focusFollowsMouse)).labelsHidden()
                    .help("Rest the pointer on another tiled window for \(file.focusFollowsMouseDelayMs) ms to focus it, as a click on its tab would")
            } reset: { overrides.focusFollowsMouse = nil }

            row("Wrap workspaces", overridden: overrides.workspaceWrap != nil) {
                Toggle("", isOn: binding(\.workspaceWrap, default: file.workspaceWrap)).labelsHidden()
                    .help("Fn+W on the first workspace goes to the last one, and Fn+S on the last back to the first")
            } reset: { overrides.workspaceWrap = nil }

            // #141: swipes are Fn+W/A/S/D; `gesture-fingers` is file-only.
            row("Trackpad swipes", overridden: overrides.gestures != nil) {
                Toggle("", isOn: binding(\.gestures, default: file.gestures)).labelsHidden()
                    .help("Swipe with \(file.gestureFingers) fingers to move between windows (left, right) and workspaces (up, down), like Fn+W/A/S/D")
            } reset: { overrides.gestures = nil }

            row("Invert swipes", overridden: overrides.gestureInvert != nil) {
                Toggle("", isOn: binding(\.gestureInvert, default: file.gestureInvert)).labelsHidden()
                    .help("Off: content follows your fingers, as with natural scrolling (swipe left for the next window). On: swipe the way the keys point (swipe left for Fn+A)")
            } reset: { overrides.gestureInvert = nil }

            // #138: what "Don't warn again" silenced, and the way back. Only shown when there is any.
            if let silenced = overrides.silencedWarnings, !silenced.isEmpty {
                row("Silenced warnings", overridden: false) {
                    HStack(spacing: 8) {
                        Text(silenced.map(Self.warningLabel).joined(separator: ", "))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Button("Warn again") { overrides.silencedWarnings = nil }
                            .help("Warn again about everything you chose Don't warn again for")
                    }
                } reset: {}
            }

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
            if let checkForUpdates {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Updates").font(.system(size: 12, weight: .semibold))
                    Text("SpacialShell checks for a new release once a day.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Check for Updates…", action: checkForUpdates)
                }
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Appearance", "Colour and opacity of the workspace rail and the window tab bar, switch motion, and whether the rail hides.")
            row("Panel colour", overridden: overrides.panelColor != nil) {
                HStack(spacing: 8) {
                    ColorPicker("", selection: colorBinding).labelsHidden()
                    Button("System") { overrides.panelColor = "system" }
                        .disabled((overrides.panelColor ?? file.panelColor) == "system")
                }
            } reset: { overrides.panelColor = nil }

            Divider()
            row("Switch animation", overridden: overrides.animations != nil) {
                Toggle("", isOn: binding(\.animations, default: file.animations)).labelsHidden()
            } reset: { overrides.animations = nil }
            row("Empty cheat sheet", overridden: overrides.emptyCheatsheet != nil) {
                Toggle("", isOn: binding(\.emptyCheatsheet, default: file.emptyCheatsheet)).labelsHidden()
            } reset: { overrides.emptyCheatsheet = nil }
            row("Auto-hide rail", overridden: overrides.railAutohide != nil) {
                Toggle("", isOn: binding(\.railAutohide, default: file.railAutohide)).labelsHidden()
            } reset: { overrides.railAutohide = nil }
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

            // #116: how much a tab shows. The whole title stays in each tab's tooltip.
            row("Tab style", overridden: overrides.tabStyle != nil) {
                Picker("", selection: binding(\.tabStyle, default: file.tabStyle)) {
                    Text("Full").tag(TabStyle.full); Text("Name").tag(TabStyle.name); Text("Icon").tag(TabStyle.icon)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
            } reset: { overrides.tabStyle = nil }
        }
    }

    /// #74: the category order and the row cap. The order is a list of every category, the ones
    /// switched on first and in order; "off" means left out of `category-order`. Up/down buttons
    /// rather than `List.onMove`: a `List` does not size itself inside this pane's `ScrollView`.
    private var workspaces: some View {
        let order = overrides.categoryOrder ?? file.categoryOrder
        let off = AppCategory.allCases.filter { !order.contains($0) }
        return VStack(alignment: .leading, spacing: 18) {
            header("Workspaces", "Where an app's first window goes. Apps of a category that is on share one workspace per display, kept at the top in this order. Every other app gets a workspace of its own below them.")
            row("Categories", overridden: overrides.categoryOrder != nil) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(order + off, id: \.self) { categoryRow($0, order: order) }
                }
            } reset: { overrides.categoryOrder = nil }

            Divider()
            row("Maximum", overridden: overrides.maxWorkspaces != nil) {
                let cap = binding(\.maxWorkspaces, default: file.maxWorkspaces)
                Stepper(value: cap, in: 1...30) {
                    Text("\(cap.wrappedValue) workspaces per display")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                }
            } reset: { overrides.maxWorkspaces = nil }
        }
    }

    private func categoryRow(_ c: AppCategory, order: [AppCategory]) -> some View {
        let i = order.firstIndex(of: c)
        func move(_ by: Int) {
            guard let i else { return }
            var o = order; o.swapAt(i, i + by); overrides.categoryOrder = o
        }
        return HStack(spacing: 8) {
            Toggle(c.label, isOn: Binding(get: { i != nil }, set: { on in
                var o = order.filter { $0 != c }
                if on { o.append(c) }
                overrides.categoryOrder = o
            }))
            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Text(c.label.prefix(1).uppercased() + c.label.dropFirst())
                .font(.system(size: 12)).foregroundStyle(i == nil ? .secondary : .primary)
                .frame(width: 120, alignment: .leading)
            Button { move(-1) } label: { Label("Move up", systemImage: "chevron.up").labelStyle(.iconOnly) }
                .disabled(i == nil || i == 0).help("Move up")
            Button { move(1) } label: { Label("Move down", systemImage: "chevron.down").labelStyle(.iconOnly) }
                .disabled(i.map { $0 == order.count - 1 } ?? true).help("Move down")
        }
        .buttonStyle(.borderless)
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
            // #119: one "set layout" command per layout the catalogue knows, saved ones included.
            ForEach(LayoutCatalogue(config: effective).all.map(\.id), id: \.self) { id in
                keyRow(name: KeyBindings.setLayoutPrefix + id.rawValue,
                       label: "Layout: \(LayoutCatalogue(config: effective).resolve(id).def.name)", config: effective)
            }
        }
    }

    private func keyRow(name: String, label: String, config: Config) -> some View {
        let bound = KeyBindings.command(named: name).flatMap { CheatSheet.primaryDisplay(for: $0, config: config) }
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
        ("focus-screen-left", "Focus screen left"), ("focus-screen-right", "Focus screen right"),
        ("focus-screen-up", "Focus screen above"), ("focus-screen-down", "Focus screen below"),
        ("move-window-to-screen-left", "Move window to screen left"),
        ("move-window-to-screen-right", "Move window to screen right"),
        ("move-window-to-screen-up", "Move window to screen above"),
        ("move-window-to-screen-down", "Move window to screen below"),
        ("move-workspace-to-screen-left", "Move workspace to screen left"),
        ("move-workspace-to-screen-right", "Move workspace to screen right"),
        ("move-workspace-to-screen-up", "Move workspace to screen above"),
        ("move-workspace-to-screen-down", "Move workspace to screen below"),
        ("cycle-layout", "Cycle layout"), ("cycle-layout-reverse", "Cycle layout backwards"), ("toggle-float", "Toggle float"),
        ("close-window", "Close window"), ("toggle-shell-ui", "Toggle Zen mode"),
        ("toggle-overview", "Open overview"), ("open-settings", "Open settings"),
    ]

    /// A silenced problem key as the user knows it: the `other-window-managers` entry it names.
    static func warningLabel(_ key: String) -> String {
        key.hasPrefix(Problem.Key.otherWindowManagerPrefix) ? String(key.dropFirst(Problem.Key.otherWindowManagerPrefix.count)) : key
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

    private var colorBinding: Binding<Color> { hexBinding(\.panelColor, default: file.panelColor, system: .gray) }

    /// A "system"-or-#RRGGBB setting as a colour well; `system` is what the well shows for "system".
    private func hexBinding(_ key: WritableKeyPath<SettingsOverrides, String?>, default fallback: String,
                            system: Color = .accentColor) -> Binding<Color> {
        Binding(
            get: {
                guard let rgba = HexColor.rgba(overrides[keyPath: key] ?? fallback) else { return system }
                return Color(.sRGB, red: rgba.0, green: rgba.1, blue: rgba.2, opacity: rgba.3)
            },
            set: { new in
                // The well's opacity slider is the panel's opacity: written as #RRGGBBAA. It used
                // to be dropped here, so that slider did nothing.
                guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
                func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
                var hex = String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
                if byte(c.alphaComponent) < 255 { hex += String(format: "%02X", byte(c.alphaComponent)) }
                overrides[keyPath: key] = hex
            })
    }
}
