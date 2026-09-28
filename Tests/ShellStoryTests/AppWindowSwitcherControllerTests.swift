import Testing
import AppKit
import SpacialShellProtocol
@testable import SpacialShellUI
@testable import SpacialShellKit

/// #188: the switcher's held-open lifecycle, driven the way the hotkey tap drives it — the
/// modifier's flags, then the chord's command, then the release. The panel is never presented:
/// `present` is a no-op, so no run leaves a switcher on the user's display.
@MainActor
@Suite(.serialized) struct AppWindowSwitcherControllerTests {
    let a1 = WindowRef(id: 1, pid: 7), a2 = WindowRef(id: 2, pid: 7), a3 = WindowRef(id: 3, pid: 7)

    final class Sent: @unchecked Sendable { var commands: [Command] = []; var modal: [[Chord: Command]] = [] }

    func controller(_ sent: Sent) -> AppWindowSwitcherController {
        var w = World.empty(screens: ["D1"], defaultLayout: .split)
        for r in [a1, a2, a3] { w.adopt(r, kind: .tile, on: "D1") }
        let c = AppWindowSwitcherController(appMeta: AppMetaCache(), send: { sent.commands.append($0) },
                                            present: { _ in }, keyboard: { [] })
        c.onModal = { sent.modal.append($0) }
        for r in [a3, a2, a1] {   // a1 focused last; a2 before it
            let env = CommandEnvironment(layouts: .builtins, displays: [], workspaceWrap: false, categoryOrder: [])
            w = CommandRunner.run(.focusWindowRef(r), on: w, in: env).world
            c.update(world: w, snapshot: ShellSnapshot(world: w, generation: 0, displays: [], config: Config(),
                                                       layouts: .builtins, titles: [:], appNames: [:],
                                                       bundleIDs: [:], locked: false))
        }
        return c
    }

    @Test func holdTapTwiceAndLetGoLandsOnTheThirdWindow() {
        let sent = Sent(), c = controller(sent)
        c.flagsChanged(.maskCommand)
        c.handle(.switchAppWindow(reverse: false))
        #expect(c.isOpen)
        #expect(sent.modal.last?.keys.contains(AppWindowSwitcher.cancelChords(held: .maskCommand)[0]) == true)
        c.handle(.switchAppWindow(reverse: false))
        c.flagsChanged(.maskShift)                         // ⌘ let go (⇧ alone holds nothing)
        #expect(!c.isOpen)
        #expect(sent.commands == [.focusWindowRef(a3)])
        #expect(sent.modal.last == [:])
    }

    @Test func escCancelsAndTheReleaseAfterItDoesNothing() {
        let sent = Sent(), c = controller(sent)
        c.flagsChanged(.maskSecondaryFn)
        c.handle(.switchAppWindow(reverse: false))
        c.handle(.cancelAppWindowSwitch)
        c.flagsChanged([])
        #expect(!c.isOpen && sent.commands.isEmpty)
    }

    /// `spacialctl run switch-app-window`, or a tap let go before the command landed: no modifier
    /// is held, so it goes straight to the app's previous window.
    @Test func withNothingHeldItSwitchesAtOnce() {
        let sent = Sent(), c = controller(sent)
        c.handle(.switchAppWindow(reverse: false))
        guard CGEventSource.flagsState(.combinedSessionState).isDisjoint(
            with: [.maskSecondaryFn, .maskControl, .maskAlternate, .maskCommand]) else { return }   // someone is holding a key
        #expect(!c.isOpen && sent.commands == [.focusWindowRef(a2)])
    }
}
