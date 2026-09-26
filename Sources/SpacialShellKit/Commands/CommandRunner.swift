import Foundation

public enum CommandRunner {
    /// `layouts` gives the layout ids meaning: what `cycleLayout` rings through and how many
    /// windows a layout shows (#9). Defaults to the five built-ins.
    /// `displays` (#118): the real display frames the directional display commands resolve
    /// against; without them those commands are no-ops. `workspaceWrap` (#120): `workspace-wrap`.
    /// `categoryOrder` (#136): `category-order`, where a workspace moved to another display lands.
    public static func apply(_ command: Command, to input: World, layouts: LayoutCatalogue = .builtins,
                             displays: [DisplayInfo] = [], workspaceWrap: Bool = false,
                             categoryOrder: [AppCategory] = []) -> (World, [Effect]) {
        let o = run(command, on: input, layouts: layouts, displays: displays, workspaceWrap: workspaceWrap,
                    categoryOrder: categoryOrder)
        return (o.world, o.effects)
    }

    /// #109: `apply` plus why a command did nothing. A path that sets no reason is `.done` when it
    /// changed the world or emitted an effect, else a generic no-op.
    public static func run(_ command: Command, on input: World, layouts: LayoutCatalogue = .builtins,
                           displays: [DisplayInfo] = [], workspaceWrap: Bool = false,
                           categoryOrder: [AppCategory] = []) -> CommandOutcome {
        var why: CommandReport?
        let (w, e) = apply(command, to: input, layouts: layouts, displays: displays, workspaceWrap: workspaceWrap,
                           categoryOrder: categoryOrder, why: &why)
        var slid = w
        slid.slideViews()   // #114: not every path normalizes, and every focus move can slide split
        return CommandOutcome(world: slid, effects: e,
                              report: why ?? (e.isEmpty && w == input ? .noop("nothing to do") : .done))
    }

