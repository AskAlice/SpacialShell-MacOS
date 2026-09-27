import Foundation

/// #169: what a window's move or resize report means.
///
/// macOS reports every frame change the same way: our own writes landing, a window refusing the
/// size we asked for, a sheet that would not move, the user's hand, an app moving itself. This
/// module holds everything needed to tell them apart — the frames we asked for (`IntentSet`), the
/// refusals learned from their echoes (#125, #164) and the first placements of attached windows
/// still being tested (#165) — and answers one question: what is this report? The store records
/// its writes here, passes each report with what it knows of the moment (`Context`), and acts on
/// the `Verdict`. The reconciler reads what was learned through `refused` and `unmovable`.
public struct WindowEchoes: Sendable {
    /// Frames and origins we asked for and have not heard back.
    private var intents = IntentSet()
    /// #125: windows that came back smaller (#164: or bigger) than the tile we asked for; the
    /// reconciler centres them.
    public private(set) var refused: [WindowRef: Refusal] = [:]
    /// #164: a first mismatched echo is only a suspicion. Browsers report transient smaller frames
    /// mid-resize, and a frame clamped while it moves between displays of different sizes looks
    /// the same, so the tile is asked for once more. A second echo of the same size confirms it.
    private var suspected: [WindowRef: Refusal] = [:]
    /// #165: a first placement written to an attached window (#134), from where it was to where
    /// we asked, until its echo or the next snapshot says which one it is at.
    private var probes: [WindowRef: (from: CGRect, to: CGRect)] = [:]
    /// #165: attached windows whose placement did not take (the echo still showed them where they
    /// were): true sheets, bound to their owner's title bar. The reconciler moves the owner instead.
    public private(set) var unmovable: Set<WindowRef> = []

    public init() {}

    /// What the store knows of the moment a report arrives.
    public struct Context: Sendable {
        public enum Event: Sendable { case moved, resized }
        public var event: Event
        /// The frame the store last observed for the window, before this report.
        public var was: CGRect?
        /// Spec §7.7: the screen is locked; nothing is acted on.
        public var locked: Bool
        /// #113: a border (or #162, a tile's edge under four fingers) is in the hand; the release settles it.
        public var grabbing: Bool
        /// #108: where the left button is held down, nil when it is up.
        public var pointerDown: CGPoint?
        /// #108: the window already in the hand, if any.
        public var dragging: WindowRef?
        /// #108: the window is a tile a drop can land on (framed by the last reconcile).
        public var isTile: Bool
        /// #57: human input arrived within `FocusEchoes.humanInputWindow`.
        public var humanRecently: Bool
        public var world: World
        public var displays: [DisplayInfo]
        /// Windows the store has parked in a corner.
        public var parked: Set<WindowRef>

        public init(event: Event, was: CGRect?, locked: Bool = false, grabbing: Bool = false,
                    pointerDown: CGPoint? = nil, dragging: WindowRef? = nil, isTile: Bool = false,
                    humanRecently: Bool = false, world: World, displays: [DisplayInfo], parked: Set<WindowRef> = []) {
            self.event = event; self.was = was; self.locked = locked; self.grabbing = grabbing
            self.pointerDown = pointerDown; self.dragging = dragging; self.isTile = isTile
            self.humanRecently = humanRecently; self.world = world; self.displays = displays; self.parked = parked
        }
    }

    /// What a report is: what it taught us about the window, and what the store should do.
    public struct Verdict: Sendable, Equatable {
        public enum Learned: Sendable, Equatable {
            /// #164: a first mismatched echo of our own write; the tile is asked for again.
            case refusalSuspected(Refusal)
            /// #164: the same mismatch a second time: the window cannot fill its tile.
            case refusalConfirmed(Refusal)
            /// #164: a refused window moved toward its tile: it can fit after all.
            case refusalForgotten
            /// #165: a first placement did not take: a sheet bound to its owner's title bar.
            case sheetUnmovable
        }
        public enum Action: Sendable, Equatable {
            /// Our own write, landed as asked: nothing to do.
            case ownEcho
            /// Locked, or a border in the hand: nothing is acted on until that ends.
            case hold
            /// #108: a tile in the user's hand. `start` is where on it the hand holds it when this
            /// report starts the drag; nil when it continues one.
            case drag(start: CGVector?)
            /// #57: dragged onto another display: its tab follows, into `workspace`, that display's active row.
            case rehome(display: DisplayID, workspace: UUID)
            /// #165: an unmovable sheet: the reconciler moves its owner instead.
            case moveOwner
            /// A tiled window moved by someone else, or refusing its tile: the reconciler puts it back.
            case snapBack
            /// A window the shell does not place (floating, ephemeral, unknown): left where it is.
            case leave
        }
        public var learned: [Learned]
        public var action: Action
        public init(learned: [Learned] = [], action: Action) { self.learned = learned; self.action = action }
    }

    // MARK: - interface

