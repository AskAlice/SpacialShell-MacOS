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
    /// #116: icon and title, title only, or icon only. The title is in the tooltip either way.
    var style: TabStyle = .full
    var chrome: PanelChrome = PanelChrome(color: "system", opacity: 1)
    let send: (Command) -> Void
    /// #10: the cog, and the ⋯ menu's "Edit layouts…" — the layout popover, which the controller
    /// owns because it is a window of its own.
    var openLayouts: () -> Void = {}
    /// Stories only: draw this tab as hovered, since a snapshot has no pointer (#180).
    var hoverPreview: SpacialShellProtocol.WindowRef? = nil

    /// Where a dragged tab would land, while it is being dragged.
    private enum DropSlot: Equatable {
        case before(SpacialShellProtocol.WindowRef)
        case endOfRow
    }

    @State private var dropSlot: DropSlot?
    /// The tab under the pointer: it shows its close button (#180).
    @State private var hoveredTab: SpacialShellProtocol.WindowRef?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The narrowest a tab gets: the design system's tab-width floor (88 pt, "tab width 88–220").
    /// That is 16 pt icon + 5 spacing + 2×9 padding, leaving ~49 pt — seven or eight characters of
    /// 11.5 pt text, enough to tell "Terminal" from "Mail". Tabs squeeze toward it before anything
    /// else happens; past it the row scrolls instead of truncating names to "…" (#14).
    static let minTabWidth: CGFloat = 88
    /// The focused tab also carries its close button (8 pt glyph + 5 spacing), and a semibold
    /// name; without this it would be the one tab you can't read — "Ter…".
    /// An icon-only tab (#116) has no text to keep readable: its floor is the icon and padding.
    private func minWidth(_ tab: WindowTabItem) -> CGFloat {
        (style == .icon ? Self.minIconTabWidth : Self.minTabWidth) + (tab.isFocused ? 16 : 0)
    }
    static let minIconTabWidth: CGFloat = 34
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
        let floor = state.tabs.reduce(Self.endGap) { $0 + minWidth($1) + Self.tabSpacing }
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
        // #121: a vertical scroll (a wheel notch, or one trackpad gesture) steps the focused tab,
        // and the `onChange` above brings it into view. A sideways scroll is not a step: it passes
        // through to the ScrollView, which pans an overflowing row as before (#14).
        .onScrollStep { if let command = state.tabScroll($0) { send(command) } }
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
                send(appDrop(dropped.ref) ?? state.endOfRowDrop(dropped.ref))
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
        // #116: `name` drops the icon; `icon` drops the text, unless there is no icon to show.
        let icon = style == .name ? nil : meta.icon
        return HStack(spacing: 5) {
            if sizing == .equal { Spacer(minLength: 0) }
            if let icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    // #126: on the icon's corner, as the Dock draws a badge; beside the name without one.
                    .overlay(alignment: .topTrailing) {
                        if tab.wantsAttention { AttentionDot().offset(x: 2, y: -2) }
                    }
            } else if tab.wantsAttention {
                AttentionDot()
            }
            if style != .icon || icon == nil {
                // #175: a title that doesn't fit keeps its beginning and ends in "…", as an app
                // name always has; the whole title is in the tooltip (#116).
                Text(titled ? tab.title : meta.name)
                    .font(.system(size: 11.5, weight: tab.isFocused ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if tab.isPinned {
                // #129: pinned — kept, as a placeholder, when its window closes.
                Image(systemName: "pin.circle.fill").symbolRenderingMode(.hierarchical).font(.system(size: 12))
            }
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
        // #128: a placeholder is outlined, dashed, where a window's tab is filled — a slot waiting
        // for its window, not a window put away (which is only dimmed).
        .overlay {
            if tab.isPlaceholder {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(tab.isFocused ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .opacity(tab.isHidden || tab.isPlaceholder ? 0.45 : 1)
        // `fit` leaves the tab at its content width, so one tab sits against the left edge
        // instead of stretching across the bar. `equal` lets every tab claim 1/n and centre.
        .frame(minWidth: minWidth(tab), maxWidth: sizing == .equal ? .infinity : nil)
        .contentShape(Rectangle())
        .onTapGesture { send(.focusWindowRef(tab.ref)) }
        // #127: right-click is the tab menu; middle-click closes the window, as in a browser.
        .overlay {
            RailClickCatcher(
                onRight: {
                    RailMenu.tab(tab, rail: state.rail, metaFor: metaFor, send: send)
                        .popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                },
                onMiddle: { if tab.canClose { send(.closeWindowRef(tab.ref)) } })
        }
        // #180: an unfocused tab reveals its close button on hover, drawn over the end of its
        // title so the tab's width, and the row, never move as the pointer passes.
        .overlay(alignment: .trailing) {
            if !tab.isFocused, tab.canClose, (hoveredTab ?? hoverPreview) == tab.ref {
                Button {
                    send(.closeWindowRef(tab.ref))
                } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.background.opacity(0.92)))
                }
                .panelButton()
                .help("Close window")
                .padding(.trailing, 5)
            }
        }
        .onHover { inside in
            if inside { hoveredTab = tab.ref } else if hoveredTab == tab.ref { hoveredTab = nil }
        }
        // #116: the whole title, however the tab truncates or hides it. The system tooltip keeps
        // its own delay; the rail's hover card (#6) is a separate surface and waits for nothing.
        .help((titled ? "\(meta.name) — \(tab.title)" : meta.name) + (tab.isPlaceholder ? " · Click to open" : ""))
        // Drag the tab to send its window somewhere: onto a rail row to move it to that
        // workspace, or onto another tab to land just before it — a reorder in its own row, a
        // move when that tab is in another row (#32).
        .draggable(DraggedWindow(ref: tab.ref))
        .overlay(alignment: .leading) { caret(visible: dropSlot == .before(tab.ref)) }
        .dropDestination(for: DraggedWindow.self) { items, _ in
            guard let dropped = items.first else { return false }
            send(appDrop(dropped.ref) ?? .moveWindowRefBefore(dropped.ref, tab.ref))
            return true
        } isTargeted: { over in
            dropSlot = over ? .before(tab.ref) : nil
        }
    }

    /// #98: Option held on the drop moves the window's whole app to this bar's workspace (appended,
    /// not before the tab aimed at). Nil without Option: an ordinary tab drop.
    private func appDrop(_ ref: SpacialShellProtocol.WindowRef) -> Command? {
        NSEvent.modifierFlags.contains(.option) ? state.appDrop(ref) : nil
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
        // #121: scrolling over the layout icons cycles them, wrapping like Fn+Space.
        .onScrollStep { if let command = state.layoutScroll($0) { send(command) } }
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
