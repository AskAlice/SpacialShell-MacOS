import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// #132 (M3 B9): the spatialisation view — the focused display's workspaces as mini-desktops, one
/// per row, top to bottom, as the model has them. Each mini-desktop is that screen at a small
/// scale: its windows are chips where the row's layout frames them (no screen capture), and the
/// rest of the row (off the layout's page, floating, minimized) waits beside it. The camera keeps
/// the active row in the middle and slides when it changes; clicking a mini-desktop goes there,
/// clicking a chip goes to that window, and clicking the backdrop closes the view.
///
/// Props in, `Command` out, like every panel: `SpatialView.state` is the whole input.
struct SpatialStripView: View {
    let state: SpatialState
    let metaFor: (Int32) -> AppMeta
    let send: (Command) -> Void
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
            ZStack(alignment: .leading) { Color.clear; aside(row) }.frame(width: Self.asideWidth)
        }
        .frame(height: height)
        .opacity(row.isActive ? 1 : 0.72)
    }

    // MARK: the label

    private func category(_ row: SpatialRow) -> AppCategory? {
        row.category ?? AppCategories.summarise(RailTile.distinctApps(row.windows).map { metaFor($0).category })
    }

    private func label(_ row: SpatialRow) -> some View {
        let c = category(row)
        let title = row.isTrailingEmpty ? "New workspace" : (c.map { $0.label.prefix(1).uppercased() + $0.label.dropFirst() } ?? row.name)
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
        let icon = min(28, max(10, min(size.width, size.height) * 0.34))
        let roomy = size.height >= 44 && size.width >= 60
        return VStack(spacing: 3) {
            appIcon(meta, side: icon)
            if roomy {
                Text(chip.title.isEmpty ? meta.name : chip.title)
                    .font(.system(size: 10, weight: chip.isFocused ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: size.width - 2, height: size.height - 2)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.regularMaterial))
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

    // MARK: the rest of the row

    @ViewBuilder
    private func aside(_ row: SpatialRow) -> some View {
        if !row.offscreen.isEmpty {
            let shown = Array(row.offscreen.prefix(Self.maxAside))
            VStack(alignment: .leading, spacing: 4) {
                Text("Also in this row").font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(shown, id: \.self) { ref in
                        appIcon(metaFor(ref.pid), side: 20)
                            .onTapGesture { send(.focusWindowRef(ref)); dismiss() }
                            .help(metaFor(ref.pid).name)
                    }
                    if row.offscreen.count > shown.count {
                        Text("+\(row.offscreen.count - shown.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
        }
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
