import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// The window tab bar + layout switcher: material-shell's `WorkspacePanel`. Tabs are the active
/// workspace's row, left→right in row order — the same order `Fn+A`/`Fn+D` walk, so the bar is a
/// map of the navigation, not just of the layout. Tabs show the app icon and the window title
/// (#110), or the app name for a window with no title.
struct WorkspacePanelView: View {
    let state: ScreenShellState
    let metaFor: (Int32) -> AppMeta
    let sizing: TabSizing
    var chrome: PanelChrome = PanelChrome(color: "system", opacity: 1)
    let send: (Command) -> Void
    /// #10: the cog, and the ⋯ menu's "Edit layouts…" — the layout popover, which the controller
    /// owns because it is a window of its own.
    var openLayouts: () -> Void = {}

    /// Where a dragged tab would land, while it is being dragged.
    private enum DropSlot: Equatable {
        case before(SpacialShellProtocol.WindowRef)
        case endOfRow
    }

    @State private var dropSlot: DropSlot?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The narrowest a tab gets: the design system's tab-width floor (88 pt, "tab width 88–220").
    /// That is 16 pt icon + 5 spacing + 2×9 padding, leaving ~49 pt — seven or eight characters of
    /// 11.5 pt text, enough to tell "Terminal" from "Mail". Tabs squeeze toward it before anything
    /// else happens; past it the row scrolls instead of truncating names to "…" (#14).
    static let minTabWidth: CGFloat = 88
    /// The focused tab also carries its close button (8 pt glyph + 5 spacing), and a semibold
    /// name; without this it would be the one tab you can't read — "Ter…".
    private static func minWidth(_ tab: WindowTabItem) -> CGFloat {
        tab.isFocused ? minTabWidth + 16 : minTabWidth
    }
    /// The design system's tab-width ceiling: a long title truncates, it does not take the bar.
    static let maxTabWidth: CGFloat = 220
    private static let tabSpacing: CGFloat = 3
    private static let endGap: CGFloat = 8