    /// Reads a `.windowMoved`/`.windowResized` report of `r` at `f`. Decided in order: what the
    /// frame teaches (a sheet that did not move, a refusal outgrown, suspected or confirmed), our
    /// own echo, locked or grabbing, the hand (a drag, then a drag onto another display), an
    /// unmovable sheet, and last a foreign move: snapped back if tiled, else left alone.
    public mutating func interpret(_ r: WindowRef, frame f: CGRect, _ c: Context) -> Verdict {
        var learned: [Verdict.Learned] = []
        let pinned = settle(r, seenAt: f)
        if pinned { learned.append(.sheetUnmovable) }
        // #164: a refused window that grew past its refused size (the user or the app resized it)
        // can fill after all: forget the refusal, and the snap-back gives it the whole tile.
        if let rf = refused[r], rf.grew(to: f) {
            refused[r] = nil; suspected[r] = nil
            learned.append(.refusalForgotten)
        }
        // #125: the echo of our own write, not the size asked — a window that cannot fill its tile.
        // Learned, not fought: the snap-back re-places it centred in the tile.
        if let asked = intents.frame(for: r), let refusal = Refusal(asked: asked, got: f) {
            if let s = suspected[r], s.sameAs(refusal) {
                refused[r] = refusal; suspected[r] = nil
                learned.append(.refusalConfirmed(refusal))
            } else {
                suspected[r] = refusal   // ask for the tile once more before believing it
                learned.append(.refusalSuspected(refusal))
            }
            intents.forget(r)
        } else if intents.matches(r, frame: f) {
            suspected[r] = nil
            return Verdict(learned: learned, action: .ownEcho)
        }
        // #113: the grabbed border's windows are being laid out move by move (and a press on a
        // window's own resize handle resizes it natively); the release settles them.
        if c.locked || c.grabbing { return Verdict(learned: learned, action: .hold) }
        if c.event == .moved, let start = drag(r, to: f, c) { return Verdict(learned: learned, action: .drag(start: start)) }
        if c.event == .moved, let (d, ws) = rehome(r, to: f, c) { return Verdict(learned: learned, action: .rehome(display: d, workspace: ws)) }
        if pinned { return Verdict(learned: learned, action: .moveOwner) }
        if let ws = c.world.workspace(containing: r), !ws.floating.contains(r) { return Verdict(learned: learned, action: .snapBack) }
        return Verdict(learned: learned, action: .leave)
    }

    /// A write the store is about to make: its echo will be ours.
    public mutating func record(_ w: Write) { intents.record(w) }

    /// #165: a first placement of an attached window, from where it was to `to`, is also the test
    /// of whether it moves. Nothing to test when it was never seen or is already there.
    public mutating func probe(_ r: WindowRef, from: CGRect?, to: CGRect) {
        guard let from, !Reconciler.approx(from, to) else { return }
        probes[r] = (from, to)
    }

    /// #165: checks a frame seen for `r` (an echo, or a snapshot) against its placement probe. At
    /// the frame we asked for, it moved: nothing more to learn. Still where it was, the write did
    /// not take: a true sheet, from now on moved by moving its owner. True when it just learned that.
    public mutating func settle(_ r: WindowRef, seenAt f: CGRect) -> Bool {
        guard let p = probes[r] else { return false }
        func near(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 }
        probes[r] = nil
        guard !near(f, p.to), near(f, p.from) else { return false }   // moved, or the user or the app moved it
        unmovable.insert(r)
        return true
    }

    /// #179: `r` goes back to what it refused before a peek asked it for another frame (nil: it
    /// refused nothing) — a refusal holds for one frame, and the peek's would replace its tile's.
    public mutating func restore(_ refusal: Refusal?, for r: WindowRef) { refused[r] = refusal; suspected[r] = nil }

    /// `r` vanished or was retired: nothing learned about it outlives it.
    public mutating func forget(_ r: WindowRef) {
        intents.forget(r); refused[r] = nil; suspected[r] = nil; probes[r] = nil; unmovable.remove(r)
    }

    // MARK: - the hand

    /// #108: a tiled window moving under a held button is in the user's hand. From its first such
    /// move to the mouse-up it is suspended — the reconciler leaves it where the hand has it. The
    /// pointer is where the button went down, carried along with the window (a title-bar drag moves
    /// the two together), so no stream of mouse positions is needed. It is a drag only if that
    /// pointer was on the window, the size did not change (a resize from the left edge also moves
    /// it), and the window was a tile on screen. Floating windows are not tracked: they keep #57's
    /// rehome and are otherwise left alone. Returns where on the window the hand holds it for a new
    /// drag, `.some(nil)` for the window already in the hand, nil for no drag.
    private func drag(_ r: WindowRef, to f: CGRect, _ c: Context) -> CGVector?? {
        guard let held = c.dragging else {
            guard let down = c.pointerDown, let was = c.was, was.contains(down), c.isTile, Self.sameSize(was, f) else { return nil }
            return .some(CGVector(dx: down.x - was.minX, dy: down.y - was.minY))
        }
        return held == r ? .some(nil) : nil
    }

