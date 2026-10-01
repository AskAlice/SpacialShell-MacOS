import AppKit

/// #200: SpacialShell is an accessory app, so it has no menu bar — and a text field gets ⌘A, ⌘C,
/// ⌘V, ⌘X and ⌘Z only through the main menu's key equivalents. This menu is never shown; it is
/// there so every field the shell draws (the overview's search, settings, the layout editor)
/// edits like any other Mac text field.
public enum ShellMainMenu {
    public static func make() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "SpacialShell")
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            edit.addItem(i)
        }
        item("Undo", Selector(("undo:")), "z")
        item("Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        item("Cut", #selector(NSText.cut(_:)), "x")
        item("Copy", #selector(NSText.copy(_:)), "c")
        item("Paste", #selector(NSText.paste(_:)), "v")
        item("Select All", #selector(NSText.selectAll(_:)), "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
