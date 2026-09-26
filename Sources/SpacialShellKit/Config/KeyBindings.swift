import Foundation

public struct Chord: Hashable, Sendable {
    public var keyCode: UInt16
    public var fn: Bool, control: Bool, option: Bool, shift: Bool, command: Bool
    public init(keyCode: UInt16, fn: Bool, control: Bool, option: Bool, shift: Bool, command: Bool) {
        self.keyCode = keyCode; self.fn = fn; self.control = control; self.option = option; self.shift = shift; self.command = command
    }
}

public enum KeyCodes {
    /// kVK_ANSI_* virtual key codes (US layout positions).
    public static let byName: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24, "9": 25, "7": 26, "minus": 27, "8": 28,
        "0": 29, "rightSquareBracket": 30, "o": 31, "u": 32, "leftSquareBracket": 33, "i": 34, "p": 35, "enter": 36, "l": 37,
        "j": 38, "quote": 39, "k": 40, "semicolon": 41, "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47,
        "tab": 48, "space": 49, "backtick": 50, "backspace": 51, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        // #118: what Fn+←/→/↑/↓ arrive as — IOHIDKeyboardFilter remaps them below the tap, with the
        // Fn flag set (docs/platform-notes.md check 2).
        "home": 115, "end": 119, "pageUp": 116, "pageDown": 121,
    ]
    /// #118: an arrow → the key Fn turns it into.
    static let fnArrow: [UInt16: UInt16] = [123: 115, 124: 119, 126: 116, 125: 121]
    public static let nameByCode: [UInt16: String] = Dictionary(uniqueKeysWithValues: byName.map { ($0.value, $0.key) })
}

public enum KeyBindings {
    public static let commandNames: [String: Command] = [
        "focus-workspace-up": .focusWorkspace(.up), "focus-workspace-down": .focusWorkspace(.down),
        "focus-window-left": .focusWindow(.left), "focus-window-right": .focusWindow(.right),
        "close-window": .closeFocusedWindow,
        "move-window-left": .moveWindow(.left), "move-window-right": .moveWindow(.right),
        "move-window-up": .moveWindowToWorkspace(.up), "move-window-down": .moveWindowToWorkspace(.down),
        "cycle-layout": .cycleLayout, "toggle-shell-ui": .toggleShellUI, "toggle-overview": .toggleOverview,
        "focus-screen-prev": .focusScreen(.prev), "focus-screen-next": .focusScreen(.next),
        "move-window-to-screen-prev": .moveWindowToScreen(.prev), "move-window-to-screen-next": .moveWindowToScreen(.next),
        "rescue-windows": .rescueWindows,
        "toggle-float": .toggleFloat, "open-settings": .openSettings,
        "focus-workspace-1": .focusWorkspaceIndex(1), "focus-workspace-2": .focusWorkspaceIndex(2), "focus-workspace-3": .focusWorkspaceIndex(3),
        "focus-workspace-4": .focusWorkspaceIndex(4), "focus-workspace-5": .focusWorkspaceIndex(5), "focus-workspace-6": .focusWorkspaceIndex(6),
        "focus-workspace-7": .focusWorkspaceIndex(7), "focus-workspace-8": .focusWorkspaceIndex(8), "focus-workspace-9": .focusWorkspaceIndex(9),
        "focus-workspace-10": .focusWorkspaceIndex(10),
        "move-app-up": .moveAppToWorkspace(.up), "move-app-down": .moveAppToWorkspace(.down),
        // #118–#120, #143: the M4 keyboard grammar.
        "focus-screen-left": .focusScreenDirection(.left), "focus-screen-right": .focusScreenDirection(.right),
        "focus-screen-up": .focusScreenDirection(.up), "focus-screen-down": .focusScreenDirection(.down),
        "move-window-to-screen-left": .moveWindowToScreenDirection(.left),
        "move-window-to-screen-right": .moveWindowToScreenDirection(.right),
        "move-window-to-screen-up": .moveWindowToScreenDirection(.up),
        "move-window-to-screen-down": .moveWindowToScreenDirection(.down),
        "cycle-layout-reverse": .cycleLayoutReverse,
    ].merging((1...10).map { ("move-window-to-workspace-\($0)", Command.moveWindowToWorkspaceIndex($0)) }) { a, _ in a }
        .merging((1...9).map { ("focus-tab-\($0)", Command.focusTab($0)) }) { a, _ in a }

