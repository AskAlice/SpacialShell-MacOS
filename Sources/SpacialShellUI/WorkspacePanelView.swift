import AppKit
import SwiftUI
import SpacialShellKit

/// The window tab bar + layout switcher: material-shell's `WorkspacePanel`. Tabs are the active
/// workspace's row, left→right in row order — the same order `Fn+A`/`Fn+D` walk, so the bar is a
/// map of the navigation, not just of the layout. Tabs show the app (name + icon); window titles
/// need an AX title feed and are a follow-up.
struct WorkspacePanelView: View {
    let state: ScreenShellState
    let metaFor: (Int32) -> AppMeta
    let send: (Command) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(state.tabs) { tab in
                tabView(tab)
            }
            Spacer(minLength: 8)
            layoutSwitcher
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 1).opacity(0.6) }
    }

    /// Not a `Button`: the close control inside it is one, and nested buttons fight over the
    /// click. The tab body selects via a tap gesture; the inner button wins for clicks on it.
    private func tabView(_ tab: WindowTabItem) -> some View {
        let meta = metaFor(tab.ref.pid)
        return HStack(spacing: 5) {
            if let icon = meta.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            Text(meta.name)
                .font(.system(size: 11.5, weight: tab.isFocused ? .semibold : .regular))
                .lineLimit(1)
            if tab.isFloating {
                Image(systemName: "pin.fill").font(.system(size: 8)).opacity(0.6)
            }
            if tab.isFocused {
                Button {
                    send(.closeWindowRef(tab.ref))
                } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).opacity(0.6)
                }
                .buttonStyle(.plain)
                .help("Close window")
            }
        }
        .padding(.horizontal, 9)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tab.isFocused ? AnyShapeStyle(Color.accentColor.opacity(0.22))
                                    : AnyShapeStyle(Color.primary.opacity(0.001)))
        )
        .overlay(alignment: .bottom) {
            if tab.isFocused {
                RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(height: 2).padding(.horizontal, 6)
            }
        }
        .foregroundStyle(tab.isFocused ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .opacity(tab.isHidden ? 0.45 : 1)
        .frame(maxWidth: 220)
        .contentShape(Rectangle())
        .onTapGesture { send(.focusWindowRef(tab.ref)) }
        .help(meta.name)
    }

    private var layoutSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(Layout.allCases, id: \.self) { l in
                Button {
                    if let ws = state.rail.first(where: \.isActive) { send(.setWorkspaceLayout(ws.id, l)) }
                } label: {
                    Image(systemName: Self.symbol(for: l))
                        .font(.system(size: 12))
                        .frame(width: 24, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(l == state.layout ? AnyShapeStyle(Color.accentColor.opacity(0.3))
                                                        : AnyShapeStyle(Color.primary.opacity(0.001)))
                        )
                        .foregroundStyle(l == state.layout ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help("\(l.rawValue) layout")
            }
        }
    }

    static func symbol(for layout: Layout) -> String {
        switch layout {
        case .maximize: "rectangle"
        case .split: "rectangle.split.2x1"
        case .column: "rectangle.split.3x1"
        case .half: "rectangle.lefthalf.filled"
        case .grid: "square.grid.2x2"
        }
    }
}
