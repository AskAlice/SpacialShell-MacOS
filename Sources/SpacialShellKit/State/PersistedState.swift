import Foundation

public struct PersistedState: Codable, Equatable, Sendable {
    public struct WorkspaceState: Codable, Equatable, Sendable {
        public var id: UUID; public var name: String; public var symbol: String; public var layout: Layout; public var pinned: Bool
        /// #74's row marker. Optional, so a state file from before it decodes as nil.
        public var category: AppCategory?
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

    public init(world: World, placements: [String: UUID] = [:]) {
        screens = world.screens.mapValues { s in
            ScreenState(workspaces: s.workspaces.map { WorkspaceState(id: $0.id, name: $0.name, symbol: $0.symbol, layout: $0.layout, pinned: $0.pinned, category: $0.category) },
                        activeIndex: s.activeIndex)
        }
        zen = world.zen
        self.placements = placements
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

    enum CodingKeys: String, CodingKey { case version, screens, zen, placements }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        screens = try c.decode([DisplayID: ScreenState].self, forKey: .screens)
        zen = try c.decodeIfPresent(Bool.self, forKey: .zen) ?? false
        placements = try c.decodeIfPresent([String: UUID].self, forKey: .placements) ?? [:]
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
    public func restore(into world: World, main: DisplayID? = nil) -> World {
        var w = world
        w.zen = zen
        let wanted = Set(placements.values)
        func kept(_ ss: ScreenState) -> [Workspace] {
            ss.workspaces.filter { $0.pinned || wanted.contains($0.id) }.map {
                Workspace(id: $0.id, name: $0.name, symbol: $0.symbol, layout: $0.layout,
                          pinned: $0.pinned, reserved: wanted.contains($0.id), category: $0.category)
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
            let moved = gone.flatMap { kept(screens[$0]!) }.filter { wanted.contains($0.id) || !names.contains($0.name) }
            let trailing = s.workspaces.last.map { $0.isEmpty && !$0.pinned && !$0.reserved } ?? false
            let at = trailing ? s.workspaces.count - 1 : s.workspaces.count
            s.workspaces.insert(contentsOf: moved, at: at)
            if s.activeIndex >= at { s.activeIndex += moved.count }
            w.screens[m] = s
        }
        w.normalize()
        return w
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
