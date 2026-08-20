import SwiftUI
import SpacialShellKit

/// The workspace rail: material-shell's `ScreenPanel`, minus the system tray (macOS has a menu
/// bar). One button per workspace, top→bottom in stack order; the trailing empty workspace is
/// drawn as "+" — activating it *is* creating one, that's invariant 4 doing the work.
struct ScreenPanelView: View {
    let state: ScreenShellState
    let send: (Command) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(state.rail) { item in
                Button {
                    send(.activateWorkspace(state.display, item.index))
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: item.isTrailingEmpty ? "plus" : item.symbol)
                            .font(.system(size: 15, weight: .medium))
                        if !item.isTrailingEmpty {
                            Text(item.windowCount > 0 ? "\(item.windowCount)" : "–")
                                .font(.system(size: 9, weight: .semibold))
                                .opacity(0.7)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(item.isActive ? AnyShapeStyle(Color.accentColor.opacity(0.85))
                                                : AnyShapeStyle(Color.primary.opacity(0.001)))
                    )
                    .foregroundStyle(item.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help(item.isTrailingEmpty ? "New workspace" : "\(item.name) (\(item.index + 1))")
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
        .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 1).opacity(0.6) }
    }
}
