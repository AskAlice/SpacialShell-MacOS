import CoreGraphics
import Foundation

/// #188: the app window switcher — Linux's Super+` on `Fn+`` and `⌘``. Every window of the
/// focused window's app (its pid, as #98's "whole app"), on every workspace and display, most
/// recently used first; the selection starts on the second, so a tap and release is the app's
/// previous window. Hold the modifier and tap `` ` `` (`⇧`` back) to step; let go to switch.
///
/// Pure: the list, the selection and the command it ends in. `AppWindowSwitcherController` opens
/// it on the chord, feeds it the steps, and sends `end` through the store like a tab click.
public struct AppWindowSwitcher: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public let ref: WindowRef
        /// The window's title from the snapshot; nil when AX gave none.
        public let title: String?
        /// Its row, named as the spatial view and the rail card name it (#183); nil for an
        /// ephemeral visitor, which has no row.
        public let workspace: String?
        public var id: WindowRef { ref }

        public init(ref: WindowRef, title: String?, workspace: String?) {
            self.ref = ref; self.title = title; self.workspace = workspace
        }
    }

    public let pid: Int32
    public let items: [Item]
    public private(set) var selected: Int
    public var selectedRef: WindowRef { items[selected].ref }

    /// How many recently focused windows the controller keeps (`noting`). Every app's, so a
    /// generous cap: the switcher lists one app's, and a window closed since is simply skipped.
    public static let recentLimit = 64

    /// Nil when there is nothing to switch to: no focused window, or the app has only this one.
    /// `recent` is most recent first (`noting`). Order: the current window, then the app's others
    /// by `recent`, then those never focused, in row order (display by display, top row first),
    /// its ephemeral windows last. Placeholders (#128) are never listed.
    public init?(world: World, recent: [WindowRef], titles: [WindowRef: String] = [:],
                 categoryOf: (Int32) -> AppCategory? = { _ in nil }, reverse: Bool = false) {
        guard let focused = world.focus.window, !focused.isPlaceholder else { return nil }
        let current = world.root(of: focused)
        var rowOrder: [WindowRef] = [], rows: [WindowRef: String] = [:]
        for sid in world.screenOrder {
            for ws in world.screens[sid]?.workspaces ?? [] {
                let mine = world.tabs(in: ws).filter { $0.pid == current.pid && !$0.isPlaceholder }
                guard !mine.isEmpty else { continue }
                let category = AppCategories.rowCategory(ws.category, windows: ws.windows, categoryOf: categoryOf)
                let name = AppCategories.rowTitle(name: ws.name, category: category, isTrailingEmpty: false)
                for r in mine { rowOrder.append(r); rows[r] = name }
            }
        }
        rowOrder += world.ephemeral.filter { $0.pid == current.pid }.sorted { $0.id < $1.id }
        let listed = Set(rowOrder)
        guard listed.contains(current) else { return nil }
        var order = [current]
        for r in recent + rowOrder where listed.contains(r) && !order.contains(r) { order.append(r) }
        guard order.count > 1 else { return nil }
        pid = current.pid
        items = order.map { Item(ref: $0, title: titles[$0].flatMap { $0.isEmpty ? nil : $0 }, workspace: rows[$0]) }
        selected = reverse ? order.count - 1 : 1
    }

    /// `` ` `` (forward) or `⇧`` while held; both wrap.
    public mutating func step(forward: Bool) {
        selected = (selected + (forward ? 1 : -1) + items.count) % items.count
    }

    /// A click on an entry. One not listed changes nothing.
    public mutating func select(_ ref: WindowRef) {
        if let i = items.firstIndex(where: { $0.ref == ref }) { selected = i }
    }

    /// Letting go of the modifier commits: the tab click's command, which switches to the window's
    /// workspace and display. Esc cancels: nothing.
    public func end(committing: Bool) -> Command? {
        committing ? .focusWindowRef(selectedRef) : nil
    }

    /// The recent list after a published world: its focused tab first (a sheet counts as its
    /// owner, as in #137), no repeats, at most `recentLimit`. The model's own history is per row
    /// (#137); this one spans them all, so the switcher can order across workspaces.
    public static func noting(_ world: World, in recent: [WindowRef]) -> [WindowRef] {
        guard let f = world.focus.window, !f.isPlaceholder else { return recent }
        let r = world.root(of: f)
        guard recent.first != r else { return recent }
        return Array(([r] + recent.filter { $0 != r }).prefix(recentLimit))
    }

    /// The modifiers that hold it open: whichever were down when it opened (Fn, ⌃⌥ or ⌘), never ⇧,
    /// which only turns the step round.
    public static func holdModifiers(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection([.maskSecondaryFn, .maskControl, .maskAlternate, .maskCommand])
    }

    /// Still held while every one of them is down; letting go of any commits. Opened with none
    /// held (`spacialctl run switch-app-window`) it is never held, so it switches at once.
    public static func isHeld(_ flags: CGEventFlags, by held: CGEventFlags) -> Bool {
        !held.isEmpty && flags.contains(held)
    }

    /// Esc with the held modifiers, ⇧ or not (it may still be down from a step back): bound in the
    /// hotkey tap only while the switcher is open, so it cancels on every preset (⌘Esc is otherwise
    /// unbound and would reach the front app).
    public static func cancelChords(held: CGEventFlags) -> [Chord] {
        [false, true].map { shift in
            Chord(keyCode: KeyCodes.byName["esc"]!, fn: held.contains(.maskSecondaryFn),
                  control: held.contains(.maskControl), option: held.contains(.maskAlternate),
                  shift: shift, command: held.contains(.maskCommand))
        }
    }
}
