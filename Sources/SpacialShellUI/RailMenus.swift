import AppKit
import SwiftUI
import SpacialShellKit

/// M3 B3's two rail menus (#111, #112). Both are `NSMenu`s popped from the non-activating rail,
/// like the switcher's ⋯ (`LayoutMenu`): system menus are keyboard-navigable and never take key
/// status from the user's window. Every item sends a `Command`.
@MainActor
enum RailMenu {
    /// #111: the app menu, on the rail's `square.stack.3d.up`. No clock (#24 P4).
    static func app(send: @escaping (Command) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("Toggle Zen") { send(.toggleShellUI) })
        menu.addItem(ActionMenuItem("Reload config") { send(.reloadConfig) })
        menu.addItem(ActionMenuItem("Settings\u{2026}") { send(.openSettings) })
        menu.addItem(ActionMenuItem("About SpacialShell") { send(.showAbout) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Quit SpacialShell") { send(.quit) })
        return menu
    }

    /// The glyphs "Set symbol" offers: a fixed list, so choosing one needs no text field (which
    /// would need a key window) and every choice is a symbol this macOS has.
    static let symbols: [(name: String, title: String)] = [
        ("square.grid.2x2", "Default"), ("globe", "Globe"), ("terminal", "Terminal"),
        ("chevron.left.forwardslash.chevron.right", "Code"), ("bubble.left.and.bubble.right", "Chat"),
        ("play.rectangle", "Media"), ("paintbrush", "Design"), ("doc.text", "Document"), ("folder", "Folder"),
        ("wrench.and.screwdriver", "Tools"), ("envelope", "Mail"), ("gamecontroller", "Games"),
        ("music.note", "Music"), ("star", "Star"),
    ]

    /// #112: a tile's right-click menu. `categories` is `category-order`, the configured ones; the
    /// rest follow, as in the settings pane, so any category can be a workspace's identity.
    static func workspace(_ item: WorkspaceRailItem, layouts: [LayoutChoice], categories: [AppCategory],
                          send: @escaping (Command) -> Void) -> NSMenu {
        let menu = NSMenu()
        let id = item.id

        let category = NSMenu()
        for c in categories + AppCategory.allCases.filter({ !categories.contains($0) }) {
            let entry = ActionMenuItem(c.label.prefix(1).uppercased() + c.label.dropFirst()) { send(.setWorkspaceCategory(id, c)) }
            entry.state = item.category == c ? .on : .off
            category.addItem(entry)
        }
        category.addItem(.separator())
        let none = ActionMenuItem("None") { send(.setWorkspaceCategory(id, nil)) }
        none.state = item.category == nil ? .on : .off
        category.addItem(none)
        menu.addItem(submenu("Set category", category))

        let symbol = NSMenu()
        for (name, title) in symbols {
            let entry = ActionMenuItem(title) { send(.setWorkspaceSymbol(id, name)) }
            entry.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            entry.state = item.symbol == name ? .on : .off
            symbol.addItem(entry)
        }
        menu.addItem(submenu("Set symbol", symbol))

        let layout = NSMenu()
        for choice in layouts {
            let entry = ActionMenuItem(choice.def.name) { send(.setWorkspaceLayout(id, choice.id)) }
            entry.image = LayoutGlyph.image(choice.def)
            entry.state = item.layout == choice.id ? .on : .off
            layout.addItem(entry)
        }
        menu.addItem(submenu("Set layout", layout))

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Remove workspace") { send(.removeWorkspace(id)) })
        return menu
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// A tile's right and middle clicks (#112, W13). SwiftUI on macOS 14 has neither, so this sits over
/// the tile and claims only those: for every other event `hitTest` answers nil, so left clicks,
/// drags, drops and hovers reach the SwiftUI button underneath exactly as before.
struct RailClickCatcher: NSViewRepresentable {
    let onRight: () -> Void
    let onMiddle: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) {
        view.onRight = onRight; view.onMiddle = onMiddle
    }

    final class CatcherView: NSView {
        var onRight: () -> Void = {}
        var onMiddle: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown?, .rightMouseUp?, .otherMouseDown?, .otherMouseUp?: super.hitTest(point)
            default: nil
            }
        }
        override func rightMouseDown(with event: NSEvent) { onRight() }
        override func otherMouseDown(with event: NSEvent) {}
        // On release, like a click: a middle press dragged off the tile removes nothing.
        override func otherMouseUp(with event: NSEvent) {
            if event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)) { onMiddle() }
        }
    }
}
