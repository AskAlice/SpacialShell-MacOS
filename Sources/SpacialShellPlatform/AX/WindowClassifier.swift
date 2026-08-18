import AppKit
import SpacialShellKit

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
}
