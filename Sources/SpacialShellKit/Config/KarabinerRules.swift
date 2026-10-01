import Foundation

/// #196: the hotkey table as a Karabiner-Elements complex-modifications asset, so the chords keep
/// working while an app holds Secure Event Input (#193), which hides key-downs from every event
/// tap. Karabiner seizes the keyboard below the WindowServer, so its rules still fire; each one
/// runs `spacialctl run <command>`.
///
/// One rule holding one manipulator per chord, so Karabiner's "Add predefined rule" is a single
/// Enable. Pure: the app writes the file (only with the user's consent, and never karabiner.json).
public enum KarabinerRules {
    /// Karabiner's documented import spot, under the home directory.
    public static let relativePath = ".config/karabiner/assets/complex_modifications/spacialshell.json"

    /// Commands a shell command cannot drive. The #188 app window switcher opens on the press and
    /// picks on the release of ⌘, and a spawned `spacialctl` never sees the release.
    public static func isModal(_ command: Command) -> Bool {
        if case .switchAppWindow = command { return true }
        return false
    }

    /// The asset file, pretty-printed with sorted keys and manipulators in (command name, chord)
    /// order, so an unchanged table writes identical bytes.
    public static func export(table: [Chord: Command], spacialctlPath: String) -> Data {
        var manipulators: [(name: String, chord: String, m: Manipulator)] = []
        var modal: [Chord] = []
        for (chord, command) in table {
            if isModal(command) { modal.append(chord); continue }
            guard let name = KeyBindings.name(of: command), let key = keyCode(chord) else { continue }
            manipulators.append((name, KeyBindings.serialize(chord), Manipulator(
                from: .init(keyCode: key, modifiers: .init(mandatory: modifiers(chord))),
                to: [.init(shellCommand: "\(quote(spacialctlPath)) run \(quote(name, ifNeeded: true))")])))
        }
        manipulators.sort { ($0.name, $0.chord) < ($1.name, $1.chord) }

        let held = table.filter { SpatialView.opensOnHold($0.value) }.keys
        var notes = ["SpacialShell hotkeys through spacialctl, so they work in password fields",
                     "A held chord fires once and does not repeat"]
        if !held.isEmpty { notes.append("Holding \(list(held)) does not open the spatial view") }
        if !modal.isEmpty { notes.append("Left out: the app window switcher (\(list(modal))), which picks on release") }
        let description = notes.joined(separator: ". ") + "."

        let file = File(title: "SpacialShell", rules: [Rule(description: description, manipulators: manipulators.map(\.m))])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try! encoder.encode(file)   // plain strings and arrays: cannot fail
    }

    /// Karabiner's `key_code` for a chord's key. Fn+arrows are bound as Home/End/PgUp/PgDn (what
    /// the tap sees, #118), but Karabiner sees the arrow the user pressed.
    static func keyCode(_ chord: Chord) -> String? {
        let code = chord.fn ? (KeyCodes.fnArrow.first { $0.value == chord.keyCode }?.key ?? chord.keyCode) : chord.keyCode
        guard let name = KeyCodes.nameByCode[code] else { return nil }
        return keyNames[name] ?? name
    }

    /// Our `KeyCodes` names that Karabiner spells differently; letters, digits and the rest match.
    static let keyNames: [String: String] = [
        "equal": "equal_sign", "minus": "hyphen",
        "leftSquareBracket": "open_bracket", "rightSquareBracket": "close_bracket",
        "enter": "return_or_enter", "space": "spacebar", "backtick": "grave_accent_and_tilde",
        "backspace": "delete_or_backspace", "esc": "escape",
        "left": "left_arrow", "right": "right_arrow", "up": "up_arrow", "down": "down_arrow",
        "pageUp": "page_up", "pageDown": "page_down",
    ]

    static func modifiers(_ c: Chord) -> [String]? {
        let m = [(c.fn, "fn"), (c.control, "control"), (c.option, "option"), (c.shift, "shift"), (c.command, "command")]
            .filter(\.0).map(\.1)
        return m.isEmpty ? nil : m
    }

    /// For `sh -c`: single quotes, with any single quote inside closed, escaped and reopened.
    static func quote(_ s: String, ifNeeded: Bool = false) -> String {
        if ifNeeded, !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func list(_ chords: some Sequence<Chord>) -> String {
        chords.sorted { KeyBindings.serialize($0) < KeyBindings.serialize($1) }.map(KeyBindings.display).joined(separator: ", ")
    }

    struct File: Encodable { let title: String; let rules: [Rule] }
    struct Rule: Encodable { let description: String; let manipulators: [Manipulator] }
    struct Manipulator: Encodable {
        var type = "basic"
        let from: From
        let to: [To]
        struct From: Encodable { let keyCode: String; let modifiers: Modifiers }
        /// Caps Lock is optional, as it is to the tap: without it Karabiner skips the chord while
        /// Caps Lock is on.
        struct Modifiers: Encodable { let mandatory: [String]?; var optional = ["caps_lock"] }
        struct To: Encodable { let shellCommand: String }
    }
}
