import Foundation

/// #199: why `focus-window --app/--title` names no single window; `spacialctl` prints it, exit 1.
public struct FindWindowRefusal: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

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
        /// #128: set (true) only on a placeholder tab, whose pid is negative and owns no process.
        public var isPlaceholder: Bool? = nil
        /// #129: set (true) only on a pinned tab.
        public var isPinned: Bool? = nil
        /// #199: the window's title and its app's name, for clients that find a window by them.
        public var title: String? = nil
        public var appName: String? = nil
    }
    public struct WorkspaceDTO: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String, symbol: String, layout: String
        public var pinned: Bool, isActive: Bool
        public var windowCount: Int
        public var windows: [WindowDTO]
        /// #198: the title the row goes by in the shell (#183: its category, capitalised, else its
        /// name; "New workspace" for the trailing empty row). `name` stays the stored name.
        public var title: String? = nil
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
    /// Payload features: what `state` carries, not verbs.
    public static let features = ["window-rows", "layouts", "problems"]
    /// #131: every verb the socket answers (`IPCDispatch.verbs`) and every payload feature, and
    /// nothing else. The pre-#131 list stays in front, in its order; new strings are appended.
    public static let capabilities: [String] = {
        let legacy = ["run", "state", "version", "window-rows", "layouts", "problems", "subscribe"]
        return legacy + (IPCDispatch.verbs + features).filter { !legacy.contains($0) }
    }()
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
                titles: [WindowRef: String] = [:], appNames: [Int32: String] = [:],
                categoryOverrides: [String: AppCategory] = [:],
                layouts: LayoutCatalogue, problems: [Problem] = []) {
        // A row's category from its apps', as the rail and the spatial view work it out (#183).
        let bundleOf = Dictionary(bundleIDs.map { ($0.key.pid, $0.value) }, uniquingKeysWith: { a, _ in a })
        let categoryOf = { (pid: Int32) in AppCategories.category(bundleID: bundleOf[pid], overrides: categoryOverrides) }
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
                    let trailing = i == s.workspaces.count - 1 && ws.windows.isEmpty
                    let title = AppCategories.rowTitle(
                        name: ws.name, category: AppCategories.rowCategory(ws.category, windows: ws.windows, categoryOf: categoryOf),
                        isTrailingEmpty: trailing)
                    return WorkspaceDTO(id: ws.id, name: ws.name, symbol: ws.symbol, layout: ws.layout.rawValue,
                                 pinned: ws.pinned, isActive: i == s.activeIndex, windowCount: ws.windows.count,
                                 windows: ws.windows.map { w in
                                     WindowDTO(id: w.id, pid: w.pid, bundleID: world.placeholders[w]?.bundleID ?? bundleIDs[w],
                                               isFocused: world.focus.window == w,
                                               isFloating: ws.floating.contains(w),
                                               isHidden: world.hidden.contains(w),
                                               isFullscreen: world.fullscreen.contains(w),
                                               isOffSpace: world.offSpace.contains(w),
                                               isParked: parked.contains(w),
                                               frame: observed[w].map { [$0.minX, $0.minY, $0.width, $0.height] },
                                               isPlaceholder: w.isPlaceholder ? true : nil,
                                               isPinned: world.pinnedTabs.contains(w) ? true : nil,
                                               title: titles[w].flatMap { $0.isEmpty ? nil : $0 },
                                               appName: appNames[w.pid])
                                 },
                                 title: title)
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

    /// #199: the window `spacialctl focus-window --app … --title …` means. `app` matches the app's
    /// name (case-insensitive substring: "brave" is "Brave Origin"), its bundle id (exact, or the
    /// last component), or its pid; `title` is a case-insensitive substring of the window's title.
    /// Candidates are in display, row, tab order — the order an ambiguity lists them in and
    /// `index` (1-based) counts in. `first` takes the focused window if it matches, else one in the
    /// focused display's shown row, else the first listed. Placeholders (#128) are never matched.
    public func findWindow(app: String?, title: String?, index: Int?, first: Bool) -> Result<WindowRef, FindWindowRefusal> {
        let app = app?.trimmingCharacters(in: .whitespaces).lowercased(), title = title?.lowercased()
        guard (app?.isEmpty == false) || (title?.isEmpty == false) else {
            return .failure(FindWindowRefusal("focus-window needs --app, --title, or a window id"))
        }
        if index != nil && first { return .failure(FindWindowRefusal("--index and --first cannot be used together")) }
        struct Hit { let ref: WindowRef; let label: String; let focused: Bool; let shown: Bool }
        var hits: [Hit] = []
        for screen in screens {
            for (row, ws) in screen.workspaces.enumerated() {
                for w in ws.windows where w.isPlaceholder != true {
                    if let app {
                        let name = w.appName?.lowercased() ?? "", bundle = w.bundleID?.lowercased() ?? ""
                        let ok = name.contains(app) || bundle == app || bundle.hasSuffix("." + app) || String(w.pid) == app
                        if !ok { continue }
                    }
                    if let title, !title.isEmpty, !(w.title?.lowercased().contains(title) ?? false) { continue }
                    let label = [w.appName ?? w.bundleID ?? "pid \(w.pid)", w.title ?? "untitled",
                                 "\(row + 1) \(ws.title ?? ws.name)"].joined(separator: " · ")
                    hits.append(Hit(ref: WindowRef(id: w.id, pid: w.pid), label: label, focused: w.isFocused,
                                    shown: screen.isFocused && ws.isActive))
                }
            }
        }
        let asked = [app.map { "app \"\($0)\"" }, title.map { "title \"\($0)\"" }].compactMap { $0 }.joined(separator: " and ")
        guard !hits.isEmpty else { return .failure(FindWindowRefusal("no window matches \(asked)")) }
        let list = hits.enumerated().map { "  [\($0.offset + 1)] \($0.element.label)" }.joined(separator: "\n")
        if let index {
            guard (1...hits.count).contains(index) else {
                return .failure(FindWindowRefusal("--index \(index) is out of range; \(hits.count) match \(asked):\n\(list)"))
            }
            return .success(hits[index - 1].ref)
        }
        if hits.count == 1 { return .success(hits[0].ref) }
        if first { return .success((hits.first(where: \.focused) ?? hits.first(where: \.shown) ?? hits[0]).ref) }
        return .failure(FindWindowRefusal("\(hits.count) windows match \(asked); add --index N or --first:\n\(list)"))
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
