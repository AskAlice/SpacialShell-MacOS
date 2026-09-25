import Foundation

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

/// #64: a switch, as motion. Every window that changes place on one display, from where it was
/// to where the reconcile is putting it, in AX top-left coordinates.
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

    public let display: DisplayID
    /// The tiling area, and the overlay's clip: windows slide out of it, not across the panels.
    public let viewport: CGRect
    public let moves: [Move]

    public init(display: DisplayID, viewport: CGRect, moves: [Move]) {
        self.display = display; self.viewport = viewport; self.moves = moves
    }

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
    func prepare(_ transitions: [Transition]) async -> Bool
    /// Start the motion to each `to` and return; the overlay removes itself when it lands.
    func play() async
    /// #77: the switches the keys could make next, as the planner would draw them from here (see
    /// `WorldStore.predictedCommands`; an entry is empty when that key moves nothing). Take their
    /// pictures ahead of time, in the background, so the next `prepare` has nothing to capture.
    /// Only a hint: it must never delay a `prepare`.
    func prefetch(_ predicted: [[Transition]]) async
}

extension SwitchAnimator {
    public func prefetch(_ predicted: [[Transition]]) async {}
}
