import Foundation
import SpacialShellProtocol

/// #128 (M3 B4, part 2): a tab standing in for a window that is not running — material-shell's
/// app placeholder (P25, S8) and Veshell's `PersistentWindow.placeholder`.
///
/// Every window saved in `state.json` comes back as one of these, in its slot, and stays until a
/// live window of its app takes the slot (`PlaceholderMatch`) or the user closes it. It is a tab
/// and nothing more: it has no window, so the layout never gives it a tile, focus never lands on
/// it, and the reconciler never writes to it. That is how I6 holds by construction — a placeholder
/// cannot cover, displace or hide a live window, because it takes no space on screen.
///
/// It lives in `Workspace.windows` under a `WindowRef` of its own (`isPlaceholder`), so a slot is
/// a position in the row like any other: tab drags, rail drops and "Move to workspace" move it
/// with no special case, and a match puts the live window exactly where it stood.
public struct Placeholder: Codable, Equatable, Sendable {
    public var bundleID: String
    /// The window's last title, for the tab and for matching; "" when it had none.
    public var title: String
    /// Its tab was clicked, so its app was asked to launch: the app's next window fills this
    /// placeholder before any other of the app's (material-shell S9, "preferring placeholders that
    /// are waiting for a launch"). Cleared by the match.
    public var launching: Bool
    public init(bundleID: String, title: String, launching: Bool = false) {
        self.bundleID = bundleID; self.title = title; self.launching = launching
    }
}

extension WindowRef {
    /// A placeholder's ref has a negative pid, which no process has. That lets any layer tell a
    /// placeholder from a window without the model at hand — the reconciler, the thumbnail
    /// refresher, the UI.
    public var isPlaceholder: Bool { pid < 0 }

    /// The pid every placeholder of `bundleID` carries: negative, and the same for one app, so the
    /// rail draws one icon per app exactly as it does for live windows (by pid). Derived from the
    /// bundle id (FNV-1a), not minted, so it is stable across relaunches and needs no counter.
    public static func placeholderPid(bundleID: String) -> Int32 {
        var h: UInt32 = 2_166_136_261
        for b in bundleID.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return -Int32(h % UInt32(Int32.max - 1)) - 1
    }
}

extension World {
    /// A fresh placeholder ref for `bundleID`: that app's placeholder pid, and an id no other
    /// placeholder of the app holds.
    func mintPlaceholderRef(bundleID: String) -> WindowRef {
        let pid = WindowRef.placeholderPid(bundleID: bundleID)
        let taken = placeholders.keys.filter { $0.pid == pid }.map(\.id)
        return WindowRef(id: (taken.max() ?? 0) + 1, pid: pid)
    }

    /// Appends a placeholder to the end of workspace `id`'s row (restore builds rows slot by slot,
    /// so appending is "in its slot"). Returns its ref, or nil when the workspace is gone.
    @discardableResult
    public mutating func addPlaceholder(_ p: Placeholder, floating: Bool = false, pinned: Bool = false, to id: UUID) -> WindowRef? {
        guard let loc = location(ofWorkspace: id) else { return nil }
        let ref = mintPlaceholderRef(bundleID: p.bundleID)
        placeholders[ref] = p
        screens[loc.screen]!.workspaces[loc.index].windows.append(ref)
        if floating { screens[loc.screen]!.workspaces[loc.index].floating.insert(ref) }
        if pinned { pinnedTabs.insert(ref) }
        return ref
    }

    /// #129 (material-shell P17): pinned window `w` has closed — its tab turns back into a
    /// placeholder in the same slot (same row, same position, floating if it was, still pinned)
    /// instead of disappearing. Focus leaves it exactly as it leaves a closed window: to the
    /// neighbour. Returns the placeholder, or nil when `w` is not a pinned window in a row, in
    /// which case nothing changes and the caller removes it the ordinary way.
    @discardableResult
    public mutating func leavePlaceholder(for w: WindowRef, bundleID: String, title: String) -> WindowRef? {
        guard pinnedTabs.contains(w), !w.isPlaceholder, let loc = location(of: w) else { return nil }
        var ws = screens[loc.screen]!.workspaces[loc.index]
        let next = neighbour(of: w, in: ws)
        let p = mintPlaceholderRef(bundleID: bundleID)
        ws.windows[ws.windows.firstIndex(of: w)!] = p
        if ws.floating.remove(w) != nil { ws.floating.insert(p) }
        if ws.anchor == w { ws.anchor = nil }
        screens[loc.screen]!.workspaces[loc.index] = ws
        placeholders[p] = Placeholder(bundleID: bundleID, title: title)
        pinnedTabs.remove(w); pinnedTabs.insert(p)
        hidden.remove(w); fullscreen.remove(w); offSpace.remove(w); parents[w] = nil
        parents = parents.filter { $0.value != w }
        if focus.window == w { focus.window = next }
        normalize()
        return p
    }

