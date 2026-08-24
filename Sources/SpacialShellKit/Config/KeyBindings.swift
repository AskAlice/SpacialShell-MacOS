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
    ]
    public static let nameByCode: [UInt16: String] = Dictionary(uniqueKeysWithValues: byName.map { ($0.value, $0.key) })
}

public enum KeyBindings {
    public static let commandNames: [String: Command] = [
        "focus-workspace-up": .focusWorkspace(.up), "focus-workspace-down": .focusWorkspace(.down),
        "focus-window-left": .focusWindow(.left), "focus-window-right": .focusWindow(.right),
        "close-window": .closeFocusedWindow,
        "move-window-left": .moveWindow(.left), "move-window-right": .moveWindow(.right),
        "move-window-up": .moveWindowToWorkspace(.up), "move-window-down": .moveWindowToWorkspace(.down),
        "cycle-layout": .cycleLayout, "toggle-shell-ui": .toggleShellUI,
        "focus-screen-prev": .focusScreen(.prev), "focus-screen-next": .focusScreen(.next),
        "move-window-to-screen-prev": .moveWindowToScreen(.prev), "move-window-to-screen-next": .moveWindowToScreen(.next),
        "toggle-float": .toggleFloat, "open-settings": .openSettings,
        "focus-workspace-1": .focusWorkspaceIndex(1), "focus-workspace-2": .focusWorkspaceIndex(2), "focus-workspace-3": .focusWorkspaceIndex(3),
        "focus-workspace-4": .focusWorkspaceIndex(4), "focus-workspace-5": .focusWorkspaceIndex(5), "focus-workspace-6": .focusWorkspaceIndex(6),
        "focus-workspace-7": .focusWorkspaceIndex(7), "focus-workspace-8": .focusWorkspaceIndex(8), "focus-workspace-9": .focusWorkspaceIndex(9),
        "focus-workspace-10": .focusWorkspaceIndex(10),
    ]

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
        return c
    }

    static let core: [(String, String)] = [   // (key suffix, command name)
        ("w", "focus-workspace-up"), ("s", "focus-workspace-down"), ("a", "focus-window-left"), ("d", "focus-window-right"),
        ("q", "close-window"), ("shift-a", "move-window-left"), ("shift-d", "move-window-right"),
        ("shift-w", "move-window-up"), ("shift-s", "move-window-down"), ("space", "cycle-layout"), ("esc", "toggle-shell-ui"),
        ("leftSquareBracket", "focus-screen-prev"), ("rightSquareBracket", "focus-screen-next"),
        ("shift-leftSquareBracket", "move-window-to-screen-prev"), ("shift-rightSquareBracket", "move-window-to-screen-next"),
        ("g", "toggle-float"), ("comma", "open-settings"),
        ("1", "focus-workspace-1"), ("2", "focus-workspace-2"), ("3", "focus-workspace-3"), ("4", "focus-workspace-4"), ("5", "focus-workspace-5"),
        ("6", "focus-workspace-6"), ("7", "focus-workspace-7"), ("8", "focus-workspace-8"), ("9", "focus-workspace-9"), ("0", "focus-workspace-10"),
    ]
    static let arrows: [(String, String)] = [
        ("ctrl-alt-up", "focus-workspace-up"), ("ctrl-alt-down", "focus-workspace-down"), ("ctrl-alt-left", "focus-window-left"), ("ctrl-alt-right", "focus-window-right"),
        ("ctrl-alt-shift-up", "move-window-up"), ("ctrl-alt-shift-down", "move-window-down"), ("ctrl-alt-shift-left", "move-window-left"), ("ctrl-alt-shift-right", "move-window-right"),
    ]

    public static func table(for config: Config) -> [Chord: Command] {
        var t: [Chord: Command] = [:]
        let prefix = config.keybindingPreset == .fn ? "fn-" : "ctrl-alt-"
        for (k, name) in core { if let ch = parse(prefix + k), let cmd = commandNames[name] { t[ch] = cmd } }
        for (k, name) in arrows { if let ch = parse(k), let cmd = commandNames[name] { t[ch] = cmd } }
        for (k, name) in config.keybindings { if let ch = parse(k), let cmd = commandNames[name] { t[ch] = cmd } }
        return t
    }

    public static func name(of command: Command) -> String? {
        commandNames.first { $0.value == command }?.key
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
