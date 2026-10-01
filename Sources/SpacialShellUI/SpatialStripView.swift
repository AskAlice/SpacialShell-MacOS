import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// #132 (M3 B9): the spatialisation view — the focused display's workspaces as mini-desktops, one
/// per row, top to bottom, as the model has them. Each mini-desktop is that screen at a small
/// scale: its windows are chips where the row's layout frames them, and the rest of the row (off
/// the layout's page, floating, minimized) waits beside it as icons. The camera keeps the active
/// row in the middle and slides when it changes; clicking a mini-desktop goes there, clicking a
/// chip goes to that window, and clicking the backdrop closes the view.
///
/// #181: a chip with a picture in `thumbnails` draws it, filling the chip, with its icon and title
/// on a material band along the bottom; a chip without one is the icon and title alone. The view
/// captures nothing: `SpatialController` looks the pictures up in `WindowThumbnails` and hands in
/// new ones as they land.
///
/// Props in, `Command` out, like every panel: `SpatialView.state` and the pictures are the input.
struct SpatialStripView: View {
    let state: SpatialState
    let metaFor: (Int32) -> AppMeta
    let send: (Command) -> Void
    /// The chips' cached window pictures; a chip missing here draws its icon and title.
    var thumbnails: [SpacialShellProtocol.WindowRef: NSImage] = [:]
    var dismiss: () -> Void = {}
    /// Reduce Motion: the camera cuts instead of sliding.
    var reduceMotion = false

    static let spacing: CGFloat = 28
    private static let labelWidth: CGFloat = 132
    private static let asideWidth: CGFloat = 132
    private static let maxAside = 5

