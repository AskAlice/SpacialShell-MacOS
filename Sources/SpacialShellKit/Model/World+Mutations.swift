import Foundation

extension World {
    public static func empty(screens ids: [DisplayID], defaultLayout: LayoutID) -> World {
        var screens: [DisplayID: Screen] = [:]
        for id in ids {
            screens[id] = Screen(display: id, workspaces: [Workspace(name: "Workspace 1", layout: defaultLayout)], activeIndex: 0)
        }
        return World(screens: screens, screenOrder: ids, focus: Focus(screen: ids.first ?? "", window: nil),
                     ephemeral: [], ignored: [], hidden: [], parents: [:], defaultLayout: defaultLayout)
    }

    // MARK: queries

    public func location(of w: WindowRef) -> (screen: DisplayID, index: Int)? {
        for id in screenOrder {
            if let i = screens[id]!.workspaces.firstIndex(where: { $0.windows.contains(w) }) { return (id, i) }
        }
        return nil
    }
    public func workspace(containing w: WindowRef) -> Workspace? {
        location(of: w).map { screens[$0.screen]!.workspaces[$0.index] }
    }
    /// Workspace by id, wherever it lives — the address the shell-UI/IPC verbs speak.
    public func location(ofWorkspace id: UUID) -> (screen: DisplayID, index: Int)? {
        for sid in screenOrder {
            if let i = screens[sid]!.workspaces.firstIndex(where: { $0.id == id }) { return (sid, i) }
        }
        return nil
    }
    public func screenContaining(_ w: WindowRef) -> DisplayID? { location(of: w)?.screen }
    /// Windows the layout engine positions: not floating, not hidden, not fullscreen, not on
    /// another Space, and not a placeholder (#128) — a placeholder has no window to position.
    public func tiled(in ws: Workspace) -> [WindowRef] {
        ws.windows.filter { !$0.isPlaceholder && !ws.floating.contains($0) && !hidden.contains($0) && !fullscreen.contains($0) && !offSpace.contains($0) }
    }
    /// Windows focus can land on: not hidden, and not a placeholder (#128).
    public func visible(in ws: Workspace) -> [WindowRef] { ws.windows.filter { !$0.isPlaceholder && !hidden.contains($0) } }

    /// #134 (M3c): the window `w` is attached to — its AX owner, when `w` is a floating child (a
    /// sheet, an attached dialog) in its owner's own row. Such a window is part of the owner's
    /// tile: no tab, moves with it, hands focus back to it. Nil for everything else.
    public func owner(of w: WindowRef) -> WindowRef? {
        guard let p = parents[w], let ws = workspace(containing: w) else { return nil }
        return Self.isAttached(w, parent: p, in: ws) ? p : nil
    }
    /// The top of `w`'s owner chain (a sheet on a sheet belongs to the first owner); `w` itself
    /// when it is attached to nothing.
    public func root(of w: WindowRef) -> WindowRef {
        var r = w, seen: Set<WindowRef> = [w]
        while let p = owner(of: r), seen.insert(p).inserted { r = p }
        return r
    }
    /// The row as the tab bar draws it and the keys walk it: every window but attached ones.
    /// Placeholders (#128) are tabs and are included; the keys step over them, `focusTab` clicks them.
    public func tabs(in ws: Workspace) -> [WindowRef] {
        ws.windows.filter { w in !(parents[w].map { Self.isAttached(w, parent: $0, in: ws) } ?? false) }
    }
    static func isAttached(_ w: WindowRef, parent p: WindowRef, in ws: Workspace) -> Bool {
        p != w && ws.floating.contains(w) && ws.windows.contains(p)
    }
    /// Whether display `d` is showing a native-fullscreen Space right now (#72): it holds a
    /// fullscreen window that is on its display's active Space. The Space test is what makes this
    /// honest — a window keeps reporting fullscreen after the user swipes away from its Space, but
    /// then macOS stops listing it and it is `offSpace` (#55). The shell's panels stay off such a
    /// display: there is no tiling there to chrome, and a panel ordered front onto a fullscreen Space
    /// sits under (or over) the video.
    /// ponytail: trusts `offSpace` for fullscreen Spaces; if the panels stay hidden after leaving
    /// fullscreen, that flag is not tracking fullscreen Spaces and the check needs a second signal.
    public func showsFullscreenSpace(_ d: DisplayID) -> Bool {
        guard let screen = screens[d] else { return false }
        return screen.workspaces.contains { ws in ws.windows.contains { fullscreen.contains($0) && !offSpace.contains($0) } }
    }
    public func newWorkspace() -> Workspace { Workspace(name: "Workspace", layout: defaultLayout) }