    static func apply(_ command: Command, to input: World, layouts: LayoutCatalogue, displays: [DisplayInfo],
                      workspaceWrap: Bool, categoryOrder: [AppCategory], why: inout CommandReport?) -> (World, [Effect]) {
        var w = input
        var effects: [Effect] = []
        /// #109: the silent `(w, [])` returns, with their reason.
        func fail(_ e: CommandError) -> (World, [Effect]) { why = .failed(e); return (w, []) }
        func noop(_ reason: String) -> (World, [Effect]) { why = .noop(reason); return (w, []) }
        let sid = w.focus.screen
        guard let screen = w.screens[sid] else { return fail(.unknownScreen) }

        /// Move one window out of the workspace it is in and into `to` (at row position `at`, else
        /// the end), carrying its pin, and follow it. Workspace moves, display moves, a dragged
        /// tab and the edge spill (#33) differ only in how they name the destination, so they
        /// share this outright rather than drifting apart.
        ///
        /// `follow: false` is a drop (#95): the window becomes its new row's anchor (parked there
        /// if that row is inactive), and nothing else moves — every active row stays active, and
        /// focus stays put unless it was on this window, when it falls to the neighbour exactly as
        /// on a close. A focus change is emitted here; the caller adds the rest.
        func move(_ ref: WindowRef, to dest: (screen: DisplayID, index: Int), at position: Int? = nil,
                  follow: Bool = true) -> Bool {
            guard let from = w.location(of: ref) else { return false }
            guard from.screen != dest.screen || from.index != dest.index else { return false }
            let source = w.screens[from.screen]!.workspaces[from.index]
            let neighbour = w.neighbour(of: ref, in: source)
            w.screens[from.screen]!.workspaces[from.index].windows.removeAll { $0 == ref }
            w.screens[from.screen]!.workspaces[from.index].floating.remove(ref)
            w.screens[dest.screen]!.workspaces[dest.index].windows.insert(
                ref, at: position ?? w.screens[dest.screen]!.workspaces[dest.index].windows.count)
            if source.floating.contains(ref) { w.screens[dest.screen]!.workspaces[dest.index].floating.insert(ref) }
            w.screens[dest.screen]!.workspaces[dest.index].anchor = ref
            if follow {
                w.rememberActive(on: dest.screen, before: dest.index)
                w.screens[dest.screen]!.activeIndex = dest.index
                w.focus = Focus(screen: dest.screen, window: ref)
            } else {
                if source.anchor == ref { w.screens[from.screen]!.workspaces[from.index].anchor = neighbour }
                if w.focus.window == ref {
                    w.focus.window = neighbour
                    if let neighbour { effects.append(.focus(neighbour)) }
                }
            }
            w.normalize()
            return true
        }

        /// #98: every managed window of app `pid` into workspace `dest`, none of them following.
        /// They keep their relative order (appended after what the row already holds) and, via
        /// `move`, their floating state. The focused window goes last, so if focus has to fall to a
        /// neighbour, no window of the app is left in its row to fall to. The destination is looked
        /// up by id on every step: a row the app empties is reaped, and indices shift under it.
        /// ponytail: the app is its pid, which is all the model knows; an app running several
        /// processes moves only the one the window belongs to.
        func moveApp(_ pid: Int32, to dest: UUID) -> Bool {
            guard let d = w.location(ofWorkspace: dest) else { return false }
            let there = w.screens[d.screen]!.workspaces[d.index].windows
            let moving = w.screenOrder.flatMap { w.screens[$0]!.workspaces.flatMap(\.windows) }
                .filter { $0.pid == pid && !there.contains($0) }
            guard !moving.isEmpty else { return false }
            var placed: [Int] = []   // ranks in `moving` already moved
            for r in moving.filter({ $0 != w.focus.window }) + moving.filter({ $0 == w.focus.window }) {
                let rank = moving.firstIndex(of: r)!
                guard let d = w.location(ofWorkspace: dest) else { break }
                _ = move(r, to: d, at: there.count + placed.filter { $0 < rank }.count, follow: false)
                placed.append(rank)
            }
            return true
        }

        /// Fn+Shift+W/S's destination (and #98's): the row above or below the active one. Past the
        /// top there is no row yet, so one is made — Fn+Shift+W from the first row opens a fresh
        /// workspace above all the others, the mirror of Fn+Shift+S from the last row landing in
        /// the trailing "+" row.
        func keyboardTarget(_ dir: Vertical) -> Int? {
            var target = screen.activeIndex + (dir == .down ? 1 : -1)
            if target == -1 {
                w.screens[sid]!.workspaces.insert(w.newWorkspace(), at: 0)
                w.screens[sid]!.activeIndex += 1
                target = 0
            }
            return w.screens[sid]!.workspaces.indices.contains(target) ? target : nil
        }

        /// Decision 2026-09-15 (#49): macOS shows only the fullscreen Space on the display that has
        /// one, so a workspace switch there is invisible until the user leaves fullscreen by hand.
        /// Leaving it first is what makes the switch mean anything. Only the window(s) of the
        /// workspace being left can be in front, so only those are asked.
        func leaveFullscreen(on screen: DisplayID) {
            guard let s = w.screens[screen] else { return }
            for win in s.active.windows where w.fullscreen.contains(win) { effects.append(.exitFullscreen(win)) }
        }

        func setFocus(_ ref: WindowRef?) {
            w.focus.window = ref
            if let ref { w.screens[w.focus.screen]!.workspaces[w.screens[w.focus.screen]!.activeIndex].anchor = ref; effects.append(.focus(ref)) }
        }

        /// Activate a row and land on it. #50: a row whose windows are all minimized or app-hidden
        /// used to activate with nothing focused, so macOS kept the previous app in front and the
        /// user saw the rail move and nothing else. A row is a promise, like a tab (#48): its
        /// anchor (else its first window) is brought back and focused.
        func activateAndLand(_ index: Int, on screen: DisplayID) {
            w.activate(index: index, on: screen)
            if w.focus.window == nil, w.focus.screen == screen, let ws = w.screens[screen]?.active,
               let r = ws.anchor.flatMap({ ws.windows.contains($0) ? $0 : nil }) ?? ws.windows.first,
               w.hidden.contains(r) {
                w.hidden.remove(r); effects.append(.unhide(r))
                setFocus(r)
            } else if let f = w.focus.window { effects.append(.focus(f)) }
        }

        switch command {
        case .focusWindow(let dir):
            // Decision 2026-09-24 (#71): the keys walk the tab row exactly as the bar draws it,
            // minimized and app-hidden windows included, and landing on one brings it back — the
            // same promise a tab click keeps (#48). Walking only the visible windows meant a tab
            // you could click was one the keyboard stepped straight over.
            let row = screen.active.windows
            guard !row.isEmpty else { return noop("no windows in this workspace") }
            let i = w.focus.window.flatMap { row.firstIndex(of: $0) } ?? 0
            let j = dir == .right ? (i + 1) % row.count : (i - 1 + row.count) % row.count
            if w.hidden.contains(row[j]) { w.hidden.remove(row[j]); effects.append(.unhide(row[j])) }
            setFocus(row[j]); effects.append(.relayout)

        case .focusWorkspace(let dir):
            var target = screen.activeIndex + (dir == .down ? 1 : -1)
            // #120 (G3), opt-in: Fn+W on the first row goes to the last non-empty one, and Fn+S
            // from the last non-empty row (or below it) goes to the first. The trailing "+" row is
            // then reached by the rail's "+" and by Fn+Shift+S, not by stepping onto it.
            if workspaceWrap, let last = screen.workspaces.lastIndex(where: { !$0.isEmpty }) {
                if dir == .up, screen.activeIndex == 0 { target = last }
                if dir == .down, screen.activeIndex >= last { target = 0 }
            }
            guard (0..<screen.workspaces.count).contains(target), target != screen.activeIndex else {
                return noop(dir == .up ? "already on the top workspace" : "already on the bottom workspace")
            }
            leaveFullscreen(on: sid)
            activateAndLand(target, on: sid)
            effects.append(.relayout)

        case .focusWorkspaceIndex(let n):
            var target = n - 1
            // Decision (#24, #106): Fn+N on the workspace already active goes back to the previous
            // one, so one chord flips between two. Nothing remembered: a no-op, as before.
            if target == screen.activeIndex {
                guard let p = screen.previous, let i = screen.workspaces.firstIndex(where: { $0.id == p }) else {
                    return noop("already on workspace \(n)")
                }
                target = i
            }
            guard (0..<screen.workspaces.count).contains(target) else { return fail(.unknownWorkspace(String(n))) }
            guard target != screen.activeIndex else { return noop("already on workspace \(n)") }
            leaveFullscreen(on: sid)
            activateAndLand(target, on: sid)
            effects.append(.relayout)

        case .closeFocusedWindow:
            guard let f = w.focus.window else { return fail(.noFocusedWindow) }
            effects.append(.close(f))

        case .moveWindow(let dir):
            guard let f = w.focus.window, var ws = Optional(screen.active), let i = ws.windows.firstIndex(of: f) else { return fail(.noFocusedWindow) }
            let j = dir == .right ? i + 1 : i - 1
            guard (0..<ws.windows.count).contains(j) else {
                // Decision 2026-09-14 (#33): past the edge of its row the window spills onto the
                // neighbouring display, landing at the near end of its active row. The outermost
                // display has no neighbour that way, so there it stays a no-op.
                guard let k = w.screenOrder.firstIndex(of: sid) else { return fail(.unknownScreen) }
                let n = dir == .right ? k + 1 : k - 1
                guard w.screenOrder.indices.contains(n) else { return noop("already at the \(dir == .right ? "right" : "left") edge") }
                let target = w.screenOrder[n]
                guard move(f, to: (target, w.screens[target]!.activeIndex), at: dir == .right ? 0 : nil) else { return (w, []) }
                effects.append(.focus(f)); effects.append(.relayout)
                return (w, effects)
            }
            ws.windows.swapAt(i, j)
            // `maximize` paints only the focused window (LayoutEngine), and the focus travels with
            // the window as it moves — so the same window stays on screen at the same rect and the
            // move is invisible, however real it is in the row. The verb means "put this beside
            // that", so it promotes to `split`, the narrowest layout that can show the pair.
            // Layouts that already show more than one window are the user's choice; leave them.
            // #9 generalises "maximize" to "any layout that shows fewer than two here" (a one-zone
            // drawn layout gets the same courtesy).
            // Placed after the bounds guard: a refused move must change nothing, layout included.
            if LayoutEngine.capacity(layouts.resolve(ws.layout).def, count: ws.windows.count) < 2 { ws.layout = .split }
            w.screens[sid]!.workspaces[screen.activeIndex] = ws
            effects.append(.relayout)

        case .moveWindowToWorkspace(let dir):
            guard let f = w.focus.window, screen.active.windows.contains(f) else { return fail(.noFocusedWindow) }
            guard let target = keyboardTarget(dir), move(f, to: (sid, target)) else { return noop("no workspace that way") }
            effects.append(.focus(f)); effects.append(.relayout)

        case .moveWindowToWorkspaceIndex(let n):
            // #105: past the last row is the trailing "+" row, which grows a new one (invariant 4).
            guard n >= 1 else { return fail(.unknownWorkspace(String(n))) }
            guard let f = w.focus.window, screen.active.windows.contains(f) else { return fail(.noFocusedWindow) }
            guard move(f, to: (sid, min(n, screen.workspaces.count) - 1)) else { return noop("already on workspace \(n)") }
            effects.append(.focus(f)); effects.append(.relayout)

        case .moveAppToWorkspace(let dir):
            guard let f = w.focus.window, screen.active.windows.contains(f) else { return fail(.noFocusedWindow) }
            guard let target = keyboardTarget(dir) else { return noop("no workspace that way") }
            let dest = w.screens[sid]!.workspaces[target].id
            guard moveApp(f.pid, to: dest), let loc = w.location(ofWorkspace: dest) else { return (w, []) }
            // Follow the focused window, as Fn+Shift+W/S does.
            w.rememberActive(on: loc.screen, before: loc.index)
            w.screens[loc.screen]!.activeIndex = loc.index
            w.screens[loc.screen]!.workspaces[loc.index].anchor = f
            w.focus = Focus(screen: loc.screen, window: f)
            w.normalize()
            effects = [.focus(f), .relayout]

        case .moveAppRefToWorkspace(let ref, let ws):
            guard w.location(of: ref) != nil else { return fail(.unknownWindow(ref)) }
            guard w.location(ofWorkspace: ws) != nil else { return fail(.unknownWorkspace(ws.uuidString)) }
            guard moveApp(ref.pid, to: ws) else { return noop("the app is already there") }
            effects.append(.relayout)

        case .moveWindowRefToWorkspace(let ref, let workspace, let follow):
            // Dropping on the rail's "+" needs no special case: the trailing empty workspace is a
            // workspace like any other, and normalize() grows a fresh "+" underneath it the moment
            // it stops being empty (invariant 4) — the same thing that makes clicking "+" work.
            guard let dest = w.location(ofWorkspace: workspace) else { return fail(.unknownWorkspace(workspace.uuidString)) }
            guard w.location(of: ref) != nil else { return fail(.unknownWindow(ref)) }
            guard move(ref, to: dest, follow: follow) else { return noop("the window is already there") }
            if follow { effects.append(.focus(ref)) }
            effects.append(.relayout)

        case .moveWindowRefBefore(let ref, let before):
            // A row operation, not a focus one: dragging a tab into a new position must not take
            // focus away from whatever the user was actually working in.
            guard let from = w.location(of: ref) else { return fail(.unknownWindow(ref)) }
            var row = w.screens[from.screen]!.workspaces[from.index].windows
            guard let i = row.firstIndex(of: ref) else { return (w, []) }
            // Decision 2026-09-24 (#32): `before` in another row (another display's bar, or another
            // workspace) is a drop there, not a reorder here — the window moves into that row just
            // before it, exactly as a rail drop would, and like one (#95) focus does not follow.
            if let before, !row.contains(before) {
                guard let dest = w.location(of: before),
                      let j = w.screens[dest.screen]!.workspaces[dest.index].windows.firstIndex(of: before),
                      move(ref, to: dest, at: j, follow: false) else { return (w, []) }
                effects.append(.relayout)
                return (w, effects)
            }
            // Resolve the destination before removing, so `before` is still findable; then convert
            // to a post-removal index so the insert cannot be off by one.
            let target: Int
            if let before {
                guard before != ref, let j = row.firstIndex(of: before) else { return (w, []) }
                target = j > i ? j - 1 : j
            } else {
                target = row.count - 1
            }
            guard target != i else { return noop("the tab is already there") }
            row.remove(at: i)
            row.insert(ref, at: target)
            w.screens[from.screen]!.workspaces[from.index].windows = row
            effects.append(.relayout)

        case .moveWorkspace(let id, let to):
            // Decision 2026-09-25 (#75): reorder by id, keep the active workspace by id. normalize()
            // then does what it always does, which covers the edge cases: moving a workspace past
            // the trailing "+" leaves that "+" empty mid-stack, so it is reaped and a fresh one is
            // grown at the end — the same result as dropping just before it. An empty unpinned
            // row can only be here if it is active or reserved, and both survive normalize().
            guard let loc = w.location(ofWorkspace: id) else { return fail(.unknownWorkspace(id.uuidString)) }
            var s = w.screens[loc.screen]!
            let target = min(max(to, 0), s.workspaces.count - 1)
            guard target != loc.index else { return noop("the workspace is already there") }
            let activeID = s.active.id
            s.workspaces.insert(s.workspaces.remove(at: loc.index), at: target)
            s.activeIndex = s.workspaces.firstIndex { $0.id == activeID }!
            w.screens[loc.screen] = s
            w.normalize()
            effects.append(.relayout)

        case .cycleLayout:
            w.screens[sid]!.workspaces[screen.activeIndex].layout = layouts.next(after: screen.active.layout)
            effects.append(.relayout)

        case .toggleShellUI:
            // Zen (M2 design ruling): one bit, one verb; the reconciler reads it for the insets.
            w.zen.toggle()
            effects.append(.relayout)

        case .focusWorkspaceID(let id):
            guard let loc = w.location(ofWorkspace: id) else { return fail(.unknownWorkspace(id.uuidString)) }
            // Focus moves to the clicked screen first so `activate` re-derives the focused window
            // from that workspace's anchor, exactly as the keyboard path does.
            if w.focus.screen != loc.screen { w.focus = Focus(screen: loc.screen, window: nil) }
            if w.screens[loc.screen]?.activeIndex != loc.index { leaveFullscreen(on: loc.screen) }
            activateAndLand(loc.index, on: loc.screen)
            effects.append(.relayout)

        case .focusWindowRef(let r):
            if w.ephemeral.contains(r) { w.focus.window = r; return (w, [.focus(r)]) }
            guard let loc = w.location(of: r) else { return fail(.unknownWindow(r)) }
            // Decision 2026-09-15 (#48): a tab is a promise. Clicking one delivers its window, so a
            // minimized or app-hidden window is brought back instead of the click doing nothing —
            // a visible control that silently no-ops was the bug. `hidden` is cleared here so focus
            // lands on something the model calls visible (invariant 5); the backend makes it true.
            if w.hidden.contains(r) { w.hidden.remove(r); effects.append(.unhide(r)) }
            w.focus.screen = loc.screen
            w.activate(index: loc.index, on: loc.screen)
            w.focus.window = r
            w.screens[loc.screen]!.workspaces[loc.index].anchor = r
            w.normalize()
            effects.append(.focus(r)); effects.append(.relayout)

        case .setWorkspaceLayout(let id, let l):
            guard let loc = w.location(ofWorkspace: id) else { return fail(.unknownWorkspace(id.uuidString)) }
            w.screens[loc.screen]!.workspaces[loc.index].layout = l
            effects.append(.relayout)

        case .closeWindowRef(let r):
            effects.append(.close(r))

        case .recoverWindow(let r):
            // #73: a placed window is exactly a tab click; a popup is focused *and* unhidden, since
            // nothing else in the model would ever un-minimize it. The rescue is the store's.
            guard w.ephemeral.contains(r) else { return apply(.focusWindowRef(r), to: w, layouts: layouts, displays: displays, workspaceWrap: workspaceWrap, categoryOrder: categoryOrder, why: &why) }
            w.focus.window = r
            return (w, [.unhide(r), .focus(r)])

        case .dropWindow(let ref, let target):
            guard let from = w.location(of: ref) else { return fail(.unknownWindow(ref)) }
            guard let to = w.location(of: target) else { return fail(.unknownWindow(target)) }
            guard ref != target,
                  !w.screens[from.screen]!.workspaces[from.index].floating.contains(ref),
                  !w.screens[to.screen]!.workspaces[to.index].floating.contains(target) else { return noop("only two tiled windows swap") }
            if from == to {
                var ws = w.screens[from.screen]!.workspaces[from.index]
                ws.windows.swapAt(ws.windows.firstIndex(of: ref)!, ws.windows.firstIndex(of: target)!)
                ws.anchor = ref
                w.screens[from.screen]!.workspaces[from.index] = ws
                w.focus = Focus(screen: from.screen, window: ref)
            } else {
                let j = w.screens[to.screen]!.workspaces[to.index].windows.firstIndex(of: target)!
                guard move(ref, to: to, at: j) else { return (w, []) }
            }
            effects.append(.focus(ref)); effects.append(.relayout)

        case .resizeWindow(let axis, let grow):
            // #113. Without geometry the page is the one the model sees (no #54 floor); the store
            // turns the key press into `setPortions` against the real tiling rect first.
            guard let (id, page, i) = w.resizePage(layouts: layouts) else { return (w, []) }
            let current = screen.active.portions[page.key]
            let (next, moved) = Resize.step(page, current, index: i, axis: axis, grow: grow)
            guard moved else { return (w, []) }
            return apply(.setPortions(id, key: page.key, next), to: w, layouts: layouts)

        case .balance:
            guard !screen.active.portions.isEmpty else { return (w, []) }
            w.screens[sid]!.workspaces[screen.activeIndex].portions = [:]
            effects.append(.relayout)

        case .setPortions(let id, let key, let p):
            guard let loc = w.location(ofWorkspace: id),
                  w.screens[loc.screen]!.workspaces[loc.index].portions[key] != p else { return (w, []) }
            w.screens[loc.screen]!.workspaces[loc.index].portions[key] = p
            effects.append(.relayout)

        case .adjustSplitColumns(let d):
            guard layouts.resolve(screen.active.layout).def.id == .split else { return noop("the layout is not split") }
            return apply(.setSplitColumns(screen.active.id, screen.active.splitColumns + d), to: w, layouts: layouts,
                         displays: displays, workspaceWrap: workspaceWrap, categoryOrder: categoryOrder, why: &why)

        case .setSplitColumns(let id, let n):
            guard let loc = w.location(ofWorkspace: id) else { return fail(.unknownWorkspace(id.uuidString)) }
            let r = SplitView.columnRange, clamped = min(max(n, r.lowerBound), r.upperBound)
            guard w.screens[loc.screen]!.workspaces[loc.index].splitColumns != clamped else {
                return noop("split already shows \(clamped) columns")
            }
            w.screens[loc.screen]!.workspaces[loc.index].splitColumns = clamped
            effects.append(.relayout)

        case .rescueWindows:
            // Geometry only: the store sweeps `observed` against the displays. Relayout so the
            // sweep runs inside the ordinary reconcile.
            effects.append(.relayout)

        case .toggleOverview, .openSettings, .editLayout, .setDefaultLayout, .showLayoutOnBar:
            // App-layer surfaces; AppRuntime routes them before the store, and if one does reach
            // the store anyway (custom wiring, tests) it must change nothing.
            break

        case .focusScreen(let n):
            guard w.screenOrder.count > 1, let i = w.screenOrder.firstIndex(of: sid) else { return noop("only one display") }
            let j = n == .next ? (i + 1) % w.screenOrder.count : (i - 1 + w.screenOrder.count) % w.screenOrder.count
            w.focus = Focus(screen: w.screenOrder[j], window: nil)
            w.normalize()
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .moveWindowToScreen(let n):
            guard let f = w.focus.window, screen.active.windows.contains(f) else { return fail(.noFocusedWindow) }
            guard w.screenOrder.count > 1, let i = w.screenOrder.firstIndex(of: sid) else { return noop("only one display") }
            let j = n == .next ? (i + 1) % w.screenOrder.count : (i - 1 + w.screenOrder.count) % w.screenOrder.count
            let target = w.screenOrder[j]
            guard move(f, to: (target, w.screens[target]!.activeIndex)) else { return (w, []) }
            effects.append(.focus(f)); effects.append(.relayout)

        // #118–#120, the M4 keyboard grammar.
        case .focusScreenDirection(let dir):
            // As `focusScreen`, but the display is the one that way on the desk (#118).
            guard let target = DisplayNeighbours.neighbour(of: sid, dir, in: displays), w.screens[target] != nil
            else { return (w, []) }
            w.focus = Focus(screen: target, window: nil)
            w.normalize()
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .moveWindowToScreenDirection(let dir):
            // As `moveWindowToScreen`: onto that display's active row, and focus follows (#118).
            guard let f = w.focus.window, screen.active.windows.contains(f),
                  let target = DisplayNeighbours.neighbour(of: sid, dir, in: displays), let dest = w.screens[target],
                  move(f, to: (target, dest.activeIndex)) else { return (w, []) }
            effects.append(.focus(f)); effects.append(.relayout)

        case .moveWorkspaceToScreenDirection(let dir):
            // #136 (G29): the active row itself moves, so its layout, portions and category go
            // with it. It lands in its category's slot if `category-order` places it (#74), else
            // just above the target's trailing empty row; focus follows. The source activates the
            // row above it (below, if it was the first), as `removeWorkspace` does.
            let from = screen.activeIndex
            guard let target = DisplayNeighbours.neighbour(of: sid, dir, in: displays), w.screens[target] != nil
            else { return noop("no display that way") }
            guard !w.isTrailingEmpty((sid, from)) else { return noop("the empty workspace stays") }
            guard screen.workspaces.indices.contains(where: { $0 != from && !screen.workspaces[$0].isEmpty })
            else { return noop("the only workspace on this display") }
            let row = w.screens[sid]!.workspaces.remove(at: from)
            w.screens[sid]!.activeIndex = max(from - 1, 0)
            // One row per category per display (#112): the arriving row keeps its category.
            if let c = row.category {
                for i in w.screens[target]!.workspaces.indices where w.screens[target]!.workspaces[i].category == c {
                    w.screens[target]!.workspaces[i].category = nil
                }
            }
            let at = World.categoryRank(row, categoryOrder).map { w.categoryRowIndex(on: target, rank: $0, order: categoryOrder) }
                ?? w.screens[target]!.workspaces.count - 1
            w.screens[target]!.workspaces.insert(row, at: at)
            if w.screens[target]!.activeIndex >= at { w.screens[target]!.activeIndex += 1 }
            w.focus.screen = target
            activateAndLand(at, on: target)
            effects.append(.relayout)

        case .cycleLayoutReverse:
            w.screens[sid]!.workspaces[screen.activeIndex].layout = layouts.previous(before: screen.active.layout)
            effects.append(.relayout)

        case .setLayout(let id):
            // #119: a binding naming a layout that is gone (or never was) must not leave the
            // workspace on a missing id — that is a warning badge, not a layout.
            guard layouts[id] != nil, screen.active.layout != id else { return (w, []) }
            w.screens[sid]!.workspaces[screen.activeIndex].layout = id
            effects.append(.relayout)

        case .focusTab(let n):
            let row = screen.active.windows
            guard !row.isEmpty else { return (w, []) }
            let r = row[min(max(n, 1), row.count) - 1]
            if w.hidden.contains(r) { w.hidden.remove(r); effects.append(.unhide(r)) }
            setFocus(r); effects.append(.relayout)

        case .toggleFloat:
            guard let f = w.focus.window, screen.active.windows.contains(f) else { return fail(.noFocusedWindow) }
            w.setFloating(f, !screen.active.floating.contains(f))
            w.normalize()
            effects.append(.relayout)

        case .toggleFloatRef(let r):
            guard let loc = w.location(of: r) else { return fail(.unknownWindow(r)) }
            w.setFloating(r, !w.screens[loc.screen]!.workspaces[loc.index].floating.contains(r))
            w.normalize()
            effects.append(.relayout)

        // M3 B3, the rail's menus (#111, #112).
        case .setWorkspaceCategory(let id, let category):
            // The trailing "+" is the way down, not a workspace with an identity.
            guard let loc = w.location(ofWorkspace: id), !w.isTrailingEmpty(loc) else { return (w, []) }
            for i in w.screens[loc.screen]!.workspaces.indices {
                if i == loc.index { w.screens[loc.screen]!.workspaces[i].category = category }
                else if category != nil, w.screens[loc.screen]!.workspaces[i].category == category {
                    w.screens[loc.screen]!.workspaces[i].category = nil
                }
            }
            effects.append(.relayout)

        case .setWorkspaceSymbol(let id, let symbol):
            guard let loc = w.location(ofWorkspace: id), !w.isTrailingEmpty(loc) else { return (w, []) }
            w.screens[loc.screen]!.workspaces[loc.index].symbol = symbol
            effects.append(.relayout)

        case .removeWorkspace(let id):
            guard let loc = w.location(ofWorkspace: id), !w.isTrailingEmpty(loc) else { return (w, []) }
            var s = w.screens[loc.screen]!
            // Never out of range: a row that is not the trailing empty always has one below it.
            let into = loc.index > 0 ? loc.index - 1 : loc.index + 1
            let gone = s.workspaces[loc.index]
            let wasActive = loc.index == s.activeIndex
            let keep = wasActive ? s.workspaces[into].id : s.active.id
            s.workspaces[into].windows += gone.windows
            s.workspaces[into].floating.formUnion(gone.floating)
            if wasActive, let a = gone.anchor { s.workspaces[into].anchor = a }
            s.workspaces.remove(at: loc.index)
            s.activeIndex = s.workspaces.firstIndex { $0.id == keep }!
            w.screens[loc.screen] = s
            // Focus follows the windows: the focused one is still focused, now in the merged row;
            // with none, normalize() lands on the merged row's anchor, the removed row's.
            w.normalize()
            if wasActive, w.focus.screen == loc.screen, let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .reloadConfig, .showAbout, .quit:
            break   // app-layer (#111), like `.openSettings`
        }
        return (w, effects)
    }
}

extension World {
    /// #112: the trailing "+" row (invariant 4), which the rail menus' verbs refuse.
    func isTrailingEmpty(_ loc: (screen: DisplayID, index: Int)) -> Bool {
        guard let rows = screens[loc.screen]?.workspaces else { return false }
        return loc.index == rows.count - 1 && rows[loc.index].isEmpty && !rows[loc.index].pinned
    }
}
