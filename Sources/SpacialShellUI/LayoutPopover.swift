import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// What the tab bar's cog opens (#10, absorbing #15; design §2 "The cog"): every layout **by name**,
/// the one this workspace holds checked, a Show-on-bar switch per row, "Set as default", and
/// New… / Edit…. Picking a row applies it, exactly like clicking its glyph.
///
/// It is the name-first way to all of them; the bar's glyphs and ⋯ menu are the quick ways. Props
/// in, commands out: the two settings edits and New/Edit are app-layer commands AppRuntime routes.
struct LayoutPopoverView: View {
    let state: ScreenShellState
    let send: (Command) -> Void

    static let width: CGFloat = 300
    private var workspace: UUID? { state.rail.first(where: \.isActive)?.id }
    private var splitColumns: Int { state.rail.first(where: \.isActive)?.splitColumns ?? SplitView.defaultColumns }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Layouts for this workspace")
                .textCase(.uppercase)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.top, 2).padding(.bottom, 4)
            ForEach(state.layouts) { row($0) }
            Divider().padding(.vertical, 6)
            let isDefault = state.defaultLayout == state.shownLayout
            Button { send(.setDefaultLayout(state.shownLayout)) } label: {
                Text(isDefault ? "Default for new workspaces" : "Set as default for new workspaces")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDefault)
            .foregroundStyle(isDefault ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            HStack(spacing: 8) {
                Button { send(.editLayout(nil, workspace: workspace)) } label: {
                    Text("New\u{2026}").frame(maxWidth: .infinity)
                }
                Button { send(.editLayout(state.shownLayout, workspace: workspace)) } label: {
                    Text("Edit\u{2026}").frame(maxWidth: .infinity)
                }
            }
            .controlSize(.regular)
            .padding(.top, 6)
        }
        .padding(10)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
    }

    private func row(_ choice: LayoutChoice) -> some View {
        let current = choice.id == state.layout
        let barFull = state.bar.count >= LayoutCatalogue.maxBar
        return HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(current ? 1 : 0)
                .frame(width: 12)
            LayoutGlyph(def: choice.def).frame(width: 18)
            Text(choice.def.name).font(.system(size: 12)).lineLimit(1)
            if choice.origin == .drawn {
                Text("drawn")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 8)
            if choice.id == .split { columnStepper }
            Toggle("Show on bar", isOn: Binding(get: { choice.onBar },
                                                set: { send(.showLayoutOnBar(choice.id, $0)) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .disabled(!choice.onBar && barFull)
                .help(!choice.onBar && barFull ? "The bar holds \(LayoutCatalogue.maxBar) layouts" : "Show on bar")
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(current ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(Color.primary.opacity(0.001))))
        .contentShape(Rectangle())
        .onTapGesture { if let workspace { send(.setWorkspaceLayout(workspace, choice.id)) } }
    }
}

extension LayoutPopoverView {
    /// #114: split's column count for this workspace, −/+ within `SplitView.columnRange`.
    fileprivate var columnStepper: some View {
        let range = SplitView.columnRange
        func step(_ symbol: String, _ d: Int, _ help: String) -> some View {
            Button { if let workspace { send(.setSplitColumns(workspace, splitColumns + d)) } } label: {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).frame(width: 16, height: 16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!range.contains(splitColumns + d))
            .foregroundStyle(range.contains(splitColumns + d) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .help(help)
        }
        return HStack(spacing: 2) {
            step("minus", -1, "Fewer columns")
            Text("\(splitColumns)").font(.system(size: 11).monospacedDigit()).frame(minWidth: 10)
            step("plus", 1, "More columns")
        }
        .padding(.horizontal, 2)
        .background(Capsule().fill(.quaternary))
        .help("Columns split shows")
    }
}

/// Owns the popover's window. A second non-activating `PanelWindow`, not an `NSPopover`, for the
/// reason `RailHoverController` gives: a popover anchored in a never-key panel would take key
/// status, and with it focus, from the window the user is working in (#15's criterion). It closes
/// on a click anywhere outside it except its own bar, where the cog toggles it and a glyph click
/// should leave it open to show the new check.
@MainActor
final class LayoutPopoverController {
    private let window = PanelWindow()
    private let host: NSHostingView<LayoutPopoverView>
    private let send: (Command) -> Void
    /// The display it is open on; nil when hidden.
    private(set) var display: DisplayID?
    private weak var bar: NSWindow?
    private var monitors: [Any] = []

    init(send: @escaping (Command) -> Void) {
        self.send = send
        // Never shown: `toggle` renders the bar's real state before it orders the window front.
        // The stand-in names its catalogue because nothing defaults one (#177).
        host = NSHostingView(rootView: LayoutPopoverView(
            state: ScreenShellState(display: "", isFocusedScreen: false, rail: [], tabs: [], layout: .maximize,
                                    layouts: .builtins),
            send: { _ in }))
        window.contentView = host
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }

    func toggle(_ state: ScreenShellState, bar: NSWindow) {
        let wasHere = display == state.display
        hide()                                  // also when it is open on another display
        if wasHere { return }
        display = state.display
        self.bar = bar
        update(state)
        window.orderFrontRegardless()
        let outside: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.window !== self.window, event.window !== self.bar else { return }
            self.hide()
        }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { outside($0) } as Any,
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { outside($0); return $0 } as Any,
        ]
    }

    /// Re-render against the latest state (a toggle, a new default, a layout applied), if open there.
    func update(_ state: ScreenShellState) {
        guard display == state.display, let bar else { return }
        host.rootView = LayoutPopoverView(state: state) { [weak self] command in
            // New/Edit open the editor window, which is where the user is going next.
            if case .editLayout = command { self?.hide() }
            self?.send(command)
        }
        let size = host.fittingSize
        // Hung under the bar's trailing end, where the cog is.
        window.setFrame(NSRect(x: bar.frame.maxX - size.width - 6, y: bar.frame.minY - size.height - 4,
                               width: size.width, height: size.height), display: true)
    }

    func hide() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        display = nil
        window.orderOut(nil)
    }
}