    /// #119: `set-layout-<id>` is one command per layout, built-in or saved, so it cannot live in
    /// the fixed table; every name lookup (config, settings, `spacialctl run`) comes through here.
    public static let setLayoutPrefix = "set-layout-"
    public static func command(named name: String) -> Command? {
        if let c = commandNames[name] { return c }
        guard name.hasPrefix(setLayoutPrefix), name.count > setLayoutPrefix.count else { return nil }
        return .setLayout(LayoutID(rawValue: String(name.dropFirst(setLayoutPrefix.count))))
    }

    /// "fn-shift-g" → Chord. Modifiers: fn, ctrl, alt, shift, cmd. Last token is a KeyCodes name.
    public static func parse(_ s: String) -> Chord? {
        var parts = s.lowercased().split(separator: "-").map(String.init)
        guard let keyName = parts.popLast() else { return nil }
        let keyLookup = KeyCodes.byName.first { $0.key.lowercased() == keyName }?.value
        guard let keyCode = keyLookup else { return nil }
        var c = Chord(keyCode: keyCode, fn: false, control: false, option: false, shift: false, command: false)
        for m in parts {
            switch m {
            case "fn": c.fn = true
            case "ctrl", "control": c.control = true
            case "alt", "option": c.option = true
            case "shift": c.shift = true
            case "cmd", "command": c.command = true
            default: return nil
            }
        }
        // #118: "fn-shift-left" can never arrive as written — Fn+← reaches the tap as Home — so it
        // means the key it really is.
        if c.fn, let k = KeyCodes.fnArrow[keyCode] { c.keyCode = k }
        return c
    }

    static let core: [(String, String)] = [   // (key suffix, command name)
        ("w", "focus-workspace-up"), ("s", "focus-workspace-down"), ("a", "focus-window-left"), ("d", "focus-window-right"),
        ("q", "close-window"), ("shift-a", "move-window-left"), ("shift-d", "move-window-right"),
        ("shift-w", "move-window-up"), ("shift-s", "move-window-down"), ("space", "cycle-layout"), ("esc", "toggle-shell-ui"),
        ("tab", "toggle-overview"), ("shift-space", "cycle-layout-reverse"),
        ("leftSquareBracket", "focus-screen-prev"), ("rightSquareBracket", "focus-screen-next"),
        ("shift-leftSquareBracket", "move-window-to-screen-prev"), ("shift-rightSquareBracket", "move-window-to-screen-next"),
        ("g", "toggle-float"), ("comma", "open-settings"),
        ("1", "focus-workspace-1"), ("2", "focus-workspace-2"), ("3", "focus-workspace-3"), ("4", "focus-workspace-4"), ("5", "focus-workspace-5"),
        ("6", "focus-workspace-6"), ("7", "focus-workspace-7"), ("8", "focus-workspace-8"), ("9", "focus-workspace-9"), ("0", "focus-workspace-10"),
    ] + (1...10).map { ("shift-\($0 % 10)", "move-window-to-workspace-\($0)") }   // #105: Fn+⇧1…0
    /// Fn preset only (#98, P6: +⌥ on the move chord = the whole app). The ctrl-alt prefix already
    /// holds ⌥, so there these would land on ⌃⌥⇧W/S and take them from move-window-up/down; they
    /// stay bindable by name.
    ///
    /// #118 (G21, and the user's 2026-09-26 ruling): Fn+⌥W/A/S/D focus the display that way, and
    /// Fn+⇧+arrows move the window there — bound as Home/End/PgUp/PgDn, which is what Fn+arrows
    /// are by the time the tap sees them. On ctrl-alt, ⌃⌥+⌥A is ⌃⌥A (focus-window-left), and ⌃⌥+
    /// arrows are already the row/tab aliases, so none of these are bound there.
    /// #143: Fn+⌥+1…9 is tab N; Fn+⌥+0 is below 1, which clamps to the first tab.
    static let fnOnly: [(String, String)] = [
        ("alt-shift-w", "move-app-up"), ("alt-shift-s", "move-app-down"),
        ("alt-a", "focus-screen-left"), ("alt-d", "focus-screen-right"), ("alt-w", "focus-screen-up"), ("alt-s", "focus-screen-down"),
        ("shift-left", "move-window-to-screen-left"), ("shift-right", "move-window-to-screen-right"),
        ("shift-up", "move-window-to-screen-up"), ("shift-down", "move-window-to-screen-down"),
        ("alt-0", "focus-tab-1"),
    ] + (1...9).map { ("alt-\($0)", "focus-tab-\($0)") }
    static let arrows: [(String, String)] = [
        ("ctrl-alt-up", "focus-workspace-up"), ("ctrl-alt-down", "focus-workspace-down"), ("ctrl-alt-left", "focus-window-left"), ("ctrl-alt-right", "focus-window-right"),
        ("ctrl-alt-shift-up", "move-window-up"), ("ctrl-alt-shift-down", "move-window-down"), ("ctrl-alt-shift-left", "move-window-left"), ("ctrl-alt-shift-right", "move-window-right"),
    ]

