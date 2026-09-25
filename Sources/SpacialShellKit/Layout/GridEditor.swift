import Foundation
import SpacialShellProtocol

/// The layout editor's model (#10, custom grid layouts design §2 "Editor model"): a guillotine grid.
/// Start from an n×m preset, drag the splitters between cells, ⇧-click two cells to merge them.
/// Only the zone list is stored; splitters are derived from the zones' edges every time.
///
/// Cells live on a 1/48 lattice, so snapping is not a step the drag has to remember to do: a
/// position the lattice cannot express cannot be stored. 48 divides by 2, 3, 4, 6 and 8, so every
/// preset and every "thirds" or "quarters" drag is exact, and the zones it writes are the same
/// doubles `x / 48` always produces.
///
/// Pure and AppKit-free: the canvas in `SpacialShellUI` draws `cells`, hit-tests with
/// `splitter(near:)` and forwards drags and ⇧-clicks here.
public struct GridEditor: Equatable, Sendable {
    public static let lattice = 48

    /// One zone in lattice units: `x…x+w`, `y…y+h` out of 48, origin top-left, y-down.
    public struct Cell: Hashable, Sendable {
        public var x, y, w, h: Int
        public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
        public var zone: LayoutZone {
            let n = Double(GridEditor.lattice)
            return LayoutZone(x: Double(x) / n, y: Double(y) / n, w: Double(w) / n, h: Double(h) / n)
        }
    }

    public enum Preset: CaseIterable, Sendable {
        case one, twoColumns, threeColumns, grid2x2, grid3x2
        var shape: (cols: Int, rows: Int) {
            switch self {
            case .one: (1, 1)
            case .twoColumns: (2, 1)
            case .threeColumns: (3, 1)
            case .grid2x2: (2, 2)
            case .grid3x2: (3, 2)
            }
        }
        public var cells: [Cell] {
            let (cols, rows) = shape, n = GridEditor.lattice
            return (0..<rows).flatMap { r in
                (0..<cols).map { c in Cell(x: c * n / cols, y: r * n / rows, w: n / cols, h: n / rows) }
            }
        }
        public var zones: [LayoutZone] { cells.map(\.zone) }
    }

    /// A shared edge between cells, which dragging moves. `vertical` is a line at `x = at`, dragged
    /// left and right; it spans `from…to` down the other axis. `before`/`after` are the cells on
    /// its leading and trailing side, captured when it was derived, so a drag keeps moving the
    /// same cells even when it lines up with another edge on the way.
    public struct Splitter: Hashable, Sendable {
        public enum Axis: Sendable { case vertical, horizontal }
        public let axis: Axis
        public let at: Int
        public let from: Int, to: Int
        let before: [Int], after: [Int]
        /// As fractions of the canvas, for drawing.
        public var position: Double { Double(at) / Double(GridEditor.lattice) }
        public var span: ClosedRange<Double> { Double(from) / Double(GridEditor.lattice)...Double(to) / Double(GridEditor.lattice) }
        /// "60%", what the hint line shows while dragging.
        public var percent: String { "\(Int((position * 100).rounded()))%" }
    }

    /// Stable while editing — a drag holds indices into it. `number(of:)` gives the fill order.
    public private(set) var cells: [Cell]
    /// The first cell of a ⇧-click pair, waiting for its partner.
    public private(set) var selected: Int?
    public private(set) var name: String
    public private(set) var id: String
    /// Kept from the layout being edited: the editor draws zones, it does not pick symbols.
    public let symbol: String?
    /// A new layout (New…, Duplicate) names its own id; an existing one keeps it, because the
    /// workspaces using it hold the id, not the name.
    public let isNew: Bool
    private var idEdited = false

    public init(preset: Preset = .grid2x2, name: String = "", id: String? = nil) {
        cells = preset.cells
        symbol = nil
        isNew = true
        self.name = name
        self.id = id ?? Self.slug(name)
        idEdited = id != nil
    }

    /// Opens an existing drawn layout; nil when its zones are not a clean block decomposition of
    /// the unit square on the lattice (hand-written overlap, holes, or thirds of a third) — design
    /// §2: such a layout opens read-only.
    public init?(editing def: LayoutDef) {
        guard case .zones(let zones) = def.body, let cells = Self.cells(zones) else { return nil }
        self.cells = cells
        symbol = def.symbol
        isNew = false
        name = def.name
        id = def.id.rawValue
    }

