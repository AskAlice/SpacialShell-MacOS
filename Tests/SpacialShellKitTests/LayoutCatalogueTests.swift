import Testing
import Foundation
import SpacialShellProtocol
@testable import SpacialShellKit

/// #9 — layouts become data (custom grid layouts design, 2026-09-25). Zone geometry and paging,
/// the five built-ins unchanged, the catalogue, and every pre-#9 file still loading.
@Suite struct LayoutCatalogueTests {
    func zones(_ z: [(Double, Double, Double, Double)]) -> LayoutDef {
        LayoutDef(id: "test", name: "Test", body: .zones(z.map { LayoutZone(x: $0.0, y: $0.1, w: $0.2, h: $0.3) }))
    }
    func columnZones(_ n: Int) -> LayoutDef { zones((0..<n).map { (Double($0) / Double(n), 0, 1 / Double(n), 1) }) }
    let grid2x2: [(Double, Double, Double, Double)] = [(0, 0, 0.5, 0.5), (0.5, 0, 0.5, 0.5), (0, 0.5, 0.5, 0.5), (0.5, 0.5, 0.5, 0.5)]
    let half4: [(Double, Double, Double, Double)] = [(0, 0, 0.5, 1), (0.5, 0, 0.5, 1.0 / 3), (0.5, 1.0 / 3, 0.5, 1.0 / 3), (0.5, 2.0 / 3, 0.5, 1.0 / 3)]
    func builtin(_ l: BuiltinLayout) -> LayoutDef { LayoutCatalogue.builtins[LayoutID(rawValue: l.rawValue)]! }

    /// Floating point makes `(W − (n−1)g)/n + g` and `(W + g)/n` differ in the last bit or so; the
    /// design's "exact" is exact arithmetic. 1e-9 pt is a billionth of a point.
    func same(_ a: [CGRect?], _ b: [CGRect?]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { x, y in
            switch (x, y) {
            case (nil, nil): true
            case let (x?, y?): abs(x.minX - y.minX) < 1e-9 && abs(x.minY - y.minY) < 1e-9
                && abs(x.width - y.width) < 1e-9 && abs(x.height - y.height) < 1e-9
            default: false
            }
        }
    }

    // MARK: - §4.2 zone → frame reproduces the generators

