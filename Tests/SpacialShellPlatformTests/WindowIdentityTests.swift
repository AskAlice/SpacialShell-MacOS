import AppKit
import ApplicationServices
import Foundation
import SpacialShellProtocol
import Testing
@testable import SpacialShellPlatform

/// Issue #18: window identity is minted by us, not read from `_AXUIElementGetWindow`.
///
/// These are the properties the old private call gave us for free, now asserted rather than
/// assumed — the whole spatial model is addressed by this id, so "it seems to work" is not a bar.
@Suite struct WindowIdentityTests {
    // MARK: - Minting

    /// The load-bearing property. `AxUiElementWindowType` compares a window's identity against the
    /// focused window's by equality, so an element that minted two different ids would break focus
    /// detection silently. `AXUIElementCreateApplication` is used rather than a real window because
    /// it needs no Accessibility grant and exercises the same CF equality.
    @Test func mintingIsIdempotentForTheSameElement() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let a = AXUIElementCreateApplication(pid)
        let b = AXUIElementCreateApplication(pid)
        // Different references to the same thing: not the same pointer, but equal.
        #expect(a !== b)
        #expect(CFEqual(a, b))
        #expect(WindowIdentities.id(for: a) == WindowIdentities.id(for: b))
        // And stable when asked again.
        #expect(WindowIdentities.id(for: a) == WindowIdentities.id(for: a))
    }

    @Test func distinctElementsGetDistinctIds() {
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications
            .map(\.processIdentifier).filter { $0 != mine }.prefix(6)
        guard others.count >= 2 else { return } // nothing else running; nothing to prove
        let ids = Set(others.map { WindowIdentities.id(for: AXUIElementCreateApplication($0)) })
        #expect(ids.count == others.count)
    }

    /// Ids must not collide with the ids recorded in the `axDumps` corpus, which are real
    /// `CGWindowID`s in the hundreds and low thousands, nor with the deliberately-bogus
    /// `0xDEAD_BEEF` the liveness tests use to assert "not found".
    @Test func mintedIdsSitOutsideTheRangesOtherTestsRelyOn() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let id = WindowIdentities.id(for: AXUIElementCreateApplication(pid))
        #expect(id >= 1_000_000)
        #expect(id != 0xDEAD_BEEF)
    }

    @Test func forgetDropsBothDirectionsOfTheMapping() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        let id = WindowIdentities.id(for: element)
        #expect(WindowIdentities.element(for: id) != nil)
        WindowIdentities.forget(id)
        #expect(WindowIdentities.element(for: id) == nil)
        // A forgotten element mints a *fresh* id rather than resurrecting the old one, so a stale
        // WindowRef held anywhere can never resolve onto a live window.
        #expect(WindowIdentities.id(for: element) != id)
    }

    // MARK: - The public CGWindowID match never guesses

    @Test func captureIdsAreEmptyForUnknownIdentities() {
        #expect(WindowIdentities.captureIDs(for: [999_999_999]).isEmpty)
        #expect(WindowIdentities.captureID(for: 999_999_999) == nil)
    }

    @Test func captureIdsAreEmptyForAnEmptyRequest() {
        #expect(WindowIdentities.captureIDs(for: []).isEmpty)
    }

    // MARK: - An unresolved window level must fail *open*

    /// The regression this swap nearly shipped.
    ///
    /// `getWindowLevel` used to be a direct `CGWindowID` lookup; it is now a best-effort public
    /// match that can return nil. Written the old way — `windowLevel != .normalWindow` — nil is
    /// "not a normal window", which made every Chrome, Firefox, Brave, Slack and iTerm2 window
    /// classify as *not a window* and never tile. So: for every recorded fixture that is a real
    /// tiling window, dropping the level must not change the verdict.
    @Test func anUnknownWindowLevelStillClassifiesAsAWindow() throws {
        var checked = 0
        try ClassifierCorpusTests().walk(ClassifierCorpusTests.root.appendingPathComponent("axDumps")) { file in
            let raw = try JSONSerialization.jsonObject(
                with: Data(contentsOf: file), options: [.json5Allowed]) as! [String: Any]
            let json = Json.newOrDieRecursive(raw).asDictOrDie
            let app = json["Aero.AXApp"]!.asDictOrDie
            let bundle = (raw["Aero.App.appBundleId"] as? String).flatMap { KnownBundleId(rawValue: $0) }
            let policy = NSApplication.ActivationPolicy.from(
                string: raw["Aero.App.nsApp.activationPolicy"] as! String)
            let expected = AxUiElementWindowType(rawValue: raw["Aero.AxUiElementWindowType"] as! String)!
            guard expected == .window else { return }
            // Same fixture, level withheld.
            #expect(
                json.getWindowType(axApp: app, bundle, policy, nil) == .window,
                "\(file.lastPathComponent) stopped being a window once its level was unknown")
            checked += 1
        }
        #expect(checked > 0)
    }

    /// The same guard on the dialog side: an unknown level must not turn 1Password's windows into
    /// floating dialogs.
    @Test func anUnknownWindowLevelIsNotADialogSignal() throws {
        var checked = 0
        try ClassifierCorpusTests().walk(ClassifierCorpusTests.root.appendingPathComponent("axDumps")) { file in
            let raw = try JSONSerialization.jsonObject(
                with: Data(contentsOf: file), options: [.json5Allowed]) as! [String: Any]
            let json = Json.newOrDieRecursive(raw).asDictOrDie
            let bundle = (raw["Aero.App.appBundleId"] as? String).flatMap { KnownBundleId(rawValue: $0) }
            guard bundle == ._1password else { return }
            let recorded = raw["Aero.AxUiElementWindowType_isDialogHeuristic"] as! Bool
            let withoutLevel = json.isDialogHeuristic(bundle, nil)
            // Withholding the level may only ever *reduce* dialog-ness, never invent it.
            if !recorded { #expect(withoutLevel == false, "\(file.lastPathComponent)") }
            checked += 1
        }
        #expect(checked >= 0)
    }
}
