import Testing
import Foundation
@testable import SpacialShellKit

/// Issue #13 — windows land on the right display and workspace at launch. One ladder
/// (`World.landing`): remembered placement, then a crowd's own workspace, then today's rules.
@Suite struct LaunchPlacementTests {
    let a = WindowRef(id: 1, pid: 10)

    // MARK: the ladder, one rung at a time

    /// Rung 1: a remembered workspace that exists wins — on whichever display it lives.
    @Test func rung1RememberedPlacementWins() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        let there = w.screens["D2"]!.active.id
        #expect(w.landing(remembered: there, crowdOn: nil) == there)
    }
    /// Rung 2: no memory, a crowd at launch → a new workspace on the crowd's display, above the
    /// trailing empty, with the display's active workspace left as it was.
    @Test func rung2CrowdGetsAWorkspaceOfItsOwnOnItsDisplay() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        let active = w.screens["D2"]!.active.id
        let id = w.landing(remembered: nil, crowdOn: "D2")
        #expect(id != nil && w.location(ofWorkspace: id!)?.screen == "D2")
        #expect(w.screens["D2"]!.active.id == active)
        #expect(w.screens["D2"]!.workspaces.last!.id == active)       // still the trailing empty
        w.adopt(a, kind: .tile, on: "D1", workspace: id)
        #expect(w.workspace(containing: a)?.id == id && w.location(of: a)?.screen == "D2")
        #expect(w.invariantViolations().isEmpty)
    }
    /// Rung 3: nothing to go on → nil, and the world is untouched, so `adopt` behaves exactly as today.
    @Test func rung3NothingMeansTodaysRules() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let before = w
        #expect(w.landing(remembered: nil, crowdOn: nil) == nil)
        #expect(w == before)
    }
    /// Precedence 1 > 2: memory beats the crowd rule, and no workspace is created for nothing.
    @Test func rememberedBeatsCrowd() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        let there = w.screens["D1"]!.active.id
        let count = w.screens["D2"]!.workspaces.count
        #expect(w.landing(remembered: there, crowdOn: "D2") == there)
        #expect(w.screens["D2"]!.workspaces.count == count)
    }
    /// Precedence 2 > 3, and a memory that no longer resolves drops to rung 2, not to rung 3.
    @Test func crowdBeatsDefaultEvenWithAStaleMemory() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let id = w.landing(remembered: UUID(), crowdOn: "D1")
        #expect(id != nil && id != w.screens["D1"]!.active.id)
    }

    // MARK: topology changed while we were not running (spec §7.8)

    /// Two displays, relaunched with the arrangement order reversed: each display's workspaces
    /// come back to that display, because screens are matched by UUID, not by order.
    @Test func workspacesReturnToTheirOwnDisplayWhateverTheOrder() {
        var w = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        let one = WindowRef(id: 1, pid: 10), two = WindowRef(id: 2, pid: 20)
        w.adopt(one, kind: .tile, on: "D1"); w.adopt(two, kind: .tile, on: "D2")
        let s = PersistedState(world: w, placements: PersistedState.placements(world: w, bundleIDs: [one: "com.one", two: "com.two"]))

        var fresh = s.restore(into: World.empty(screens: ["D2", "D1"], defaultLayout: .maximize), main: "D2")
        let one2 = WindowRef(id: 91, pid: 99), two2 = WindowRef(id: 92, pid: 98)
        fresh.adopt(one2, kind: .tile, on: "D2", workspace: fresh.landing(remembered: s.placements["com.one"], crowdOn: nil))
        fresh.adopt(two2, kind: .tile, on: "D1", workspace: fresh.landing(remembered: s.placements["com.two"], crowdOn: nil))
        #expect(fresh.location(of: one2)?.screen == "D1")
        #expect(fresh.location(of: two2)?.screen == "D2")
        #expect(fresh.invariantViolations().isEmpty)
    }
    /// A display gone at relaunch: its workspaces merge into the main display, appended above the
    /// trailing empty — the unplug ruling — so its apps still come back to their own workspace.
    /// The config's pinned seeds are not doubled up on main.
    @Test func aGoneDisplaysWorkspacesMergeIntoMain() throws {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code")]
        var w = World.seeded(screens: ["D1", "D2"], config: c)
        let two = WindowRef(id: 2, pid: 20)
        w.activate(index: 1, on: "D2")
        w.adopt(two, kind: .tile, on: "D2")                     // D2's unpinned row, below "Code"
        let s = PersistedState(world: w, placements: PersistedState.placements(world: w, bundleIDs: [two: "com.two"]))
        let remembered = try #require(s.placements["com.two"])

        var fresh = s.restore(into: World.seeded(screens: ["D1"], config: c), main: "D1")   // D2 unplugged
        let rows = fresh.screens["D1"]!.workspaces
        #expect(rows.filter { $0.name == "Code" }.count == 1)
        #expect(rows.map(\.id) == [rows[0].id, remembered], "main's own rows first, then D2's")
        let back = WindowRef(id: 92, pid: 98)
        fresh.adopt(back, kind: .tile, on: "D1", workspace: fresh.landing(remembered: remembered, crowdOn: nil))
        #expect(fresh.workspace(containing: back)?.id == remembered)
        #expect(fresh.screens["D1"]!.workspaces.last!.isEmpty)
        #expect(fresh.invariantViolations().isEmpty)
    }
    /// A display new at relaunch gets an empty stack — its seeds only, nobody else's workspaces.
    @Test func aNewDisplayGetsAnEmptyStack() {
        var c = Config(); c.workspaces = [WorkspaceSeed(name: "Code")]
        var w = World.seeded(screens: ["D1"], config: c)
        let one = WindowRef(id: 1, pid: 10)
        w.activate(index: 1, on: "D1")
        w.adopt(one, kind: .tile, on: "D1")
        let s = PersistedState(world: w, placements: PersistedState.placements(world: w, bundleIDs: [one: "com.one"]))

        let fresh = s.restore(into: World.seeded(screens: ["D1", "D3"], config: c), main: "D1")
        #expect(fresh.screens["D3"]!.workspaces.map(\.name) == ["Code", "Workspace 1"])
        #expect(fresh.screens["D3"]!.workspaces.allSatisfy { $0.isEmpty })
        #expect(fresh.location(ofWorkspace: s.placements["com.one"]!)?.screen == "D1")
        #expect(fresh.invariantViolations().isEmpty)
    }

    // MARK: compatibility

    /// A state file exactly as the build before #13 wrote it (version 1, #5's placements) loads,
    /// and restores onto the right displays.
    @Test func stateWrittenBeforeThisChangeStillLoads() throws {
        let json = """
        {
          "placements" : { "com.apple.Safari" : "5B0F8E2A-3C1D-4E5F-8A9B-0C1D2E3F4A5B" },
          "screens" : {
            "D1" : { "activeIndex" : 0, "workspaces" : [
              { "id" : "11111111-2222-3333-4444-555555555555", "layout" : "half", "name" : "Code", "pinned" : true, "symbol" : "terminal" } ] },
            "D2" : { "activeIndex" : 0, "workspaces" : [
              { "id" : "5B0F8E2A-3C1D-4E5F-8A9B-0C1D2E3F4A5B", "layout" : "maximize", "name" : "Workspace", "pinned" : false, "symbol" : "square.grid.2x2" } ] }
          },
          "version" : 1,
          "zen" : false
        }
        """
        let s = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        let fresh = s.restore(into: World.empty(screens: ["D1", "D2"], defaultLayout: .maximize), main: "D1")
        #expect(fresh.location(ofWorkspace: s.placements["com.apple.Safari"]!)?.screen == "D2")
        #expect(fresh.screens["D1"]!.workspaces.first?.name == "Code")
        #expect(fresh.invariantViolations().isEmpty)
    }
    @Test func crowdThresholdIsAConfigKeyDefaulting8() throws {
        #expect(Config().crowdThreshold == 8)
        #expect(try Config.parse(toml: "crowd-threshold = 3").crowdThreshold == 3)
    }
}