    @Test(arguments: 0..<50)
    func zoneSetsReproduceTheBuiltins(seed: Int) {
        var rng = TestRNG(seed: UInt64(seed) &+ 900)
        let r = CGRect(x: Double.random(in: -2000...2000, using: &rng), y: Double.random(in: 0...500, using: &rng),
                       width: Double.random(in: 800...3000, using: &rng), height: Double.random(in: 600...1600, using: &rng))
        let g = CGFloat(Double.random(in: 0...24, using: &rng))
        // #122: a portrait rect turns column and half to the long axis, so the zones that match are
        // the transposed ones. A 2×2 grid is row-major either way.
        let turn = LayoutEngine.isPortrait(r)
        func t(_ z: [(Double, Double, Double, Double)]) -> [(Double, Double, Double, Double)] { turn ? z.map { ($0.1, $0.0, $0.3, $0.2) } : z }
        let col3 = (0..<3).map { (Double($0) / 3, 0.0, 1.0 / 3, 1.0) }
        #expect(same(LayoutEngine.frames(zones(t(col3)), count: 3, focused: 0, in: r, gap: g),
                     LayoutEngine.frames(.column, count: 3, focused: 0, in: r, gap: g)), "column 3 \(r) g=\(g)")
        #expect(same(LayoutEngine.frames(zones(grid2x2), count: 4, focused: 0, in: r, gap: g),
                     LayoutEngine.frames(.grid, count: 4, focused: 0, in: r, gap: g)), "grid 4 \(r) g=\(g)")
        #expect(same(LayoutEngine.frames(zones(t(half4)), count: 4, focused: 0, in: r, gap: g),
                     LayoutEngine.frames(.half, count: 4, focused: 0, in: r, gap: g)), "half 4 \(r) g=\(g)")
    }

    // MARK: - §4.3 paging over zones (#54)

    let r = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func moreWindowsThanZonesPagesAroundTheFocus() {
        let def = zones(grid2x2)
        func shown(_ n: Int, _ f: Int) -> [Int] {
            let fs = LayoutEngine.frames(def, count: n, focused: f, in: r, gap: 8)
            return fs.indices.filter { fs[$0] != nil }
        }
        #expect(shown(10, 0) == [0, 1, 2, 3])
        #expect(shown(10, 3) == [0, 1, 2, 3])       // last of a page: nothing flips
        #expect(shown(10, 4) == [4, 5, 6, 7])       // first of the next: the page flips
        #expect(shown(10, 9) == [6, 7, 8, 9])       // the last page is pulled back, never short
        // Window i of the page is zone i, in array order.
        let fs = LayoutEngine.frames(def, count: 10, focused: 5, in: r, gap: 8)
        let first = LayoutEngine.frames(def, count: 4, focused: 0, in: r, gap: 8)
        #expect(Array(fs[4...7]) == first)
    }

    @Test func focusInsideAPageMovesNothing() {
        let def = zones(grid2x2)
        let a = LayoutEngine.frames(def, count: 7, focused: 0, in: r, gap: 8)
        for f in 1...3 { #expect(LayoutEngine.frames(def, count: 7, focused: f, in: r, gap: 8) == a) }
    }

    @Test func fewerWindowsThanZonesLeaveTrailingZonesEmpty() {
        let fs = LayoutEngine.frames(zones(grid2x2), count: 2, focused: 1, in: r, gap: 0)
        #expect(fs == [CGRect(x: 0, y: 0, width: 500, height: 300), CGRect(x: 500, y: 0, width: 500, height: 300)])
    }

    /// A 6-zone ultrawide layout on a laptop: zones under 120 × 80 drop out of the page.
    @Test func zonesBelowTheFloorDropOutOfCapacity() {
        // Five slivers of 1/40 and one big zone. At 1280 pt a 1/40 zone is ~24 pt wide.
        var cells: [(Double, Double, Double, Double)] = (0..<5).map { i -> (Double, Double, Double, Double) in (Double(i) / 40, 0, 1.0 / 40, 1) }
        cells.append((5.0 / 40, 0, 35.0 / 40, 1))
        let def = zones(cells)
        let laptop = CGRect(x: 0, y: 0, width: 1280, height: 800)
        #expect(LayoutEngine.capacity(def, count: 6, in: laptop, gap: 8) == 1)
        #expect(LayoutEngine.capacity(def, count: 6, in: CGRect(x: 0, y: 0, width: 40_000, height: 800), gap: 8) == 6)
        let fs = LayoutEngine.frames(def, count: 3, focused: 2, in: laptop, gap: 8)
        #expect(fs[0] == nil && fs[1] == nil && fs[2] != nil)
        #expect(fs.compactMap { $0 }.allSatisfy { $0.width >= 120 && $0.height >= 80 })
    }

    @Test func noUsableZoneGivesTheFocusedWindowTheWholeRect() {
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 100)
        let fs = LayoutEngine.frames(zones(grid2x2), count: 3, focused: 1, in: tiny, gap: 0)
        #expect(fs == [nil, tiny, nil])
        #expect(LayoutEngine.frames(zones(grid2x2), count: 0, focused: 0, in: r, gap: 0).isEmpty)
    }

    // MARK: - the five built-ins, before and after

    /// Built-in frames equal, to the bit, what the pre-#9 engine produced (golden captured before
    /// any #9 change: every built-in, counts 1–9, every focus, a 4K-ish and a cramped rect, gap 8).
    @Test func builtinsMatchThePre9Golden() throws {
        let url = try #require(Bundle.module.url(forResource: "pre9-builtin-frames", withExtension: "json", subdirectory: "Fixtures"))
        let golden = try JSONDecoder().decode([String: [[Double]?]].self, from: Data(contentsOf: url))
        let rects = [CGRect(x: 8, y: 42, width: 1864, height: 1021), CGRect(x: 0, y: 0, width: 500, height: 300)]
        var checked = 0
        let pre9: [BuiltinLayout] = [.maximize, .split, .column, .half, .grid]   // #123's ratio came later
        for l in pre9 { for (ri, rect) in rects.enumerated() { for n in 1...9 { for f in 0..<n {
            // #114: split's view starting at the focused window is the pre-#9 split exactly.
            let now = LayoutEngine.frames(builtin(l), count: n, focused: f, in: rect, gap: 8, split: SplitView(start: f))
                .map { $0.map { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] } }
            #expect(now == golden["\(l.rawValue) r\(ri) n\(n) f\(f)"], "\(l) r\(ri) n\(n) f\(f)")
            checked += 1
        } } } }
        #expect(checked == golden.count)
    }

    /// And over random rects, gaps, counts and focus: the catalogue row is the generator, exactly.
    @Test(arguments: 0..<100)
    func builtinRowsAreTheGenerators(seed: Int) {
        var rng = TestRNG(seed: UInt64(seed) &+ 9_000)
        let rect = CGRect(x: 0, y: 0, width: Double.random(in: 50...4000, using: &rng), height: Double.random(in: 50...2000, using: &rng))
        let g = CGFloat(Double.random(in: 0...30, using: &rng))
        let n = Int.random(in: 0...30, using: &rng), f = Int.random(in: -1...31, using: &rng)
        for l in BuiltinLayout.allCases {
            #expect(LayoutEngine.frames(builtin(l), count: n, focused: f, in: rect, gap: g)
                    == LayoutEngine.frames(l, count: n, focused: f, in: rect, gap: g), "\(l) n=\(n) f=\(f)")
        }
    }

    /// Random legal zone sets (a random grid, in shuffled fill order) through the reconciler: the
    /// focused window is framed, nothing is under the floor, nothing overlaps, all inside the rect.
    @Test(arguments: 0..<100)
    func randomZoneSetsKeepTheEngineProperties(seed: Int) {
        var rng = TestRNG(seed: UInt64(seed) &+ 19_000)
        let cols = Int.random(in: 1...6, using: &rng), rows = Int.random(in: 1...4, using: &rng)
        var cells: [(Double, Double, Double, Double)] = []
        for y in 0..<rows { for x in 0..<cols {
            cells.append((Double(x) / Double(cols), Double(y) / Double(rows), 1 / Double(cols), 1 / Double(rows)))
        } }
        let def = zones(cells.shuffled(using: &rng))
        var c = Config(); c.layouts = [def]; c.defaultLayout = def.id
        let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                             visibleFrame: CGRect(x: 0, y: 25, width: Double.random(in: 300...1440, using: &rng), height: 875), isMain: true)
        var w = World.empty(screens: ["D1"], defaultLayout: def.id)
        let refs = (1...Int.random(in: 1...20, using: &rng)).map { WindowRef(id: WindowID($0), pid: 1) }
        for r in refs { w.adopt(r, kind: .tile, on: "D1") }
        let focus = refs.randomElement(using: &rng)!
        w.screens["D1"]!.workspaces[0].anchor = focus
        let desired = Reconciler.desired(world: w, displays: [d1], config: LayoutConfig(gap: 8, layouts: LayoutCatalogue(config: c)),
                                         observed: [:], prePark: [:], parkedNow: [], zeroSliver: [])
        let framed = refs.compactMap { r -> CGRect? in if case .frame(let f) = desired[r] { f } else { nil } }
        if case .frame = desired[focus] {} else { Issue.record("seed \(seed): focused window not framed") }
        #expect(framed.allSatisfy { d1.visibleFrame.contains($0) }, "seed \(seed)")
        if framed.count > 1 { #expect(framed.allSatisfy { $0.width >= 120 && $0.height >= 80 }, "seed \(seed)") }
        for i in framed.indices { for j in framed.indices where j > i {
            let x = framed[i].intersection(framed[j])
            #expect(x.isNull || x.width < 0.01 || x.height < 0.01, "seed \(seed): overlap")
        } }
    }

    // MARK: - the catalogue

    @Test func theDefaultCatalogueIsTheBuiltinsInCycleOrder() {
        let cat = LayoutCatalogue.builtins
        #expect(cat.all.map(\.id) == [.maximize, .split, .column, .half, .grid, .ratio])
        #expect(cat.bar == [.maximize, .split, .column, .half, .grid, .ratio], "#123, 2026-09-26: ratio joins the ring, sixth")
        #expect(cat.all.map(\.name) == BuiltinLayout.allCases.map { $0.rawValue.capitalized })   // what the Hint printed
        #expect(cat.all.map(\.body) == BuiltinLayout.allCases.map { .builtin($0) })
        let ids = cat.bar
        for (i, id) in ids.enumerated() { #expect(cat.next(after: id) == ids[(i + 1) % ids.count]) }
        #expect(cat.next(after: .ratio) == .maximize, "the ring closes after ratio")
        var c = Config(); c.layoutBar = [.split, .column]
        #expect(LayoutCatalogue(config: c).next(after: .ratio) == .split, "from off the bar, its start")
    }

    @Test func unknownIdsFallBackThroughDefaultThenMaximize() {
        var c = Config(); c.defaultLayout = .grid
        let cat = LayoutCatalogue(config: c)
        #expect(cat.resolve("code-3").def.id == .grid && !cat.resolve("code-3").resolved)
        #expect(cat.resolve(.half).def.id == .half && cat.resolve(.half).resolved)
        c.defaultLayout = "also-gone"
        #expect(LayoutCatalogue(config: c).resolve("code-3").def.id == .maximize)
        #expect(LayoutCatalogue(config: c).warning(for: "code-3") == "layout \"code-3\" is missing — using maximize")
        #expect(LayoutCatalogue(config: c).warning(for: .split) == nil)
    }

    @Test func userLayoutsCannotShadowABuiltin() {
        var c = Config()
        c.layouts = [LayoutDef(id: .split, name: "Evil", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 1)])), columnZones(2)]
        let cat = LayoutCatalogue(config: c)
        #expect(cat[.split]?.isBuiltin == true)
        #expect(cat.all.map(\.id) == [.maximize, .split, .column, .half, .grid, .ratio, "test"])
    }

    @Test func theBarIsFilteredDedupedAndCappedAtEight() {
        var c = Config()
        c.layouts = (0..<10).map { LayoutDef(id: LayoutID(rawValue: "z\($0)"), name: "Z\($0)", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 1)])) }
        c.layoutBar = ["gone", .split, .split] + c.layouts.map(\.id)
        let cat = LayoutCatalogue(config: c)
        #expect(cat.bar == [.split, "z0", "z1", "z2", "z3", "z4", "z5", "z6"])
        #expect(cat.next(after: "z6") == .split)             // a ring
        #expect(cat.next(after: .grid) == .split)            // from outside the bar, its start
    }

    @Test func settingsWinPerIdOverTheFile() {
        let fileDef = LayoutDef(id: "a", name: "File A", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 1)]))
        let fileB = LayoutDef(id: "b", name: "File B", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 1)]))
        var gui = fileDef; gui.name = "GUI A"
        let guiC = LayoutDef(id: "c", name: "GUI C", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 1)]))
        var file = Config(); file.layouts = [fileDef, fileB]; file.defaultLayout = "b"
        var o = SettingsOverrides(); o.layouts = [guiC, gui]; o.layoutBar = ["c", .maximize]; o.defaultLayout = "c"
        let eff = Settings.effective(config: file, overrides: o)
        #expect(eff.layouts.map(\.name) == ["GUI A", "File B", "GUI C"])
        #expect(eff.layoutBar == ["c", .maximize])
        #expect(eff.defaultLayout == "c")
        #expect(Settings.effective(config: file, overrides: SettingsOverrides()).layouts == file.layouts)
    }

    // MARK: - persistence

    /// Design §3.2: one bad layout entry in settings.json is dropped; the rest, and every other
    /// setting, load.
    @Test func aBadSettingsLayoutEntryIsSkipped() throws {
        let json = #"""
        {"panelWidth": 64,
         "layouts": [
           {"id": "good", "name": "Good", "zones": [{"x": 0, "y": 0, "w": 0.5, "h": 1}, {"x": 0.5, "y": 0, "w": 0.5, "h": 1}]},
           {"id": "no-zones", "name": "Broken"},
           {"id": "bad-zone", "zones": [{"x": "left"}]},
           {"id": "all-degenerate", "zones": [{"x": 0, "y": 0, "w": 0, "h": 1}]},
           {"id": "also-good", "zones": [{"x": -1, "y": 0, "w": 3, "h": 1}, {"x": 0, "y": 0, "w": 0, "h": 1}]}
         ],
         "layoutBar": ["good", "maximize"], "defaultLayout": "good"}
        """#
        let o = try JSONDecoder().decode(SettingsOverrides.self, from: Data(json.utf8))
        #expect(o.panelWidth == 64)
        #expect(o.layouts?.map(\.id) == ["good", "also-good"])
        // Clamped into the unit square, the degenerate zone dropped, the name defaulted to the id.
        #expect(o.layouts?.last == LayoutDef(id: "also-good", name: "also-good", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 1)])))
        #expect(o.layoutBar == ["good", .maximize] && o.defaultLayout == "good")
        // And it round-trips.
        #expect(try JSONDecoder().decode(SettingsOverrides.self, from: JSONEncoder().encode(o)) == o)
    }

    @Test func layoutBlocksParseFromTOML() throws {
        let c = try Config.parse(toml: """
        default-layout = "code-3"
        layout-bar = ["maximize", "split", "column", "code-3"]

        [[layout]]
        id = "code-3"
        name = "Code, three"
        zones = [
          { x = 0.0,  y = 0.0, w = 0.5,  h = 1.0 },
          { x = 0.5,  y = 0.0, w = 0.5,  h = 0.5 },
          { x = 0.5,  y = 0.5, w = 0.5,  h = 0.5 },
        ]

        [[layout]]
        id = "broken"
        name = "no zones at all"

        [[layout]]
        id = "icon"
        name = "With icon"
        symbol = "sidebar.left"
        zones = [ { x = 0.0, y = 0.0, w = 1.0, h = 1.0 } ]

        [[workspace]]
        name = "Code"
        layout = "code-3"
        """)
        #expect(c.defaultLayout == "code-3")
        #expect(c.layoutBar == [.maximize, .split, .column, "code-3"])
        #expect(c.layouts.map(\.id) == ["code-3", "icon"])      // the broken block is dropped, not the file
        #expect(c.layouts[0].name == "Code, three" && c.layouts[0].symbol == nil)
        #expect(c.layouts[0].body == .zones([LayoutZone(x: 0, y: 0, w: 0.5, h: 1), LayoutZone(x: 0.5, y: 0, w: 0.5, h: 0.5),
                                            LayoutZone(x: 0.5, y: 0.5, w: 0.5, h: 0.5)]))
        #expect(c.layouts[1].symbol == "sidebar.left")
        #expect(c.workspaces[0].layout == "code-3")
        #expect(try Config.parse(toml: c.render()) == c)
        let cat = LayoutCatalogue(config: c)
        #expect(cat.bar.last == "code-3" && cat.resolve("code-3").resolved)
    }

    /// Today a typo rejected the whole file; now the id is kept and resolved late.
    @Test func anUnknownLayoutNoLongerRejectsConfigOrState() throws {
        let c = try Config.parse(toml: "default-layout = \"nonsense\"\n[[workspace]]\nname = \"A\"\nlayout = \"nonsense\"")
        #expect(c.defaultLayout == "nonsense" && c.workspaces[0].layout == "nonsense")
        let json = #"{"screens":{"D1":{"activeIndex":0,"workspaces":[{"id":"00000000-0000-0000-0000-000000000001","layout":"nonsense","name":"A","pinned":true,"symbol":"x"}]}}}"#
        let s = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        #expect(s.screens["D1"]?.workspaces[0].layout == "nonsense")
    }

    // MARK: - pre-#9 fixtures (captured before #9 changed a line)

    func fixture(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")))
    }

    @Test func thePre9ConfigLoadsUnchanged() throws {
        let c = try Config.parse(toml: String(decoding: fixture("pre9-config", "toml"), as: UTF8.self))
        #expect(c.defaultLayout == .column)
        #expect(c.workspaces.map(\.layout) == [.maximize, .split, .column, .half, .grid, .maximize])
        #expect(c.layouts.isEmpty && c.layoutBar == Config.defaultLayoutBar)
    }

    /// Decodes, and re-encodes to the very same bytes: `LayoutID` is the enum's encoding.
    @Test func thePre9StateLoadsAndReencodesByteForByte() throws {
        let data = try fixture("pre9-state", "json")
        let s = try JSONDecoder().decode(PersistedState.self, from: data)
        #expect(s.screens["D1"]?.workspaces.map(\.layout) == [.maximize, .split, .column, .half, .grid, .maximize, .column])
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        #expect(try enc.encode(s) == data)
    }

    /// A pre-#9 `state` payload still decodes, and today's has the same workspaces plus `layouts`.
    @Test func thePre9WireStateStillDecodes() throws {
        let data = try fixture("pre9-wire", "json")
        let old = try JSONDecoder().decode(WireState.self, from: data)
        #expect(old.v == 2 && old.layouts.isEmpty)
        #expect(old.screens[0].workspaces.map(\.layout) == ["maximize", "split", "column", "half", "grid", "maximize", "column"])
        // The same world today: identical screens, plus the catalogue and its capability.
        let c = try Config.parse(toml: String(decoding: fixture("pre9-config", "toml"), as: UTF8.self))
        var w = World.seeded(screens: ["D1"], config: c)
        w.adopt(WindowRef(id: 11, pid: 7), kind: .tile, on: "D1")
        w.adopt(WindowRef(id: 12, pid: 7), kind: .tile, on: "D1")
        for i in w.screens["D1"]!.workspaces.indices {
            w.screens["D1"]!.workspaces[i].id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i + 1))!
        }
        let now = WireState(world: w, bundleIDs: [WindowRef(id: 11, pid: 7): "com.example.app"])
        #expect(now.screens == old.screens)
        // #109 `problems`, #117 `subscribe`; #131's verbs are appended after them.
        #expect(Array(now.capabilities.prefix(7)) == old.capabilities + ["layouts", "problems", "subscribe"])
        #expect(now.layouts.map(\.id) == ["maximize", "split", "column", "half", "grid", "ratio"])   // #123
        #expect(now.layouts.allSatisfy { $0.builtin && $0.zones == nil })
    }

    // MARK: - commands, view state, wire

    @Test func cycleLayoutRingsTheBar() {
        var c = Config(); c.layouts = [columnZones(2)]; c.layoutBar = [.maximize, "test"]
        let cat = LayoutCatalogue(config: c)
        var w = World.empty(screens: ["D1"], defaultLayout: .grid)
        w = CommandRunner.apply(.cycleLayout, to: w, layouts: cat).0
        #expect(w.screens["D1"]!.active.layout == .maximize)
        w = CommandRunner.apply(.cycleLayout, to: w, layouts: cat).0
        #expect(w.screens["D1"]!.active.layout == "test")
        w = CommandRunner.apply(.cycleLayout, to: w, layouts: cat).0
        #expect(w.screens["D1"]!.active.layout == .maximize)
    }

    /// "maximize → split" is now "anything that shows fewer than two → split".
    @Test func moveWindowPromotesAOneZoneLayoutButLeavesATwoZoneOne() {
        let one = LayoutDef(id: "one", name: "One", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 1)]))
        var c = Config(); c.layouts = [one, columnZones(2)]
        let cat = LayoutCatalogue(config: c)
        for (id, expected) in [("one", LayoutID.split), ("test", "test"), ("maximize", .split), ("column", .column)] as [(LayoutID, LayoutID)] {
            var w = World.empty(screens: ["D1"], defaultLayout: id)
            w.adopt(WindowRef(id: 1, pid: 1), kind: .tile, on: "D1"); w.adopt(WindowRef(id: 2, pid: 1), kind: .tile, on: "D1")
            w = CommandRunner.apply(.focusWindowRef(WindowRef(id: 1, pid: 1)), to: w, layouts: cat).0
            w = CommandRunner.apply(.moveWindow(.right), to: w, layouts: cat).0
            #expect(w.screens["D1"]!.active.windows.first == WindowRef(id: 2, pid: 1))   // the move happened
            #expect(w.screens["D1"]!.active.layout == expected, "\(id.rawValue)")
        }
    }

    /// Design §8: the workspace keeps the dangling id, the shell draws the fallback, the view state
    /// says so, and the wire carries the id as stored.
    @Test func aDeletedLayoutKeepsItsIdAndSurfacesAWarning() throws {
        var w = World.empty(screens: ["D1"], defaultLayout: "code-3")
        w.adopt(WindowRef(id: 1, pid: 1), kind: .tile, on: "D1"); w.adopt(WindowRef(id: 2, pid: 1), kind: .tile, on: "D1")
        let ui = try #require(ShellUI.state(for: "D1", in: w))
        #expect(ui.layout == "code-3")
        #expect(ui.layoutWarning == "layout \"code-3\" is missing — using maximize")
        #expect(WireState(world: w).screens[0].workspaces[0].layout == "code-3")
        // It draws maximize: the focused window framed, the other parked.
        let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 700), isMain: true)
        let desired = Reconciler.desired(world: w, displays: [d1], config: LayoutConfig(gap: 10), observed: [:], prePark: [:], parkedNow: [], zeroSliver: [])
        let framed = [WindowRef(id: 1, pid: 1), WindowRef(id: 2, pid: 1)].filter { if case .frame = desired[$0] { true } else { false } }
        #expect(framed.count == 1)
        // Restoring the layout restores the workspace, with no further action.
        var c = Config(); c.layouts = [LayoutDef(id: "code-3", name: "Code", body: .zones([LayoutZone(x: 0, y: 0, w: 0.5, h: 1), LayoutZone(x: 0.5, y: 0, w: 0.5, h: 1)]))]
        #expect(ShellUI.state(for: "D1", in: w, layouts: LayoutCatalogue(config: c))?.layoutWarning == nil)
    }

    @Test func wireStateListsTheCatalogue() {
        var c = Config(); c.layouts = [columnZones(3)]
        let s = WireState(world: World.empty(screens: ["D1"], defaultLayout: .maximize), layouts: LayoutCatalogue(config: c))
        #expect(s.capabilities.contains("layouts") && s.v == 2)
        #expect(s.layouts.last == WireState.LayoutDTO(id: "test", name: "Test", symbol: nil, builtin: false, zones: 3))
        #expect(s.layouts.first == WireState.LayoutDTO(id: "maximize", name: "Maximize", symbol: "rectangle", builtin: true, zones: nil))
    }

    @Test func theHintNamesTheLayoutByItsName() {
        var c = Config(); c.layouts = [LayoutDef(id: "code-3", name: "Code, three", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 1)]))]
        let w = World.empty(screens: ["D1"], defaultLayout: "code-3")
        #expect(Hint.after(.cycleLayout, before: w, after: w, config: c)?.hasPrefix("Code, three") == true)
        let m = World.empty(screens: ["D1"], defaultLayout: .maximize)
        #expect(Hint.after(.cycleLayout, before: m, after: m, config: Config())?.hasPrefix("Maximize") == true)
    }
}