    // MARK: mutations

    /// `workspace` is the remembered placement for this window's app (`PersistedState.placements`),
    /// and applies only while that workspace still exists — a placement naming a workspace that is
    /// gone never resurrects it, the window just lands by the ordinary rules. A parent still wins:
    /// a dialog belongs with its owner, wherever the owner ended up.
    public mutating func adopt(_ w: WindowRef, kind: WindowKind, on screen: DisplayID, parent: WindowRef? = nil,
                               workspace: UUID? = nil) {
        guard location(of: w) == nil, !ephemeral.contains(w), !ignored.contains(w) else { return }
        switch kind {
        case .ignore: ignored.insert(w); return
        case .ephemeral: ephemeral.insert(w); return
        case .tile, .float: break
        }
        var target = screens[screen] != nil ? screen : focus.screen
        var index: Int? = nil
        if let id = workspace, let loc = location(ofWorkspace: id) { target = loc.screen; index = loc.index }
        if let p = parent, let loc = location(of: p) {
            target = loc.screen; index = loc.index; parents[w] = p
        }
        let wsIndex = index ?? screens[target]!.activeIndex
        var ws = screens[target]!.workspaces[wsIndex]
        if let p = parent, let pi = ws.windows.firstIndex(of: p) { ws.windows.insert(w, at: pi + 1) } else { ws.windows.append(w) }
        if kind == .float { ws.floating.insert(w) }
        screens[target]!.workspaces[wsIndex] = ws
        if focus.window == nil, target == focus.screen, wsIndex == screens[target]!.activeIndex { focus.window = w }
        normalize()
    }

    /// Where a window seen for the first time lands (#13, #74) — the workspace to hand `adopt`, or
    /// nil for today's rules. One ladder, highest rung first:
    ///
    /// 1. Category routing (#74), for an app whose `category` is in `order`: that category's row
    ///    on `routeOn`, the display the window is on. App type beats memory for these apps, so a
    ///    browser remembered on another display still lands on the one it opened on. None yet →
    ///    one is made where the order puts it (see `categoryRowIndex`).
    /// 2. `remembered`, the app's placement from the state file, if that workspace still exists.
    ///    It is display-aware by construction: a workspace lives on a display keyed by the
    ///    display's UUID, and `PersistedState.restore` puts it back there.
    /// 3. `crowdOn`, set by the store only for an app arriving at launch with more windows than
    ///    `Config.crowdThreshold`: a new workspace of its own on that display, inserted above the
    ///    trailing empty one (invariant 4) and `reserved` until its first window lands.
    /// 4. "Other" (#74): with routing on, any other app gets a row of its own at the bottom of
    ///    `routeOn`'s stack.
    /// 5. nil: `adopt`'s ordinary rules, unchanged. Also what `routeOn == nil` or an empty `order`
    ///    falls to.
    ///
    /// Routing never grows a display past `maxWorkspaces` rows (the trailing empty one does not
    /// count); past it, the app joins the last row. The store passes `routeOn` only for a window
    /// `adopt` will actually file — tileable, no parent — so a routed row is never left empty.
    public mutating func landing(remembered: UUID?, crowdOn: DisplayID?, routeOn: DisplayID? = nil,
                                 category: AppCategory? = nil, order: [AppCategory] = [],
                                 maxWorkspaces: Int = 12) -> UUID? {
        let route = routeOn.flatMap { screens[$0] == nil || order.isEmpty ? nil : $0 }
        if let d = route, let c = category, let rank = order.firstIndex(of: c) {
            if let row = screens[d]!.workspaces.first(where: { $0.category == c }) { return row.id }
            return newRow(on: d, category: c, at: categoryRowIndex(on: d, rank: rank, order: order), max: maxWorkspaces)
        }
        if let id = remembered, location(ofWorkspace: id) != nil { return id }
        if let d = crowdOn, screens[d] != nil {
            var ws = newWorkspace(); ws.reserved = true
            return insertRow(ws, on: d, at: screens[d]!.workspaces.count - 1)
        }
        if let d = route { return newRow(on: d, category: category, at: screens[d]!.workspaces.count - 1, max: maxWorkspaces) }
        return nil
    }

