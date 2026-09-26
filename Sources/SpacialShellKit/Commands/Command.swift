import Foundation

public enum Vertical: Sendable, Hashable { case up, down }
public enum Horizontal: Sendable, Hashable { case left, right }
public enum Neighbor: Sendable, Hashable { case prev, next }
/// #118: a display "in a direction" — resolved against real display frames by
/// `DisplayNeighbours.neighbour`, never against `screenOrder`.
public enum Direction: Sendable, Hashable, CaseIterable { case left, right, up, down }

public enum Command: Sendable, Hashable {
    case focusWorkspace(Vertical)
    case focusWorkspaceIndex(Int)          // 1-based; Fn+0 → 10. On the active one: back to the previous (#106)
    case focusWindow(Horizontal)
    case closeFocusedWindow
    case moveWindow(Horizontal)
    case moveWindowToWorkspace(Vertical)
    case moveWindowToWorkspaceIndex(Int)   // #105: 1-based, like focusWorkspaceIndex; focus follows
    /// #98: every managed window of the focused window's app to the row above/below the focused
    /// one, in order, keeping each one's floating state. Focus follows, as with a single window.
    case moveAppToWorkspace(Vertical)
    /// #98: Option held while dropping a tab — that window's whole app to the workspace. Does not
    /// follow, like every drop (#95).
    case moveAppRefToWorkspace(WindowRef, UUID)
    case cycleLayout
    case toggleShellUI                     // Zen mode: hide/show the shell panels
    case focusScreen(Neighbor)
    case moveWindowToScreen(Neighbor)
    case toggleFloat
    case openSettings

    // #118–#120, the M4 keyboard grammar (spec G21, G24, G3).
    /// #118: Fn+⌥W/A/S/D — focus the display in that direction, by frame geometry.
    case focusScreenDirection(Direction)
    /// #118: Fn+⇧+arrows — the focused window to the display in that direction; focus follows.
    case moveWindowToScreenDirection(Direction)
    /// #136 (G29): Fn+⌥⇧+arrows — the active workspace, whole (windows, layout, portions,
    /// category), to the display in that direction; focus follows it.
    case moveWorkspaceToScreenDirection(Direction)
    /// #119: Fn+⇧Space — `cycleLayout` backwards round the bar.
    case cycleLayoutReverse
    /// #119: `set-layout-<id>` — the focused display's active workspace to that layout. Unbound by
    /// default; an id the catalogue does not know is a no-op.
    case setLayout(LayoutID)
    /// #143: Fn+⌥+N — the Nth tab of the focused display's active row, clamped to the first and
    /// last; a minimized one is brought back, as a tab click does (#48, #71).
    case focusTab(Int)

    // Shell-UI verbs (M2 design §Decisions: distinct base names, payloads Hashable). The keyboard
    // verbs above are relative to the focused screen; a panel click or IPC call names its target
    // outright — the rail on a second screen must work without moving focus there first.
    case focusWorkspaceID(UUID)            // rail click; workspace by id, wherever it lives
    case focusWindowRef(WindowRef)         // tab click / overview selection; on a placeholder, launches its app (#128)
    case setWorkspaceLayout(UUID, LayoutID)  // layout switcher; targets that workspace directly
    case closeWindowRef(WindowRef)         // tab close button, tab menu, middle-click (#127); a placeholder is forgotten (#128)
    /// #127: the tab menu's Float/Tile — `toggleFloat` for a named window, focused or not. Focus
    /// and the active rows stay put.
    case toggleFloatRef(WindowRef)
    case toggleOverview                    // overview/launcher overlay; app-layer surface, not a World mutation
    /// #132 (M3 B9): the spatialisation view — the focused display's workspaces as mini-desktops,
    /// zoomed out. App-layer, like the overview; holding Fn+W/S opens it too (`SpatialView`).
    case toggleSpatialView
    /// Tab dragged onto a rail row. Absolute where `moveWindowToWorkspace(Vertical)` is relative:
    /// a drag names both the window and the destination, and neither need be the focused one.
    /// `follow` (#95): the store's own moves follow the window, as the keyboard does; a drop passes
    /// false, so the active rows and the focus stay put and the window is only re-filed.
    case moveWindowRefToWorkspace(WindowRef, UUID, follow: Bool = true)
    /// Tab dragged within the bar: put the first window immediately before the second, or at the
    /// end of the row when the second is nil; a second in another row is a drop there, which does
    /// not follow (#95). Reference-based rather than index-based because an
    /// index means something different before and after the removal — a classic off-by-one.
    case moveWindowRefBefore(WindowRef, WindowRef?)
    /// Rail tile dragged to a new place in its own display's stack (#75): the workspace ends up at
    /// `toIndex` of the reordered stack (clamped). The same workspace stays active and focused.
    /// There is no display in the payload on purpose: a workspace only moves within its own.
    case moveWorkspace(UUID, toIndex: Int)
    /// Spec §13.3 / M3a A4 (#52): put every window that has ended up off every display back where
    /// a human can reach it. The model says nothing about geometry, so this changes nothing here —
    /// `WorldStore` does the work — but it is a `Command` so it arrives by the same door as a
    /// hotkey, a menu item and `spacialctl run rescue-windows`.
    case rescueWindows
    /// The rail tray (#73): bring back a window no tab reaches — hidden, minimized, or an
    /// `ephemeral` popup. `focusWindowRef` already unhides and focuses a placed window, but for a
    /// popup it only focuses: a minimized popup stays minimized (the model never marks an
    /// ephemeral `hidden`) and one off every display stays there. This adds exactly those two
    /// things — an `unhide`, and `WorldStore`'s off-display rescue — and never re-files anything:
    /// workspace, row, floating state and `ephemeral` membership are all left as they were.
    case recoverWindow(WindowRef)
    /// #108: a tiled window dragged by its title bar and released over another tile. Same row: the
    /// two swap places. Another row (another display's tile): the window takes that tile's slot,
    /// and — being in the user's hand, as in #57 — focus follows it.
    case dropWindow(WindowRef, onto: WindowRef)

