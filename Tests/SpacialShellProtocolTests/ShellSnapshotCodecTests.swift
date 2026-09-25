import Testing
import Foundation
@testable import SpacialShellProtocol

@Suite struct ShellSnapshotCodecTests {

    // Task 2 predates IPCCodec (Task 3) — use a local encoder/decoder rather than reach ahead.
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()
    static let decoder = JSONDecoder()

    static func sample(generation: UInt64 = 1) -> ShellSnapshot {
        let wsID = UUID()
        let windowID = UUID()
        _ = windowID
        let ref = WindowRef(id: 7, pid: 123)

        let workspaceRow = ShellSnapshot.WorkspaceRow(
            id: wsID, name: "Code", symbol: "chevron.left.forwardslash.chevron.right",
            layout: .half, pinned: true, isActive: true, windowCount: 1, isTrailingEmpty: false)

        let windowRow = ShellSnapshot.WindowRow(
            window: ref, pid: 123, workspaceId: wsID, title: "main.swift", appName: "Xcode",
            bundleID: "com.apple.dt.Xcode", isFocused: true, isVisibleUnderLayout: true,
            isFloating: false, isHidden: false)

        let screenRow = ShellSnapshot.ScreenRow(
            display: "D1", frame: RectDTO(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: RectDTO(x: 0, y: 0, width: 1920, height: 1055),
            isMain: true, isFocused: true, isCoveredByFullscreen: false,
            insets: EdgeInsetsDTO(top: 34, left: 48, right: 0, bottom: 0),
            activeWorkspaceId: wsID, workspaces: [workspaceRow], windows: [windowRow])

        let focus = ShellSnapshot.FocusRow(screen: "D1", window: ref)

        let chrome = ShellSnapshot.ChromeRow(
            panelWidth: 48, panelHeight: 34, railSide: "left",
            launcherURL: "raycast://", showPanels: true)

        return ShellSnapshot(
            v: 1, generation: generation, screens: [screenRow], focus: focus, zen: false,
            capabilities: ["workspace-crud", "zen", "symbols"],
            locked: false, chrome: chrome)
    }

    @Test func roundTripsThroughJSON() throws {
        let snap = Self.sample()
        let data = try Self.encoder.encode(snap)
        let decoded = try Self.decoder.decode(ShellSnapshot.self, from: data)
        #expect(decoded == snap)
    }

    @Test func goldenTopLevelKeySet() throws {
        let snap = Self.sample()
        let data = try Self.encoder.encode(snap)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = Set((obj ?? [:]).keys)
        let expected: Set<String> = [
            "v", "generation", "screens", "focus", "zen",
            "capabilities", "locked", "chrome",
        ]
        #expect(keys == expected)
    }

    @Test func goldenLayoutAndUUIDEncoding() throws {
        let snap = Self.sample()
        let data = try Self.encoder.encode(snap)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let screens = obj?["screens"] as? [[String: Any]]
        let workspaces = screens?.first?["workspaces"] as? [[String: Any]]
        let layout = workspaces?.first?["layout"] as? String
        #expect(layout == "half")
        let id = workspaces?.first?["id"] as? String
        #expect(id == id?.uppercased())
    }

    @Test func isEquivalentIgnoresOnlyGeneration() {
        let a = Self.sample(generation: 1)
        var b = a
        b.generation = 2
        #expect(a.isEquivalent(to: b))
        #expect(a != b)   // Equatable still sees the generation difference

        var c = a
        c.zen = true
        #expect(!a.isEquivalent(to: c))
    }

    @Test func windowRowsCarryWorkspaceIdAcrossAllWorkspacesOnTheScreen() throws {
        let snap = Self.sample()
        #expect(snap.screens[0].windows.allSatisfy { $0.workspaceId != nil })
        var ephemeral = snap.screens[0].windows[0]
        ephemeral.workspaceId = nil
        #expect(ephemeral.workspaceId == nil)
    }
}
