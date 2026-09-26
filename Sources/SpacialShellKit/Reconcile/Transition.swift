import Foundation
import OpenTelemetryApi

/// What one display's tiling showed at the end of a reconcile — enough to tell, at the next one,
/// which way the user went. `frames` holds every window the row shows: tiled windows at their
/// layout frames, floating ones where they sit, so a floating window (System Settings) travels
/// with its row on a workspace switch. Hidden and fullscreen windows are never carried (#67).
public struct ShownRow: Sendable, Equatable {
    public var workspace: UUID
    public var index: Int
    /// Every workspace id on the display, in rail order, as it stood then — so a switch that
    /// reaps the row being left (renumbering the rest) still reads as the direction it was.
    public var order: [UUID]
    /// The tiled windows in tab order.
    public var row: [WindowRef]
    public var focused: WindowRef?
    public var frames: [WindowRef: CGRect]

    public init(workspace: UUID, index: Int, order: [UUID], row: [WindowRef], focused: WindowRef?,
                frames: [WindowRef: CGRect]) {
        self.workspace = workspace; self.index = index; self.order = order
        self.row = row; self.focused = focused; self.frames = frames
    }
}

/// #64: a switch, as motion (and, #140, a re-tile: see `Kind`). Every window that changes place on
/// one display, from where it was to where the reconcile is putting it, in AX top-left coordinates.
///
/// The rail is a vertical stack and the tab row a horizontal strip, so a switch has a direction:
/// down the rail and the rows travel up (#66); along the row and the strip travels the other way,
/// by as many places as focus moved (#67). A window on screen before and after goes straight from
/// one frame to the other; one leaving travels out along the direction, one arriving comes in
/// from the opposite side. The tiling layouts and maximize are the same rule — under maximize
/// the strip is simply one window wide.
public struct Transition: Sendable, Equatable {
    public struct Move: Sendable, Equatable {
        public let ref: WindowRef
        public let from: CGRect
        public let to: CGRect
        public init(ref: WindowRef, from: CGRect, to: CGRect) { self.ref = ref; self.from = from; self.to = to }
    }

    /// #140 (G13): what kind of motion this is. A **switch** takes the user somewhere: another
    /// workspace, or along the row to another window, and things slide in and out. A **re-tile**
    /// keeps the user where they are while the row rearranges: a layout change, a swap, a window
    /// opening or closing next to it. Only the windows on screen before and after move, between
    /// their frames; nothing slides in from an edge. Re-tiles animate only with `animate-retile`.
    public enum Kind: String, Sendable, Equatable { case `switch`, retile }

    public let display: DisplayID
    /// The tiling area, and the overlay's clip: windows slide out of it, not across the panels.
    public let viewport: CGRect
    public let moves: [Move]
    public let kind: Kind
    /// #140: a re-tile's windows that were shown before or after but do not fly: arriving (opened,
    /// paged in) or leaving (paged out; a closed one is simply gone). The overlay takes them out of
    /// its backdrop, so none sits frozen where it was while the others fly; the real ones are
    /// already in place when it drops. Always empty for a switch, whose every such window moves.
    public let offstage: [WindowRef]

    public init(display: DisplayID, viewport: CGRect, moves: [Move], kind: Kind = .switch, offstage: [WindowRef] = []) {
        self.display = display; self.viewport = viewport; self.moves = moves
        self.kind = kind; self.offstage = offstage
    }

    public var isRetile: Bool { kind == .retile }

    /// One display's motion between two reconciles, or nil when nothing on it changes place.
    ///
    /// A re-tile is the same workspace with the same window still focused, or with windows joining
    /// or leaving the row (a window opened or closed: focus may follow it in the same pass), as
    /// long as some window stays on screen and changes frame. Everything else is a switch, planned
    /// by `moves`. So a window opening under `maximize`, where nothing stays on screen, is still
    /// the switch it always was: the new one slides in, the old one out.
    public static func plan(display: DisplayID, before: ShownRow, after: ShownRow, viewport: CGRect, gap: CGFloat) -> Transition? {
        if before.workspace == after.workspace, Set(before.row) != Set(after.row) || before.focused == after.focused {
            let stay = stayers(before: before, after: after)
            if !stay.isEmpty {
                let shown = Set(before.frames.keys).union(after.frames.keys)
                let once = shown.filter { (before.frames[$0] == nil) != (after.frames[$0] == nil) }
                return Transition(display: display, viewport: viewport, moves: stay, kind: .retile,
                                  offstage: once.sorted { $0.id < $1.id })
            }
        }
        let ms = moves(before: before, after: after, viewport: viewport, gap: gap)
        return ms.isEmpty ? nil : Transition(display: display, viewport: viewport, moves: ms)
    }