    // #113 (M4 G9 + G10): resizable portions.
    /// Fn+⌃A/D (width) and Fn+⌃W/S (height): the focused tile shrinks or grows by 5 %, stopping on
    /// the 25/50/75 % detents. A no-op where that tile has no interior edge (maximize).
    case resizeWindow(ResizeAxis, grow: Bool)
    /// The focused row's layouts back to their designed sizes.
    case balance
    /// A workspace's portions for one page key, set outright (nil = as designed) — what a border
    /// drag commits, move by move.
    case setPortions(UUID, key: String, Portions?)

    // #114 (M4 G5): split's column count, per workspace.
    /// `split-columns-more` / `split-columns-fewer`: the focused row's split shows one column more
    /// (+1) or fewer (−1), within `SplitView.columnRange`. A no-op on a row that is not split.
    case adjustSplitColumns(Int)
    /// The layout popover's −/+: a workspace's split column count, set outright (clamped).
    case setSplitColumns(UUID, Int)

    // #10: the layout popover and editor. App-layer, like `.openSettings`: `AppRuntime` routes them
    // to the layouts controller, they edit `settings.json`, and the model ignores them.
    /// New… (nil) or Edit… from the popover. `workspace` is the one a newly saved layout is applied to.
    case editLayout(LayoutID?, workspace: UUID?)
    case setDefaultLayout(LayoutID)
    case showLayoutOnBar(LayoutID, Bool)

    // M3 B3, the rail's menus (#111, #112).
    /// #112, G1: a workspace's category is its identity (#24 P2), so this is B3's "rename". Nil
    /// clears it. The row becomes the one category routing (#74) sends that category's apps to on
    /// its display, taking the category off any other row there — one row per category per
    /// display. It is not re-sorted now: like a dragged row (#75), it holds its place for the
    /// session, and the next launch's `sortCategoryRows` puts it where the order says.
    case setWorkspaceCategory(UUID, AppCategory?)
    /// #112: the tile's glyph (an SF Symbol name), from the menu's fixed list.
    case setWorkspaceSymbol(UUID, String)
    /// #112, the M2 `removeWorkspace` ruling: refused on the trailing empty row; allowed on the
    /// active one and on pinned ones. Its windows merge into the row above (below, if it is the
    /// first), and when it was the active row, that row becomes active and focus follows them.
    case removeWorkspace(UUID)
    /// #111: the rail's app menu. App-layer: `AppRuntime` reloads config.toml, shows the About
    /// panel, or quits through the termination gate (spec §7.4) — never `NSApp.terminate`.
    case reloadConfig
    case showAbout
    case quit

    /// Commands the app layer handles (overview, settings, the layout surfaces) — no-ops in the
    /// model. Every command source, the hotkey tap and the control socket alike, routes these to
    /// their controllers instead of the store (#88).
    public var isAppLayer: Bool {
        switch self {
        case .toggleOverview, .toggleSpatialView, .openSettings, .editLayout, .setDefaultLayout, .showLayoutOnBar: true
        case .reloadConfig, .showAbout, .quit: true   // #111
        default: false
        }
    }
}

public enum Effect: Sendable, Equatable {
    case focus(WindowRef)
    case close(WindowRef)
    /// Decision 2026-09-15 (#49): a workspace switch on a display whose front Space is a native
    /// fullscreen window takes that window out of fullscreen first — macOS shows only that Space
    /// there, so the workspace being switched to would otherwise stay invisible until the user
    /// left fullscreen by hand.
    case exitFullscreen(WindowRef)
    /// Decision 2026-09-15 (#48): a tab is a promise that clicking it delivers the window, so a
    /// minimized or app-hidden one is brought back rather than ignored. The backend clears
    /// `AXMinimized` and unhides the app; the reconciler then places it by its row's layout.
    case unhide(WindowRef)
    /// #128: a placeholder tab was clicked — open its app (by bundle id). The window it opens fills
    /// the placeholder when it appears (`PlaceholderMatch`); nothing else waits for it.
    case launch(String)
    case relayout
}
