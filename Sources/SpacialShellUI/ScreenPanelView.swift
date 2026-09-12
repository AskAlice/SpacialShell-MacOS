import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// The workspace rail: material-shell's `ScreenPanel`, minus the system tray (macOS has a menu
/// bar). One row per workspace, top→bottom in stack order; the trailing empty workspace is
/// drawn as "+" — activating it *is* creating one, that's invariant 4 doing the work.
///
/// Each row shows the apps that are actually in that workspace (one icon per distinct app, in row
/// order) and what kind of work it is for, so the rail answers "where is my terminal?" without
/// visiting every workspace to find out.
struct ScreenPanelView: View {
    let state: ScreenShellState
    let launcherURL: String
    let metaFor: (Int32) -> AppMeta
    /// The settings cog lives on one screen only — it is a way into the app, not per-display
    /// furniture, and one cog per monitor is clutter.
    let isPrimaryScreen: Bool
    let send: (Command) -> Void

    /// Which row the pointer is currently over mid-drag. Purely presentational — the drop itself
    /// re-enters through `Command` like every other interaction.
    @State private var dropTarget: UUID?

    /// Enough icons to tell workspaces apart at a glance; past this the count carries the load.
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

            if isPrimaryScreen {
                // Opens the config file — there is no settings window yet and none is pretended.
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
        VStack(alignment: .leading, spacing: 3) {
            if item.isTrailingEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                    Text("New").font(.system(size: 11))
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 3) {
                    if apps.isEmpty {
                        Image(systemName: item.symbol).font(.system(size: 12, weight: .medium)).opacity(0.7)
                    } else {
                        ForEach(Array(apps.prefix(Self.maxIcons).enumerated()), id: \.offset) { _, meta in
                            if let icon = meta.icon {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "app.dashed").font(.system(size: 12)).frame(width: 16, height: 16)
                            }
                        }
                        if apps.count > Self.maxIcons {
                            Text("+\(apps.count - Self.maxIcons)")
                                .font(.system(size: 9, weight: .semibold)).opacity(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(item.windowCount > 0 ? "\(item.windowCount)" : "–")
                        .font(.system(size: 9, weight: .semibold)).opacity(0.6)
                }
                if let label = categoryLabel(apps) {
                    Text(label)
                        .font(.system(size: 9.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(0.75)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(item.isActive ? AnyShapeStyle(Color.accentColor.opacity(0.85))
                                    : AnyShapeStyle(Color.primary.opacity(0.001)))
        )
        // The drop target has to read at a glance while the pointer is moving and the cursor is
        // carrying a drag image, so it is a stroke rather than a fill — it reads over both the
        // active row's accent and an inactive row's transparency.
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(dropTarget == item.id ? 1 : 0)
        )
        .foregroundStyle(item.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
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

    private func tooltip(_ item: WorkspaceRailItem) -> String {
        let apps = distinctApps(item)
        let names = apps.map(\.name).joined(separator: ", ")
        let head = "\(item.name) (\(item.index + 1))"
        return names.isEmpty ? head : "\(head) — \(names)"
    }
}
