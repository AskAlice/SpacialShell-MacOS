import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// The workspace rail: material-shell's `ScreenPanel`, minus the system tray (macOS has a menu
/// bar). One row per workspace, top→bottom in stack order; the trailing empty workspace is
/// drawn as "+" — activating it *is* creating one, that's invariant 4 doing the work.
///
/// A tile shows up to four of the apps actually in that workspace, as a 2x2 icon grid, plus its
/// window count — or, per `rail-icon-style` (#115), its category's glyph, alone or over its top
/// apps (`RailTile.face`). Names and window previews live in the hover popover rather than on the
/// tile: the rail is furniture and stays narrow, and the detail is one hover away.
struct ScreenPanelView: View {
    let state: ScreenShellState
    let launcherURL: String
    let metaFor: (Int32) -> AppMeta
    var chrome: PanelChrome = PanelChrome(color: "system", opacity: 1)
    let send: (Command) -> Void
    /// Pointer entered or left a tile. The rect is the tile's frame in the hosting view's
    /// coordinate space; the controller owns the conversion to screen coordinates and the card
    /// itself — the rail is 48 pt wide and cannot draw outside its own window.
    ///
    /// The exited tile is named rather than reported as a bare "gone", because SwiftUI does not
    /// promise that leaving one tile is delivered before entering the next: an unlabelled exit
    /// arriving late would dismiss the card the next tile had already opened.
    var onHoverTile: (WorkspaceRailItem, Bool, CGRect) -> Void = { _, _, _ in }
    /// Pointer entered or left the tray (#73), or clicked it — a click opens the list too, for
    /// anyone who clicks before the hover lands. Same coordinate space as `onHoverTile`.
    var onHoverTray: (Bool, CGRect) -> Void = { _, _ in }
    /// #109: what the shell cannot do right now. Non-empty badges the cog, and hovering it lists them.
    var problems: [Problem] = []
    var onHoverProblems: (Bool, CGRect) -> Void = { _, _ in }
    /// #112: `category-order`, which the workspace menu's "Set category" lists first.
    var categories: [AppCategory] = Config.defaultCategoryOrder
    /// #115: `rail-icon-style` and `category-colors`.
    var iconStyle: RailIconStyle = .app
    var categoryColors: [AppCategory: String] = [:]

    /// Which row the pointer is currently over mid-drag. Purely presentational — the drop itself
    /// re-enters through `Command` like every other interaction. Settable for the stories.
    @State var dropTarget: UUID?

    /// The tile this rail is dragging, if any (#75). Set when the drag begins (SwiftUI builds the
    /// payload then), because a hover cannot tell a tile from a tab otherwise — both arrive as
    /// `public.data` — and the two get different indicators: an insertion line, or a ring.
    /// ponytail: a drag cancelled outside the rail leaves this set until the next drop or click
    /// on the rail, so a tab dragged over it meanwhile shows the line; the drop is still right.
    @State var reordering: UUID?

    /// Where each tile is, so a hover can tell the controller what to put the card next to.
    @State private var tileFrames: [UUID: CGRect] = [:]
    @State private var trayFrame: CGRect = .zero
    @State private var cogFrame: CGRect = .zero

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
            .panelButton()
            .help("Search / launcher")