    /// Where a new row for the category ranked `rank` goes: just after the last category row of an
    /// earlier rank, else just before the first of a later one, else at the top. On a stack in
    /// category order (`sortCategoryRows`) that is the same as inserting and sorting; on one where
    /// a category row was dragged this session (#75) it places the new row among its neighbours
    /// and leaves the dragged one where the user put it. The trailing empty is not a row.
    func categoryRowIndex(on d: DisplayID, rank: Int, order: [AppCategory]) -> Int {
        let rows = screens[d]!.workspaces.dropLast()
        if let i = rows.lastIndex(where: { Self.categoryRank($0, order).map { $0 < rank } ?? false }) { return i + 1 }
        return rows.firstIndex { Self.categoryRank($0, order).map { $0 > rank } ?? false } ?? 0
    }

    /// A row's place in `order`, or nil for a row the order does not sort: pinned, no category, or
    /// a category not in the order.
    static func categoryRank(_ ws: Workspace, _ order: [AppCategory]) -> Int? {
        ws.pinned ? nil : ws.category.flatMap { order.firstIndex(of: $0) }
    }

    /// #74: on every display, rows of a category in `order` move to the top, in that order
    /// (stable); pinned rows and rows without one keep their relative order below them. The
    /// active row stays active — this is the model, and the reconciler follows it.
    ///
    /// Run at launch only, after `PersistedState.restore`. A new category row is placed by
    /// `categoryRowIndex` instead of re-sorting, so a category row the user drags (#75) holds until
    /// the next launch puts it back in order, and a row without a category is never moved at all.
    public mutating func sortCategoryRows(_ order: [AppCategory]) {
        guard !order.isEmpty else { return }
        for id in screens.keys {
            var s = screens[id]!
            let active = s.workspaces.indices.contains(s.activeIndex) ? s.workspaces[s.activeIndex].id : nil
            let ranked = s.workspaces.enumerated()
                .compactMap { i, ws in Self.categoryRank(ws, order).map { (rank: $0, i: i, ws: ws) } }
                .sorted { ($0.rank, $0.i) < ($1.rank, $1.i) }
                .map(\.ws)
            s.workspaces = ranked + s.workspaces.filter { Self.categoryRank($0, order) == nil }
            s.activeIndex = s.workspaces.firstIndex { $0.id == active } ?? s.activeIndex
            screens[id] = s
        }
    }

    /// A routed row, or — once the display holds `max` rows — the last row instead.
    private mutating func newRow(on d: DisplayID, category: AppCategory?, at i: Int, max: Int) -> UUID {
        let ws = screens[d]!.workspaces
        if ws.count - 1 >= Swift.max(max, 1) { return ws[ws.count - 2].id }
        var row = newWorkspace(); row.category = category
        return insertRow(row, on: d, at: i)
    }

    /// Inserts without disturbing which workspace is active.
    private mutating func insertRow(_ ws: Workspace, on d: DisplayID, at i: Int) -> UUID {
        screens[d]!.workspaces.insert(ws, at: i)
        if screens[d]!.activeIndex >= i { screens[d]!.activeIndex += 1 }
        return ws.id
    }

    /// #137: how many windows a row's `focusHistory` remembers — material-shell's five.
    public static let focusHistoryLimit = 5

    /// #137: the focused window goes to the front of its row's history. Idempotent; a placeholder
    /// or an ephemeral visitor (no row) is never recorded. Run by `normalize()` and after every
    /// command, so every way focus moves — a key, a click, macOS's own report — is seen.
    /// #134: a focused sheet is recorded as its owner — history is of tabs, which a sheet is not.
    public mutating func noteFocus() {
        guard let focused = focus.window, !focused.isPlaceholder, let loc = location(of: focused) else { return }
        let f = root(of: focused)
        var h = screens[loc.screen]!.workspaces[loc.index].focusHistory
        guard h.first != f else { return }
        h.removeAll { $0 == f }
        h.insert(f, at: 0)
        screens[loc.screen]!.workspaces[loc.index].focusHistory = Array(h.prefix(Self.focusHistoryLimit))
    }

    /// Who takes over when `w` leaves `ws` (closed, or dropped elsewhere without following, #95).
    /// #137: the most recent window of the row's history that is still there and visible; with no
    /// history, `neighbour`.
    func successor(of w: WindowRef, in ws: Workspace) -> WindowRef? {
        let vis = visible(in: ws)
        return ws.focusHistory.first { $0 != w && vis.contains($0) } ?? neighbour(of: w, in: ws)
    }

    /// The visible window before `w`, else the one after, else nobody — `successor`'s fallback.
    func neighbour(of w: WindowRef, in ws: Workspace) -> WindowRef? {
        let vis = visible(in: ws)
        guard let i = vis.firstIndex(of: w) else { return nil }
        return i > 0 ? vis[i - 1] : (vis.count > 1 ? vis[i + 1] : nil)
    }

