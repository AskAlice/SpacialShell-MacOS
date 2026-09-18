import AppKit
import Testing
@testable import SpacialShellPlatform
import SpacialShellProtocol

private typealias Ref = SpacialShellProtocol.WindowRef

/// Minimal AX element: only the three attributes the native-tab detection reads.
private final class FakeElement: AxUiElementMock {
    let role: String?
    let subrole: String?
    let children: [AxUiElementMock]
    init(role: String? = nil, subrole: String? = nil, children: [AxUiElementMock] = []) {
        self.role = role; self.subrole = subrole; self.children = children
    }
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        switch attr.key {
            case kAXRoleAttribute: role as? Attr.T
            case kAXSubroleAttribute: subrole as? Attr.T
            case kAXChildrenAttribute: children as? Attr.T
            default: nil
        }
    }
    /// Was `containingWindowId()` before #18 minted ids in `WindowIdentities`. Nil is right here:
    /// these fakes stand in for AX shapes, and the tab detection never asks for an identity.
    func windowIdentity() -> WindowID? { nil }
}

/// The selected tab's AX window, carrying the tab bar: a top-level `AXTabGroup` of `AXTabButton`s
/// plus the "+" button Finder puts at its end. Shape taken from a live AX dump of Finder
/// (macOS 26.5, issue #27).
private func selectedTab(of tabs: Int) -> FakeElement {
    FakeElement(role: kAXWindowRole, children: [
        FakeElement(role: kAXTabGroupRole, children:
            (0 ..< tabs).map { _ in FakeElement(role: "AXRadioButton", subrole: "AXTabButton") }
                + [FakeElement(role: "AXButton")]),
    ])
}

/// A background tab, or any ordinary untabbed window: no tab bar of its own.
private func plainWindow() -> FakeElement {
    FakeElement(role: kAXWindowRole, children: [FakeElement(role: "AXSplitGroup")])
}

/// Issue #27. A native macOS tab group is one managed window; the rest of its tabs must be
/// demoted so the reconciler neither tiles nor parks them — parking any member of a group drags
/// the whole group, the visible tab included, off-screen.
@Suite struct NativeTabsTests {
    let frame = CGRect(x: 2577, y: 74, width: 1460, height: 907)
    let other = CGRect(x: 0, y: 0, width: 800, height: 600)

    /// Live Finder, two tabs: two AX windows, one shared frame, only the selected tab carries the
    /// tab bar. Exactly one survives as a managed window.
    @Test func twoTabFinderWindowKeepsOneManagedWindow() {
        let selected = Ref(id: 162, pid: 1), background = Ref(id: 163, pid: 1)
        let demoted = WindowClassifier.backgroundNativeTabs([
            (ref: selected, frame: frame, ax: selectedTab(of: 2)),
            (ref: background, frame: frame, ax: plainWindow()),
        ])
        #expect(demoted == [background])
    }

    /// The representative is the group's *oldest* window, not the selected tab: switching tabs or
    /// opening one moves the tab bar, and a representative that moved with it would hand the group
    /// a second managed window on the next ⌘T — the bug all over again.
    @Test func representativeIsTheOldestWindowNotTheSelectedTab() {
        let older = Ref(id: 162, pid: 1), newer = Ref(id: 163, pid: 1)
        // Same group, but now the *newer* window is the one showing (it carries the tab bar).
        let demoted = WindowClassifier.backgroundNativeTabs([
            (ref: older, frame: frame, ax: plainWindow()),
            (ref: newer, frame: frame, ax: selectedTab(of: 2)),
        ])
        #expect(demoted == [newer])
    }

    /// ⌘T: a third tab appears, still one managed window.
    @Test func openingAThirdTabDemotesTwo() {
        let a = Ref(id: 10, pid: 1), b = Ref(id: 11, pid: 1), c = Ref(id: 12, pid: 1)
        let demoted = WindowClassifier.backgroundNativeTabs([
            (ref: a, frame: frame, ax: plainWindow()),
            (ref: b, frame: frame, ax: plainWindow()),
            (ref: c, frame: frame, ax: selectedTab(of: 3)),
        ])
        #expect(demoted == [b, c])
    }

    /// Two ordinary windows can land on the exact same frame — observed live in Sublime Text —
    /// and neither may be swallowed. With no tab bar in sight there is no group to collapse.
    @Test func windowsSharingAFrameWithoutATabBarAreLeftAlone() {
        let a = Ref(id: 1, pid: 1), b = Ref(id: 2, pid: 1)
        let demoted = WindowClassifier.backgroundNativeTabs([
            (ref: a, frame: frame, ax: plainWindow()),
            (ref: b, frame: frame, ax: plainWindow()),
        ])
        #expect(demoted.isEmpty)
    }

    /// The tab count is the consistency check: if the windows on the frame don't add up to the
    /// number of tabs, this isn't one tab group, and demoting would eat a real window.
    @Test func tabCountMismatchDemotesNothing() {
        let a = Ref(id: 1, pid: 1), b = Ref(id: 2, pid: 1)
        let demoted = WindowClassifier.backgroundNativeTabs([
            (ref: a, frame: frame, ax: selectedTab(of: 3)),   // claims 3 tabs…
            (ref: b, frame: frame, ax: plainWindow()),        // …but only 2 windows are here
        ])
        #expect(demoted.isEmpty)
    }

    /// A tabbed group and a separate untabbed window of the same app: only the group collapses.
    @Test func aSecondUntabbedWindowElsewhereSurvives() {
        let tab1 = Ref(id: 1, pid: 1), tab2 = Ref(id: 2, pid: 1), loose = Ref(id: 3, pid: 1)
        let demoted = WindowClassifier.backgroundNativeTabs([
            (ref: tab1, frame: frame, ax: selectedTab(of: 2)),
            (ref: tab2, frame: frame, ax: plainWindow()),
            (ref: loose, frame: other, ax: plainWindow()),
        ])
        #expect(demoted == [tab2])
    }

    /// One tab is not a tab group — an app configured to always show the tab bar must keep tiling.
    @Test func aSingleTabIsNotAGroup() {
        let a = Ref(id: 1, pid: 1)
        #expect(WindowClassifier.backgroundNativeTabs([(ref: a, frame: frame, ax: selectedTab(of: 1))]).isEmpty)
    }
}
