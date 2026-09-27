import Testing
import Foundation
@testable import SpacialShellKit

/// #124 (M4 G11): `screen-gap` sets the space between the row and the screen edge on its own;
/// `gap` stays the space between tiles. Unset, the screen gap follows `gap`.
@Suite struct ScreenGapTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1)

    func columns() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .column)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        return w
    }
    func frame(_ p: Placement?) -> CGRect? { if case .frame(let f)? = p { f } else { nil } }

    @Test func screenGapInsetsTheRowAndGapSeparatesTiles() throws {
        let d = Reconciler.desired(world: columns(), displays: [d1], config: LayoutConfig.test(gap: 10, screenGap: 30),
                                   observed: [:], prePark: [:], parkedNow: [], zeroSliver: [])
        let fa = try #require(frame(d[a])), fb = try #require(frame(d[b]))
        #expect(fa.minX == 30 && fa.minY == 25 + 30, "outer edge is the screen gap")
        #expect(abs(fb.maxX - (1000 - 30)) < 1e-6, "and on the far side too")
        #expect(abs(fa.height - (675 - 60 - 1)) < 1e-6)
        #expect(abs(fb.minX - fa.maxX - 10) < 1e-6, "tiles are the inner gap apart")
    }

    @Test func unsetScreenGapFollowsGap() {
        #expect(LayoutConfig(gap: 12, layouts: .builtins).screenGap == 12)
        #expect(Config().screenGap == nil && Config().outerGap == 8)
        var c = Config(); c.gap = 20
        #expect(c.outerGap == 20)
        c.screenGap = 0
        #expect(c.outerGap == 0, "0 is a real value: windows flush with the screen edge")
    }

    @Test func zeroScreenGapIsFlush() throws {
        let d = Reconciler.desired(world: columns(), displays: [d1], config: LayoutConfig.test(gap: 10, screenGap: 0),
                                   observed: [:], prePark: [:], parkedNow: [], zeroSliver: [])
        let fa = try #require(frame(d[a]))
        #expect(fa.minX == 0 && fa.minY == 25)
    }

    @Test func parsesAndFollowsGapWhenUnset() throws {
        let c = try Config.parse(toml: "gap = 6\nscreen-gap = 20")
        #expect(c.gap == 6 && c.screenGap == 20 && c.outerGap == 20)
        #expect(Config.unknownKeys(toml: "screen-gap = 4").isEmpty)
        // Unset stays unset, so it keeps following `gap`.
        let unset = try Config.parse(toml: "gap = 6")
        #expect(unset.screenGap == nil && unset.outerGap == 6)
    }

    @Test func settingsOverrideIt() throws {
        var gui = SettingsOverrides()
        gui.gap = 16
        #expect(Settings.effective(config: Config(), overrides: gui).outerGap == 16, "a GUI gap moves an unset screen gap")
        gui.screenGap = 2
        let out = Settings.effective(config: Config(), overrides: gui)
        #expect(out.gap == 16 && out.outerGap == 2)
        #expect(try JSONDecoder().decode(SettingsOverrides.self, from: JSONEncoder().encode(gui)) == gui)
    }
}
