import Testing
import AppKit
import SwiftUI
import UniformTypeIdentifiers
@testable import SpacialShellUI
@testable import SpacialShellKit

/// Does a tab drag actually reach the rail?
///
/// The panels are borderless, non-activating `NSPanel`s that can never become key, in an
/// `LSUIElement` app. Whether AppKit wires SwiftUI's `.dropDestination` up under those conditions
/// is not answerable by reading the code, so it is answered here instead of by hand.
///
/// These assert the *plumbing* — that a drop destination exists and advertises the right
/// pasteboard type. They cannot assert that a human dragging a mouse lands one; that needs the
/// real event stream. But a view that registers no dragged types can never receive a drop, so a
/// failure here is conclusive in the unhappy direction.
@MainActor
@Suite(.serialized) struct DragTests {
    let meta: (Int32) -> AppMeta = { _ in
        AppMeta(name: "App", icon: nil, bundleID: "com.apple.Safari", category: .web)
    }

    func railState() -> ScreenShellState {
        ScreenShellState(
            display: "D1", isFocusedScreen: true,
            rail: [WorkspaceRailItem(id: UUID(), index: 0, name: "Code", symbol: "terminal",
                                     windowCount: 1, windows: [WindowRef(id: 1, pid: 1)],
                                     isActive: true, isPinned: false, isTrailingEmpty: false),
                   WorkspaceRailItem(id: UUID(), index: 1, name: "New", symbol: "plus",
                                     windowCount: 0, windows: [],
                                     isActive: false, isPinned: false, isTrailingEmpty: true)],
            tabs: [], layout: .split)
    }

    func barState() -> ScreenShellState {
        ScreenShellState(
            display: "D1", isFocusedScreen: true, rail: railState().rail,
            tabs: [WindowTabItem(ref: WindowRef(id: 1, pid: 1), isFocused: true,
                                 isFloating: false, isHidden: false)],
            layout: .split)
    }

    /// Every dragged type registered anywhere in the hosted hierarchy.
    func registeredTypes(in view: NSView) -> Set<String> {
        var out = Set(view.registeredDraggedTypes.map(\.rawValue))
        for sub in view.subviews { out.formUnion(registeredTypes(in: sub)) }
        return out
    }

    /// A destination can receive a tab drag only if it registered a type the tab conforms to.
    func acceptsTabDrags(_ view: NSView) -> Bool {
        registeredTypes(in: view).contains { tabType.conforms(to: UTType($0) ?? .item) }
    }

    func mount(_ v: some View, in window: NSWindow, size: CGSize) -> NSView {
        let host = NSHostingView(rootView: v)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // A drop destination is registered when the view joins a window; give AppKit the runloop
        // turn it needs to get there before asking what it registered.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return host
    }

    /// What the dragged tab actually advertises.
    var tabType: UTType { .data }

    /// The control: an ordinary window. If this fails, the drop destination is wrong in a way
    /// that has nothing to do with the panels, and the panel result below means nothing.
    @Test func railInAnOrdinaryWindowRegistersTheTabType() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 140, height: 800),
                         styleMask: [.titled], backing: .buffered, defer: false)
        let host = mount(ScreenPanelView(state: railState(), launcherURL: "raycast://",
                                         metaFor: meta, send: { _ in }),
                         in: w, size: CGSize(width: 140, height: 800))
        #expect(acceptsTabDrags(host), "an ordinary window registers: \(registeredTypes(in: host))")
    }

    /// The real question: the same view in the window the shell actually uses.
    @Test func railInAPanelWindowRegistersTheTabType() {
        let panel = PanelWindow()
        panel.setFrame(NSRect(x: 0, y: 0, width: 140, height: 800), display: false)
        let host = mount(ScreenPanelView(state: railState(), launcherURL: "raycast://",
                                         metaFor: meta, send: { _ in }),
                         in: panel, size: CGSize(width: 140, height: 800))
        #expect(acceptsTabDrags(host), "PanelWindow registers: \(registeredTypes(in: host))")
    }

    @Test func barInAPanelWindowRegistersTheTabType() {
        let panel = PanelWindow()
        panel.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 34), display: false)
        let host = mount(WorkspacePanelView(state: barState(), metaFor: meta, sizing: .fit, send: { _ in }),
                         in: panel, size: CGSize(width: 1200, height: 34))
        #expect(acceptsTabDrags(host), "PanelWindow bar registers: \(registeredTypes(in: host))")
    }

    /// The regression this suite exists for. A dragged item is only ever offered to a destination
    /// that registered a type it conforms to. A private `UTType(exportedAs:)` conforms to nothing
    /// — the bundle never declares it — so the drag ran and silently went nowhere.
    @Test func theDraggedTypeConformsToWhatDestinationsRegister() {
        #expect(tabType.isDeclared)
        #expect(tabType.conforms(to: .data), "supertypes: \(tabType.supertypes)")
        #expect(tabType.conforms(to: .item))
    }

    /// #75: a tile and a tab share `public.data`, so the rail tells them apart by decoding. Each
    /// must come back as what it is, and neither may decode as the other.
    @Test func railDropsTellATileFromATab() throws {
        let tab = try JSONEncoder().encode(DraggedWindow(ref: WindowRef(id: 1, pid: 1)))
        let tile = try JSONEncoder().encode(DraggedWorkspace(workspace: UUID()))
        guard case .window = try JSONDecoder().decode(RailDrop.self, from: tab) else { Issue.record("tab"); return }
        guard case .workspace = try JSONDecoder().decode(RailDrop.self, from: tile) else { Issue.record("tile"); return }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(DraggedWindow.self, from: tile) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(DraggedWorkspace.self, from: tab) }
    }

    /// Why a private type cannot be used here, recorded so nobody re-introduces one: a UTI
    /// invented at runtime has no conformance unless the bundle declares it, and the dev binary
    /// (Scripts/dev.sh) has no Info.plist to declare it in.
    @Test func aRuntimeDeclaredPrivateTypeWouldConformToNothing() {
        let n = Int.random(in: 10_000...99_999)
        for t in [UTType(exportedAs: "me.askalice.probe.e\(n)", conformingTo: .data),
                  UTType(importedAs: "me.askalice.probe.i\(n)", conformingTo: .data)] {
            #expect(t.supertypes.isEmpty, "macOS started honouring conformingTo — a private type is viable again")
            #expect(!t.conforms(to: .data))
        }
    }
}
