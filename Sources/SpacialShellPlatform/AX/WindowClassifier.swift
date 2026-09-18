import AppKit
import SpacialShellKit
import SpacialShellProtocol

/// `WindowRef` is ambiguous in a file that imports AppKit — Quickdraw exports one too.
typealias Ref = SpacialShellProtocol.WindowRef

/// Maps AeroSpace's AX window-type heuristics onto SpacialShell's `WindowKind`.
///
/// The heuristics themselves live in `Lifted/AxUiElementWindowType.swift` and are pinned by
/// the `axDumps/` regression corpus (see `ClassifierCorpusTests`).
enum WindowClassifier {
    static func kind(for t: AxUiElementWindowType) -> WindowKind {
        switch t {
            case .window: .tile
            case .dialog: .float
            case .popup: .ignore
        }
    }

    /// Spec §7.3 rules 1–6 (rule 0 — config — is applied by the Kit store).
    static func kind(
        axWindow: any AxUiElementMock,
        axApp: any AxUiElementMock,
        bundleID: String?,
        activationPolicy: NSApplication.ActivationPolicy,
        windowLevel: MacOsWindowLevel?,
    ) -> WindowKind {
        kind(for: axWindow.getWindowType(
            axApp: axApp,
            bundleID.flatMap { KnownBundleId(rawValue: $0) },
            activationPolicy,
            windowLevel,
        ))
    }

    // MARK: native macOS window tabs (issue #27)

    /// macOS native window tabs — Finder, and any app using `NSWindow` tabbing — expose **one AX
    /// window per tab**, every one of them reporting the tab group's single shared frame. Adopting
    /// each tab as its own managed window makes the reconciler park the inactive ones under any
    /// layout that shows fewer windows than the row holds, and because the frame is shared,
    /// parking any member drags the whole group — the tab the user is looking at included —
    /// off-screen.
    ///
    /// A tab group is therefore represented by exactly **one** managed window; this returns the
    /// others, which the caller demotes to `.ignore` so they are neither tiled nor parked
    /// (`Reconciler.desired` leaves ignored windows out of its result entirely).
    ///
    /// The representative is the group's *oldest* window — lowest `CGWindowID` — not the selected
    /// tab. Selection moves every time the user switches or opens a tab; a representative that
    /// moved with it would hand the group a second managed window on the next ⌘T, and the bug
    /// would be back. Writes to a background tab do reach the group: that is precisely how parking
    /// one of them drags the whole thing off-screen today.
    ///
    /// Only the selected tab's window carries the tab bar, so that window is how a group is found
    /// at all. The tab-button count must match the number of windows sitting on that frame;
    /// otherwise this is not one tab group — two ordinary windows can coincidentally share a frame
    /// (observed live in Sublime Text) — and nothing is demoted.
    static func backgroundNativeTabs(
        _ windows: [(ref: Ref, frame: CGRect, ax: any AxUiElementMock)],
    ) -> Set<Ref> {
        var carriers: [(ref: Ref, frame: CGRect, tabs: Int)] = []
        var plain: [(ref: Ref, frame: CGRect)] = []
        for w in windows {
            if let tabs = nativeTabBarCount(w.ax) { carriers.append((w.ref, w.frame, tabs)) }
            else { plain.append((w.ref, w.frame)) }
        }
        guard !carriers.isEmpty else { return [] }
        var demoted: Set<Ref> = []
        for carrier in carriers {
            let group = [carrier.ref] + plain.filter { $0.frame == carrier.frame }.map { $0.ref }
            guard group.count == carrier.tabs else { continue }
            demoted.formUnion(group.sorted { $0.id < $1.id }.dropFirst())
        }
        return demoted
    }

    /// The number of tabs in this window's native tab bar — a top-level `AXTabGroup` whose
    /// children are `AXTabButton`s — or nil when the window carries no tab bar, which covers both
    /// an untabbed window and a tab group's background tabs. Fewer than two buttons is not a group.
    private static func nativeTabBarCount(_ window: any AxUiElementMock) -> Int? {
        for child in window.get(Ax.childrenAttr) ?? [] where child.get(Ax.roleAttr) == kAXTabGroupRole {
            let tabs = (child.get(Ax.childrenAttr) ?? []).filter { $0.get(Ax.subroleAttr) == kAXTabButtonSubrole }
            return tabs.count >= 2 ? tabs.count : nil
        }
        return nil
    }
}

/// `kAXTabGroupRole` ships in `ApplicationServices`; the tab-button subrole does not.
private let kAXTabButtonSubrole = "AXTabButton"