    /// Duplicate: a new layout starting from `def`. A built-in has no zone list (it is a function of
    /// the window count, design §5), so it starts from the drawn grid closest to its usual look.
    public init(duplicating def: LayoutDef) {
        switch def.body {
        case .zones(let zones): cells = Self.cells(zones) ?? Preset.grid2x2.cells
        case .builtin(let b):
            switch b {
            case .maximize: cells = Preset.one.cells
            case .split: cells = Preset.twoColumns.cells
            case .column: cells = Preset.threeColumns.cells
            case .grid: cells = Preset.grid2x2.cells
            case .half: cells = [Cell(x: 0, y: 0, w: 24, h: 48), Cell(x: 24, y: 0, w: 24, h: 24), Cell(x: 24, y: 24, w: 24, h: 24)]
            }
        }
        symbol = def.symbol
        isNew = true
        name = "\(def.name) copy"
        id = Self.slug(name)
    }

    // MARK: - editing

    public mutating func apply(_ preset: Preset) {
        cells = preset.cells
        selected = nil
    }

    /// While the id is still the one the name suggested, it follows the name.
    public mutating func setName(_ new: String) {
        name = new
        if isNew && !idEdited { id = Self.slug(new) }
    }

    public mutating func setID(_ new: String) {
        guard isNew else { return }
        id = new
        idEdited = true
    }

    /// Merge two cells when together they are exactly a rectangle. They never overlap, so that is
    /// "their bounding box has no area either lacks". Returns whether it merged.
    @discardableResult
    public mutating func merge(_ a: Int, _ b: Int) -> Bool {
        guard a != b, cells.indices.contains(a), cells.indices.contains(b) else { return false }
        let p = cells[a], q = cells[b]
        let x = min(p.x, q.x), y = min(p.y, q.y)
        let box = Cell(x: x, y: y, w: max(p.x + p.w, q.x + q.w) - x, h: max(p.y + p.h, q.y + q.h) - y)
        guard box.w * box.h == p.w * p.h + q.w * q.h else { return false }
        cells[a] = box
        cells.remove(at: b)
        return true
    }

    /// ⇧-click: the first picks a cell, the second merges with it if the pair is a rectangle, and
    /// otherwise becomes the new pick. Clicking the picked cell again drops it.
    public mutating func shiftClick(_ i: Int) {
        guard cells.indices.contains(i) else { return }
        guard let s = selected else { selected = i; return }
        if s == i { selected = nil } else if merge(s, i) { selected = nil } else { selected = i }
    }

    /// Every edge two or more cells share, as draggable segments.
    public var splitters: [Splitter] { derive(.vertical) + derive(.horizontal) }

    /// The splitter under a point, in canvas fractions, within `tolerance` of it (also fractions,
    /// per axis, since the canvas is not square). Nil in the middle of a cell.
    public func splitter(near p: (x: Double, y: Double), tolerance: (x: Double, y: Double)) -> Splitter? {
        splitters.filter { s in
            switch s.axis {
            case .vertical: abs(p.x - s.position) <= tolerance.x && s.span.contains(p.y)
            case .horizontal: abs(p.y - s.position) <= tolerance.y && s.span.contains(p.x)
            }
        }.min { a, b in
            abs((a.axis == .vertical ? p.x : p.y) - a.position) < abs((b.axis == .vertical ? p.x : p.y) - b.position)
        }
    }

    /// Drag `s` to `position` (a canvas fraction): snapped to the lattice and clamped so no cell on
    /// either side drops below one step. Returns the splitter where it now is, to keep dragging.
    @discardableResult
    public mutating func move(_ s: Splitter, to position: Double) -> Splitter {
        let n = Self.lattice
        let lo = s.before.map { s.axis == .vertical ? cells[$0].x : cells[$0].y }.max() ?? 0
        let hi = s.after.map { s.axis == .vertical ? cells[$0].x + cells[$0].w : cells[$0].y + cells[$0].h }.min() ?? n
        let at = min(max(Int((position * Double(n)).rounded()), lo + 1), hi - 1)
        for i in s.before {
            if s.axis == .vertical { cells[i].w = at - cells[i].x } else { cells[i].h = at - cells[i].y }
        }
        for i in s.after {
            if s.axis == .vertical { cells[i].w += cells[i].x - at; cells[i].x = at }
            else { cells[i].h += cells[i].y - at; cells[i].y = at }
        }
        return Splitter(axis: s.axis, at: at, from: s.from, to: s.to, before: s.before, after: s.after)
    }

    // MARK: - output

