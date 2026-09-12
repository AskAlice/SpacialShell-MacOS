import Testing
import AppKit
import SwiftUI
import SnapshotTesting
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
/// design has not built handling for yet (tab "+N" badge, rail overflow) — their lint runs under
/// `withKnownIssue` so the gap stays visible without a red suite.
@MainActor
@Suite(.serialized) struct ShellStoryTests {
    static let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"

    /// Hosts the story at its true geometry inside an offscreen window — accessibility frames
    /// (which LayoutLint reads) only exist for views in a window.
    func host(_ story: Story, appearance: NSAppearance.Name) -> NSView {
        let view = NSHostingView(rootView: story.view)
        view.appearance = NSAppearance(named: appearance)
        let size = story.size ?? view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test(arguments: ["light", "dark"])
    func storiesRenderCleanly(mode: String) {
        let appearance: NSAppearance.Name = mode == "dark" ? .darkAqua : .aqua
        for story in Stories.all {
            let view = host(story, appearance: appearance)
            assertSnapshot(of: view, as: .image, named: "\(story.name)-\(mode)", record: Self.record)
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