    public static func table(for config: Config) -> [Chord: Command] {
        var t: [Chord: Command] = [:]
        let prefix = config.keybindingPreset == .fn ? "fn-" : "ctrl-alt-"

        // A rebind is only usable if the chord it replaced stops working, so the commands that
        // have an override contribute no default at all — neither the preset chord nor the arrow
        // chord, which is a second way into the same command and would otherwise survive.
        // An override that names an unknown command, or a chord that will not parse, is dropped
        // here rather than later: it must not take the default away and leave nothing behind.
        let rebound = Set(config.keybindingOverrides.compactMap { name, chord in
            command(named: name) != nil && parse(chord) != nil ? name : nil
        })

        for (k, name) in core + (config.keybindingPreset == .fn ? fnOnly : []) where !rebound.contains(name) {
            if let ch = parse(prefix + k), let cmd = command(named: name) { t[ch] = cmd }
        }
        for (k, name) in arrows where !rebound.contains(name) {
            if let ch = parse(k), let cmd = command(named: name) { t[ch] = cmd }
        }
        for name in rebound {
            if let ch = parse(config.keybindingOverrides[name]!), let cmd = command(named: name) { t[ch] = cmd }
        }
        // Hand-written `keybindings` last: the file is the user's, and it wins over everything.
        for (k, name) in config.keybindings { if let ch = parse(k), let cmd = command(named: name) { t[ch] = cmd } }
        return t
    }

    public static func name(of command: Command) -> String? {
        if case .setLayout(let id) = command { return setLayoutPrefix + id.rawValue }
        return commandNames.first { $0.value == command }?.key
    }

    public static func serialize(_ c: Chord) -> String {
        var p: [String] = []
        if c.fn { p.append("fn") }
        if c.control { p.append("ctrl") }
        if c.option { p.append("alt") }
        if c.shift { p.append("shift") }
        if c.command { p.append("cmd") }
        p.append(KeyCodes.nameByCode[c.keyCode] ?? "\(c.keyCode)")
        return p.joined(separator: "-")
    }

    public static func display(_ c: Chord) -> String {
        var p = ""
        if c.fn { p += "Fn+" }
        if c.control { p += "⌃" }
        if c.option { p += "⌥" }
        if c.shift { p += "⇧" }
        if c.command { p += "⌘" }
        return p + displayKey(c.keyCode)
    }

    public static func displayKey(_ code: UInt16) -> String {
        switch KeyCodes.nameByCode[code] {
        case "space": "Space"
        case "enter": "↩"
        case "esc": "Esc"
        case "tab": "⇥"
        case "backspace": "⌫"
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        // #118: shown as the arrow the user presses; `display` has already written "Fn+".
        case "home": "←"
        case "end": "→"
        case "pageUp": "↑"
        case "pageDown": "↓"
        case "leftSquareBracket": "["
        case "rightSquareBracket": "]"
        case "comma": ","
        case "period": "."
        case "slash": "/"
        case "backslash": "\\"
        case "minus": "-"
        case "equal": "="
        case "semicolon": ";"
        case "quote": "'"
        case "backtick": "`"
        case let n?: n.uppercased()
        default: "?\(code)"
        }
    }

    public static func chords(for command: Command, config: Config) -> [Chord] {
        table(for: config).compactMap { $0.value == command ? $0.key : nil }
            .sorted { serialize($0) < serialize($1) }
    }
}
