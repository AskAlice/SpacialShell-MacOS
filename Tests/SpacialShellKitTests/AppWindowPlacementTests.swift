import Foundation
import Testing
@testable import SpacialShellKit

extension WorldStoreTests {
    @Test(arguments: [499.0, 500.0, 501.0])
    func onlyPopoutsStrictlyBelowAQuarterOfTheirDisplayFloat(width: Double) async {
        let main = CGRect(x: 0, y: 25, width: 800, height: 600)
        let (store, be) = await make(snap([win(a, main)], focused: a))
        let popup = CGRect(x: 100, y: 100, width: width, height: 350)
        await be.open(b, at: popup)
        await store.apply(.snapshot(snap([win(a, main), win(b, popup)], focused: b)))
        let world = await store.world
        #expect(world.workspace(containing: b)?.floating.contains(b) == (width < 500))
        #expect(world.owner(of: b) == (width < 500 ? a : nil))
        #expect(world.focus.window == b)
        if width < 500 {
            #expect(await be.frames[b]?.size == popup.size)
            #expect(world.tabs(in: world.workspace(containing: a)!) == [a])
            await be.reset()
            await store.run(.focusWindowRef(a))
            #expect(await be.calls.contains(.raiseWithoutActivating(b)))
            #expect(await store.world.focus.window == a)
            await store.apply(.snapshot(snap([win(a, main), win(b, main)], focused: b)))
            #expect(await store.world.workspace(containing: b)?.floating.contains(b) == true)
        }
    }

    @Test func anExplicitTileRuleWinsOverSmallPopoutDetection() async {
        var config = m1Config(); config.tile = [AppRule(bundleId: "com.x")]
        let (store, _) = await make(snap([win(a)], focused: a), config: config)
        await store.apply(.snapshot(snap([win(a), win(b)], focused: b)))
        #expect(await store.world.owner(of: b) == nil)
        #expect(await store.world.workspace(containing: b)?.floating.contains(b) == false)
    }

    @Test func aSmallWindowNeedsAnOwnerOnItsOwnDisplay() async {
        let (store, _) = await make(twoDisplays([win(a)], focused: a))
        let frame = CGRect(x: d2.frame.minX + 50, y: d2.frame.minY + 50, width: 200, height: 150)
        await store.apply(.snapshot(twoDisplays([win(a), win(b, frame)], focused: b)))
        #expect(await store.world.owner(of: b) == nil)
        #expect(await store.world.workspace(containing: b)?.floating.contains(b) == false)
    }

    @Test func movingOneWindowCarriesItsAppGroupOnThatDisplay() async {
        let other = WindowRef(id: 3, pid: 3)
        let (store, _) = await make(snap([win(a), win(b), win(other, bundle: "com.other")], focused: a), config: routing())
        let destination = await store.world.workspace(containing: other)!.id
        await store.run(.moveWindowRefToWorkspace(b, destination, follow: false))
        #expect(await store.world.workspace(containing: a)?.id == destination)
        #expect(await store.world.workspace(containing: b)?.id == destination)
        #expect(await store.currentMovedApps().contains("com.x"))
        let later = WindowRef(id: 4, pid: 4)
        await store.apply(.snapshot(snap([win(a), win(b), win(other, bundle: "com.other"),
                                         win(later, CGRect(x: 0, y: 25, width: 800, height: 600))])))
        #expect(await store.world.workspace(containing: later)?.id == destination)
        #expect(await store.world.invariantViolations().isEmpty)
    }

    @Test func existingAppSplitsAreRepairedWithoutCrossingDisplays() async {
        let other = WindowRef(id: 3, pid: 1)
        var world = World.empty(screens: ["D1", "D2"], defaultLayout: .maximize)
        world.adopt(a, kind: .tile, on: "D1")
        world = CommandRunner.apply(.focusWorkspace(.down), to: world, in: .test()).0
        world.adopt(b, kind: .float, on: "D1")
        world.adopt(other, kind: .tile, on: "D2")
        let there = CGRect(x: d2.frame.minX + 50, y: d2.frame.minY + 50, width: 600, height: 400)
        let (store, _) = await make(twoDisplays([win(a), win(b, kind: .float), win(other, there)], focused: b),
                                    config: routing(), world: world)
        let grouped = await store.world
        #expect(grouped.workspace(containing: a)?.id == grouped.workspace(containing: b)?.id)
        #expect(grouped.workspace(containing: b)?.floating.contains(b) == true)
        #expect(grouped.location(of: other)?.screen == "D2")
        #expect(grouped.location(of: a)?.screen == "D1")
        #expect(grouped.invariantViolations().isEmpty)
    }
}
