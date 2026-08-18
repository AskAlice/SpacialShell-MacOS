import Foundation

extension World {
    public static func empty(screens ids: [DisplayID], defaultLayout: Layout) -> World {
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
    public func screenContaining(_ w: WindowRef) -> DisplayID? { location(of: w)?.screen }
    /// Windows the layout engine positions: not floating, not hidden.
    public func tiled(in ws: Workspace) -> [WindowRef] { ws.windows.filter { !ws.floating.contains($0) && !hidden.contains($0) } }
    /// Windows reachable by left/right navigation: not hidden.
    public func visible(in ws: Workspace) -> [WindowRef] { ws.windows.filter { !hidden.contains($0) } }
    public func newWorkspace() -> Workspace { Workspace(name: "Workspace", layout: defaultLayout) }

    // MARK: mutations

    public mutating func adopt(_ w: WindowRef, kind: WindowKind, on screen: DisplayID, parent: WindowRef? = nil) {
        guard location(of: w) == nil, !ephemeral.contains(w), !ignored.contains(w) else { return }
        switch kind {
        case .ignore: ignored.insert(w); return
        case .ephemeral: ephemeral.insert(w); return
        case .tile, .float: break
        }
        var target = screens[screen] != nil ? screen : focus.screen
        var index: Int? = nil
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

    public mutating func remove(_ w: WindowRef) {
        ephemeral.remove(w); ignored.remove(w); hidden.remove(w); parents[w] = nil
        parents = parents.filter { $0.value != w }
        if let loc = location(of: w) {
            var ws = screens[loc.screen]!.workspaces[loc.index]
            let vis = visible(in: ws)
            if focus.window == w {
                let i = vis.firstIndex(of: w)!
                focus.window = i > 0 ? vis[i - 1] : (vis.count > 1 ? vis[i + 1] : nil)
            }
            ws.windows.removeAll { $0 == w }; ws.floating.remove(w)
            if ws.anchor == w { ws.anchor = focus.window.flatMap { ws.windows.contains($0) ? $0 : nil } ?? ws.windows.first }
            screens[loc.screen]!.workspaces[loc.index] = ws
        } else if focus.window == w { focus.window = nil }
        normalize()
    }

    public mutating func setHidden(_ w: WindowRef, _ isHidden: Bool) {
        guard location(of: w) != nil else { return }
        if isHidden { hidden.insert(w) } else { hidden.remove(w) }
        normalize()
    }

    public mutating func setFloating(_ w: WindowRef, _ floating: Bool) {
        guard let loc = location(of: w) else { return }
        if floating { screens[loc.screen]!.workspaces[loc.index].floating.insert(w) }
        else { screens[loc.screen]!.workspaces[loc.index].floating.remove(w) }
    }

    public mutating func activate(index: Int, on screen: DisplayID) {
        guard var s = screens[screen], (0..<s.workspaces.count).contains(index) else { return }
        s.activeIndex = index
        screens[screen] = s
        if focus.screen == screen {
            let vis = visible(in: s.active)
            focus.window = s.active.anchor.flatMap { vis.contains($0) ? $0 : nil } ?? vis.first
        }
        normalize()
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

    /// Restores invariants 4 and 5 after any mutation. Idempotent.
    public mutating func normalize() {
        for id in screens.keys {
            var s = screens[id]!
            let activeId = s.workspaces.indices.contains(s.activeIndex) ? s.workspaces[s.activeIndex].id : nil
            var kept: [Workspace] = []
            for (i, ws) in s.workspaces.enumerated() {
                let last = i == s.workspaces.count - 1
                if ws.isEmpty && !last && ws.id != activeId && !ws.pinned { continue }
                kept.append(ws)
            }
            if kept.isEmpty || !kept.last!.isEmpty || kept.last!.pinned { kept.append(newWorkspace()) }
            s.workspaces = kept
            s.activeIndex = kept.firstIndex { $0.id == activeId } ?? min(s.activeIndex, kept.count - 1)
            for i in kept.indices {
                if let a = kept[i].anchor, !kept[i].windows.contains(a) { s.workspaces[i].anchor = nil }
                if s.workspaces[i].anchor == nil { s.workspaces[i].anchor = tiled(in: s.workspaces[i]).first }
            }
            screens[id] = s
        }
        if screens[focus.screen] == nil { focus.screen = screenOrder.first ?? "" }
        guard let fs = screens[focus.screen] else { return }
        let vis = visible(in: fs.active)
        if let w = focus.window, !(vis.contains(w) || ephemeral.contains(w)) { focus.window = nil }
        if focus.window == nil { focus.window = fs.active.anchor.flatMap { vis.contains($0) ? $0 : nil } ?? vis.first }
        if let w = focus.window, vis.contains(w) { screens[focus.screen]!.workspaces[fs.activeIndex].anchor = w }
    }
}