    /// The windows on screen both times whose frame changed, straight from one to the other.
    static func stayers(before: ShownRow, after: ShownRow) -> [Move] {
        before.frames.sorted { $0.key.id < $1.key.id }.compactMap { r, from in
            guard let to = after.frames[r], to != from else { return nil }
            return Move(ref: r, from: from, to: to)
        }
    }

    /// A switch's moves: the stayers, plus every window leaving or arriving along the direction.
    public static func moves(before: ShownRow, after: ShownRow, viewport: CGRect, gap: CGFloat) -> [Move] {
        let delta = direction(before: before, after: after, viewport: viewport, gap: gap)
        var out: [Move] = []
        for (r, from) in before.frames.sorted(by: { $0.key.id < $1.key.id }) {
            if let to = after.frames[r] {
                if from != to { out.append(Move(ref: r, from: from, to: to)) }
            } else if delta != .zero {
                out.append(Move(ref: r, from: from, to: from.offsetBy(dx: delta.dx, dy: delta.dy)))
            }
        }
        guard delta != .zero else { return out }
        for (r, to) in after.frames.sorted(by: { $0.key.id < $1.key.id }) where before.frames[r] == nil {
            out.append(Move(ref: r, from: to.offsetBy(dx: -delta.dx, dy: -delta.dy), to: to))
        }
        return out
    }

    /// How far the content travels: a row switch moves one viewport, up or down; a tab switch
    /// moves one slot per place, where a slot is the focused window's width plus the gap — unless
    /// it flips a page (#54 paging, custom grid layouts design §9): a page of several windows
    /// replaced by a wholly different one slides one whole viewport, so a 2×2 zone page or a
    /// column page never has its leaving and arriving windows cross inside the clip. A one-window
    /// page (maximize) is the strip itself and keeps travelling by places.
    static func direction(before: ShownRow, after: ShownRow, viewport: CGRect, gap: CGFloat) -> CGVector {
        if before.workspace != after.workspace {
            let target = before.order.firstIndex(of: after.workspace) ?? after.index
            guard target != before.index else { return .zero }
            // Down the rail (a higher index) and the rows travel up: AX y grows downward.
            return CGVector(dx: 0, dy: target > before.index ? -viewport.height : viewport.height)
        }
        guard let old = before.focused, let new = after.focused, old != new,
              let i = before.row.firstIndex(of: old),
              let j = before.row.firstIndex(of: new) ?? after.row.firstIndex(of: new) else { return .zero }
        let shownBefore = before.row.filter { before.frames[$0] != nil }
        let shownAfter = after.row.filter { after.frames[$0] != nil }
        if shownAfter.count > 1, Set(shownBefore).isDisjoint(with: shownAfter) {
            return CGVector(dx: j > i ? -(viewport.width + gap) : viewport.width + gap, dy: 0)
        }
        let slot = (after.frames[new]?.width).map { $0 + gap } ?? viewport.width
        return CGVector(dx: -CGFloat(j - i) * slot, dy: 0)
    }
}

/// Draws a switch (#65's ruling: screenshot proxies). Kit decides *what* moves; the app layer owns
/// the pixels. The store calls `prepare` before it writes a single frame, so the overlay already
/// covers the tiling when the real windows jump to their final places underneath it, then `play`
/// once the writes are done. The real windows are therefore always at real frames: dropping the
/// overlay at any moment — a newer switch, Zen, a hot-plug — can never strand one mid-flight.
public protocol SwitchAnimator: Sendable {
    /// Capture and cover, with every moving window drawn at its `from`. False means "place
    /// instantly" — no Screen Recording grant, reduce-motion, or a capture that failed. A switch
    /// arriving while the last is still in flight drops that one and starts over (never queues).
    /// `trace` is the reconcile pass this switch belongs to (#148): the animator's own spans are its
    /// children, so a switch reads as one trace, command to landing. `since` is when the command
    /// (or, with none, the reconcile pass) began: #97 measures the latency to the slide from it.
    func prepare(_ transitions: [Transition], trace: SpanContext?, since: ContinuousClock.Instant) async -> Bool
    /// Start the motion to each `to` and return; the overlay removes itself when it lands.
    func play(trace: SpanContext?) async
    /// #77: the switches the keys could make next, as the planner would draw them from here (see
    /// `WorldStore.predictedCommands`; an entry is empty when that key moves nothing). Take their
    /// pictures ahead of time, in the background, so the next `prepare` has nothing to capture.
    /// Only a hint: it must never delay a `prepare`.
    func prefetch(_ predicted: [[Transition]]) async
}

extension SwitchAnimator {
    public func prefetch(_ predicted: [[Transition]]) async {}
}
