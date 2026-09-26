import Foundation

public struct PersistedState: Codable, Equatable, Sendable {
    /// #128: one tab of a row, as it survives a relaunch — the app and the window's last title,
    /// which is all that outlives the process (a `WindowRef` does not). Restored as a placeholder
    /// in its slot until a live window of the app takes it (`PlaceholderMatch`).
    public struct SavedWindow: Codable, Equatable, Sendable {
        public var bundleID: String
        public var title: String
        /// Written only when true, like every optional here.
        public var floating: Bool?
        /// #129: a pinned tab. Written only when true, so a file from before #129 reads as unpinned.
        public var pinned: Bool?
        public init(bundleID: String, title: String, floating: Bool? = nil, pinned: Bool? = nil) {
            self.bundleID = bundleID; self.title = title; self.floating = floating; self.pinned = pinned
        }
    }
    public struct WorkspaceState: Codable, Equatable, Sendable {
        public var id: UUID; public var name: String; public var symbol: String; public var layout: LayoutID; public var pinned: Bool
        /// #74's row marker. Optional, so a state file from before it decodes as nil.
        public var category: AppCategory?
        /// #113: the row's resized layouts. Optional, so older state files decode and a row with
        /// none writes nothing.
        public var portions: [String: Portions]?
        /// #114: split's column count; nil (not written) at the default, so older files decode.
        public var splitColumns: Int?
        /// #128: the row's tabs, in order — live windows and placeholders alike. Nil (not written)
        /// for a row with none, so older files decode and a file with no windows is unchanged.
        public var windows: [SavedWindow]?
    }
    public struct ScreenState: Codable, Equatable, Sendable {
        public var workspaces: [WorkspaceState]; public var activeIndex: Int
    }
    public var version: Int = 1
    public var screens: [DisplayID: ScreenState]
    /// M2 design ruling: Zen survives relaunch. `decodeIfPresent ?? false` keeps M1 state files
    /// loading; version stays 1.
    public var zen: Bool = false
    /// Where each app's windows were when we quit: bundle id → workspace id.
    ///
    /// A `WindowRef` is a pid plus a window id and both die with the process, so nothing about a
    /// window itself survives a relaunch. The bundle id does, and it is the key the store already
    /// resolves. One entry per app, not per window: the windows of one app are interchangeable at
    /// adoption time — we cannot tell which of tomorrow's windows is which of today's, and titles
    /// are per-document, so a finer key would mostly miss and place nothing.
    ///
    /// `decodeIfPresent ?? [:]` keeps older state files loading; version stays 1 (an old build
    /// reading a new file ignores the key it does not know).
    public var placements: [String: UUID] = [:]
    /// #98: bundle ids whose placement the user set by moving the whole app; it beats category
    /// routing for them. `decodeIfPresent ?? []`, like `placements`.
    public var movedApps: Set<String> = []

    /// `bundleIDs` and `titles` are the store's side tables (#128): a live window is saved only
    /// if its app is known; a placeholder carries its own.
    public init(world: World, placements: [String: UUID] = [:], movedApps: Set<String> = [],
                bundleIDs: [WindowRef: String] = [:], titles: [WindowRef: String] = [:]) {
        func saved(_ ws: Workspace) -> [SavedWindow]? {
            let rows = ws.windows.compactMap { w -> SavedWindow? in
                let floating: Bool? = ws.floating.contains(w) ? true : nil
                let pinned: Bool? = world.pinnedTabs.contains(w) ? true : nil
                if let p = world.placeholders[w] { return SavedWindow(bundleID: p.bundleID, title: p.title, floating: floating, pinned: pinned) }
                return bundleIDs[w].map { SavedWindow(bundleID: $0, title: titles[w] ?? "", floating: floating, pinned: pinned) }
            }
            return rows.isEmpty ? nil : rows
        }
        screens = world.screens.mapValues { s in
            ScreenState(workspaces: s.workspaces.map { WorkspaceState(id: $0.id, name: $0.name, symbol: $0.symbol, layout: $0.layout, pinned: $0.pinned, category: $0.category,
                                                          portions: $0.portions.isEmpty ? nil : $0.portions,
                                                          splitColumns: $0.splitColumns == SplitView.defaultColumns ? nil : $0.splitColumns,
                                                          windows: saved($0)) },
                        activeIndex: s.activeIndex)
        }
        zen = world.zen
        self.placements = placements
        self.movedApps = movedApps
    }

    /// The placement memory a world implies right now. Apps with no windows contribute nothing —
    /// there is nothing to put back — so the map only ever describes what was actually on screen.
    public static func placements(world: World, bundleIDs: [WindowRef: String]) -> [String: UUID] {
        var p: [String: UUID] = [:]
        for id in world.screenOrder {
            for ws in world.screens[id]?.workspaces ?? [] {
                for w in ws.windows { if let bundle = bundleIDs[w] { p[bundle] = ws.id } }
            }
        }
        return p
    }

