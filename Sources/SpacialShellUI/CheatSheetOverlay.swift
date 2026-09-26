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

    /// A chord fired while the modifier was down: this press was a command, not "what can I
    /// press?", so a pending show is dropped (a sheet already up stays). Without it, holding
    /// Fn+W to open the spatial view (#132) brought the sheet up over it 700 ms in.
    public func chordFired() {
        showTask?.cancel(); showTask = nil
    }

    private func present() {
        shown = true
        let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        // #87: it floats over everything, so the whole visible frame is its to fit.
        let (view, size) = CheatSheetView.fitting(Self.grouped(CheatSheet.rows(for: config)), in: vf.width)
        let host = NSHostingView(rootView: view)
        self.host = host
        panel.contentView = host
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
    private var shown: (config: Config, width: CGFloat)?
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
        // #87: it sits behind the shell, so it fits (and centres in) the area beside the rail —
        // the same insets the tiled windows get, so Zen hands it the rail's strip back.
        let insets = ShellInsets(config: config, hidden: world.zen)
        let vf = screen.visibleFrame
        let area = NSRect(x: vf.minX + insets.left, y: vf.minY,
                          width: vf.width - insets.left - insets.right, height: vf.height)
        // Only rebuild when the bindings or the room could have changed.
        if shown?.config != config || shown?.width != area.width {
            shown = (config, area.width)
            let (view, size) = CheatSheetView.fitting(CheatSheetController.grouped(CheatSheet.rows(for: config)),
                                                      dimmed: true, in: area.width)
            panel.contentView = NSHostingView(rootView: view)
            self.size = size
        }
        panel.setFrame(NSRect(x: area.midX - size.width / 2, y: vf.minY + Self.bottomMargin,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}

struct CheatSheetView: View {
    let groups: [(group: CheatSheet.Group, rows: [CheatSheet.Row])]
    /// The empty-workspace background (#29): the same sheet, stepped back.
    var dimmed = false
    /// #87: how many rows the groups are dealt into. One is the sheet as designed; more is how it
    /// fits a narrow display — see `fitting(_:dimmed:in:)`.
    var rows = 1

    /// Clear space kept between the sheet and the edges of the area it sits in.
    static let sideMargin: CGFloat = 16

    /// #87: the sheet with the fewest rows that fits an area `width` wide, and its size. Wrapping
    /// rather than scaling keeps the type at its designed size; a single column is the floor.
    static func fitting(_ groups: [(group: CheatSheet.Group, rows: [CheatSheet.Row])], dimmed: Bool = false,
                        in width: CGFloat) -> (view: CheatSheetView, size: CGSize) {
        var best: (view: CheatSheetView, size: CGSize)?
        for rows in 1...max(groups.count, 1) {
            let view = CheatSheetView(groups: groups, dimmed: dimmed, rows: rows)
            let size = NSHostingView(rootView: view).fittingSize
            best = (view, size)
            if size.width <= width - 2 * sideMargin { break }
        }
        return best!
    }

    var body: some View {
        let perRow = max(1, Int((Double(groups.count) / Double(rows)).rounded(.up)))
        let lines = stride(from: 0, to: groups.count, by: perRow).map { Array(groups[$0..<min($0 + perRow, groups.count)]) }
        Grid(alignment: .topLeading, horizontalSpacing: 22, verticalSpacing: 16) {
            ForEach(lines.indices, id: \.self) { i in
                GridRow {
                    ForEach(lines[i], id: \.group) { column($0) }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .opacity(dimmed ? 0.55 : 1)
        .padding(8)   // breathing room for the panel shadow
    }

    private func column(_ entry: (group: CheatSheet.Group, rows: [CheatSheet.Row])) -> some View {
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