    var body: some View {
        HStack(spacing: 3) {
            tabRow
            layoutSwitcher
            // ⋯: every layout, not just the bar set (design §7).
            Button {
                LayoutMenu.make(state, send: send, editLayouts: openLayouts)
                    .popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 22)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .panelButton()
            .help("All layouts")
            // Flush to the trailing edge: the layout popover (#10, absorbing #15) — every layout by
            // name, the bar set, the default, and the editor. The rail's cog is the one for settings.
            Button(action: openLayouts) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 22)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .panelButton()
            .help("Layouts")
            .padding(.leading, 2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 1).opacity(0.6) }
    }

    /// The tabs, in row order — the order `Fn+A`/`Fn+D` walk, scrolled or not. The row is given
    /// the viewport's width, so tabs squeeze toward `minTabWidth`; once every tab is at the floor it
    /// is given the floor total instead and scrolls, keeping the focused tab in view.
    private var tabRow: some View {
        let floor = state.tabs.reduce(Self.endGap) { $0 + Self.minWidth($1) + Self.tabSpacing }
        let focused = state.tabs.first(where: \.isFocused)?.ref
        return GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Self.tabSpacing) {
                        ForEach(state.tabs) { tab in
                            tabView(tab).id(tab.ref)
                        }
                        endOfRowTarget
                    }
                    .frame(width: max(geo.size.width, floor), height: geo.size.height, alignment: .leading)
                }
                // `initial`: a bar that appears with focus off-screen jumps there; old == new
                // only on that first call, so only focus *changes* animate.
                .onChange(of: focused, initial: true) { old, ref in
                    guard let ref else { return }
                    withAnimation(old == ref || reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(ref) }
                }
            }
        }
    }

    /// The gap after the last tab is itself a drop target: dropping there appends, which is the
    /// only way to move a tab to the end of the row without a tab to aim before — or, for a tab
    /// dragged from another display's bar, to put it on this one (#32).
    private var endOfRowTarget: some View {
        Spacer(minLength: Self.endGap)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(alignment: .leading) { caret(visible: dropSlot == .endOfRow) }
            .dropDestination(for: DraggedWindow.self) { items, _ in
                guard let dropped = items.first else { return false }
                send(state.endOfRowDrop(dropped.ref))
                return true
            } isTargeted: { over in
                dropSlot = over ? .endOfRow : nil
            }
    }

    /// Not a `Button`: the close control inside it is one, and nested buttons fight over the
    /// click. The tab body selects via a tap gesture; the inner button wins for clicks on it.
    private func tabView(_ tab: WindowTabItem) -> some View {
        let meta = metaFor(tab.ref.pid)
        let titled = !tab.title.isEmpty
        return HStack(spacing: 5) {
            if sizing == .equal { Spacer(minLength: 0) }
            if let icon = meta.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            // Middle truncation for titles: both ends carry the meaning ("Report — Pages",
            // "~/code/spacial-shell — zsh"). An app name keeps the tail truncation it always had.
            Text(titled ? tab.title : meta.name)
                .font(.system(size: 11.5, weight: tab.isFocused ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(titled ? .middle : .tail)
            if tab.isFloating {
                Image(systemName: "pin.fill").font(.system(size: 8)).opacity(0.6)
            }
            if tab.isFullscreen {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8, weight: .semibold)).opacity(0.6)
            } else if tab.isOffSpace && !tab.isHidden {
                // #55: "elsewhere", not "put away" — hidden already reads as dimmed, and a
                // fullscreen window is on its own Space by definition, so its marker says it.
                Image(systemName: "macwindow.on.rectangle").font(.system(size: 8, weight: .semibold)).opacity(0.6)
            }
            if tab.isFocused {
                Button {
                    send(.closeWindowRef(tab.ref))
                } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).opacity(0.6)
                }
                .panelButton()
                .help("Close window")
            }
            if sizing == .equal { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 9)
        .modifier(WidthCap(max: sizing == .fit ? Self.maxTabWidth : .infinity))
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
        // `fit` leaves the tab at its content width, so one tab sits against the left edge
        // instead of stretching across the bar. `equal` lets every tab claim 1/n and centre.
        .frame(minWidth: Self.minWidth(tab), maxWidth: sizing == .equal ? .infinity : nil)
        .contentShape(Rectangle())
        .onTapGesture { send(.focusWindowRef(tab.ref)) }
        .help(titled ? "\(meta.name) — \(tab.title)" : meta.name)
        // Drag the tab to send its window somewhere: onto a rail row to move it to that
        // workspace, or onto another tab to land just before it — a reorder in its own row, a
        // move when that tab is in another row (#32).
        .draggable(DraggedWindow(ref: tab.ref))
        .overlay(alignment: .leading) { caret(visible: dropSlot == .before(tab.ref)) }
        .dropDestination(for: DraggedWindow.self) { items, _ in
            guard let dropped = items.first else { return false }
            send(.moveWindowRefBefore(dropped.ref, tab.ref))
            return true
        } isTargeted: { over in
            dropSlot = over ? .before(tab.ref) : nil
        }
    }

    /// Where the dragged tab would land. An insertion caret rather than a highlight on the target
    /// tab: the drag inserts *between* tabs, and a highlighted tab would suggest replacing it.
    private func caret(visible: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 2)
            .padding(.vertical, 3)
            .opacity(visible ? 1 : 0)
    }

    /// Design §7: the bar set (≤ 8), then the layout on screen if it is not in the set. A workspace
    /// whose layout is missing highlights the fallback it is drawing, badged, and says why.
    private var layoutSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(state.switcher) { choice in
                let shown = choice.id == state.shownLayout
                Button {
                    if let ws = state.rail.first(where: \.isActive) { send(.setWorkspaceLayout(ws.id, choice.id)) }
                } label: {
                    LayoutGlyph(def: choice.def)
                        .frame(width: 24, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(shown ? AnyShapeStyle(Color.accentColor.opacity(0.3))
                                            : AnyShapeStyle(Color.primary.opacity(0.001)))
                        )
                        .foregroundStyle(shown ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .overlay(alignment: .topTrailing) {
                            if shown, state.layoutWarning != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 9))
                                    .offset(x: 2, y: -2)
                            }
                        }
                }
                .panelButton()
                .help(shown ? state.layoutWarning ?? "\(choice.def.name) layout" : "\(choice.def.name) layout")
            }
        }
    }
}

/// Proposes at most `max` and takes the child's own width — unlike `.frame(maxWidth:)`, which
/// grows to whatever it is offered. A short tab stays its content width; a long title truncates
/// at the cap instead of taking the bar (#110).
private struct WidthCap: ViewModifier {
    let max: CGFloat
    func body(content: Content) -> some View { Cap(max: max) { content } }

    private struct Cap: Layout {
        let max: CGFloat
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            subviews.first?.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? .infinity, max),
                                                          height: proposal.height)) ?? .zero
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}
