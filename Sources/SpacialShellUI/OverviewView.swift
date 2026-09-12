import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// One open window anywhere in the world, as the overview lists it.
struct OverviewWindowItem: Identifiable {
    var id: SpacialShellProtocol.WindowRef { ref }
    let ref: SpacialShellProtocol.WindowRef
    let name: String            // app name (window titles are a follow-up, same as the tab bar)
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
struct OverviewView: View {
    let windows: [OverviewWindowItem]
    let apps: [OverviewAppItem]
    let onSelectWindow: (SpacialShellProtocol.WindowRef) -> Void
    let onLaunchApp: (URL) -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filteredWindows: [OverviewWindowItem] {
        query.isEmpty ? windows : windows.filter { $0.name.localizedCaseInsensitiveContains(query) }
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
                    .onSubmit(openFirst)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !filteredWindows.isEmpty {
                        sectionHeader("Windows")
                        grid(filteredWindows.map { item in
                            cell(name: item.name, detail: item.detail, icon: item.icon) { onSelectWindow(item.ref) }
                        })
                    }
                    if !filteredApps.isEmpty {
                        sectionHeader("Applications")
                        grid(filteredApps.map { item in
                            cell(name: item.name, detail: nil, icon: item.icon) { onLaunchApp(item.url) }
                        })
                    }
                    if filteredWindows.isEmpty && filteredApps.isEmpty {
                        Text("No matches").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 24)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .onAppear { searchFocused = true }
    }

    /// Enter opens the first visible result, windows before apps — the "I typed enough" path.
    private func openFirst() {
        if let w = filteredWindows.first { onSelectWindow(w.ref) } else if let a = filteredApps.first { onLaunchApp(a.url) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 2)
    }

    private func grid(_ cells: [AnyView]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { $0.element }
        }
    }

    private func cell(name: String, detail: String?, icon: NSImage?, action: @escaping () -> Void) -> AnyView {
        AnyView(
            Button(action: action) {
                VStack(spacing: 4) {
                    if let icon {
                        Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                    } else {
                        Image(systemName: "app.dashed").font(.system(size: 30)).frame(width: 40, height: 40)
                            .foregroundStyle(.secondary)
                    }
                    Text(name).font(.system(size: 11)).lineLimit(1)
                    if let detail {
                        Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(width: 92, height: detail == nil ? 74 : 84)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(name)
        )
    }
}
