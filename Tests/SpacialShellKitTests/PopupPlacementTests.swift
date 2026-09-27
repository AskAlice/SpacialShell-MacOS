import Testing
import Foundation
@testable import SpacialShellKit

/// #165: dialogs and popups never land partly off screen. Movable ones are centred on their
/// owner's tile when they fit, else on the display, then clamped inside the display's usable
/// frame; an unmovable sheet moves its owner instead, for as long as it is open. Placement happens
/// on first appearance and on a display change only, so a popup the user moved stays put.
@Suite struct PopupPlacementTests {
    /// The usable frame: a 1000×700 display less a 25 pt menu bar.
    let usable = CGRect(x: 0, y: 25, width: 1000, height: 675)
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                         visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)

    // MARK: - geometry

    @Test func aPopupThatFitsItsOwnersTileIsCentredInTheTile() {
        let tile = CGRect(x: 504, y: 33, width: 488, height: 658)
        #expect(Reconciler.popupPlacement(size: CGSize(width: 300, height: 200), owner: tile, display: usable)
                == CGRect(x: 598, y: 262, width: 300, height: 200))
    }

    @Test func aPopupWiderThanItsOwnersTileIsCentredOnTheDisplay() {
        let narrow = CGRect(x: 8, y: 33, width: 200, height: 658)
        #expect(Reconciler.popupPlacement(size: CGSize(width: 400, height: 200), owner: narrow, display: usable)
                == CGRect(x: 300, y: 262.5, width: 400, height: 200))
        // Taller than the tile is the same: it does not fit, so the display it is.
        let short = CGRect(x: 504, y: 33, width: 488, height: 300)
        #expect(Reconciler.popupPlacement(size: CGSize(width: 300, height: 400), owner: short, display: usable)
                == CGRect(x: 350, y: 162.5, width: 300, height: 400))
    }

    @Test func withNoOwnerAPopupIsCentredOnTheDisplay() {
        #expect(Reconciler.popupPlacement(size: CGSize(width: 400, height: 300), owner: nil, display: usable)
                == CGRect(x: 300, y: 212.5, width: 400, height: 300))
    }

    /// An owner hanging off the display (a shifted owner, an app that put its window there): the
    /// popup centred on it would too, so it is clamped back inside.
    @Test func aPopupCentredOnAnOwnerOffTheEdgeIsClampedOnScreen() {
        let offLeft = CGRect(x: -400, y: 33, width: 600, height: 658)
        #expect(Reconciler.popupPlacement(size: CGSize(width: 300, height: 200), owner: offLeft, display: usable)
                == CGRect(x: 0, y: 262, width: 300, height: 200))
    }

    @Test func aPopupWiderThanTheDisplayIsCentredHorizontally() {
        #expect(Reconciler.popupPlacement(size: CGSize(width: 1200, height: 300), owner: nil, display: usable)
                == CGRect(x: -100, y: 212.5, width: 1200, height: 300))
        #expect(Reconciler.clampPopup(CGRect(x: 300, y: 100, width: 1200, height: 300), to: usable)
                == CGRect(x: -100, y: 100, width: 1200, height: 300))
    }

    @Test func aPopupTallerThanTheDisplayIsAlignedToTheTop() {
        #expect(Reconciler.popupPlacement(size: CGSize(width: 400, height: 800), owner: nil, display: usable)
                == CGRect(x: 300, y: 25, width: 400, height: 800))
        #expect(Reconciler.clampPopup(CGRect(x: 100, y: 300, width: 400, height: 800), to: usable)
                == CGRect(x: 100, y: 25, width: 400, height: 800))
    }

    @Test func aPopupNearAnEdgeIsClampedInside() {
        #expect(Reconciler.clampPopup(CGRect(x: 900, y: 600, width: 300, height: 200), to: usable)
                == CGRect(x: 700, y: 500, width: 300, height: 200), "right and bottom")
        #expect(Reconciler.clampPopup(CGRect(x: -50, y: 0, width: 300, height: 200), to: usable)
                == CGRect(x: 0, y: 25, width: 300, height: 200), "left, and under the menu bar")
        let inside = CGRect(x: 120, y: 80, width: 300, height: 200)
        #expect(Reconciler.clampPopup(inside, to: usable) == inside, "already on screen: not moved")
    }

    @Test func aSheetShiftIsJustEnoughToBringItOnScreen() {
        #expect(Reconciler.sheetShift(CGRect(x: 892, y: 55, width: 400, height: 200), display: usable) == -292)
        #expect(Reconciler.sheetShift(CGRect(x: -60, y: 55, width: 400, height: 200), display: usable) == 60)
        #expect(Reconciler.sheetShift(CGRect(x: 300, y: 55, width: 400, height: 200), display: usable) == 0)
        // Wider than the display: centred on it.
        #expect(Reconciler.sheetShift(CGRect(x: 400, y: 55, width: 1200, height: 200), display: usable) == -500)
    }

    // MARK: - the reconciler: an unmovable sheet moves its owner

    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1), s = WindowRef(id: 3, pid: 1)

    /// `a` and `b` as columns, `s` a sheet on `b`, the right-hand column.
    func world() -> World {
        var w = World.empty(screens: ["D1"], defaultLayout: .column)
        w.adopt(a, kind: .tile, on: "D1"); w.adopt(b, kind: .tile, on: "D1")
        w.adopt(s, kind: .float, on: "D1", parent: b)
        return w
    }
    func desired(_ w: World, observed: [WindowRef: CGRect], unmovable: Set<WindowRef> = []) -> [WindowRef: Placement] {
        Reconciler.desired(world: w, displays: [d1], config: LayoutConfig(gap: 8), observed: observed, prePark: [:],
                           parkedNow: [], zeroSliver: [], unmovable: unmovable)
    }
    func tileB() throws -> CGRect {
        guard case .frame(let f)? = desired(world(), observed: [:])[b] else { throw CancellationError() }
        return f
    }

    @Test func anUnmovableSheetOffTheEdgeShiftsItsOwnerJustEnough() throws {
        let tile = try tileB()
        let sheet = CGRect(x: tile.maxX - 100, y: tile.minY + 22, width: 400, height: 200)
        let observed = [b: tile, s: sheet]
        // Not known to be unmovable: the owner keeps its tile (the sheet is placed like any popup).
        #expect(desired(world(), observed: observed)[b] == .frame(tile))
        let d = desired(world(), observed: observed, unmovable: [s])
        let dx = usable.maxX - sheet.maxX
        #expect(d[b] == .frame(tile.offsetBy(dx: dx, dy: 0)))
        #expect(d[s] == .frame(sheet.offsetBy(dx: dx, dy: 0)))
        if case .frame(let f)? = d[s] { #expect(usable.contains(f), "the sheet is fully visible") }
        #expect(d[a] == desired(world(), observed: observed)[a], "the neighbour is not disturbed")
    }

    @Test func anUnmovableSheetAlreadyOnScreenLeavesItsOwnerAlone() throws {
        let tile = try tileB()
        let sheet = CGRect(x: tile.midX - 150, y: tile.minY + 22, width: 300, height: 200)
        #expect(desired(world(), observed: [b: tile, s: sheet], unmovable: [s])[b] == .frame(tile))
    }

    /// Once the owner has moved (and the sheet with it) the shift is the same: the reconciler holds
    /// the shifted frame instead of fighting it back to the tile.
    @Test func theShiftHoldsOnceTheOwnerHasMoved() throws {
        let tile = try tileB()
        let sheet = CGRect(x: tile.maxX - 100, y: tile.minY + 22, width: 400, height: 200)
        let dx = usable.maxX - sheet.maxX
        let moved = [b: tile.offsetBy(dx: dx, dy: 0), s: sheet.offsetBy(dx: dx, dy: 0)]
        let d = desired(world(), observed: moved, unmovable: [s])
        #expect(d[b] == .frame(moved[b]!) && d[s] == .frame(moved[s]!))
        #expect(Reconciler.plan(desired: d, observed: moved, parkedNow: []).allSatisfy {
            if case .setFrame(let r, _) = $0 { r != b && r != s } else { true }
        })
    }

    // MARK: - placePopups

    func place(_ requests: [WindowRef: PopupRequest], _ w: World, observed: [WindowRef: CGRect],
               parkedNow: Set<WindowRef> = []) -> ([WindowRef: Placement], Set<WindowRef>) {
        var d = Reconciler.desired(world: w, displays: [d1], config: LayoutConfig(gap: 8), observed: observed, prePark: [:],
                                   parkedNow: parkedNow, zeroSliver: [])
        let placed = Reconciler.placePopups(requests, into: &d, world: w, displays: [d1], observed: observed, parkedNow: parkedNow)
        return (d, placed)
    }

    @Test func anAttachedDialogIsCentredOnItsOwnersTile() throws {
        let tile = try tileB()
        let dialog = CGRect(x: tile.maxX - 100, y: tile.minY + 22, width: 300, height: 200)
        let (d, placed) = place([s: PopupRequest(.place)], world(), observed: [b: tile, s: dialog])
        #expect(placed == [s])
        #expect(d[s] == .frame(Reconciler.centered(size: dialog.size, in: tile)))
    }

    @Test func anEphemeralPopupIsCentredOnItsOwnerHint() throws {
        let tile = try tileB()
        var w = world(); w.remove(s)
        let v = WindowRef(id: 9, pid: 1)
        w.adopt(v, kind: .ephemeral, on: "D1")
        let popup = CGRect(x: 950, y: 600, width: 300, height: 200)
        let (d, _) = place([v: PopupRequest(.place, owner: b)], w, observed: [b: tile, v: popup])
        #expect(d[v] == .frame(Reconciler.centered(size: popup.size, in: tile)))
        // Without an owner: the display.
        let (alone, _) = place([v: PopupRequest(.place)], w, observed: [b: tile, v: popup])
        #expect(alone[v] == .frame(Reconciler.centered(size: popup.size, in: usable)))
    }

    /// No request, no placement: a popup the user moved (even partly off screen) is left alone.
    @Test func aPopupWithNoRequestIsLeftWhereItIs() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let v = WindowRef(id: 9, pid: 1)
        w.adopt(v, kind: .ephemeral, on: "D1")
        let (d, placed) = place([:], w, observed: [v: CGRect(x: 900, y: 600, width: 300, height: 200)])
        #expect(d[v] == .untouched && placed.isEmpty)
    }

    /// A display change clamps: a popup still fully on screen stays exactly where it is.
    @Test func aClampLeavesAnOnScreenPopupWhereItIs() {
        var w = World.empty(screens: ["D1"], defaultLayout: .maximize)
        let v = WindowRef(id: 9, pid: 1)
        w.adopt(v, kind: .ephemeral, on: "D1")
        let here = CGRect(x: 40, y: 400, width: 300, height: 200)
        let (d, _) = place([v: PopupRequest(.clamp)], w, observed: [v: here])
        #expect(d[v] == .frame(here))
        let (off, _) = place([v: PopupRequest(.clamp)], w, observed: [v: here.offsetBy(dx: 900, dy: 0)])
        #expect(off[v] == .frame(CGRect(x: 700, y: 400, width: 300, height: 200)))
    }

    /// A dialog on an owner in an inactive (parked) row waits for its row to be shown.
    @Test func aParkedPopupKeepsItsRequest() {
        var w = world()
        w = CommandRunner.apply(.focusWindowRef(s), to: w).0
        w = CommandRunner.apply(.focusWorkspace(.down), to: w).0
        let (_, placed) = place([s: PopupRequest(.place)], w, observed: [b: CGRect(x: 10, y: 35, width: 485, height: 654),
                                                                           s: CGRect(x: 50, y: 63, width: 300, height: 180)])
        #expect(placed.isEmpty)
    }

    // MARK: - end to end through the store

    let c = WindowRef(id: 4, pid: 1)

    func columns() -> Config { var c = Config(); c.showPanels = false; c.categoryOrder = []; c.defaultLayout = .column; return c }
    func win(_ r: WindowRef, _ f: CGRect, kind: WindowKind = .tile, parent: WindowRef? = nil, standard: Bool = true) -> WindowSnapshot {
        WindowSnapshot(ref: r, frame: f, title: "t", bundleID: "com.x", kind: kind, parent: parent, isMinimized: false,
                       isFullscreen: false, isStandard: standard)
    }
    func snap(_ ws: [WindowSnapshot], focused: WindowRef?, display: DisplayInfo? = nil) -> Snapshot {
        Snapshot(displays: [display ?? d1], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false)], windows: ws, focused: focused)
    }
    /// `a` and `b` tiled as columns, `b` focused. Returns the store, the backend and b's tile.
    func start() async -> (WorldStore, FakeBackend, CGRect) {
        let be = FakeBackend(snapshot: snap([win(a, CGRect(x: 0, y: 0, width: 300, height: 200)),
                                             win(b, CGRect(x: 0, y: 0, width: 300, height: 200))], focused: b))
        let store = WorldStore(backend: be, config: columns(), world: nil, zeroSliverBundleIDs: [], onChange: { _, _ in })
        await store.start()
        return (store, be, await be.frames[b]!)
    }
    /// What the backend has on screen now, as a snapshot.
    func current(_ be: FakeBackend, _ extra: [WindowSnapshot] = [], focused: WindowRef? = nil) async -> Snapshot {
        let f = await be.frames
        return snap([win(a, f[a]!), win(b, f[b]!)] + extra.map { w in win(w.ref, f[w.ref] ?? w.frame, kind: w.kind, parent: w.parent,
                                                                           standard: w.isStandard) },
                    focused: focused ?? b)
    }
    func frameWrites(_ r: WindowRef, _ be: FakeBackend) async -> [CGRect] {
        await be.calls.compactMap { if case .setFrame(r, let f) = $0 { f } else { nil } }
    }

    /// The acceptance case: a sheet opened off the right edge will not move; its owner shifts left
    /// just enough to show it, the reconciler holds that shift while it is open, and the owner
    /// gets its tile back when the sheet closes.
    @Test func aSheetOffTheEdgeShiftsItsOwnerAndTheOwnerIsRestoredOnClose() async throws {
        let (store, be, tile) = await start()
        let sheet = CGRect(x: tile.maxX - 100, y: tile.minY + 22, width: 400, height: 200)
        await be.open(s, at: sheet); await be.pin(s, to: b)
        let opened = win(s, sheet, kind: .float, parent: b, standard: false)
        await store.apply(.snapshot(await current(be, [opened], focused: s)))
        // First the ordinary placement is tried: centred on the owner's tile. It does not take.
        #expect(await frameWrites(s, be) == [Reconciler.centered(size: sheet.size, in: tile)])
        #expect(await be.frames[s] == sheet)
        // Its echo shows it where it was: an unmovable sheet. The owner moves instead.
        await be.reset()
        await store.apply(.windowMoved(s, sheet))
        let dx = d1.visibleFrame.maxX - sheet.maxX
        #expect(await frameWrites(b, be) == [tile.offsetBy(dx: dx, dy: 0)])
        let shown = try #require(await be.frames[s])
        #expect(d1.visibleFrame.contains(shown), "the sheet is fully on screen")
        // Held while it is open: the echoes and the next snapshot write nothing for the owner.
        await be.reset()
        await store.apply(.windowMoved(b, await be.frames[b]!))
        await store.apply(.snapshot(await current(be, [opened], focused: s)))
        #expect(await frameWrites(b, be).isEmpty, "the reconciler fought the shift")
        // Closed: the owner is restored to its tile.
        await be.reset()
        await store.apply(.snapshot(await current(be, focused: b)))
        #expect(await frameWrites(b, be) == [tile])
    }

    /// An attached dialog that can move is simply placed: centred on its owner's tile, owner untouched.
    @Test func aMovableAttachedDialogIsPlacedAndItsOwnerStays() async {
        let (store, be, tile) = await start()
        let dialog = CGRect(x: tile.maxX - 100, y: tile.minY + 22, width: 300, height: 200)
        await be.open(s, at: dialog); await be.reset()
        await store.apply(.snapshot(await current(be, [win(s, dialog, kind: .float, parent: b, standard: false)], focused: s)))
        let target = Reconciler.centered(size: dialog.size, in: tile)
        #expect(await be.frames[s] == target)
        await store.apply(.windowMoved(s, target))   // its echo: it moved
        #expect(await frameWrites(b, be).isEmpty)
        #expect(await be.frames[b] == tile)
    }

    /// A standalone file panel (not a standard window, no AX parent) from the focused app, opened
    /// hanging off the edge: centred on that app's tile.
    @Test func aStandaloneDialogIsCentredOnTheFocusedAppsTile() async {
        let (store, be, tile) = await start()
        let panel = CGRect(x: 900, y: 500, width: 300, height: 250)
        await be.open(c, at: panel)
        await store.apply(.snapshot(await current(be, [win(c, panel, kind: .float, standard: false)], focused: b)))
        #expect(await be.frames[c] == Reconciler.centered(size: panel.size, in: tile))
    }

    /// Wider than its owner's tile: centred on the display instead.
    @Test func aPopupWiderThanItsOwnersTileIsCentredOnTheDisplayThroughTheStore() async {
        let (store, be, tile) = await start()
        let wide = CGRect(x: 900, y: 500, width: tile.width + 100, height: 250)
        await be.open(c, at: wide)
        await store.apply(.snapshot(await current(be, [win(c, wide, kind: .ephemeral, parent: b)], focused: b)))
        #expect(await be.frames[c] == Reconciler.centered(size: wide.size, in: d1.visibleFrame))
    }

    /// Placed once: after the user drags it (even partly off screen), nothing moves it back.
    @Test func aPopupTheUserMovedStaysPut() async {
        let (store, be, _) = await start()
        let popup = CGRect(x: 100, y: 100, width: 300, height: 200)
        await be.open(c, at: popup)
        let visitor = win(c, popup, kind: .ephemeral)
        await store.apply(.snapshot(await current(be, [visitor], focused: b)))
        #expect(await be.frames[c] != popup, "placed on first appearance")
        await be.reset()
        let dragged = CGRect(x: 850, y: 600, width: 300, height: 200)
        await be.open(c, at: dragged)
        await store.apply(.humanInput)
        await store.apply(.windowMoved(c, dragged))
        await store.apply(.snapshot(await current(be, [visitor], focused: b)))
        await store.run(.focusWindow(.left))
        #expect(await frameWrites(c, be).isEmpty, "a popup the user moved was moved back")
    }

    /// A display change clamps every popup back inside its display, once.
    @Test func aDisplayChangeClampsPopupsBackOnScreen() async {
        let (store, be, _) = await start()
        let popup = CGRect(x: 650, y: 300, width: 300, height: 200)
        await be.open(c, at: popup)
        let visitor = win(c, popup, kind: .ephemeral)
        await store.apply(.snapshot(await current(be, [visitor], focused: b)))
        await be.open(c, at: popup)   // the user put it back at the right, fully on this display
        await store.apply(.windowMoved(c, popup))
        await be.reset()
        let narrower = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 800, height: 700),
                                   visibleFrame: CGRect(x: 0, y: 25, width: 800, height: 675), isMain: true)
        var s = await current(be, [visitor], focused: b); s.displays = [narrower]
        await store.apply(.snapshot(s))
        #expect(await frameWrites(c, be) == [CGRect(x: 500, y: 300, width: 300, height: 200)])
        // Once: the next snapshot on the same displays leaves it alone.
        await be.reset()
        s = await current(be, [visitor], focused: b); s.displays = [narrower]
        await store.apply(.snapshot(s))
        #expect(await frameWrites(c, be).isEmpty)
    }
}
