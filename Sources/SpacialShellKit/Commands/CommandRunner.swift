import Foundation

public enum CommandRunner {
    public static func apply(_ command: Command, to input: World) -> (World, [Effect]) {
        var w = input
        var effects: [Effect] = []
        let sid = w.focus.screen
        guard let screen = w.screens[sid] else { return (w, []) }

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
            w.activate(index: target, on: sid)
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .focusWorkspaceIndex(let n):
            let target = n - 1
            guard (0..<screen.workspaces.count).contains(target), target != screen.activeIndex else { return (w, []) }
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
            let wasFloating = screen.active.floating.contains(f)
            w.screens[sid]!.workspaces[screen.activeIndex].windows.removeAll { $0 == f }
            w.screens[sid]!.workspaces[screen.activeIndex].floating.remove(f)
            w.screens[sid]!.workspaces[target].windows.append(f)
            if wasFloating { w.screens[sid]!.workspaces[target].floating.insert(f) }
            w.screens[sid]!.workspaces[target].anchor = f
            w.screens[sid]!.activeIndex = target
            w.focus.window = f
            w.normalize()
            effects.append(.focus(f)); effects.append(.relayout)

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
            w.activate(index: loc.index, on: loc.screen)
            if let f = w.focus.window { effects.append(.focus(f)) }
            effects.append(.relayout)

        case .focusWindowRef(let r):
            if w.ephemeral.contains(r) { w.focus.window = r; return (w, [.focus(r)]) }
            // A minimized/hidden window keeps its tab but a click cannot land focus on it: raising
            // it would not deminiaturize it, and focus must stay somewhere real (invariant 5).
            guard let loc = w.location(of: r), !w.hidden.contains(r) else { return (w, []) }
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
