import AppKit
import SpacialShellKit

/// The switcher's ⋯ (#10, design §7): an `NSMenu` of every layout, sectioned built-in / config.toml /
/// drawn, glyph and name, a check on the one the workspace holds, and "Edit layouts…" last.
///
/// A real menu, not a panel: it is a list of choices and nothing else, and the system menu is
/// already keyboard-navigable, type-to-select and never takes key status from the user's window.
@MainActor
enum LayoutMenu {
    static func make(_ state: ScreenShellState, send: @escaping (Command) -> Void,
                     editLayouts: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        let workspace = state.rail.first(where: \.isActive)?.id
        for (i, section) in state.menuSections.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: section.title))
            for choice in section.items {
                let item = ActionMenuItem(choice.def.name) {
                    if let workspace { send(.setWorkspaceLayout(workspace, choice.id)) }
                }
                item.image = LayoutGlyph.image(choice.def)
                item.state = choice.id == state.layout ? .on : .off
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Edit layouts\u{2026}", editLayouts))
        return menu
    }
}

/// A menu item that runs a closure. It is its own target; the menu retains it.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { handler() }
}
