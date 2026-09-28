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
        add(.navigate, "focus-previous-window", "Previous window", "clock.arrow.circlepath", "P")   // #137
        add(.navigate, "switch-app-window", "App windows", "macwindow.on.rectangle", "`")   // #188
        /// One row for a family of ten digit commands ("Fn+1…0"), prefixed with its first chord's modifiers.
        func digits(_ g: Group, _ family: String, _ title: String, _ symbol: String, _ letter: String) {
            guard let ch = (1...10).flatMap({ byName["\(family)\($0)"] ?? [] }).first else { return }
            var p = ""
            if ch.fn { p += "Fn+" }; if ch.control { p += "⌃" }; if ch.option { p += "⌥" }
            if ch.shift { p += "⇧" }; if ch.command { p += "⌘" }
            out.append(Row(group: g, title: title, commandName: "\(family)1", chords: ["\(p)1…0"], symbol: symbol, letter: letter))
        }
        digits(.navigate, "focus-workspace-", "Workspace 1–10 / back", "1.circle", "1")
        /// #143: tabs 1–9 ("Fn+⌥1…9"); the 0 chord is an alias of tab 1, so the family stops at 9.
        if let ch = byName["focus-tab-1"]?.filter({ $0.keyCode != KeyCodes.byName["0"] }).first {
            let p = KeyBindings.display(ch).dropLast()
            out.append(Row(group: .navigate, title: "Tab 1–9", commandName: "focus-tab-1", chords: ["\(p)1…9"],
                           symbol: "rectangle.topthird.inset.filled", letter: "⌥1"))
        }
        add(.move, "move-window-left", "Move window left", "rectangle.lefthalf.inset.filled.arrow.left", "⇧A")
        add(.move, "move-window-right", "Move window right", "rectangle.righthalf.inset.filled.arrow.right", "⇧D")
        add(.move, "move-window-up", "Move to workspace above", "rectangle.tophalf.inset.filled", "⇧W")
        add(.move, "move-window-down", "Move to workspace below (new category)", "rectangle.bottomhalf.inset.filled", "⇧S")
        digits(.move, "move-window-to-workspace-", "Move to workspace 1–10", "1.square", "⇧1")
        add(.move, "move-app-up", "Move whole app up", "square.stack.3d.up", "⌥⇧W")
        add(.move, "move-app-down", "Move whole app down", "square.stack.3d.down.right", "⌥⇧S")
        add(.move, "toggle-float", "Toggle float", "rectangle.portrait.on.rectangle.portrait", "G")
        add(.layout, "cycle-layout", "Cycle layout", "square.split.2x1", "Space")
        add(.layout, "cycle-layout-reverse", "Cycle layout backwards", "arrow.uturn.backward", "⇧Space")
        add(.layout, "shrink-width", "Narrower", "arrow.right.and.line.vertical.and.arrow.left", "⌃A")
        add(.layout, "grow-width", "Wider", "arrow.left.and.line.vertical.and.arrow.right", "⌃D")
        add(.layout, "shrink-height", "Shorter", "arrow.down.and.line.horizontal.and.arrow.up", "⌃W")
        add(.layout, "grow-height", "Taller", "arrow.up.and.line.horizontal.and.arrow.down", "⌃S")
        add(.layout, "balance", "Balance sizes", "equal.square", "⌃=")
        add(.screens, "focus-screen-prev", "Previous screen", "display", "[")
        add(.screens, "focus-screen-next", "Next screen", "display.2", "]")
        add(.screens, "move-window-to-screen-prev", "Move to previous screen", "rectangle.lefthalf.inset.filled.arrow.left", "⇧[")
        add(.screens, "move-window-to-screen-next", "Move to next screen", "rectangle.righthalf.inset.filled.arrow.right", "⇧]")
        /// #118: one row per four-way family ("Fn+⌥W/A/S/D", "Fn+⇧↑/←/↓/→"), when all four share
        /// their modifiers — the defaults do; a rebound family falls back to a row per direction.
        func directions(_ family: String, _ title: String, _ symbol: String, _ letter: String) {
            let names = ["up", "left", "down", "right"].map { family + $0 }
            let chords = names.compactMap { byName[$0]?.sorted { KeyBindings.serialize($0) < KeyBindings.serialize($1) }.first }
            let mods = Set(chords.map { KeyBindings.display(Chord(keyCode: 0, fn: $0.fn, control: $0.control,
                                                                   option: $0.option, shift: $0.shift, command: $0.command)) })
            if chords.count == 4, let m = mods.first, mods.count == 1 {
                let keys = chords.map { KeyBindings.displayKey($0.keyCode) }.joined(separator: "/")
                out.append(Row(group: .screens, title: title, commandName: names[0],
                               chords: [m.dropLast() + keys], symbol: symbol, letter: letter))
            } else {
                for (n, d) in zip(names, ["up", "left", "down", "right"]) { add(.screens, n, "\(title) (\(d))", symbol, letter) }
            }
        }
        directions("focus-screen-", "Screen that way", "display", "⌥W")
        directions("move-window-to-screen-", "Move to screen that way", "macwindow.on.rectangle", "⇧←")
        directions("move-workspace-to-screen-", "Move workspace that way", "rectangle.stack", "⌥⇧←")   // #136
        add(.app, "toggle-shell-ui", "Zen mode", "eye", "Esc")
        add(.app, "toggle-overview", "Overview / launcher", "magnifyingglass", "⇥")
        add(.app, "toggle-spatial-view", "Spatial view (or hold W/S)", "rectangle.grid.1x2", "Z")   // #132
        add(.app, "open-settings", "Open config file", "gearshape", ",")
        add(.app, "close-window", "Close window", "xmark", "Q")
        return out
    }

    public static func primaryDisplay(for command: Command, config: Config) -> String? {
        KeyBindings.chords(for: command, config: config).first.map(KeyBindings.display)
    }
}

/// Transient toast copy for command feedback. **Not yet wired** — the toast surface lands with
/// M3b task B5 (`2026-08-25-m3-roadmap.md`); until then nothing calls this. It stays because the
/// cheat-sheet overlay (which is wired) shares `primaryDisplay`, and the copy is spec'd.
public enum Hint {
    public static func after(_ command: Command, before: World, after: World, config: Config) -> String? {
        switch command {
        case .cycleLayout:
            let name = after.screens[after.focus.screen].map { LayoutCatalogue(config: config).resolve($0.active.layout).def.name } ?? "Layout"
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