    enum CodingKeys: String, CodingKey { case version, screens, zen, placements, movedApps }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        screens = try c.decode([DisplayID: ScreenState].self, forKey: .screens)
        zen = try c.decodeIfPresent(Bool.self, forKey: .zen) ?? false
        placements = try c.decodeIfPresent([String: UUID].self, forKey: .placements) ?? [:]
        movedApps = try c.decodeIfPresent(Set<String>.self, forKey: .movedApps) ?? []
    }
    /// Written only when there is one, so a state file with no whole-app move is byte-for-byte
    /// what it was before #98.
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version); try c.encode(screens, forKey: .screens)
        try c.encode(zen, forKey: .zen); try c.encode(placements, forKey: .placements)
        if !movedApps.isEmpty { try c.encode(movedApps.sorted(), forKey: .movedApps) }
    }

    /// Re-creates, empty, the workspaces on screens the state knows that are either pinned or
    /// named by `placements` — the ones some app has to come back to. Those are marked `reserved`
    /// so `normalize()` does not reap them before their windows are adopted. Every other unpinned
    /// workspace is still dropped (nothing is coming back to it); trailing empty and invariants
    /// restored by normalize().
    ///
    /// Topology changed while we were not running (#13, spec §7.8): screens are matched by display
    /// UUID, never by arrangement order. A display that is gone brings its workspaces to `main`
    /// (the unplug ruling: appended in order above the trailing empty), so the apps remembered
    /// there still have somewhere to come back to — except pinned rows whose name `main` already
    /// has, which are just the config's seeds twice over. A display the state has never seen keeps
    /// the stack the caller seeded it with: nobody else's workspaces.
    ///
    /// `order` is `Config.categoryOrder`: category rows go back to the top in that order (#74,
    /// `World.sortCategoryRows`), undoing any drag of one last session.
    ///
    /// #128: every saved tab comes back as a placeholder in its slot, so a row that held windows
    /// is kept even when no placement names it — its placeholders hold it open, and `reserved` is
    /// moot. A live window that turns up takes its slot (`PlaceholderMatch`); one that never does
    /// stays a placeholder until the user closes it.
    public func restore(into world: World, main: DisplayID? = nil, order: [AppCategory] = []) -> World {
        var w = world
        w.zen = zen
        let wanted = Set(placements.values)
        let slots = Dictionary(screens.values.flatMap(\.workspaces).compactMap { ws in ws.windows.map { (ws.id, $0) } },
                               uniquingKeysWith: { a, _ in a })
        func kept(_ ss: ScreenState) -> [Workspace] {
            ss.workspaces.filter { $0.pinned || wanted.contains($0.id) || slots[$0.id] != nil }.map {
                Workspace(id: $0.id, name: $0.name, symbol: $0.symbol, layout: $0.layout,
                          pinned: $0.pinned, reserved: wanted.contains($0.id), category: $0.category,
                          portions: $0.portions ?? [:], splitColumns: $0.splitColumns ?? SplitView.defaultColumns)
            }
        }
        for (id, ss) in screens {
            guard var screen = w.screens[id] else { continue }
            let restored = kept(ss)
            let names = Set(restored.filter(\.pinned).map(\.name))
            let existing = screen.workspaces.filter { !$0.isEmpty || $0.pinned }
            let ids = Set(restored.map(\.id))
            screen.workspaces = restored + existing.filter { !ids.contains($0.id) && !($0.pinned && names.contains($0.name)) }
            screen.activeIndex = min(max(ss.activeIndex, 0), max(screen.workspaces.count - 1, 0))
            w.screens[id] = screen
        }
        let gone = screens.keys.filter { w.screens[$0] == nil }.sorted()
        if let m = main.flatMap({ w.screens[$0] == nil ? nil : $0 }) ?? w.screenOrder.first, var s = w.screens[m], !gone.isEmpty {
            let names = Set(s.workspaces.filter(\.pinned).map(\.name))
            let moved = gone.flatMap { kept(screens[$0]!) }.filter { wanted.contains($0.id) || slots[$0.id] != nil || !names.contains($0.name) }
            let trailing = s.workspaces.last.map { $0.isEmpty && !$0.pinned && !$0.reserved } ?? false
            let at = trailing ? s.workspaces.count - 1 : s.workspaces.count
            s.workspaces.insert(contentsOf: moved, at: at)
            if s.activeIndex >= at { s.activeIndex += moved.count }
            w.screens[m] = s
        }
        for (id, saved) in slots {
            for s in saved {
                w.addPlaceholder(Placeholder(bundleID: s.bundleID, title: s.title), floating: s.floating == true,
                                 pinned: s.pinned == true, to: id)
            }
        }
        w.sortCategoryRows(order)
        w.normalize()
        return w
    }

    /// The degraded termination path (#128): a world exported without the store's side tables
    /// cannot name its live windows' apps, so each row keeps the tabs the last good save gave it
    /// rather than coming back without them.
    public mutating func keepWindows(from saved: PersistedState) {
        let before = Dictionary(saved.screens.values.flatMap(\.workspaces).map { ($0.id, $0.windows) }, uniquingKeysWith: { a, _ in a })
        for (d, ss) in screens {
            for i in ss.workspaces.indices where ss.workspaces[i].windows == nil {
                screens[d]!.workspaces[i].windows = before[ss.workspaces[i].id] ?? nil
            }
        }
    }

    public static func load(from url: URL) throws -> PersistedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: url))
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}

extension World {
    /// Empty world where every screen starts with the config's pinned workspaces, then a trailing empty.
    public static func seeded(screens ids: [DisplayID], config: Config) -> World {
        var w = World.empty(screens: ids, defaultLayout: config.defaultLayout)
        for id in ids {
            let seeds = config.workspaces.map { Workspace(name: $0.name, symbol: $0.symbol, layout: $0.layout, pinned: true) }
            w.screens[id]!.workspaces = seeds + w.screens[id]!.workspaces
            w.screens[id]!.activeIndex = 0
        }
        w.normalize()
        return w
    }
}