    /// Fill order (design §2): row-major, y then x. Window `i` of a page goes to zone `i`.
    private var order: [Int] { cells.indices.sorted { (cells[$0].y, cells[$0].x) < (cells[$1].y, cells[$1].x) } }

    /// The number the canvas prints on cell `i`, 1-based.
    public func number(of i: Int) -> Int { (order.firstIndex(of: i) ?? 0) + 1 }

    /// The zone list Save writes, in fill order.
    public var zones: [LayoutZone] { order.map { cells[$0].zone } }

    public var def: LayoutDef {
        LayoutDef(id: LayoutID(rawValue: id), name: name.trimmingCharacters(in: .whitespaces), symbol: symbol,
                  body: .zones(zones))
    }

    /// Why Save is disabled, or nil when it is not. `taken` is every id the catalogue already has.
    public func problem(taken: Set<LayoutID>) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the layout a name." }
        if id.isEmpty || !id.allSatisfy({ ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" || $0 == "_" }) {
            return "The id can use lowercase letters, digits, - and _."
        }
        if LayoutDef.builtins.contains(where: { $0.id.rawValue == id }) { return "\"\(id)\" is a built-in layout. Pick another id." }
        if isNew && taken.contains(LayoutID(rawValue: id)) { return "A layout with the id \"\(id)\" already exists." }
        return nil
    }

    /// "Code, three" → "code-three".
    public static func slug(_ name: String) -> String {
        name.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? String($0) : "-" }.joined()
            .split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
    }

    /// The delete sheet's second line (design §8.6).
    public static func deleteWarning(usage: Int, fallback: LayoutID) -> String {
        switch usage {
        case 0: "No workspace uses this layout."
        case 1: "1 workspace uses this layout; it will use \(fallback.rawValue) until you choose another."
        default: "\(usage) workspaces use this layout; they will use \(fallback.rawValue) until you choose another."
        }
    }

    // MARK: - private

    /// Lattice cells for a zone list, or nil if it is not a clean decomposition: every edge on the
    /// lattice, nothing overlapping (design §2: the editor refuses overlap > 1e-6), nothing missing.
    static func cells(_ zones: [LayoutZone]) -> [Cell]? {
        let n = Double(lattice)
        func snap(_ v: Double) -> Int? {
            let s = (v * n).rounded()
            return abs(v * n - s) < 1e-6 ? Int(s) : nil
        }
        var out: [Cell] = []
        for z in zones {
            guard let x = snap(z.x), let y = snap(z.y), let w = snap(z.w), let h = snap(z.h), w > 0, h > 0 else { return nil }
            out.append(Cell(x: x, y: y, w: w, h: h))
        }
        for (i, a) in out.enumerated() {
            for b in out[(i + 1)...] where a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h {
                return nil
            }
        }
        return out.reduce(0) { $0 + $1.w * $1.h } == lattice * lattice ? out : nil
    }

    /// One axis's splitters: every interior edge position, split into connected segments.
    private func derive(_ axis: Splitter.Axis) -> [Splitter] {
        // (leading edge, trailing edge, span start, span end) along the chosen axis.
        func edges(_ c: Cell) -> (lead: Int, trail: Int, from: Int, to: Int) {
            axis == .vertical ? (c.x, c.x + c.w, c.y, c.y + c.h) : (c.y, c.y + c.h, c.x, c.x + c.w)
        }
        let positions = Set(cells.map { edges($0).trail }).filter { $0 < Self.lattice }.sorted()
        var out: [Splitter] = []
        for at in positions {
            let before = cells.indices.filter { edges(cells[$0]).trail == at }
            let after = cells.indices.filter { edges(cells[$0]).lead == at }
            // Merge the touching spans of both sides into segments.
            let spans = (before + after).map { (edges(cells[$0]).from, edges(cells[$0]).to) }.sorted { $0.0 < $1.0 }
            var segments: [(Int, Int)] = []
            for s in spans {
                if let last = segments.last, s.0 <= last.1 { segments[segments.count - 1].1 = max(last.1, s.1) }
                else { segments.append(s) }
            }
            for (from, to) in segments {
                func inside(_ i: Int) -> Bool { edges(cells[i]).from >= from && edges(cells[i]).to <= to }
                let b = before.filter(inside), a = after.filter(inside)
                guard !b.isEmpty, !a.isEmpty else { continue }
                out.append(Splitter(axis: axis, at: at, from: from, to: to, before: b, after: a))
            }
        }
        return out
    }
}
