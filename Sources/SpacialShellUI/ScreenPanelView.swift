import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// The workspace rail: material-shell's `ScreenPanel`, minus the system tray (macOS has a menu
/// bar). One row per workspace, top→bottom in stack order; the trailing empty workspace is
/// drawn as "+" — activating it *is* creating one, that's invariant 4 doing the work.
///
/// A tile shows up to four of the apps actually in that workspace, as a 2x2 icon grid, plus its
/// window count. Names, category and window previews live in the hover popover rather than on the
/// tile: the rail is furniture and stays narrow, and the detail is one hover away.
struct ScreenPanelView: View {
    let state: ScreenShellState
    let launcherURL: String
    let metaFor: (Int32) -> AppMeta
    let send: (Command) -> Void

    /// Which row the pointer is currently over mid-drag. Purely presentational — the drop itself
    /// re-enters through `Command` like every other interaction.
    @State private var dropTarget: UUID?

    /// A 2x2 grid inside a 32 pt tile; past four, the count carries the load.
    private static let maxIcons = 4

    var body: some View {
        VStack(spacing: 4) {
            // M2 design: the search glyph opens the configured launcher (Raycast by default) —
            // the honest macOS "overview". No handler for the URL → the built-in overview.
            Button {
                let opened = URL(string: launcherURL).map { NSWorkspace.shared.open($0) } ?? false
                if !opened { send(.toggleOverview) }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search / launcher")

            ForEach(state.rail) { item in
                Button {
                    send(.focusWorkspaceID(item.id))
                    // "+" is "start a new workspace", and a workspace with nothing in it is a
                    // dead end — so opening one opens the overview to put something in it. The
                    // built-in overview, never `launcherURL`: the overview is our own
                    // non-activating panel, while an external launcher would activate another
                    // app, and that focus change is exactly what drags you back out again.
                    if item.isTrailingEmpty { send(.toggleOverview) }
                } label: {
                    row(item)
                }
                .buttonStyle(.plain)
                .help(item.isTrailingEmpty ? "New workspace" : tooltip(item))
                // Dropping a tab here sends its window to this workspace. The trailing "+" row is
                // not special-cased: it is a workspace, and moving into it grows a new one.
                .dropDestination(for: DraggedWindow.self) { items, _ in
                    guard let dropped = items.first else { return false }
                    send(.moveWindowRefToWorkspace(dropped.ref, item.id))
                    return true
                } isTargeted: { over in
                    dropTarget = over ? item.id : (dropTarget == item.id ? nil : dropTarget)
                }
            }
            Spacer(minLength: 0)

            do {
                // Every display: reaching for settings should not mean finding the right monitor.
                Button { send(.openSettings) } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("SpacialShell settings")
                .padding(.bottom, 6)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
        .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 1).opacity(0.6) }
    }

    @ViewBuilder
    private func row(_ item: WorkspaceRailItem) -> some View {
        let apps = distinctApps(item)
        ZStack {
            if item.isTrailingEmpty {
                Image(systemName: "plus").font(.system(size: 15, weight: .medium))
            } else if apps.isEmpty {
                Image(systemName: item.symbol).font(.system(size: 15, weight: .medium))
            } else {
                icons(apps)
            }
            if !item.isTrailingEmpty && item.windowCount > 0 {
                Text("\(item.windowCount)")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .foregroundStyle(.white)
                    .offset(x: 13, y: 13)
            }
        }
        .frame(width: 32, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(item.isActive ? AnyShapeStyle(Color.accentColor.opacity(0.85))
                                    : AnyShapeStyle(Color.primary.opacity(0.001)))
        )
        // Reads over both the active tile's accent and an inactive tile's transparency, which a
        // fill would not while the cursor is carrying a drag image.
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(dropTarget == item.id ? 1 : 0)
        )
        .foregroundStyle(item.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
    }

    /// One icon fills the tile; two to four share it as a 2x2 grid. Enough to recognise a
    /// workspace by shape and colour without reading anything.
    @ViewBuilder
    private func icons(_ apps: [AppMeta]) -> some View {
        let shown = Array(apps.prefix(Self.maxIcons))
        let side: CGFloat = shown.count == 1 ? 22 : 11
        let columns = shown.count == 1 ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 1), count: columns), spacing: 1) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, meta in
                if let icon = meta.icon {
                    Image(nsImage: icon).resizable().frame(width: side, height: side)
                } else {
                    Image(systemName: "app.dashed").font(.system(size: side * 0.7))
                        .frame(width: side, height: side)
                }
            }
        }
        .frame(width: shown.count == 1 ? 22 : 23)
    }

    /// One entry per app, in the order the row first mentions it — two Safari windows are one
    /// Safari icon, and the icons read left→right in the same order the tab bar does.
    private func distinctApps(_ item: WorkspaceRailItem) -> [AppMeta] {
        var seen: Set<Int32> = []
        return item.windows.compactMap { seen.insert($0.pid).inserted ? metaFor($0.pid) : nil }
    }

    private func categoryLabel(_ apps: [AppMeta]) -> String? {
        AppCategories.summarise(apps.map(\.category))?.label
    }

    /// The tile has no room for words, so everything the old inline label said lives here.
    private func tooltip(_ item: WorkspaceRailItem) -> String {
        let apps = distinctApps(item)
        var head = "\(item.name) (\(item.index + 1))"
        if let label = categoryLabel(apps) { head += " · \(label)" }
        let names = apps.map(\.name).joined(separator: ", ")
        return names.isEmpty ? head : "\(head)\n\(names)"
    }
}