            ForEach(state.rail) { item in
                Button {
                    reordering = nil
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
                .panelButton()
                // No `.help` here any more: the hover card says everything the tooltip said and
                // shows the windows as well, and two hover surfaces on one tile is one too many.
                .background(GeometryReader { geo in
                    Color.clear.onChange(of: geo.frame(in: .global), initial: true) { _, frame in
                        tileFrames[item.id] = frame
                    }
                })
                .onHover { inside in
                    onHoverTile(item, inside, tileFrames[item.id] ?? .zero)
                }
                // #112: right-click is the workspace menu; middle-click removes it (W13), per the
                // `removeWorkspace` ruling (its windows merge into a neighbour). Not on "+".
                .overlay {
                    if !item.isTrailingEmpty {
                        RailClickCatcher(
                            onRight: {
                                RailMenu.workspace(item, layouts: state.layouts, categories: categories, send: send)
                                    .popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                            },
                            onMiddle: { send(.removeWorkspace(item.id)) })
                    }
                }
                .modifier(Reorderable(item: item) { reordering = item.id })
                // Dropping a tab here sends its window to this workspace without following it
                // (#95): the rail highlight and focus stay put. The trailing "+" row is not
                // special-cased: it is a workspace, and moving into it grows a new one.
                // Dropping a tile here puts it just before this one (#75). Only within this
                // display: a tile from another display's rail is not in `state.rail`, so
                // `railReorder` refuses it — moving a workspace across displays is out of scope.
                .dropDestination(for: RailDrop.self) { items, _ in
                    defer { reordering = nil }
                    switch items.first {
                    case .window(let dropped)?:
                        // #98: Option held on the drop moves the window's whole app.
                        send(NSEvent.modifierFlags.contains(.option)
                             ? .moveAppRefToWorkspace(dropped.ref, item.id)
                             : .moveWindowRefToWorkspace(dropped.ref, item.id, follow: false))
                        return true
                    case .workspace(let dragged)?:
                        guard let command = state.railReorder(dragged.workspace, before: item.id) else { return false }
                        send(command)
                        return true
                    case nil:
                        return false
                    }
                } isTargeted: { over in
                    dropTarget = over ? item.id : (dropTarget == item.id ? nil : dropTarget)
                }
            }
            Spacer(minLength: 0)

            // #73: the tray — hidden windows and popups, one hover away. Pinned above the cog, so
            // the workspace list never moves it; absent when there is nothing to bring back.
            if !state.tray.isEmpty {
                Button { onHoverTray(true, trayFrame) } label: { tray }
                    .panelButton()
                    .background(GeometryReader { geo in
                        Color.clear.onChange(of: geo.frame(in: .global), initial: true) { _, frame in trayFrame = frame }
                    })
                    .onHover { onHoverTray($0, trayFrame) }
            }

            // #111: the app menu — Zen, reload, settings, about, quit. No clock (#24 P4).
            Button {
                RailMenu.app(send: send).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            } label: {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .panelButton()
            .help("SpacialShell")

            do {
                // Every display: reaching for settings should not mean finding the right monitor.
                Button { send(.openSettings) } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        // #109: the worst severity, where the "+N" badge sits on a tile.
                        .overlay {
                            if let worst = problems.map(\.severity).max() {
                                Image(systemName: ProblemsList.symbol(worst))
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 9))
                                    .offset(x: 7, y: -7)
                            }
                        }
                }
                .panelButton()
                // With problems the hover card is the label; two hover surfaces is one too many.
                .help(problems.isEmpty ? "SpacialShell settings" : "")
                .background(GeometryReader { geo in
                    Color.clear.onChange(of: geo.frame(in: .global), initial: true) { _, frame in cogFrame = frame }
                })
                .onHover { onHoverProblems($0, cogFrame) }
                .padding(.bottom, 6)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // #121: scrolling the rail walks the stack, one workspace per notch or gesture.
        .onScrollStep { if let command = state.railScroll($0) { send(command) } }
        .background(chrome)
        .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 1).opacity(0.6) }
    }

    @ViewBuilder
    private func row(_ item: WorkspaceRailItem) -> some View {
        ZStack {
            switch RailTile.face(for: item, style: iconStyle, categoryOf: { metaFor($0).category }) {
            case .plus:
                Image(systemName: "plus").font(.system(size: 15, weight: .medium))
            case .symbol(let name, let category):
                Image(systemName: name).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint(category, active: item.isActive))
            case .apps(let pids):
                icons(pids.map(metaFor))
            case .hybrid(let name, let category, let pids):
                // The glyph names the work, the icons below it name the apps doing it.
                VStack(spacing: 2) {
                    Image(systemName: name).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tint(category, active: item.isActive))
                        .frame(height: 13)
                    HStack(spacing: 1) {
                        ForEach(pids, id: \.self) { appIcon(metaFor($0), side: 11) }
                    }
                }
                .offset(x: pids.count > 1 ? -2 : 0, y: -1)
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
                .opacity(dropTarget == item.id && reordering == nil ? 1 : 0)
        )
        // A tile being reordered lands *between* tiles, so it gets the tab bar's insertion caret,
        // turned horizontal and centred in the gap above this tile — not the ring, which says
        // "into". Hidden where the drop would change nothing (over itself or the tile below it).
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(height: 2)
                .offset(y: -3)
                .opacity(dropTarget == item.id && reordering.flatMap { state.railReorder($0, before: item.id) } != nil ? 1 : 0)
        }
        .foregroundStyle(item.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
    }

    private var tray: some View {
        ZStack {
            Image(systemName: "tray.full").font(.system(size: 14, weight: .medium))
            Text("\(state.tray.count)")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 3)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .foregroundStyle(.white)
                .offset(x: 13, y: 13)
        }
        .frame(width: 32, height: 32)
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
    }

    /// One icon fills the tile; two to four share it as a 2x2 grid. Enough to recognise a
    /// workspace by shape and colour without reading anything. The apps come from `RailTile`:
    /// one per app, in the order the row first mentions it, like the tab bar.
    @ViewBuilder
    private func icons(_ apps: [AppMeta]) -> some View {
        let shown = Array(apps.prefix(RailTile.maxApps))
        let side: CGFloat = shown.count == 1 ? 22 : 11
        let columns = shown.count == 1 ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 1), count: columns), spacing: 1) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, meta in appIcon(meta, side: side) }
        }
        .frame(width: shown.count == 1 ? 22 : 23)
    }

    @ViewBuilder
    private func appIcon(_ meta: AppMeta, side: CGFloat) -> some View {
        if let icon = meta.icon {
            Image(nsImage: icon).resizable().frame(width: side, height: side)
        } else {
            Image(systemName: "app.dashed").font(.system(size: side * 0.7))
                .frame(width: side, height: side)
        }
    }

    /// #115: a category's `category-colors` entry tints its glyph. Not on the active tile, whose
    /// glyph is white on the accent fill: the accent says "you are here", and a tint would fight it.
    private func tint(_ category: AppCategory?, active: Bool) -> AnyShapeStyle {
        guard !active, let hex = category.flatMap({ categoryColors[$0] }), let (r, g, b, a) = HexColor.rgba(hex) else {
            return AnyShapeStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
        return AnyShapeStyle(Color(.sRGB, red: r, green: g, blue: b, opacity: a))
    }
}

/// A tile drags to reorder its display's stack (#75); "+" does not — it is the way down, not a
/// workspace with a place of its own. `began` runs when the drag starts: the payload is built then.
private struct Reorderable: ViewModifier {
    let item: WorkspaceRailItem
    let began: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if item.isTrailingEmpty {
            content
        } else {
            content.draggable({ began(); return DraggedWorkspace(workspace: item.id) }())
        }
    }
}
