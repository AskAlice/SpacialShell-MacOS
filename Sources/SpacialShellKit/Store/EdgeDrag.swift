import Foundation

/// #113, #162, #173: the border and four-finger edge drag — which line is in the hand, and what
/// each pointer or swipe event does to it.
///
/// A press on a shared edge between two tiles takes it (#113); four fingers dragging sideways take
/// the focused tile's side edge (#162). Either way one line is in one hand: the pointer and the
/// fingers never take it from each other. Moves arrive far faster than frames can be written, so
/// the drag only records where the hand has the line (`latest`); the store's pump asks `step` for
/// the `setPortions` that lays the row out there, as often as it can. The release (`settle`) lands
/// it and says whether it collapses to maximize (#178).
///
/// Pure: the store hands each call a `Scene` and acts on the `Verdict` — the highlight panel, the
/// pump, the settle — and owns every side effect. Its tests are `EdgeDragTests`.
struct EdgeDrag {
    /// What a decision is made against: the world now, and the geometry the last reconcile used.
    struct Scene {
        var world: World
        var layouts: LayoutCatalogue
        var gap: CGFloat
        /// Each display's tiling rect for its active row, as the reconciler computes it.
        var rects: [DisplayID: CGRect]
        /// Every tile as the last reconcile framed it: four fingers' highlight is looked for at the
        /// focused one.
        var tiles: [WindowRef: CGRect]
    }

    /// Where the hand has the line: a pointer position, or (#162) a unit position on the axis.
    enum Target: Equatable { case pointer(CGPoint), unit(Double) }

    /// The line in the hand, from the press on it to the release — or from four fingers' axis lock
    /// to the lift.
    struct Hand: Equatable {
        /// Which workspace, which page of it, which line on which axis.
        let workspace: UUID, key: String, axis: ResizeAxis, line: Int
        /// #162: where the line was when four fingers took it; nil for the pointer.
        let swipeStart: Double?
        /// Where the hand has it now, and where the row was last laid out for.
        var latest: Target
        var applied: Target?
        /// Where the highlight is looked for along the line: the pointer, or the focused tile.
        var anchor: CGPoint?
        /// #178: where the line was when this hand first laid it out, so a settle can tell a resize
        /// from a click on a border the keys left at 90 % (only a resize ends in maximize).
        var from: Double?
        var bySwipe: Bool { swipeStart != nil }
    }

    /// A shared edge between two tiles in an active row, as the last reconcile framed it.
    struct Border: Equatable {
        let workspace: UUID, key: String, border: Resize.Border
    }

    /// What the store does about an event.
    enum Verdict: Equatable {
        /// Nothing: no line in this input's hand (a release goes on to a window drag's drop), or the
        /// event belongs to the other input, which has it.
        case nothing
        /// Points the border highlight at the rect, or hides it.
        case highlight(CGRect?)
        /// The hand moved the line: the pump owes the row a layout (`step`).
        case layOut
        /// The hand let go: the pump catches up, then `settle`.
        case settle
        /// A swipe that does nothing, and why — the store's `CommandReport.noop`.
        case noop(String)
    }

    private(set) var hand: Hand?
    private var borders: [Border] = []

    // MARK: the pointer (#113)

    /// A press: on a border, it takes it — instead of anything else a press can start.
    @discardableResult
    mutating func press(at p: CGPoint, locked: Bool) -> Verdict {
        if hand?.bySwipe == true { return .nothing }   // four fingers have the edge; the button waits
        guard !locked, let b = borders.first(where: { $0.border.contains(p) }) else { return .highlight(nil) }
        hand = Hand(workspace: b.workspace, key: b.key, axis: b.border.axis, line: b.border.line,
                    swipeStart: nil, latest: .pointer(p), applied: nil, anchor: p)
        return .highlight(b.border.indicator)
    }

    /// A move: the held line follows; with none held, hovering a border highlights it.
    @discardableResult
    mutating func move(to p: CGPoint, buttonDown: Bool) -> Verdict {
        guard let h = hand else { return .highlight(buttonDown ? nil : border(at: p)) }
        guard !h.bySwipe else { return .nothing }
        hand?.latest = .pointer(p); hand?.anchor = p
        return .layOut
    }

    /// A mouse-up: the held line lands where it was let go.
    @discardableResult
    mutating func release(at p: CGPoint) -> Verdict {
        guard let h = hand, !h.bySwipe else { return .nothing }
        hand?.latest = .pointer(p); hand?.anchor = p
        return .settle
    }

    /// The highlight for a pointer at `p`: the border under it, if any.
    func border(at p: CGPoint) -> CGRect? { borders.first { $0.border.contains(p) }?.border.indicator }

    // MARK: four fingers (#162)