    /// #57: a window the user drags onto another display moves there in the model — into that
    /// display's active workspace, focused (the window is in the user's hand, so unlike a tab drop,
    /// #95, it follows) — so the tab follows the window instead of the window being snapped back.
    /// Every other disagreement about which display a window is on (placement memory, an app moving
    /// its own window) is left to the reconciler, which puts the window where its tab is: the model wins.
    ///
    /// "The user dragged it" is judged from what the store has: human input within
    /// `FocusEchoes.humanInputWindow` (the platform reports mouse-drags as input, so a long drag
    /// stays fresh), a frame whose size did not change (a drag never resizes; macOS clamping one of
    /// our own writes to a minimum size does), and a window that was on screen to be dragged — tiled or
    /// floating in its display's active workspace, not parked, hidden or fullscreen. The display is
    /// the one under the frame's centre.
    /// ponytail: input-within-a-second, not a true drag signal — an app moving its own window just
    /// after a key press would be rehomed too. Upgrade path: a mouse-up event carrying the drag.
    private func rehome(_ r: WindowRef, to f: CGRect, _ c: Context) -> (DisplayID, UUID)? {
        let world = c.world
        guard c.humanRecently, let was = c.was, Self.sameSize(was, f),
              !c.parked.contains(r), !world.hidden.contains(r), !world.fullscreen.contains(r),
              let loc = world.location(of: r), world.screens[loc.screen]!.activeIndex == loc.index,
              let dest = c.displays.first(where: { $0.frame.contains(CGPoint(x: f.midX, y: f.midY)) })?.id,
              dest != loc.screen, let target = world.screens[dest]?.active.id else { return nil }
        return (dest, target)
    }

    private static func sameSize(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1 }
}

/// #125 (M4 G12): a window that came back smaller than the frame we asked for — a maximum size,
/// or an app that refuses resizes. It holds only for the frame it was learned on: a new tile is
/// asked for in full, so a window that merely snaps to its own increments (a terminal's cell grid)
/// is never kept small, and a window that can now grow does. Learned by `WindowEchoes`; applied by
/// the reconciler (`fitted`).
public struct Refusal: Sendable, Equatable {
    public var asked: CGRect
    public var size: CGSize
    public init(asked: CGRect, size: CGSize) { self.asked = asked; self.size = size }
    /// The echo of our own `setFrame(asked)`: a refusal when its size doesn't equal what was
    /// asked on either axis. Smaller is a window that can't grow to its tile; bigger (#164) is an
    /// app minimum wider or taller than its tile. Either way it is centred on the tile.
    public init?(asked: CGRect, got: CGRect, tolerance: CGFloat = 1) {
        guard abs(got.width - asked.width) > tolerance || abs(got.height - asked.height) > tolerance else { return nil }
        self.init(asked: asked, size: got.size)
    }

    /// #164: the same refusal twice: the same tile asked for, and (within a couple of points)
    /// the same size back. Two such echoes in a row confirm a window really cannot fill its tile.
    func sameAs(_ other: Refusal, tolerance: CGFloat = 2) -> Bool {
        Reconciler.approx(asked, other.asked)
            && abs(size.width - other.size.width) <= tolerance && abs(size.height - other.size.height) <= tolerance
    }

    /// #164: `frame`'s size moved toward the tile on an axis this refusal mismatched: grew
    /// where it was smaller, or shrank where it was bigger. The window can fit better than
    /// recorded, so the record is stale; holding the old size would fight it.
    func grew(to frame: CGRect, tolerance: CGFloat = 1) -> Bool {
        func toward(_ got: CGFloat, _ was: CGFloat, _ want: CGFloat) -> Bool {
            abs(was - want) > tolerance && abs(got - want) < abs(was - want) - tolerance
        }
        return toward(frame.width, size.width, asked.width) || toward(frame.height, size.height, asked.height)
    }

    /// `tile`, with the window centred in it on each axis where it is smaller; nil when this
    /// refusal was learned on another tile.
    /// #164: centred on each axis where the size doesn't equal the tile's, smaller or bigger. A
    /// bigger window is then kept inside `bounds` (the display's tiling area), centred on it if it
    /// is bigger still, so an overflowing tile never runs off the display.
    func fitted(in tile: CGRect, bounds: CGRect? = nil, tolerance: CGFloat = 1) -> CGRect? {
        guard Reconciler.approx(asked, tile) else { return nil }
        var f = tile
        if abs(size.width - tile.width) > tolerance { f.origin.x = tile.midX - size.width / 2; f.size.width = size.width }
        if abs(size.height - tile.height) > tolerance { f.origin.y = tile.midY - size.height / 2; f.size.height = size.height }
        return bounds.map { Reconciler.keepInside(f, $0) } ?? f
    }
}
