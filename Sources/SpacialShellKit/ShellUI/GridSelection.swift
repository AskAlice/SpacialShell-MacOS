/// #200: a keyboard selection over sections of results, each laid out in a fixed number of
/// columns: the Fn+Tab overview's windows, then its applications. Pure, so the view only maps keys
/// onto it and draws a highlight where `at` says.
///
/// ←/→ run through the results in reading order, on across a section boundary; ↑/↓ keep the
/// column, landing on a shorter row's last item and crossing into the section above or below;
/// Tab jumps to the next section with results, wrapping. Empty sections are never selected.
public struct GridSelection: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public var count: Int, columns: Int
        public init(count: Int, columns: Int) { self.count = count; self.columns = max(1, columns) }
    }
    public struct Position: Equatable, Sendable {
        public var section: Int, index: Int
        public init(section: Int, index: Int) { self.section = section; self.index = index }
    }
    public enum Direction: Sendable { case left, right, up, down }

    public private(set) var sections: [Section]
    /// The selected result; nil when there are none.
    public private(set) var at: Position?

    public init(sections: [Section]) {
        self.sections = sections
        at = sections.firstIndex { $0.count > 0 }.map { Position(section: $0, index: 0) }
    }

    /// The results changed (the search narrowed or widened): stay put where possible, else the
    /// last result of the same section, else the first result there is.
    public mutating func resize(_ sections: [Section]) {
        self.sections = sections
        if let at, sections.indices.contains(at.section), sections[at.section].count > 0 {
            self.at = Position(section: at.section, index: min(at.index, sections[at.section].count - 1))
        } else {
            at = sections.firstIndex { $0.count > 0 }.map { Position(section: $0, index: 0) }
        }
    }

    public mutating func move(_ direction: Direction) {
        guard let at else { return }
        let s = sections[at.section], col = at.index % s.columns, row = at.index / s.columns
        switch direction {
        case .right:
            if at.index + 1 < s.count { self.at!.index += 1 }
            else if let next = filled(after: at.section) { self.at = Position(section: next, index: 0) }
        case .left:
            if at.index > 0 { self.at!.index -= 1 }
            else if let prev = filled(before: at.section) { self.at = Position(section: prev, index: sections[prev].count - 1) }
        case .down:
            if row + 1 <= (s.count - 1) / s.columns {
                self.at!.index = min((row + 1) * s.columns + col, s.count - 1)
            } else if let next = filled(after: at.section) {
                self.at = Position(section: next, index: min(col, sections[next].count - 1))
            }
        case .up:
            if row > 0 {
                self.at!.index = (row - 1) * s.columns + col
            } else if let prev = filled(before: at.section) {
                let p = sections[prev], lastRow = (p.count - 1) / p.columns
                self.at = Position(section: prev, index: min(lastRow * p.columns + col, p.count - 1))
            }
        }
    }

    /// The pointer is over a result: it becomes the selection, so the keys carry on from there.
    public mutating func select(_ position: Position) {
        guard sections.indices.contains(position.section),
              (0..<sections[position.section].count).contains(position.index) else { return }
        at = position
    }

    /// The next (or previous) section with results, wrapping; its first result.
    public mutating func tab(backward: Bool) {
        guard let at else { return }
        let n = sections.count
        for step in 1...n {
            let i = ((at.section + (backward ? -step : step)) % n + n) % n
            if sections[i].count > 0 { self.at = Position(section: i, index: 0); return }
        }
    }

    private func filled(after i: Int) -> Int? { sections.indices.first { $0 > i && sections[$0].count > 0 } }
    private func filled(before i: Int) -> Int? { sections.indices.last { $0 < i && sections[$0].count > 0 } }
}
