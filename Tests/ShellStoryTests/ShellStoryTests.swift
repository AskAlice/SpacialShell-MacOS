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
/// Draws the next number every time it is drawn: an animation or a clock, reduced to the part
/// `settle` sees. Synchronous, so nothing keeps drawing once the test is over. A `TimelineView`
/// ticks on a background thread and outlives the test.
private struct Ticking: NSViewRepresentable {
    final class View: NSView {
        private var draws = 0
        override func draw(_ dirtyRect: NSRect) {
            draws += 1
            ("\(draws)" as NSString).draw(at: .zero, withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
        }
    }
    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ view: View, context: Context) {}
}

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
        settle(view, story: story)
        return view
    }

    /// Consecutive identical renders that count as settled. Every deferred change measured so far
    /// lands on the first pass, idle or with every core busy. Five leaves room for a chain of them.
    static let quietPasses = 5
    /// The give-up point, in passes rather than seconds. A wall-clock cap fails the big stories
    /// (the 1440 × 900 spatial view) on a loaded machine, where one render takes seconds. A story
    /// that changes on every pass reaches this many passes all the same.
    static let maxPasses = 100

    /// Spin the run loop until the story stops changing, however long that takes (#159).
    ///
    /// SwiftUI finishes some of a view's first appearance on later run-loop passes. The overview
    /// focuses its search field from `onAppear`, which greys the placeholder and moves the content
    /// down 2 pt. The problem alerts settle their buttons the same way, and the tab bar scrolls its
    /// focused tab into view (#14). This used to be a fixed 50 ms spin. Under load the main thread
    /// could miss that window, so the snapshot caught the half-built frame: `overview-results-light`
    /// mismatched on 3.8% of its pixels. What matters is run-loop passes, not wall time. So pass
    /// until `quietPasses` renders in a row come out byte-identical. A story that never settles (an
    /// animation, a clock, a blinking caret) fails here instead of being snapshotted mid-change.
    ///
    /// Quiet passes cannot bound work whose *scheduling* depends on load. Under a loaded full-suite
    /// run, 2 in 10 still snapshotted the overview before its focus landed. That is plausibly because
    /// other suites' main-actor jobs run inside this spin. So a story that asks for focus
    /// (`awaitsFocus`) waits for the condition itself, a field editor holding first responder,
    /// before its quiet passes start to count.
    func settle(_ view: NSView, story: Story) {
        func pixels() -> Data {
            let rep = bitmap(view)
            return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
        }
        func focused() -> Bool { !story.awaitsFocus || view.window?.firstResponder is NSTextView }
        var focusPasses = 0
        while !focused() {
            guard focusPasses < Self.maxFocusPasses else {
                Issue.record("\(story.name): its search field never took focus in \(focusPasses) run-loop passes")
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            focusPasses += 1
        }
        var last = pixels(), quiet = 0, changes = 0
        for _ in 0..<Self.maxPasses {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            view.layoutSubtreeIfNeeded()
            let now = pixels()
            if now == last { quiet += 1 } else { quiet = 0; changes += 1; last = now }
            if quiet >= Self.quietPasses { return }
        }
        let why = "\(story.name) never settled: \(changes) changes in \(Self.maxPasses) run-loop passes. "
            + "Something on it keeps changing (an animation, a clock?)"
        Issue.record(Comment(rawValue: why))
    }
    /// About 10 s on an idle machine. A focus that has not landed by then is not coming.
    static let maxFocusPasses = 1000

    /// Draw the story at exactly **one pixel per point**, whatever display the test happens to run
    /// on (#53).
    ///
    /// Snapshotting an `NSView` directly renders through its window, whose backing scale comes from
    /// the screen: 2× on this Mac, 1× on the machine that recorded the references, so *every* story
    /// mismatched — 96×1600 pixels against a 48×800 reference — and the gate silently depended on
    /// the hardware. Drawing into a bitmap we size ourselves takes that variable away.
    func render(_ view: NSView) -> NSImage {
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap(view))
        return image
    }

    /// The bitmap behind `render`, which `settle` also compares pass by pass.
    func bitmap(_ view: NSView) -> NSBitmapImageRep {
        let size = view.bounds.size
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width.rounded()), pixelsHigh: Int(size.height.rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size                       // 1 pt == 1 px, regardless of the screen
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// #159: the overview focuses its search field a pass after it appears, and its snapshot is of
    /// the focused field. The fixed 50 ms spin sometimes captured the unfocused one under load.
    @Test func theOverviewIsSnapshottedWithItsSearchFieldFocused() throws {
        let story = try #require(Stories.all.first { $0.name == "overview-results" })
        let view = host(story, appearance: .aqua)
        #expect(view.window?.firstResponder is NSTextView, "the search field's editor should have focus")
    }

    /// #159: a story that never stops changing fails rather than being snapshotted mid-change.
    @Test func aStoryThatNeverSettlesFails() {
        let ticking = Story(name: "ticking", size: CGSize(width: 200, height: 20), view: AnyView(Ticking()))
        withKnownIssue("a view that changes on every draw never settles") { _ = host(ticking, appearance: .aqua) }
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