    /// A four-finger horizontal drag moves the focused tile's side edge the way a mouse drags a
    /// border: `began` takes the edge the resize keys move (measured against the real tiling
    /// rect, like them), each `moved` puts it `Resize.swiped` from where it was, and `ended` (a
    /// real lift) settles it there, once. In maximize, and wherever the focused tile has no edge
    /// sideways, `began` is a no-op with the resize keys' reason, and the moves and the lift that
    /// follow find nothing in the hand.
    ///
    /// A `began` with four fingers' line still in the hand is a lost lift: the store settles it first.
    @discardableResult
    mutating func swipe(_ drag: SwipeDrag, in s: Scene) -> Verdict {
        switch drag.phase {
        case .began:
            if hand?.bySwipe == false { return .noop("a border is already in the hand") }
            let w = s.world
            guard let rect = s.rects[w.focus.screen],
                  let (id, page, i) = w.resizePage(layouts: s.layouts, in: rect, gap: s.gap)
            else { return .noop("nothing to resize") }
            guard let line = Resize.swipeLine(page, index: i) else { return .noop(Resize.stuck(page, index: i, axis: .width)) }
            let start = page.positions(w.screens[w.focus.screen]?.active.portions[page.key], .width)[line]
            let anchor = w.focus.window.flatMap { s.tiles[$0] }.map { CGPoint(x: $0.midX, y: $0.midY) }
            hand = Hand(workspace: id, key: page.key, axis: .width, line: line, swipeStart: start,
                        latest: .unit(Resize.swiped(from: start, travel: drag.travel)), applied: nil, anchor: anchor)
            return .layOut
        case .moved, .ended:
            guard let start = hand?.swipeStart else { return .noop("no edge in the hand") }
            hand?.latest = .unit(Resize.swiped(from: start, travel: drag.travel))
            return drag.phase == .moved ? .layOut : .settle
        }
    }

    // MARK: the store's pump and reconcile

    /// Whether the row still has to be laid out for where the hand has the line.
    var behind: Bool { hand.map { $0.latest != $0.applied } ?? false }

    /// The pump's next step: the `setPortions` that puts the held line where the hand has it,
    /// snapped and clamped — nil when that changes nothing, or the row no longer shows the page
    /// the line belongs to. Either way the hand counts as laid out for it.
    mutating func step(in s: Scene) -> Command? {
        guard let h = hand, h.latest != h.applied else { return nil }
        hand?.applied = h.latest
        guard let (ws, _, page, rect) = page(of: h, in: s) else { return nil }
        let now = ws.portions[h.key]
        if h.from == nil { hand?.from = page.positions(now, h.axis)[h.line] }
        let u = switch h.latest {
        case .pointer(let p): Resize.unit(h.axis == .width ? p.x : p.y, axis: h.axis, in: rect, gap: s.gap)
        case .unit(let u): u
        }
        let next = Resize.drag(page, now, axis: h.axis, line: h.line, to: u)
        return next == now ? nil : .setPortions(h.workspace, key: h.key, next)
    }

    /// The release, once the pump has caught up: the hand lets go. #178: a resize (the line moved
    /// more than a snap's radius) that leaves a split tile within `Resize.maximizeMargin` of the
    /// largest it can get is the commands that maximize that window, like a hotkey's.
    mutating func settle(in s: Scene) -> [Command] {
        let settled = hand
        hand = nil
        guard let h = settled, let from = h.from, let (ws, row, page, _) = page(of: h, in: s),
              abs(page.positions(ws.portions[h.key], h.axis)[h.line] - from) > Resize.snapRadius else { return [] }
        return Resize.collapse(page, ws.portions[h.key], layout: s.layouts.resolve(ws.layout).def.id, workspace: ws.id, row: row)
    }

    /// A lost mouse-up (released over the shell's own panels: `pointerOnly`) or a lock: the line is
    /// let go where it last was.
    @discardableResult
    mutating func drop(pointerOnly: Bool = false) -> Verdict {
        guard let h = hand, !(pointerOnly && h.bySwipe) else { return .nothing }
        hand = nil
        return .highlight(nil)
    }

    /// A reconcile is about to frame `desired`: every draggable border, per display's active row.
    /// The held line's highlight follows it to where this pass puts it.
    @discardableResult
    mutating func framed(_ desired: [WindowRef: Placement], in s: Scene) -> Verdict {
        borders = []
        for sid in s.world.screenOrder {
            guard let screen = s.world.screens[sid], let rect = s.rects[sid] else { continue }
            let ws = screen.active, row = s.world.tiled(in: ws)
            guard let page = Self.page(ws, row, s, rect) else { continue }
            let frames: [CGRect?] = row.map { if case .frame(let f)? = desired[$0] { f } else { nil } }
            borders += Resize.borders(page, frames: frames).map { Border(workspace: ws.id, key: page.key, border: $0) }
        }
        guard let h = hand else { return .nothing }
        return .highlight(h.anchor.flatMap { a in
            borders.first { $0.workspace == h.workspace && $0.key == h.key && $0.border.axis == h.axis
                && $0.border.line == h.line && $0.border.contains(a, tolerance: 1_000) }?.border.indicator
        })
    }

    /// The held line's workspace, its tiled row, the page it shows now and the real tiling rect
    /// that page is measured in; nil when the row no longer shows the page the line belongs to.
    private func page(of h: Hand, in s: Scene) -> (Workspace, [WindowRef], Resize.Page, CGRect)? {
        guard let loc = s.world.location(ofWorkspace: h.workspace), let rect = s.rects[loc.screen] else { return nil }
        let ws = s.world.screens[loc.screen]!.workspaces[loc.index], row = s.world.tiled(in: ws)
        guard let page = Self.page(ws, row, s, rect), page.key == h.key else { return nil }
        return (ws, row, page, rect)
    }

    private static func page(_ ws: Workspace, _ row: [WindowRef], _ s: Scene, _ rect: CGRect) -> Resize.Page? {
        let focused = ws.anchor.flatMap { row.firstIndex(of: $0) } ?? 0
        return LayoutEngine.page(s.layouts.resolve(ws.layout).def, count: row.count, focused: focused, in: rect, gap: s.gap,
                                 split: ws.split(in: row))
    }
}
