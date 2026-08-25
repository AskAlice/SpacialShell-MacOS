import Foundation
import SpacialShellProtocol

public enum CheatSheet {
    public enum Group: String, CaseIterable, Sendable {
        case navigate, move, layout, screens, app
        public var title: String {
            switch self {
            case .navigate: "Navigate"
            case .move: "Move & tiling"
            case .layout: "Layout"
            case .screens: "Screens"
            case .app: "App"
            }
        }
    }

    public struct Row: Equatable, Sendable {
        public var group: Group
        public var title: String
        public var commandName: String
        public var chords: [String]
        public var symbol: String
        public var letter: String
    }

    public static func rows(for config: Config) -> [Row] {
        let table = KeyBindings.table(for: config)
        var byName: [String: [Chord]] = [:]
        for (ch, cmd) in table {
            guard let n = KeyBindings.name(of: cmd) else { continue }
            byName[n, default: []].append(ch)
        }
        func shown(_ name: String) -> [String] {
            (byName[name] ?? []).sorted { KeyBindings.serialize($0) < KeyBindings.serialize($1) }
                .map(KeyBindings.display)
        }
        var out: [Row] = []
        func add(_ g: Group, _ name: String, _ title: String, _ symbol: String, _ letter: String) {
            let c = shown(name)
            guard !c.isEmpty else { return }
            out.append(Row(group: g, title: title, commandName: name, chords: c, symbol: symbol, letter: letter))
        }
        add(.navigate, "focus-workspace-up", "Workspace up", "arrow.up", "W")
        add(.navigate, "focus-workspace-down", "Workspace down", "arrow.down", "S")
        add(.navigate, "focus-window-left", "Window left", "arrow.left", "A")
        add(.navigate, "focus-window-right", "Window right", "arrow.right", "D")
        let jump = (1...10).flatMap { byName["focus-workspace-\($0)"] ?? [] }
        if !jump.isEmpty {
            let prefix = jump.first.map { ch in
                var p = ""
                if ch.fn { p += "Fn+" }; if ch.control { p += "⌃" }; if ch.option { p += "⌥" }
                if ch.shift { p += "⇧" }; if ch.command { p += "⌘" }
                return p
            } ?? ""
            out.append(Row(group: .navigate, title: "Jump to workspace 1–10", commandName: "focus-workspace-1",
                           chords: ["\(prefix)1…0"], symbol: "1.circle", letter: "1"))
        }
        add(.move, "move-window-left", "Move window left", "rectangle.lefthalf.inset.filled.arrow.left", "⇧A")
        add(.move, "move-window-right", "Move window right", "rectangle.righthalf.inset.filled.arrow.right", "⇧D")
        add(.move, "move-window-up", "Move to workspace above", "rectangle.tophalf.inset.filled.arrow.up", "⇧W")
        add(.move, "move-window-down", "Move to workspace below (new category)", "rectangle.bottomhalf.inset.filled.arrow.down", "⇧S")
        add(.move, "toggle-float", "Toggle float", "rectangle.portrait.on.rectangle.portrait", "G")
        add(.layout, "cycle-layout", "Cycle layout", "square.split.2x1", "Space")
        add(.screens, "focus-screen-prev", "Previous screen", "display", "[")
        add(.screens, "focus-screen-next", "Next screen", "display.2", "]")
        add(.screens, "move-window-to-screen-prev", "Move to previous screen", "rectangle.portrait.and.arrow.left", "⇧[")
        add(.screens, "move-window-to-screen-next", "Move to next screen", "rectangle.portrait.and.arrow.right", "⇧]")
        add(.app, "toggle-shell-ui", "Toggle shell UI", "eye", "Esc")
        add(.app, "open-settings", "Settings", "gearshape", ",")
        add(.app, "close-window", "Close window", "xmark", "Q")
        return out
    }

    public static func primaryDisplay(for command: Command, config: Config) -> String? {
        KeyBindings.chords(for: command, config: config).first.map(KeyBindings.display)
    }
}

public enum Hint {
    public static func after(_ command: Command, before: World, after: World, config: Config) -> String? {
        switch command {
        case .cycleLayout:
            let name = after.screens[after.focus.screen]?.active.layout.rawValue.capitalized ?? "Layout"
            let chord = CheatSheet.primaryDisplay(for: .cycleLayout, config: config) ?? ""
            return chord.isEmpty ? name : "\(name)  ·  \(chord)"
        case .moveWindowToWorkspace:
            let sid = after.focus.screen
            let b = before.screens[sid]?.workspaces.count ?? 0
            let a = after.screens[sid]?.workspaces.count ?? 0
            guard a > b else { return nil }
            let chord = CheatSheet.primaryDisplay(for: .moveWindowToWorkspace(.down), config: config) ?? ""
            return chord.isEmpty ? "New category" : "New category  ·  \(chord)"
        default: return nil
        }
    }
}