    public mutating func remove(_ w: WindowRef) {
        let owner = self.owner(of: w)
        ephemeral.remove(w); ignored.remove(w); hidden.remove(w); fullscreen.remove(w); offSpace.remove(w); parents[w] = nil
        placeholders[w] = nil   // #128: removing a placeholder forgets its slot
        pinnedTabs.remove(w)
        parents = parents.filter { $0.value != w }
        if let loc = location(of: w) {
            var ws = screens[loc.screen]!.workspaces[loc.index]
            // #134: a closed sheet hands focus back to the window it was on; anything else to the
            // row's most recent window (#137), else its neighbour.
            if focus.window == w { focus.window = owner.flatMap { hidden.contains($0) ? nil : $0 } ?? successor(of: w, in: ws) }
            ws.windows.removeAll { $0 == w }; ws.floating.remove(w)
            if ws.anchor == w { ws.anchor = focus.window.flatMap { ws.windows.contains($0) ? $0 : nil } ?? ws.windows.first }
            screens[loc.screen]!.workspaces[loc.index] = ws
        } else if focus.window == w { focus.window = nil }
        normalize()
    }

    /// Hidden wins over fullscreen (I6). A minimized or ⌘H-hidden window is put away whatever
    /// `AXFullScreen` still says about it, and the two states arrive from different reads of the
    /// same snapshot — so without a precedence the model could hold both and the layout would skip
    /// the window twice over: once as hidden, once as macOS-owned.
    public mutating func setHidden(_ w: WindowRef, _ isHidden: Bool) {
        guard location(of: w) != nil else { return }
        if isHidden { hidden.insert(w); fullscreen.remove(w) } else { hidden.remove(w) }
        normalize()
    }

    /// No-op while the window is hidden — see `setHidden`. A window that leaves minimization while
    /// still fullscreen is flagged again by the next snapshot, which is the only place both facts
    /// are read together.
    public mutating func setFullscreen(_ w: WindowRef, _ isFullscreen: Bool) {
        guard location(of: w) != nil, !hidden.contains(w) else { return }
        if isFullscreen { fullscreen.insert(w) } else { fullscreen.remove(w) }
    }

    /// #55. Independent of hidden and fullscreen: each only ever makes the reconciler leave the
    /// window alone, so holding more than one of them is harmless.
    public mutating func setOnActiveSpace(_ w: WindowRef, _ onActiveSpace: Bool) {
        guard location(of: w) != nil else { return }
        if onActiveSpace { offSpace.remove(w) } else { offSpace.insert(w) }
    }

    public mutating func setFloating(_ w: WindowRef, _ floating: Bool) {
        guard let loc = location(of: w) else { return }
        if floating { screens[loc.screen]!.workspaces[loc.index].floating.insert(w) }
        else { screens[loc.screen]!.workspaces[loc.index].floating.remove(w) }
    }

    public mutating func activate(index: Int, on screen: DisplayID) {
        guard (screens[screen]?.workspaces.indices)?.contains(index) == true else { return }
        rememberActive(on: screen, before: index)
        peek = nil   // #179: a workspace switch ends a peek
        var s = screens[screen]!
        s.activeIndex = index
        screens[screen] = s
        if focus.screen == screen {
            let vis = visible(in: s.active)
            focus.window = s.active.anchor.flatMap { vis.contains($0) ? $0 : nil } ?? vis.first
        }
        normalize()
    }

    /// #106: about to make row `index` active on `screen` — remember the row being left, so Fn+N on
    /// the new one can come back. Staying put remembers nothing.
    mutating func rememberActive(on screen: DisplayID, before index: Int) {
        guard let s = screens[screen], s.activeIndex != index, s.workspaces.indices.contains(s.activeIndex) else { return }
        screens[screen]!.previous = s.active.id
    }

    /// Spec §7.8: unplug merges into main; replug creates an empty stack (state restore may refill it).
    ///
    /// An empty `order` is refused outright. macOS reports an empty screen list mid-hot-plug, at
    /// wake and around the lock screen, and it is always transient — honouring it would delete
    /// every screen and with it every workspace, and leave `focus.screen` pointing at nothing for
    /// the next `adopt` to force-unwrap. Callers guard as well; this is the backstop.
    public mutating func setScreens(_ order: [DisplayID], main: DisplayID) {
        guard !order.isEmpty else { return }
        for id in order where screens[id] == nil {
            screens[id] = Screen(display: id, workspaces: [newWorkspace()], activeIndex: 0)
        }
        for id in Array(screens.keys) where !order.contains(id) {
            let gone = screens.removeValue(forKey: id)!
            let mainId = screens[main] != nil ? main : (order.first ?? "")
            guard var m = screens[mainId] else { continue }
            let insertAt = m.workspaces.count - 1
            m.workspaces.insert(contentsOf: gone.workspaces.filter { !$0.isEmpty || $0.pinned }, at: insertAt)
            screens[mainId] = m
            if focus.screen == id { focus.screen = mainId }
        }
        screenOrder = order.filter { screens[$0] != nil }
        if screens[focus.screen] == nil { focus.screen = screenOrder.first ?? "" }
        normalize()
    }

