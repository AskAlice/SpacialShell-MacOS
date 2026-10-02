import CoreGraphics

/// #205: the Fn+Tab overview held like alt-tab. Opened with a modifier still down (Fn, or ⌃⌥ on
/// the ctrl-alt preset), Tab and ⇧Tab with that modifier step the selection; letting go opens the
/// selected result — once it has been stepped. A plain Fn+Tab tap, let go without a step, leaves
/// the overview open for searching, as before.
public struct OverviewHold: Equatable, Sendable {
    /// What letting go (or not yet) means.
    public enum Release: Equatable, Sendable {
        /// Still held: nothing yet.
        case holding
        /// Let go after cycling: open the selection.
        case open
        /// Let go without cycling: the overview stays, the hold is over.
        case letGo
    }

    public let held: CGEventFlags
    public private(set) var cycled = false

    /// Nil when nothing that holds it is down (opened from a click or `spacialctl`).
    public init?(held flags: CGEventFlags) {
        let held = AppWindowSwitcher.holdModifiers(flags)
        guard !held.isEmpty else { return nil }
        self.held = held
    }

    public mutating func stepped() { cycled = true }

    public mutating func flagsChanged(_ flags: CGEventFlags) -> Release {
        if AppWindowSwitcher.isHeld(flags, by: held) { return .holding }
        return cycled ? .open : .letGo
    }

    /// Tab and ⇧Tab with the held modifiers, bound in the hotkey tap while the hold lasts — ahead
    /// of the normal table, so Fn+Tab steps rather than closing the overview.
    public var stepChords: [Chord: Command] {
        let tab = KeyCodes.byName["tab"]!
        return Dictionary(uniqueKeysWithValues: [false, true].map { shift in
            (Chord(keyCode: tab, fn: held.contains(.maskSecondaryFn), control: held.contains(.maskControl),
                   option: held.contains(.maskAlternate), shift: shift, command: held.contains(.maskCommand)),
             Command.overviewStep(reverse: shift))
        })
    }
}

