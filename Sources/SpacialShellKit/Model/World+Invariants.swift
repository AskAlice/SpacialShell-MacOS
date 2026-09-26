import Foundation

extension World {
    /// Spec §4.2. Empty array == all invariants hold.
    public func invariantViolations() -> [String] {
        var v: [String] = []
        if Set(screenOrder) != Set(screens.keys) { v.append("screenOrder \(screenOrder) != screens \(screens.keys.sorted())") }
        var seen: [WindowRef: String] = [:]
        for (id, s) in screens {
            guard !s.workspaces.isEmpty else { v.append("\(id): no workspaces"); continue }
            guard (0..<s.workspaces.count).contains(s.activeIndex) else { v.append("\(id): activeIndex \(s.activeIndex) out of range"); continue }
            if !s.workspaces.last!.isEmpty { v.append("\(id): last workspace not empty") }
            for (i, ws) in s.workspaces.enumerated() {
                let last = i == s.workspaces.count - 1
                if ws.isEmpty && !last && i != s.activeIndex && !ws.pinned && !ws.reserved { v.append("\(id)[\(i)]: empty, unpinned, unreserved, non-trailing, non-active") }
                if Set(ws.windows).count != ws.windows.count { v.append("\(id)[\(i)]: duplicate windows") }
                for w in ws.windows {
                    if let prev = seen[w] { v.append("\(w) in \(prev) and \(id)[\(i)]") }
                    seen[w] = "\(id)[\(i)]"
                    if ephemeral.contains(w) { v.append("\(w) both placed and ephemeral") }
                    if ignored.contains(w) { v.append("\(w) both placed and ignored") }
                }
                for f in ws.floating where !ws.windows.contains(f) { v.append("\(id)[\(i)]: floating \(f) not in windows") }
                if let a = ws.anchor, !ws.windows.contains(a) { v.append("\(id)[\(i)]: anchor \(a) not in windows") }
            }
        }
        for w in ephemeral where ignored.contains(w) { v.append("\(w) both ephemeral and ignored") }
        // #128: a placeholder is a tab and nothing else — placed, and never anything a window is.
        for (p, _) in placeholders {
            if !p.isPlaceholder { v.append("\(p) is a placeholder with a window's pid") }
            if seen[p] == nil { v.append("placeholder \(p) not placed") }
            if hidden.contains(p) || fullscreen.contains(p) || offSpace.contains(p) || ephemeral.contains(p) || ignored.contains(p) {
                v.append("placeholder \(p) carries window state")
            }
        }
        for (w, at) in seen where w.isPlaceholder && placeholders[w] == nil { v.append("\(w) in \(at) is a placeholder ref with no placeholder") }
        for s in screens.values { for ws in s.workspaces where ws.anchor?.isPlaceholder == true { v.append("placeholder \(ws.anchor!) is an anchor") } }
        for w in hidden where seen[w] == nil { v.append("\(w) hidden but not placed") }
        for w in fullscreen where seen[w] == nil { v.append("\(w) fullscreen but not placed") }
        for w in offSpace where seen[w] == nil { v.append("\(w) off-Space but not placed") }
        // I6, model half (M3a roadmap): a window cannot be both put away and filling a display.
        // The states come from different sources — `AXMinimized`/app-hidden vs `AXFullScreen` — so
        // holding both means a snapshot was applied out of order, and whichever the layout believes
        // leaves the window unreachable: skipped as hidden, or skipped as macOS-owned.
        for w in fullscreen where hidden.contains(w) { v.append("\(w) both fullscreen and hidden") }
        guard let fs = screens[focus.screen] else { v.append("focus.screen \(focus.screen) unknown"); return v }
        if let w = focus.window {
            if w.isPlaceholder { v.append("focus \(w) is a placeholder") }
            if !fs.active.windows.contains(w) && !ephemeral.contains(w) { v.append("focus \(w) not in active workspace of \(focus.screen) nor ephemeral") }
            if hidden.contains(w) { v.append("focus \(w) is hidden") }
        }
        return v
    }
}
