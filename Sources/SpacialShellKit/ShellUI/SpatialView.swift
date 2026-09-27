import Foundation
import CoreGraphics
import SpacialShellProtocol

// #132 (M3 B9): the spatialisation view. The zoomed-out picture of the model the README draws —
// one mini-desktop per workspace, top to bottom — made a real mode. Drawn *schematically from the
// model*: each window a chip where its row's layout puts it, no screen capture. Everything the
// view needs is derived here; the UI resolves pids to names and icons, as the panels do.

/// One window drawn on a mini-desktop, where the row's layout frames it.
public struct SpatialChip: Identifiable, Equatable, Sendable {
    public var id: WindowRef { ref }
    public let ref: WindowRef
    /// Unit coordinates of the mini-desktop: 0…1, top-left origin.
    public let frame: CGRect
    public let title: String
    public let isFocused: Bool
    public init(ref: WindowRef, frame: CGRect, title: String = "", isFocused: Bool = false) {
        self.ref = ref; self.frame = frame; self.title = title; self.isFocused = isFocused
    }
}

/// One workspace as a mini-desktop.
public struct SpatialRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let index: Int
    public let name: String
    public let symbol: String
    /// The row's own category (#112); the view falls back to its apps', as the rail does.
    public let category: AppCategory?
    /// The windows its layout shows on screen, framed as they are.
    public let chips: [SpatialChip]
    /// The rest of the row, in order: off the layout's page, floating, minimized, fullscreen or on
    /// another Space. Still in the row; drawn beside the mini-desktop, not on it.
    public let offscreen: [WindowRef]
    public let isActive: Bool
    public let isTrailingEmpty: Bool
    public init(id: UUID, index: Int, name: String, symbol: String = RailTile.defaultSymbol, category: AppCategory? = nil,
                chips: [SpatialChip] = [], offscreen: [WindowRef] = [], isActive: Bool = false, isTrailingEmpty: Bool = false) {
        self.id = id; self.index = index; self.name = name; self.symbol = symbol; self.category = category
        self.chips = chips; self.offscreen = offscreen; self.isActive = isActive; self.isTrailingEmpty = isTrailingEmpty
    }
    public var windows: [WindowRef] { chips.map(\.ref) + offscreen }
}

public struct SpatialState: Equatable, Sendable {
    public let display: DisplayID
    public let rows: [SpatialRow]
    /// The mini-desktops' width ÷ height: the display's tiling area.
    public let aspect: CGFloat
    public init(display: DisplayID, rows: [SpatialRow], aspect: CGFloat) {
        self.display = display; self.rows = rows; self.aspect = aspect
    }
    /// The row the camera centres on.
    public var activeIndex: Int { rows.firstIndex(where: \.isActive) ?? 0 }
}

public enum SpatialView {
    /// `viewport` is the display's tiling rect size (what the layout divides), in points, and
    /// `gap` the configured gap — so a mini-desktop is that screen at a smaller scale.
    public static func state(for display: DisplayID, in world: World, layouts: LayoutCatalogue,
                             titles: [WindowRef: String] = [:], viewport: CGSize, gap: CGFloat = 8) -> SpatialState? {
        guard let screen = world.screens[display], viewport.width > 0, viewport.height > 0 else { return nil }
        let rect = CGRect(origin: .zero, size: viewport)
        let rows = screen.workspaces.enumerated().map { i, ws in
            let tiled = world.tiled(in: ws)
            let focusedIndex = ws.anchor.flatMap { tiled.firstIndex(of: $0) } ?? 0
            let frames = LayoutEngine.frames(layouts.resolve(ws.layout).def, count: tiled.count, focused: focusedIndex,
                                             in: rect, gap: gap, portions: ws.portions, split: ws.split(in: tiled))
            var chips: [SpatialChip] = []
            for (w, f) in zip(tiled, frames) {
                guard let f else { continue }
                chips.append(SpatialChip(ref: w, frame: CGRect(x: f.minX / viewport.width, y: f.minY / viewport.height,
                                                               width: f.width / viewport.width, height: f.height / viewport.height),
                                         title: titles[w] ?? "", isFocused: world.focus.window == w))
            }
            let shown = Set(chips.map(\.ref))
            return SpatialRow(id: ws.id, index: i, name: ws.name, symbol: ws.symbol, category: ws.category, chips: chips,
                              offscreen: ws.windows.filter { !shown.contains($0) },
                              isActive: i == screen.activeIndex,
                              isTrailingEmpty: i == screen.workspaces.count - 1 && ws.isEmpty && !ws.pinned)
        }
        return SpatialState(display: display, rows: rows, aspect: viewport.width / viewport.height)
    }

    /// The camera: how far to shift a column of rows `rowHeight` tall, `spacing` apart, so row
    /// `active` sits in the middle of a view `viewHeight` tall. Moving between rows is a change of
    /// this one number, which the view animates — the slide.
    public static func cameraOffset(active: Int, rowHeight: CGFloat, spacing: CGFloat, viewHeight: CGFloat) -> CGFloat {
        viewHeight / 2 - (CGFloat(active) * (rowHeight + spacing) + rowHeight / 2)
    }

    /// Holding the workspace keys opens the view: an autorepeat of a chord bound to one of these.
    public static func opensOnHold(_ command: Command) -> Bool {
        switch command {
        case .focusWorkspace, .moveWindowToWorkspace: true
        default: false
        }
    }

    /// Whether the preset's modifier is still down. A view opened by holding closes when it is
    /// released, where the last Fn+W/S left the focus — the ⌘Tab gesture.
    public static func isHeld(_ flags: CGEventFlags, preset: KeybindingPreset) -> Bool {
        switch preset {
        case .fn: flags.contains(.maskSecondaryFn)
        case .ctrlAlt: flags.contains(.maskControl) && flags.contains(.maskAlternate)
        }
    }
}
