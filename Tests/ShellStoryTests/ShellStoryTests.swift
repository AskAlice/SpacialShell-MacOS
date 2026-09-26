import Testing
import AppKit
import SwiftUI
import SnapshotTesting
import SpacialShellKit
@testable import SpacialShellUI

/// Storybook-style rendering of every shell story, twice over:
///
/// 1. **Image snapshots** — pixel references per story × appearance under `__Snapshots__/`.
///    First run (or `SNAPSHOT_RECORD=1`) records; later runs diff. References are committed, so
///    a stray padding change shows up as an image diff in review, and the recorded stills double
///    as PR media (AGENTS.md rule).
/// 2. **LayoutLint** — structural asserts: no text drawn over text, nothing escaping its
///    container, content fits the geometry it was given (wrap/truncate, don't clip).
///
/// macOS-only, like everything AppKit; stories flagged `knownOverflow` model conditions the
/// design has not built handling for yet (rail overflow) — their lint runs under
/// `withKnownIssue` so the gap stays visible without a red suite.
@MainActor
@Suite(.serialized) struct ShellStoryTests {
    static let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"

    /// Hosts the story at its true geometry inside an offscreen window — accessibility frames
    /// (which LayoutLint reads) only exist for views in a window.
    func host(_ story: Story, appearance: NSAppearance.Name) -> NSView {
        let view = NSHostingView(rootView: story.view)
        // #53: setting it on the view alone is not enough. The panels draw on materials, and
        // `NSVisualEffectView` resolves vibrancy against the *application's* appearance — so with
        // the view forced to `.aqua` on a Mac running Dark, every light reference mismatched and
        // the gate silently depended on a machine setting. Forcing it app-wide is what the render
        // actually reads; the view's own appearance stays set for SwiftUI's resolved colours.
        view.appearance = NSAppearance(named: appearance)
        let size = story.size ?? view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        // One runloop turn for work SwiftUI defers past the first layout — the tab bar scrolling
        // its focused tab into view (#14) — so the snapshot shows the settled state.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// Draw the story at exactly **one pixel per point**, whatever display the test happens to run
    /// on (#53).
    ///
    /// Snapshotting an `NSView` directly renders through its window, whose backing scale comes from
    /// the screen: 2× on this Mac, 1× on the machine that recorded the references, so *every* story
    /// mismatched — 96×1600 pixels against a 48×800 reference — and the gate silently depended on
    /// the hardware. Drawing into a bitmap we size ourselves takes that variable away.
    func render(_ view: NSView) -> NSImage {
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width.rounded()), pixelsHigh: Int(size.height.rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return NSImage(size: size) }
        rep.size = size                       // 1 pt == 1 px, regardless of the screen
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// #87: a sheet that fits stays the designed single row; one that does not wraps until it does.
    /// Every cheat-sheet row names an SF Symbol this macOS actually has. A missing one is a SwiftUI
    /// fault on every render, and the flood got the whole process's logging quarantined (#94).
    @Test func everyCheatSheetSymbolExists() {
        let missing = CheatSheet.rows(for: Config()).map(\.symbol)
            .filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "missing SF Symbols: \(missing)")
    }

    /// #112: likewise every glyph the workspace menu's "Set symbol" offers.
    @Test func everyWorkspaceMenuSymbolExists() {
        let missing = RailMenu.symbols.map(\.name)
            .filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "missing SF Symbols: \(missing)")
    }

    /// #115: and every glyph a category draws on the rail.
    @Test func everyCategorySymbolExists() {
        let missing = AppCategory.allCases.map(\.symbol)
            .filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "missing SF Symbols: \(missing)")
    }

    /// #128, #129: the tab bar's and tab menu's own glyphs.
    @Test func everyTabGlyphExists() {
        let missing = ["pin.fill", "pin.circle.fill", "pin.circle", "pin.slash", "xmark"]
            .filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "missing SF Symbols: \(missing)")
    }

    @Test func cheatSheetWrapsToFitItsArea() {
        let groups = CheatSheetController.grouped(CheatSheet.rows(for: Config()))
        #expect(CheatSheetView.fitting(groups, in: 4000).view.rows == 1)
        let narrow = CheatSheetView.fitting(groups, in: 1024 - 48)
        #expect(narrow.view.rows > 1)
        #expect(narrow.size.width <= 1024 - 48 - 2 * CheatSheetView.sideMargin)
    }

    @Test(arguments: ["light", "dark"])
    func storiesRenderCleanly(mode: String) {
        let appearance: NSAppearance.Name = mode == "dark" ? .darkAqua : .aqua
        for story in Stories.all {
            let view = host(story, appearance: appearance)
            // Tolerances, not exactness (#53): the same story rendered on two Macs differs in
            // anti-aliasing and colour-space rounding while looking identical to a human — the
            // recorded references and this machine's render are indistinguishable side by side, yet
            // every one mismatched byte-wise. `perceptualPrecision` compares how it *looks*, which
            // is what these stories are for; a real regression (a moved control, a wrong colour, a
            // clipped label) moves far more than this.
            assertSnapshot(of: render(view), as: .image(precision: 0.99, perceptualPrecision: 0.98),
                           named: "\(story.name)-\(mode)", record: Self.record)
            let lint = { LayoutLint.issues(in: view, story: "\(story.name)-\(mode)", truncates: story.truncates) }
            if story.knownOverflow {
                withKnownIssue("\(story.name): overflow handling not built yet (T18/T19)", isIntermittent: true) {
                    let issues = lint()
                    #expect(issues.isEmpty, "\(issues.joined(separator: "\n"))")
                }
            } else {
                let issues = lint()
                #expect(issues.isEmpty, "\(issues.joined(separator: "\n"))")
            }
        }
    }
}
