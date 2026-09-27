import Foundation

/// #165: a dialog or popup the store wants placed on the next pass. Placement happens only when a
/// popup first appears and when the displays change, never in between, so a popup the user moved
/// stays where they put it.
public struct PopupRequest: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        /// First appearance: centred on its owner's tile when it fits there, else on the display,
        /// then clamped inside the display's usable frame (`Reconciler.popupPlacement`).
        case place
        /// The displays changed: kept where it is, only clamped back inside its display.
        case clamp
    }
    public var mode: Mode
    /// The window it belongs to when the model does not record one: an ephemeral visitor's AX
    /// parent, or the app's focused window for a standalone dialog. An attached window (#134)
    /// always uses its owner's tile.
    public var owner: WindowRef?
    public init(_ mode: Mode, owner: WindowRef? = nil) { self.mode = mode; self.owner = owner }
}

extension Reconciler {
    /// #165: where a movable popup of `size` goes. Centred on `owner` (its owner's tile) when it
    /// fits there on both axes, otherwise centred on `display` (the usable frame: menu bar and
    /// Dock excluded), then clamped fully inside `display`. It may overlap neighbouring tiles and
    /// the shell's panels; it is never resized.
    public static func popupPlacement(size: CGSize, owner: CGRect?, display: CGRect) -> CGRect {
        let fits = owner.map { size.width <= $0.width && size.height <= $0.height } ?? false
        return clampPopup(centered(size: size, in: fits ? owner! : display), to: display)
    }

    /// #165: `frame` moved the least distance that puts it fully inside `display` — the same
    /// clamp as #164's refused tiles (`keepInside`). Wider than the display, it is centred
    /// horizontally; taller, it is aligned to the top, so its title bar and buttons stay reachable.
    public static func clampPopup(_ frame: CGRect, to display: CGRect) -> CGRect {
        keepInside(frame, display, topAlignTall: true)
    }

    /// #165: how far to move an unmovable sheet's owner sideways so the sheet is fully inside
    /// `display` (0 when it already is): `keepInside`'s horizontal move. A sheet wider than the
    /// display is centred on it.
    public static func sheetShift(_ sheet: CGRect, display: CGRect) -> CGFloat {
        keepInside(sheet, display).minX - sheet.minX
    }

    /// #165: applies each request to `desired` (the reconciler's output for this pass) and returns
    /// the popups it placed. A popup not on screen this pass (parked in an inactive row, hidden,
    /// fullscreen, on another Space) is skipped and keeps its request for a later pass. Unmovable
    /// sheets are skipped too: their owner moves instead (`desired`'s `unmovable`).
    public static func placePopups(_ requests: [WindowRef: PopupRequest], into desired: inout [WindowRef: Placement],
                                   world: World, displays: [DisplayInfo], observed: [WindowRef: CGRect],
                                   parkedNow: Set<WindowRef>, unmovable: Set<WindowRef> = []) -> Set<WindowRef> {
        var placed: Set<WindowRef> = []
        func away(_ w: WindowRef) -> Bool { world.hidden.contains(w) || world.fullscreen.contains(w) || world.offSpace.contains(w) }
        for (w, request) in requests.sorted(by: { $0.key.id < $1.key.id }) {
            guard !unmovable.contains(w), !away(w) else { continue }
            let base: CGRect
            switch desired[w] {
            case .frame(let f)?: base = f
            case .untouched?:
                guard !parkedNow.contains(w), let o = observed[w] else { continue }
                base = o
            default: continue   // parked, or not ours to place
            }
            let owner = world.owner(of: w) != nil ? world.root(of: w) : request.owner
            if let o = owner, away(o) { continue }
            let ownerFrame: CGRect? = owner.flatMap { o in
                switch desired[o] {
                case .frame(let f)?: f
                case .parked?: nil
                default: parkedNow.contains(o) ? nil : observed[o]
                }
            }
            let screen: DisplayID? = switch request.mode {
            case .place: owner.flatMap(world.screenContaining) ?? world.screenContaining(w)
                ?? ownerFrame.flatMap { mostlyOn($0, displays) } ?? world.focus.screen
            case .clamp: world.screenContaining(w) ?? mostlyOn(base, displays) ?? world.focus.screen
            }
            guard let display = displays.first(where: { $0.id == screen }) ?? displays.first else { continue }
            let target = switch request.mode {
            case .place: popupPlacement(size: base.size, owner: ownerFrame, display: display.visibleFrame)
            case .clamp: clampPopup(base, to: display.visibleFrame)
            }
            desired[w] = .frame(target)
            placed.insert(w)
        }
        return placed
    }
}
