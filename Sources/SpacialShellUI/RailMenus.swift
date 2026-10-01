import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

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
        menu.addItem(ActionMenuItem("Reload SpacialShell") { send(.reload) })   // #194
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
    /// #201: it leads with the tile's windows, each a submenu holding that window's own menu.
    static func workspace(_ item: WorkspaceRailItem, layouts: [LayoutChoice], categories: [AppCategory],
                          rail: [WorkspaceRailItem], windowInfo: (SpacialShellProtocol.WindowRef) -> WindowInfo,
                          metaFor: (Int32) -> AppMeta, send: @escaping (Command) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let id = item.id
        if !item.windows.isEmpty {
            let header = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for ref in item.windows {
                let info = windowInfo(ref)
                let entry = submenu(info.title, window(info, rail: rail, metaFor: metaFor, send: send))
                entry.image = metaFor(ref.pid).icon.map { icon in
                    let small = icon.copy() as! NSImage
                    small.size = NSSize(width: 16, height: 16)
                    return small
                }
                menu.addItem(entry)
            }
            menu.addItem(.separator())
        }

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

    /// #201: what a window menu needs to know; a tab has it all, a window elsewhere gets it from
    /// the shell controller's world.
    struct WindowInfo {
        let ref: SpacialShellProtocol.WindowRef
        let title: String
        let isFloating: Bool, isPinned: Bool, isPlaceholder: Bool
        /// #129: a pinned placeholder cannot be closed until it is unpinned.
        var canClose: Bool { !(isPlaceholder && isPinned) }
    }

    /// #127: a tab's right-click menu — #201's window menu, built from the tab.
    static func tab(_ tab: WindowTabItem, rail: [WorkspaceRailItem], metaFor: (Int32) -> AppMeta,
                    send: @escaping (Command) -> Void) -> NSMenu {
        window(WindowInfo(ref: tab.ref, title: tab.title, isFloating: tab.isFloating, isPinned: tab.isPinned,
                          isPlaceholder: tab.isPlaceholder), rail: rail, metaFor: metaFor, send: send)
    }

    /// #201: one window menu wherever a window appears — a tab (#127), a sidebar card's preview
    /// (#179), a tile's per-window submenu. "Move to Workspace" lists this display's other rows as
    /// the hover card names them, then "+" as "New workspace": a drop in menu form, not followed
    /// (#95). Hide and Quit act on the app itself (the store sees the result like any other).
    /// A placeholder (#128) has no window: Open and Close only.
    static func window(_ w: WindowInfo, rail: [WorkspaceRailItem], metaFor: (Int32) -> AppMeta,
                       send: @escaping (Command) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false   // `isEnabled` below is the truth, not target/action validation
        let ref = w.ref
        if w.isPlaceholder {
            menu.addItem(ActionMenuItem("Open") { send(.focusWindowRef(ref)) })
            let close = ActionMenuItem("Close") { send(.closeWindowRef(ref)) }
            close.isEnabled = w.canClose
            menu.addItem(close)
            return menu
        }
        menu.addItem(ActionMenuItem("Switch to Window") { send(.focusWindowRef(ref)) })
        menu.addItem(.separator())
        let others = rail.filter { !$0.windows.contains(ref) }
        let move = workspaceList(others, metaFor: metaFor) { send(.moveWindowRefToWorkspace(ref, $0, follow: false)) }
        let moveItem = submenu("Move to Workspace", move)
        moveItem.isEnabled = !move.items.isEmpty
        menu.addItem(moveItem)
        let app = workspaceList(others, metaFor: metaFor) { send(.moveAppRefToWorkspace(ref, $0)) }   // #98
        let appItem = submenu("Move App to Workspace", app)
        appItem.isEnabled = !app.items.isEmpty
        menu.addItem(appItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(w.isFloating ? "Tile" : "Float") { send(.toggleFloatRef(ref)) })
        let pin = ActionMenuItem(w.isPinned ? "Unpin" : "Pin") { send(.togglePinRef(ref)) }
        pin.image = NSImage(systemSymbolName: w.isPinned ? "pin.slash" : "pin.circle", accessibilityDescription: nil)
        menu.addItem(pin)
        menu.addItem(.separator())
        let name = metaFor(ref.pid).name
        let hide = ActionMenuItem("Hide App") { NSRunningApplication(processIdentifier: ref.pid)?.hide() }
        hide.toolTip = "Hide \(name)"
        menu.addItem(hide)
        menu.addItem(ActionMenuItem("Close Window") { send(.closeWindowRef(ref)) })
        let quit = ActionMenuItem("Quit App") { NSRunningApplication(processIdentifier: ref.pid)?.terminate() }
        quit.toolTip = "Quit \(name)"
        menu.addItem(quit)
        return menu
    }

    /// This display's rows as a menu of destinations, named as the hover card names them (#183),
    /// with "+" last as "New workspace".
    private static func workspaceList(_ rows: [WorkspaceRailItem], metaFor: (Int32) -> AppMeta,
                                      pick: @escaping (UUID) -> Void) -> NSMenu {
        let menu = NSMenu()
        for item in rows {
            if item.isTrailingEmpty, !menu.items.isEmpty { menu.addItem(.separator()) }
            let category = AppCategories.rowCategory(item.category, windows: item.windows) { metaFor($0).category }
            let title = item.isTrailingEmpty ? "New workspace"
                : "\(AppCategories.rowTitle(name: item.name, category: category, isTrailingEmpty: false)) (\(item.index + 1))"
            let entry = ActionMenuItem(title) { pick(item.id) }
            entry.image = NSImage(systemSymbolName: item.isTrailingEmpty ? "plus" : item.symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }
        return menu
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// A tile's or a tab's right and middle clicks (#112, W13, #127). SwiftUI on macOS 14 has neither,
/// so this sits over the tile or tab and claims only those: for every other event `hitTest` answers nil, so left clicks,
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
