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
        for w in hidden where seen[w] == nil { v.append("\(w) hidden but not placed") }
        for w in fullscreen where seen[w] == nil { v.append("\(w) fullscreen but not placed") }
        guard let fs = screens[focus.screen] else { v.append("focus.screen \(focus.screen) unknown"); return v }
        if let w = focus.window {
            if !fs.active.windows.contains(w) && !ephemeral.contains(w) { v.append("focus \(w) not in active workspace of \(focus.screen) nor ephemeral") }
            if hidden.contains(w) { v.append("focus \(w) is hidden") }
        }
        return v
    }
}