    var body: some View {
        GeometryReader { geo in
            let rowHeight = Self.rowHeight(in: geo.size, aspect: state.aspect)
            ZStack(alignment: .top) {
                Color.primary.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)
                VStack(spacing: Self.spacing) {
                    ForEach(state.rows) { row(row: $0, height: rowHeight) }
                }
                .frame(width: geo.size.width)
                .offset(y: SpatialView.cameraOffset(active: state.activeIndex, rowHeight: rowHeight,
                                                    spacing: Self.spacing, viewHeight: geo.size.height))
                .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: state.activeIndex)
            }
        }
        .background(Rectangle().fill(.ultraThinMaterial))
        .clipped()
    }

    /// Under a third of the view per row, so the rows either side of the active one show; never
    /// wider than the space the label and the aside leave.
    static func rowHeight(in size: CGSize, aspect: CGFloat) -> CGFloat {
        let byWidth = (size.width - labelWidth - asideWidth - 2 * 24 - 64) / max(aspect, 0.1)
        return max(40, min(size.height * 0.28, byWidth))
    }

    private func row(row: SpatialRow, height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 24) {
            label(row).frame(width: Self.labelWidth, alignment: .trailing)
            desktop(row, height: height)
            // Held open when empty, so every mini-desktop lines up under the others.
            ZStack(alignment: .leading) { Color.clear; aside(row, height: height) }.frame(width: Self.asideWidth)
        }
        .frame(height: height)
        .opacity(row.isActive ? 1 : 0.72)
    }

    // MARK: the label

    private func category(_ row: SpatialRow) -> AppCategory? {
        AppCategories.rowCategory(row.category, windows: row.windows) { metaFor($0).category }
    }

    private func label(_ row: SpatialRow) -> some View {
        let c = category(row)
        let title = AppCategories.rowTitle(name: row.name, category: c, isTrailingEmpty: row.isTrailingEmpty)
        return VStack(alignment: .trailing, spacing: 3) {
            Text("\(row.index + 1)")
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(row.isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            HStack(spacing: 4) {
                if !row.isTrailingEmpty, let c {
                    Image(systemName: c.symbol).font(.system(size: 10, weight: .medium))
                }
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(row.isActive ? .primary : .secondary)
            let n = row.windows.count
            if !row.isTrailingEmpty {
                Text(n == 1 ? "1 window" : "\(n) windows").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: the mini-desktop

    private func desktop(_ row: SpatialRow, height: CGFloat) -> some View {
        let size = CGSize(width: height * state.aspect, height: height)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(Color.primary.opacity(0.06))
            if row.isTrailingEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                    Text("Start a new workspace").font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .frame(width: size.width, height: size.height)
            } else if row.chips.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: category(row)?.symbol ?? row.symbol).font(.system(size: 20, weight: .medium))
                    Text(row.offscreen.isEmpty ? "Empty" : "Nothing tiled").font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .frame(width: size.width, height: size.height)
            }
            ForEach(row.chips) { chip in
                let f = CGRect(x: chip.frame.minX * size.width, y: chip.frame.minY * size.height,
                               width: chip.frame.width * size.width, height: chip.frame.height * size.height)
                self.chip(chip, size: f.size)
                    .frame(width: f.width, height: f.height)
                    .offset(x: f.minX, y: f.minY)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            shape.strokeBorder(row.isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                               style: StrokeStyle(lineWidth: row.isActive ? 2 : 1, dash: row.isTrailingEmpty ? [5, 4] : []))
        )
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { send(.focusWorkspaceID(row.id)); dismiss() }
        .help(row.isTrailingEmpty ? "New workspace" : "Go to workspace \(row.index + 1)")
    }

    private func chip(_ chip: SpatialChip, size: CGSize) -> some View {
        let meta = metaFor(chip.ref.pid)
        return chipFace(chip, meta: meta, size: size)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(chip.isFocused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                              lineWidth: chip.isFocused ? 1.5 : 0.5)
        )
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { send(.focusWindowRef(chip.ref)); dismiss() }
        .help(chip.title.isEmpty ? meta.name : "\(meta.name) — \(chip.title)")
    }

    private static let chipShape = RoundedRectangle(cornerRadius: 5, style: .continuous)

    /// Titled where there is room for a line of text.
    private static func roomy(_ size: CGSize) -> Bool { size.height >= 44 && size.width >= 60 }

    private func chipTitle(_ chip: SpatialChip, meta: AppMeta) -> some View {
        Text(chip.title.isEmpty ? meta.name : chip.title)
            .font(.system(size: 10, weight: chip.isFocused ? .semibold : .regular))
            .lineLimit(1).truncationMode(.tail)   // #175: the beginning, like the tab bar
    }

    /// The window's picture if there is one (#181), otherwise its icon and title on material.
    @ViewBuilder
    private func chipFace(_ chip: SpatialChip, meta: AppMeta, size: CGSize) -> some View {
        let inner = CGSize(width: max(0, size.width - 2), height: max(0, size.height - 2))
        if let picture = thumbnails[chip.ref] {
            // The window fills its chip as it fills its tile; the band keeps the label legible
            // over whatever the picture is, in either appearance.
            let band = min(18, max(12, inner.height * 0.3))
            ZStack(alignment: .bottom) {
                Image(nsImage: picture).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: inner.width, height: inner.height).clipped()
                HStack(spacing: 4) {
                    appIcon(meta, side: band - 6)
                    if Self.roomy(size) { chipTitle(chip, meta: meta) }
                }
                .padding(.horizontal, 4)
                .frame(width: inner.width, height: band, alignment: .leading)
                .background(Rectangle().fill(.regularMaterial))
            }
            .frame(width: inner.width, height: inner.height)
            .clipShape(Self.chipShape)
        } else {
            VStack(spacing: 3) {
                appIcon(meta, side: min(28, max(10, min(size.width, size.height) * 0.34)))
                if Self.roomy(size) { chipTitle(chip, meta: meta).padding(.horizontal, 4) }
            }
            .frame(width: inner.width, height: inner.height)
            .background(Self.chipShape.fill(.regularMaterial))
        }
    }

    // MARK: the rest of the row

    /// #197: the row's other tabs, the windows its layout does not show (in maximize, every tab
    /// but the focused one), as previews beside the mini-desktop: the window's picture when there
    /// is one (#181), its app icon otherwise, a click going to that window. One column for up to
    /// two, two beyond, each cell sized to fit the row; past `maxAside`, "+n" in the label.
    @ViewBuilder
    private func aside(_ row: SpatialRow, height: CGFloat) -> some View {
        if !row.offscreen.isEmpty {
            let shown = Array(row.offscreen.prefix(Self.maxAside))
            let more = row.offscreen.count - shown.count
            let gap: CGFloat = 4, labelHeight: CGFloat = 14
            let (columns, cell) = Self.tabGrid(count: shown.count, aspect: state.aspect, gap: gap,
                                               height: height - labelHeight - gap)
            VStack(alignment: .leading, spacing: gap) {
                Text(more > 0 ? "Other tabs  +\(more)" : "Other tabs").font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(height: labelHeight)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell.width), spacing: gap), count: columns),
                          alignment: .leading, spacing: gap) {
                    ForEach(shown, id: \.self) { ref in
                        tabPreview(ref, size: cell)
                            .onTapGesture { send(.focusWindowRef(ref)); dismiss() }
                            .help(metaFor(ref.pid).name)
                    }
                }
            }
        }
    }

    /// #197: one column or two for `count` previews in the aside, whichever gives each the larger
    /// picture; each at the display's shape (a maximized window's), fitting `height` in rows.
    static func tabGrid(count: Int, aspect: CGFloat, gap: CGFloat, height: CGFloat) -> (Int, CGSize) {
        let a = max(aspect, 0.1)
        return [1, 2].map { columns -> (Int, CGSize) in
            let lines = (count + columns - 1) / columns
            let fitW = (asideWidth - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let fitH = max(16, (height - CGFloat(lines - 1) * gap) / CGFloat(lines))
            let h = min(fitH, fitW / a)
            return (columns, CGSize(width: min(fitW, h * a), height: h))
        }.max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }!
    }

    /// One other tab (#197): its picture, aspect-filled, with the app icon on the corner; or the
    /// icon alone on material while there is none.
    private func tabPreview(_ ref: SpacialShellProtocol.WindowRef, size: CGSize) -> some View {
        let meta = metaFor(ref.pid)
        let badge = min(16, max(10, size.height * 0.3))
        return ZStack(alignment: .bottomTrailing) {
            if let picture = thumbnails[ref] {
                Image(nsImage: picture).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height).clipped()
                appIcon(meta, side: badge).padding(3)
            } else {
                appIcon(meta, side: min(24, size.height * 0.6))
                    .frame(width: size.width, height: size.height)
                    .background(Self.chipShape.fill(.regularMaterial))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Self.chipShape)
        .overlay(Self.chipShape.strokeBorder(.separator, lineWidth: 0.5))
    }

    @ViewBuilder
    private func appIcon(_ meta: AppMeta, side: CGFloat) -> some View {
        if let icon = meta.icon {
            Image(nsImage: icon).resizable().frame(width: side, height: side)
        } else {
            Image(systemName: "app.dashed").font(.system(size: side * 0.7)).frame(width: side, height: side)
        }
    }
}