    /// The placeholders, in rail order: displays left→right, workspaces top→bottom, tabs
    /// left→right. The order matching breaks ties in.
    public func placeholdersInOrder() -> [(ref: WindowRef, placeholder: Placeholder)] {
        screenOrder.flatMap { sid in
            (screens[sid]?.workspaces ?? []).flatMap { ws in
                ws.windows.compactMap { r in placeholders[r].map { (r, $0) } }
            }
        }
    }

    /// #128: live window `w`, seen for the first time, takes placeholder `p`'s slot — same row,
    /// same position, and floating if the placeholder was (or the window's own kind says so). It
    /// is adopted like any window otherwise: it takes focus only where `adopt` would give it.
    /// No-op unless `p` is a placeholder in a row and `w` is a window the model does not hold yet.
    public mutating func fill(_ p: WindowRef, with w: WindowRef, kind: WindowKind) {
        guard placeholders[p] != nil, let loc = location(of: p), location(of: w) == nil,
              !w.isPlaceholder, !ephemeral.contains(w), !ignored.contains(w),
              kind == .tile || kind == .float else { return }
        var ws = screens[loc.screen]!.workspaces[loc.index]
        ws.windows[ws.windows.firstIndex(of: p)!] = w
        if ws.floating.remove(p) != nil || kind == .float { ws.floating.insert(w) }
        screens[loc.screen]!.workspaces[loc.index] = ws
        placeholders[p] = nil
        if pinnedTabs.remove(p) != nil { pinnedTabs.insert(w) }   // #129: the pin stays with the slot
        if focus.window == nil, loc.screen == focus.screen, loc.index == screens[loc.screen]!.activeIndex { focus.window = w }
        normalize()
    }
}

/// #128: which placeholder each newly seen window fills — the Veshell / material-shell matching
/// (S9), on the identity #18 made public: the app's bundle id. A window never matches a
/// placeholder of another app; among the app's placeholders it prefers, in order:
///
/// 1. one with **the same title** (a document window reopening on the same document);
/// 2. one **waiting for a launch** (its tab was clicked — the user said where the window goes);
/// 3. the **earliest in rail order** (sequence: the app's windows come back in the order they were).
///
/// Material-shell ranks by minimum total cost with these same keys; greedy in this order gives the
/// same answer because each key strictly dominates the next. Windows are taken in snapshot order.
/// ponytail: no pid key (a placeholder does not remember one) and no re-shuffle while titles
/// settle (material-shell allows 3 s); a window whose title arrives late matches by sequence.
public enum PlaceholderMatch {
    public struct Arrival: Equatable, Sendable {
        public let ref: WindowRef
        public let bundleID: String
        public let title: String
        public init(ref: WindowRef, bundleID: String, title: String) {
            self.ref = ref; self.bundleID = bundleID; self.title = title
        }
    }

    /// Window → the placeholder it fills. Windows with no placeholder of their app are absent.
    public static func match(_ arrivals: [Arrival], in world: World) -> [WindowRef: WindowRef] {
        var free = world.placeholdersInOrder()
        var out: [WindowRef: WindowRef] = [:]
        func take(_ a: Arrival, where ok: (Placeholder) -> Bool) {
            let candidates = free.indices.filter { free[$0].placeholder.bundleID == a.bundleID && ok(free[$0].placeholder) }
            guard let i = candidates.first(where: { free[$0].placeholder.launching }) ?? candidates.first else { return }
            out[a.ref] = free.remove(at: i).ref
        }
        for a in arrivals where !a.title.isEmpty { take(a) { $0.title == a.title } }
        for a in arrivals where out[a.ref] == nil { take(a) { _ in true } }
        return out
    }
}
