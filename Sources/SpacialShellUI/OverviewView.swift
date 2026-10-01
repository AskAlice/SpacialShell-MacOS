import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// One open window anywhere in the world, as the overview lists it.
struct OverviewWindowItem: Identifiable {
    var id: SpacialShellProtocol.WindowRef { ref }
    let ref: SpacialShellProtocol.WindowRef
    let name: String            // the window title, or the app name when it has none (#110)
    let app: String             // the app name: searchable, and the tooltip beside the title
    let detail: String          // "workspace · screen n" or "visitor" for ephemeral windows
    let icon: NSImage?
}

/// One installed application the launcher can open.
struct OverviewAppItem: Identifiable {
    var id: URL { url }
    let url: URL
    let name: String
    let icon: NSImage
}

/// material-shell's launcher, macOS-shaped: a search field over two sections — the windows that
/// already exist (click = go there) and the applications that could (click = launch; the new
/// window then lands at the end of the active workspace by the ordinary adoption rules).
///
/// #189: a window is drawn as its picture from `thumbnails`, with its app icon as a corner badge,
/// or as its icon alone while the capture is pending or after it failed. The view captures
/// nothing: `OverviewController` hands the pictures in and swaps in new ones as they land.
struct OverviewView: View {
    let windows: [OverviewWindowItem]
    let apps: [OverviewAppItem]
    var thumbnails: [SpacialShellProtocol.WindowRef: NSImage] = [:]
    let onSelectWindow: (SpacialShellProtocol.WindowRef) -> Void
    let onLaunchApp: (URL) -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// #200: the keyboard's place in the results. The search field keeps the focus, so typing
    /// always searches; arrows, Tab and Return work on the selection, as in Spotlight.
    @State private var selection = GridSelection(sections: [])
    /// Where the pointer was when it last chose: a panel opening under a resting pointer (or a
    /// scroll moving cells under it) is not the pointer choosing, so only a moved one selects.
    @State private var pointer = NSEvent.mouseLocation

    /// #200: fixed columns, so ↑/↓ move by the rows the user sees: four pictures, seven apps.
    static let windowColumns = 4, appColumns = 7
    private var sections: [GridSelection.Section] {
        [.init(count: filteredWindows.count, columns: Self.windowColumns),
         .init(count: filteredApps.count, columns: Self.appColumns)]
    }

    private var filteredWindows: [OverviewWindowItem] {
        query.isEmpty ? windows : windows.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.app.localizedCaseInsensitiveContains(query)
        }
    }
    private var filteredApps: [OverviewAppItem] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type to search…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($searchFocused)
                    .onSubmit(openSelection)
                    .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                        switch press.key {
                        case .upArrow: selection.move(.up)
                        case .downArrow: selection.move(.down)
                        case .leftArrow: selection.move(.left)
                        default: selection.move(.right)
                        }
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        selection.tab(backward: NSEvent.modifierFlags.contains(.shift))
                        return .handled
                    }
                    // Esc clears a search first; with nothing typed it falls through and closes.
                    .onKeyPress(.escape) {
                        guard !query.isEmpty else { return .ignored }
                        query = ""
                        return .handled
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !filteredWindows.isEmpty {
                            sectionHeader("Windows")
                            grid(section: 0, columns: Self.windowColumns, filteredWindows.map(windowCell))
                        }
                        if !filteredApps.isEmpty {
                            sectionHeader("Applications")
                            grid(section: 1, columns: Self.appColumns, filteredApps.map(appCell))
                        }
                        if filteredWindows.isEmpty && filteredApps.isEmpty {
                            Text("No matches").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 24)
                        }
                    }
                }
                .onChange(of: selection.at) { _, at in
                    guard let at else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(Self.cellID(at), anchor: nil) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .onAppear { searchFocused = true; selection = GridSelection(sections: sections); pointer = NSEvent.mouseLocation }
        // A new search starts at its first result, as Spotlight's does.
        .onChange(of: query) { selection = GridSelection(sections: sections) }
    }

    /// Return opens the selected result (#200): the first one until the keys or pointer move it.
    private func openSelection() {
        guard let at = selection.at else { return }
        if at.section == 0, filteredWindows.indices.contains(at.index) { onSelectWindow(filteredWindows[at.index].ref) }
        else if at.section == 1, filteredApps.indices.contains(at.index) { onLaunchApp(filteredApps[at.index].url) }
    }

    private static func cellID(_ at: GridSelection.Position) -> String { "\(at.section)-\(at.index)" }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 2)
    }

    /// A section's results in `columns` fixed columns, each cell highlighted while selected (the
    /// lighter rounded background of #179's previews) and selected by the pointer as it passes.
    private func grid(section: Int, columns: Int, _ cells: [AnyView]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                let at = GridSelection.Position(section: section, index: i)
                cell
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(selection.at == at ? 0.10 : 0)))
                    .onHover { inside in
                        let now = NSEvent.mouseLocation
                        guard inside, now != pointer else { return }
                        pointer = now
                        selection.select(at)
                    }
                    .id(Self.cellID(at))
            }
        }
    }

    /// #189: the frame a window's picture is fitted into.
    static let thumbSize = CGSize(width: 180, height: 112)
    private static let thumbShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    /// The picture, aspect-fit, the app icon on its corner; the icon alone without one. Then the
    /// title and where the window is.
    private func windowCell(_ item: OverviewWindowItem) -> AnyView {
        let picture = thumbnails[item.ref]
        return AnyView(
            Button { onSelectWindow(item.ref) } label: {
                VStack(spacing: 3) {
                    ZStack {
                        Self.thumbShape.fill(.quaternary.opacity(0.6))
                        if let picture {
                            Image(nsImage: picture).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        } else {
                            icon(item.icon, side: 40)
                        }
                    }
                    .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                    .clipShape(Self.thumbShape)
                    .overlay(alignment: .bottomTrailing) {
                        if picture != nil { icon(item.icon, side: 20).shadow(radius: 1).padding(4) }
                    }
                    title(item.name)
                    Text(item.detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: Self.thumbSize.width)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.name == item.app ? item.name : "\(item.app) — \(item.name)")
        )
    }

    private func appCell(_ item: OverviewAppItem) -> AnyView {
        AnyView(
            Button { onLaunchApp(item.url) } label: {
                VStack(spacing: 4) {
                    icon(item.icon, side: 40)
                    title(item.name)
                }
                .frame(width: 92, height: 74)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.name)
        )
    }

    /// Middle truncation: a title's two ends say the most ("Report — Pages", "~/code — zsh").
    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
    }

    @ViewBuilder
    private func icon(_ image: NSImage?, side: CGFloat) -> some View {
        if let image {
            Image(nsImage: image).resizable().frame(width: side, height: side)
        } else {
            Image(systemName: "app.dashed").font(.system(size: side * 0.75)).frame(width: side, height: side)
                .foregroundStyle(.secondary)
        }
    }
}