// MARK: the ladder in the store — launch-only, threshold, and #72's rehome

extension WorldStoreTests {
    func crowd(_ n: Int, bundle: String, pid: Int32, on frame: CGRect, from first: Int = 0) -> [WindowSnapshot] {
        (first..<first + n).map { win(WindowRef(id: WindowID(100 * Int(pid) + $0), pid: pid), frame, bundle: bundle) }
    }
    var onD2: CGRect { CGRect(x: 1100, y: 100, width: 300, height: 200) }

    /// Rung 2 at launch: 9 windows (> 8) on D2 take a workspace of their own on D2; an app at the
    /// threshold exactly (8) keeps today's behaviour — D1's active workspace.
    @Test func aCrowdAtLaunchGetsItsOwnWorkspaceOnItsDisplay() async {
        let big = crowd(9, bundle: "com.big", pid: 7, on: onD2)
        let small = crowd(8, bundle: "com.small", pid: 8, on: CGRect(x: 0, y: 0, width: 300, height: 200))
        let (store, _) = await make(twoDisplays(big + small, focused: nil))
        let w = await store.world
        let homes = Set(big.map { w.workspace(containing: $0.ref)!.id })
        #expect(homes.count == 1 && w.location(ofWorkspace: homes.first!)?.screen == "D2")
        #expect(homes.first != w.screens["D2"]!.active.id, "the crowd piled into D2's active workspace")
        #expect(small.allSatisfy { w.workspace(containing: $0.ref)?.id == w.screens["D1"]!.active.id })
        #expect(await store.currentPlacements()["com.big"] == homes.first)
        #expect(w.invariantViolations().isEmpty)
    }
    /// Rung 1 beats rung 2 in the store too: a remembered crowd goes back where it was.
    @Test func aRememberedCrowdGoesWhereItWas() async {
        let seeded = World.seeded(screens: ["D1", "D2"], config: m1Config())
        let remembered = seeded.screens["D1"]!.active.id
        let big = crowd(9, bundle: "com.big", pid: 7, on: onD2)
        let (store, _) = await make(twoDisplays(big, focused: nil), world: seeded, placements: ["com.big": remembered])
        let w = await store.world
        #expect(big.allSatisfy { w.workspace(containing: $0.ref)?.id == remembered })
    }
    /// Launch-time only: an app first appearing after the launch window is not swept up, and nor
    /// are later windows of an app that was below the threshold at launch — they land by today's
    /// rules (D2's active workspace, where their frames are) or by the app's memory.
    @Test func windowsLaterInTheSessionAreNeverSweptUp() async {
        let clock = Clock()
        let be = FakeBackend(snapshot: twoDisplays([win(a)], focused: a))
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: [],
                               now: { clock.t }, onChange: { _, _ in })
        await store.start()
        clock.t += WorldStore.launchWindow + .seconds(1)
        let late = crowd(9, bundle: "com.late", pid: 7, on: onD2)
        let more = crowd(9, bundle: "com.x", pid: 1, on: onD2, from: 50)
        await store.apply(.snapshot(twoDisplays([win(a)] + late + more, focused: a)))
        let w = await store.world
        #expect(late.allSatisfy { w.workspace(containing: $0.ref)?.id == w.screens["D2"]!.active.id })
        // More windows of an app seen at launch follow the app's memory (a's workspace), never a new row.
        #expect(more.allSatisfy { w.workspace(containing: $0.ref)?.id == w.workspace(containing: a)?.id })
    }
    /// …but an app that first appears inside the launch window still counts as arriving at launch.
    @Test func anAppAppearingWithinTheLaunchWindowIsACrowd() async {
        let clock = Clock()
        let be = FakeBackend(snapshot: twoDisplays([win(a)], focused: a))
        let store = WorldStore(backend: be, config: m1Config(), world: nil, zeroSliverBundleIDs: [],
                               now: { clock.t }, onChange: { _, _ in })
        await store.start()
        clock.t += .seconds(3)
        let big = crowd(9, bundle: "com.big", pid: 7, on: onD2)
        await store.apply(.snapshot(twoDisplays([win(a)] + big, focused: a)))
        let w = await store.world
        #expect(Set(big.map { w.workspace(containing: $0.ref)!.id }).count == 1)
        #expect(w.workspace(containing: big[0].ref)?.id != w.screens["D2"]!.active.id)
    }
    /// #72 still wins over memory: a fullscreen window remembered on D1 but found fullscreen on D2
    /// is filed under D2, because macOS owns its frame.
    @Test func aFullscreenWindowsDisplayBeatsItsMemory() async {
        let seeded = World.seeded(screens: ["D1", "D2"], config: m1Config())
        let remembered = seeded.screens["D1"]!.active.id
        let (store, _) = await make(twoDisplays([win(a, d2.frame, fs: true)], focused: a), world: seeded,
                                    placements: ["com.x": remembered])
        #expect(await store.world.location(of: a)?.screen == "D2")
    }
}