    /// Drops every workspace reservation and reaps what that exposes. `PersistedState.restore`
    /// reserves a workspace per remembered placement so the window can land back in it; once the
    /// first snapshot has adopted everything that is running, a reservation still empty belongs to
    /// an app that did not come back, and keeping it leaves a dead row in the middle of the rail.
    public mutating func clearReservations() {
        for id in screens.keys {
            for i in screens[id]!.workspaces.indices { screens[id]!.workspaces[i].reserved = false }
        }
        normalize()
    }

    /// #179: whether `w` can be peeked: a real window placed in a row, that the reconciler may
    /// frame — not minimized or app-hidden, not in its own fullscreen Space, not on another Space.
    public func canPeek(_ w: WindowRef) -> Bool {
        !w.isPlaceholder && location(of: w) != nil
            && !hidden.contains(w) && !fullscreen.contains(w) && !offSpace.contains(w)
    }

    /// Restores invariants 4 and 5 after any mutation. Idempotent.
    public mutating func normalize() {
        defer { slideViews() }
        if let p = peek, !canPeek(p) { peek = nil }   // #179: a peeked window that vanished or hid ends the peek
        for id in screens.keys {
            var s = screens[id]!
            let activeId = s.workspaces.indices.contains(s.activeIndex) ? s.workspaces[s.activeIndex].id : nil
            var kept: [Workspace] = []
            for (i, ws) in s.workspaces.enumerated() {
                let last = i == s.workspaces.count - 1
                if ws.isEmpty && !last && ws.id != activeId && !ws.pinned && !ws.reserved { continue }
                var ws = ws
                if !ws.isEmpty { ws.reserved = false }   // its windows are back; stop holding it open
                kept.append(ws)
            }
            if kept.isEmpty || !kept.last!.isEmpty || kept.last!.pinned { kept.append(newWorkspace()) }
            s.workspaces = kept
            s.activeIndex = kept.firstIndex { $0.id == activeId } ?? min(s.activeIndex, kept.count - 1)
            if let p = s.previous, !kept.contains(where: { $0.id == p }) { s.previous = nil }   // #106
            for i in kept.indices {
                if let a = kept[i].anchor, !kept[i].windows.contains(a) || a.isPlaceholder { s.workspaces[i].anchor = nil }
                // #137: history holds only windows still in this row.
                s.workspaces[i].focusHistory.removeAll { !kept[i].windows.contains($0) || $0.isPlaceholder }
                if s.workspaces[i].anchor == nil { s.workspaces[i].anchor = tiled(in: s.workspaces[i]).first }
            }
            screens[id] = s
        }
        if screens[focus.screen] == nil { focus.screen = screenOrder.first ?? "" }
        guard let fs = screens[focus.screen] else { return }
        let vis = visible(in: fs.active)
        if let w = focus.window, !(vis.contains(w) || ephemeral.contains(w)) { focus.window = nil }
        if focus.window == nil { focus.window = fs.active.anchor.flatMap { vis.contains($0) ? $0 : nil } ?? vis.first }
        // #134: a focused sheet anchors its owner, so the layout's page stays on the owner's tile.
        if let w = focus.window, vis.contains(w) { screens[focus.screen]!.workspaces[fs.activeIndex].anchor = root(of: w) }
        noteFocus()
    }

    /// #114: every row's split view slid just far enough to hold its anchor — past the edge by
    /// one, never a page. Run after every change that can move an anchor (`normalize()`, and
    /// `CommandRunner` after each command), so the view remembers where it was between them.
    public mutating func slideViews() {
        for id in screens.keys {
            for i in screens[id]!.workspaces.indices {
                let ws = screens[id]!.workspaces[i], row = tiled(in: ws)
                guard !row.isEmpty else { screens[id]!.workspaces[i].splitStart = nil; continue }
                let f = ws.anchor.flatMap { row.firstIndex(of: $0) } ?? 0
                let v = ws.split(in: row)
                screens[id]!.workspaces[i].splitStart = row[SplitView.slide(v.start, focused: f, k: min(v.columns, row.count), count: row.count)]
            }
        }
    }
}
