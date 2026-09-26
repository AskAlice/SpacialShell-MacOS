import Foundation

public struct SetLayoutRefusal: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// `spacialctl state` payload — workspaces, and since v2 the windows in them.
/// ponytail: superseded by ShellSnapshot (M2 Task 8), which adds titles/appNames/chrome.
public struct WireState: Codable, Equatable, Sendable {
    /// One managed window, as the model sees it (#57). Counts alone could not answer the question
    /// that mattered — *which* window is where, and is it parked — so diagnosing a window that
    /// holds focus while sitting off-screen meant reading the window server instead of asking the
    /// shell. `isParked` and `frame` are the store's own view, not AX's: when they disagree with
    /// reality, that disagreement is the bug.
    public struct WindowDTO: Codable, Equatable, Sendable {
        public var id: WindowID
        public var pid: Int32
        public var bundleID: String?
        public var isFocused: Bool
        public var isFloating: Bool
        public var isHidden: Bool
        public var isFullscreen: Bool
        public var isOffSpace: Bool
        public var isParked: Bool
        public var frame: [Double]?      // x, y, w, h — the last frame the backend observed
    }
    public struct WorkspaceDTO: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String, symbol: String, layout: String
        public var pinned: Bool, isActive: Bool
        public var windowCount: Int
        public var windows: [WindowDTO]
    }
    public struct ScreenDTO: Codable, Equatable, Sendable {
        public var display: String
        public var isFocused: Bool
        public var activeIndex: Int
        public var workspaces: [WorkspaceDTO]
    }
    /// #9: one catalogue row. `zones` is nil for a built-in. A workspace whose `layout` is absent
    /// from `layouts` is unresolved — the shell is drawing its fallback — so there is no flag.
    public struct LayoutDTO: Codable, Equatable, Sendable {
        public var id: String, name: String, symbol: String?, builtin: Bool, zones: Int?
    }
    /// Additive changes only, so `v` stays 2 (#9 added `layouts` and its capability).
    public var v: Int = 2
    public static let capabilities = ["run", "state", "version", "window-rows", "layouts", "problems", "subscribe"]
    public var capabilities: [String] = WireState.capabilities
    public var screens: [ScreenDTO]
    /// The catalogue, built-ins first. Bar membership is UI-only and not sent.
    public var layouts: [LayoutDTO]
    /// #109: what the shell cannot do right now, errors first — the rail cog's badge, as data.
    public var problems: [Problem]

    /// `bundleIDs`, `parked` and `observed` are the store's side tables; a caller without them
    /// still gets every workspace, just with anonymous windows.
    public init(world: World, bundleIDs: [WindowRef: String] = [:],
                parked: Set<WindowRef> = [], observed: [WindowRef: CGRect] = [:],
                layouts: LayoutCatalogue = .builtins, problems: [Problem] = []) {
        self.problems = problems
        self.layouts = layouts.all.map { d in
            var zones: Int?
            if case .zones(let z) = d.body { zones = z.count }
            return LayoutDTO(id: d.id.rawValue, name: d.name, symbol: d.symbol, builtin: d.isBuiltin, zones: zones)
        }
        screens = world.screenOrder.compactMap { id in
            guard let s = world.screens[id] else { return nil }
            return ScreenDTO(
                display: id, isFocused: id == world.focus.screen, activeIndex: s.activeIndex,
                workspaces: s.workspaces.enumerated().map { i, ws in
                    WorkspaceDTO(id: ws.id, name: ws.name, symbol: ws.symbol, layout: ws.layout.rawValue,
                                 pinned: ws.pinned, isActive: i == s.activeIndex, windowCount: ws.windows.count,
                                 windows: ws.windows.map { w in
                                     WindowDTO(id: w.id, pid: w.pid, bundleID: bundleIDs[w],
                                               isFocused: world.focus.window == w,
                                               isFloating: ws.floating.contains(w),
                                               isHidden: world.hidden.contains(w),
                                               isFullscreen: world.fullscreen.contains(w),
                                               isOffSpace: world.offSpace.contains(w),
                                               isParked: parked.contains(w),
                                               frame: observed[w].map { [$0.minX, $0.minY, $0.width, $0.height] })
                                 })
                })
        }
    }

    /// #10, design §6: IPC `set-layout {layout, workspace?}` as the command it sends, or the error
    /// the caller gets back (`spacialctl` exits 1). An id the catalogue does not know is refused —
    /// the opposite of decoding on purpose: a live caller can be corrected, a file on disk is kept.
    /// No workspace means the active one on the focused display.
    public func setLayout(_ layout: String?, workspace: String?) -> Result<Command, SetLayoutRefusal> {
        guard let layout, !layout.isEmpty else { return .failure(SetLayoutRefusal("set-layout needs a layout id")) }
        guard layouts.contains(where: { $0.id == layout }) else {
            return .failure(SetLayoutRefusal("unknown layout \"\(layout)\" (known: \(layouts.map(\.id).joined(separator: ", ")))"))
        }
        let all = screens.flatMap(\.workspaces)
        let target: UUID?
        if let workspace {
            target = UUID(uuidString: workspace).flatMap { id in all.contains { $0.id == id } ? id : nil }
            guard target != nil else { return .failure(SetLayoutRefusal("unknown workspace \"\(workspace)\"")) }
        } else {
            target = screens.first(where: \.isFocused)?.workspaces.first(where: \.isActive)?.id
        }
        guard let target else { return .failure(SetLayoutRefusal("no active workspace")) }
        return .success(.setWorkspaceLayout(target, LayoutID(rawValue: layout)))
    }

    /// A pre-#9 payload has no `layouts`, a pre-#109 one no `problems`; both still decode.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        capabilities = try c.decode([String].self, forKey: .capabilities)
        screens = try c.decode([ScreenDTO].self, forKey: .screens)
        layouts = try c.decodeIfPresent([LayoutDTO].self, forKey: .layouts) ?? []
        problems = try c.decodeIfPresent([Problem].self, forKey: .problems) ?? []
    }
}
