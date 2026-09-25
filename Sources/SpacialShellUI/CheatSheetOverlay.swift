import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellPlatform

/// The Fn-hold cheat sheet: hold the bare modifier (no key) for a beat and the bindings appear,
/// grouped the way `CheatSheet.rows(for:)` groups them; release and it fades. Driven by
/// `HotkeyTap`'s `onFlags` stream — the tap never consumes flags, so holding Fn still does
/// whatever macOS wants it to do; this is read-only discoverability.
@MainActor
public final class CheatSheetController {
    /// Bare-modifier hold time before the sheet shows. Long enough that chording (Fn+D) never
    /// flashes it, short enough to answer "what can I press?" as the question forms.
    private static let holdDelay = Duration.milliseconds(700)

    private let panel = PanelWindow()
    private var host: NSHostingView<CheatSheetView>?
    private var config: Config
    private var showTask: Task<Void, Never>?
    private var shown = false

    public init(config: Config) {
        self.config = config
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)   // above everything of ours
    }

    public func update(config: Config) {
        self.config = config
        if shown { present() }   // re-render with the new bindings
    }

    /// Fed from the tap thread via a main-actor hop. The modifier of interest is the preset's:
    /// bare Fn under the `fn` preset, bare ⌃⌥ under `ctrl-alt`.
    public func flagsChanged(_ flags: CGEventFlags) {
        let bare: Bool =
            switch config.keybindingPreset {
            case .fn:
                flags.contains(.maskSecondaryFn)
                    && flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift])
            case .ctrlAlt:
                flags.contains(.maskControl) && flags.contains(.maskAlternate)
                    && flags.isDisjoint(with: [.maskCommand, .maskShift, .maskSecondaryFn])
            }
        if bare {
            guard showTask == nil, !shown else { return }
            showTask = Task { [weak self] in
                try? await Task.sleep(for: Self.holdDelay)
                guard !Task.isCancelled else { return }
                self?.present()
            }
        } else {
            showTask?.cancel(); showTask = nil
            dismiss()
        }
    }

    private func present() {
        shown = true
        let view = CheatSheetView(groups: Self.grouped(CheatSheet.rows(for: config)))
        let host = NSHostingView(rootView: view)
        self.host = host
        panel.contentView = host
        let size = host.fittingSize
        let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    private func dismiss() {
        guard shown else { return }
        shown = false
        panel.orderOut(nil)
        panel.contentView = nil
        host = nil
    }

    static func grouped(_ rows: [CheatSheet.Row]) -> [(group: CheatSheet.Group, rows: [CheatSheet.Row])] {
        CheatSheet.Group.allCases.compactMap { g in
            let inGroup = rows.filter { $0.group == g }
            return inGroup.isEmpty ? nil : (g, inGroup)
        }
    }
}

/// #29: the same sheet as a passive background. While the focused display's active workspace is
/// empty (`ShellUI.showsEmptyCheatSheet`), it sits dimmed at the bottom of that screen, just above
/// the desktop — so every window, the shell panels and the overview are in front of it — and
/// click-through. Owned by `ShellController`, which already has both the world and the effective
/// config, so rebinds show up here the moment they land.
@MainActor
final class EmptyCheatSheetController {
    private static let bottomMargin: CGFloat = 16   // + the view's own 8 pt shadow padding

    private let panel = PanelWindow()
    private var shownConfig: Config?
    private var size: CGSize = .zero

    init() {
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.ignoresMouseEvents = true
    }

    func update(world: World, config: Config) {
        guard let screen = NSScreen.screens.first(where: {
            ShellUI.showsEmptyCheatSheet(DisplayTopology.uuid(for: $0), in: world, config: config)
        }) else {
            panel.orderOut(nil)
            return
        }
        if shownConfig != config {   // only rebuild when the bindings could have changed
            shownConfig = config
            let host = NSHostingView(rootView: CheatSheetView(
                groups: CheatSheetController.grouped(CheatSheet.rows(for: config)), dimmed: true))
            panel.contentView = host
            size = host.fittingSize
        }
        let vf = screen.visibleFrame
        panel.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.minY + Self.bottomMargin,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}

struct CheatSheetView: View {
    let groups: [(group: CheatSheet.Group, rows: [CheatSheet.Row])]
    /// The empty-workspace background (#29): the same sheet, stepped back.
    var dimmed = false

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach(groups, id: \.group) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.group.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(entry.rows, id: \.commandName) { row in
                        HStack(spacing: 7) {
                            Image(systemName: row.symbol)
                                .font(.system(size: 11))
                                .frame(width: 16)
                                .foregroundStyle(.secondary)
                            Text(row.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer(minLength: 10)
                            Text(row.chords.joined(separator: "  "))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 190, alignment: .leading)
                    }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .opacity(dimmed ? 0.55 : 1)
        .padding(8)   // breathing room for the panel shadow
    }
}
