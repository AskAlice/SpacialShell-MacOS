import Foundation

public enum CommandRunner {
    public static func apply(_ command: Command, to input: World) -> (World, [Effect]) {
        var w = input
        var effects: [Effect] = []
        let sid = w.focus.screen
        guard let screen = w.screens[sid] else { return (w, []) }

        /// Move one window out of the workspace it is in and onto the end of `to`, carrying its
        /// pin, and follow it. The keyboard verb and a dragged tab differ only in how they name
        /// the destination, so they share this outright rather than drifting apart.
        func move(_ ref: WindowRef, to dest: (screen: DisplayID, index: Int)) -> Bool {
            guard let from = w.location(of: ref) else { return false }
            guard from.screen != dest.screen || from.index != dest.index else { return false }
            let wasFloating = w.screens[from.screen]!.workspaces[from.index].floating.contains(ref)
            w.screens[from.screen]!.workspaces[from.index].windows.removeAll { $0 == ref }
            w.screens[from.screen]!.workspaces[from.index].floating.remove(ref)
            w.screens[dest.screen]!.workspaces[dest.index].windows.append(ref)
            if wasFloating { w.screens[dest.screen]!.workspaces[dest.index].floating.insert(ref) }
            w.screens[dest.screen]!.workspaces[dest.index].anchor = ref
            w.screens[dest.screen]!.activeIndex = dest.index
            w.focus = Focus(screen: dest.screen, window: ref)
            w.normalize()
            return true
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

        switch command {
        case .focusWindow(let dir):
            let vis = w.visible(in: screen.active)
            guard !vis.isEmpty else { return (w, []) }
            let i = w.focus.window.flatMap { vis.firstIndex(of: $0) } ?? 0
            let j = dir == .right ? (i + 1) % vis.count : (i - 1 + vis.count) % vis.count
            setFocus(vis[j]); effects.append(.relayout)

        case .focusWorkspace(let dir):
            let target = screen.activeIndex + (dir == .down ? 1 : -1)
            guard (0..<screen.workspaces.count).contains(target) else { return (w, []) }
            leaveFullscreen(on: sid)
            w.activate(index: target, on: sid)
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .focusWorkspaceIndex(let n):
            let target = n - 1
            guard (0..<screen.workspaces.count).contains(target), target != screen.activeIndex else { return (w, []) }
            leaveFullscreen(on: sid)
            w.activate(index: target, on: sid)
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .closeFocusedWindow:
            if let f = w.focus.window { effects.append(.close(f)) }

        case .moveWindow(let dir):
            guard let f = w.focus.window, var ws = Optional(screen.active), let i = ws.windows.firstIndex(of: f) else { return (w, []) }
            let j = dir == .right ? i + 1 : i - 1
            guard (0..<ws.windows.count).contains(j) else { return (w, []) }
            ws.windows.swapAt(i, j)
            // `maximize` paints only the focused window (LayoutEngine), and the focus travels with
            // the window as it moves — so the same window stays on screen at the same rect and the
            // move is invisible, however real it is in the row. The verb means "put this beside
            // that", so it promotes to `split`, the narrowest layout that can show the pair.
            // Layouts that already show more than one window are the user's choice; leave them.
            // Placed after the bounds guard: a refused move must change nothing, layout included.
            if ws.layout == .maximize { ws.layout = .split }
            w.screens[sid]!.workspaces[screen.activeIndex] = ws
            effects.append(.relayout)

        case .moveWindowToWorkspace(let dir):
            guard let f = w.focus.window, screen.active.windows.contains(f) else { return (w, []) }
            let target = screen.activeIndex + (dir == .down ? 1 : -1)
            guard (0..<screen.workspaces.count).contains(target) else { return (w, []) }
            guard move(f, to: (sid, target)) else { return (w, []) }
            effects.append(.focus(f)); effects.append(.relayout)

        case .moveWindowRefToWorkspace(let ref, let workspace):
            // Dropping on the rail's "+" needs no special case: the trailing empty workspace is a
            // workspace like any other, and normalize() grows a fresh "+" underneath it the moment
            // it stops being empty (invariant 4) — the same thing that makes clicking "+" work.
            guard let dest = w.location(ofWorkspace: workspace) else { return (w, []) }
            guard move(ref, to: dest) else { return (w, []) }
            effects.append(.focus(ref)); effects.append(.relayout)

        case .moveWindowRefBefore(let ref, let before):
            // A row operation, not a focus one: dragging a tab into a new position must not take
            // focus away from whatever the user was actually working in.
            guard let from = w.location(of: ref) else { return (w, []) }
            var row = w.screens[from.screen]!.workspaces[from.index].windows
            guard let i = row.firstIndex(of: ref) else { return (w, []) }
            // Resolve the destination before removing, so `before` is still findable; then convert
            // to a post-removal index so the insert cannot be off by one.
            let target: Int
            if let before {
                guard before != ref, let j = row.firstIndex(of: before) else { return (w, []) }
                target = j > i ? j - 1 : j
            } else {
                target = row.count - 1
            }
            guard target != i else { return (w, []) }
            row.remove(at: i)
            row.insert(ref, at: target)
            w.screens[from.screen]!.workspaces[from.index].windows = row
            effects.append(.relayout)

        case .cycleLayout:
            w.screens[sid]!.workspaces[screen.activeIndex].layout = screen.active.layout.next
            effects.append(.relayout)

        case .toggleShellUI:
            // Zen (M2 design ruling): one bit, one verb; the reconciler reads it for the insets.
            w.zen.toggle()
            effects.append(.relayout)

        case .focusWorkspaceID(let id):
            guard let loc = w.location(ofWorkspace: id) else { return (w, []) }
            // Focus moves to the clicked screen first so `activate` re-derives the focused window
            // from that workspace's anchor, exactly as the keyboard path does.
            if w.focus.screen != loc.screen { w.focus = Focus(screen: loc.screen, window: nil) }
            if w.screens[loc.screen]?.activeIndex != loc.index { leaveFullscreen(on: loc.screen) }
            w.activate(index: loc.index, on: loc.screen)
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .focusWindowRef(let r):
            if w.ephemeral.contains(r) { w.focus.window = r; return (w, [.focus(r)]) }
            guard let loc = w.location(of: r) else { return (w, []) }
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
            guard let loc = w.location(ofWorkspace: id) else { return (w, []) }
            w.screens[loc.screen]!.workspaces[loc.index].layout = l
            effects.append(.relayout)

        case .closeWindowRef(let r):
            effects.append(.close(r))

        case .rescueWindows:
            // Geometry only: the store sweeps `observed` against the displays. Relayout so the
            // sweep runs inside the ordinary reconcile.
            effects.append(.relayout)

        case .toggleOverview, .openSettings:
            // App-layer surfaces; AppRuntime routes them before the store, and if one does reach
            // the store anyway (custom wiring, tests) it must change nothing.
            break

        case .focusScreen(let n):
            guard w.screenOrder.count > 1, let i = w.screenOrder.firstIndex(of: sid) else { return (w, []) }
            let j = n == .next ? (i + 1) % w.screenOrder.count : (i - 1 + w.screenOrder.count) % w.screenOrder.count
            w.focus = Focus(screen: w.screenOrder[j], window: nil)
            w.normalize()
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .moveWindowToScreen(let n):
            guard let f = w.focus.window, screen.active.windows.contains(f), w.screenOrder.count > 1,
                  let i = w.screenOrder.firstIndex(of: sid) else { return (w, []) }
            let j = n == .next ? (i + 1) % w.screenOrder.count : (i - 1 + w.screenOrder.count) % w.screenOrder.count
            let target = w.screenOrder[j]
            let wasFloating = screen.active.floating.contains(f)
            w.screens[sid]!.workspaces[screen.activeIndex].windows.removeAll { $0 == f }
            w.screens[sid]!.workspaces[screen.activeIndex].floating.remove(f)
            let ti = w.screens[target]!.activeIndex
            w.screens[target]!.workspaces[ti].windows.append(f)
            if wasFloating { w.screens[target]!.workspaces[ti].floating.insert(f) }
            w.screens[target]!.workspaces[ti].anchor = f
            w.focus = Focus(screen: target, window: f)
            w.normalize()
            effects.append(.focus(f)); effects.append(.relayout)

        case .toggleFloat:
            guard let f = w.focus.window, screen.active.windows.contains(f) else { return (w, []) }
            w.setFloating(f, !screen.active.floating.contains(f))
            w.normalize()
            effects.append(.relayout)
        }
        return (w, effects)
    }
}
