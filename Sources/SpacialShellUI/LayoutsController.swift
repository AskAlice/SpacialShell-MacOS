import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// The app-layer side of layouts (#10): the editor window, and the `settings.json` edits the
/// popover asks for (Set as default, Show on bar). Everything it writes goes out through
/// `onChange` — the same door the settings window uses — so AppRuntime persists, re-layers and
/// pushes it like any other override, and hands the result back through `update(config:overrides:)`.
@MainActor
public final class LayoutsController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var config: Config          // effective: what the shell runs on
    private var overrides: SettingsOverrides
    private var world: World?
    private let send: @Sendable (Command) -> Void
    private let onChange: (SettingsOverrides) -> Void

    public init(config: Config, overrides: SettingsOverrides,
                send: @escaping @Sendable (Command) -> Void,
                onChange: @escaping (SettingsOverrides) -> Void) {
        self.config = config
        self.overrides = overrides
        self.send = send
        self.onChange = onChange
    }

    public func update(config: Config, overrides: SettingsOverrides) {
        self.config = config
        self.overrides = overrides
    }

    public func update(world: World) { self.world = world }

    private var catalogue: LayoutCatalogue { LayoutCatalogue(config: config) }

    /// The popover's commands. Anything else is not ours.
    public func handle(_ command: Command) {
        switch command {
        case .editLayout(let id, let workspace): open(id, workspace: workspace)
        case .setDefaultLayout(let id): edit { $0.defaultLayout = id }
        case .showLayoutOnBar(let id, let on):
            let bar = catalogue.bar
            edit { $0.setLayout(id, onBar: on, current: bar) }
        default: break
        }
    }

    private func edit(_ change: (inout SettingsOverrides) -> Void) {
        var new = overrides
        change(&new)
        guard new != overrides else { return }
        overrides = new
        onChange(new)
    }

    // MARK: - the editor window

    /// New… when `id` is nil (from a 2×2 grid, as in the approved mockup); otherwise that layout —
    /// editable if it is a drawn grid, read-only if it is a built-in or zones the grid cannot express.
    public func open(_ id: LayoutID?, workspace: UUID?) {
        let catalogue = catalogue
        let taken = Set(catalogue.all.map(\.id))
        guard let id, let def = catalogue[id] else {
            show(LayoutEditorView(mode: .edit(GridEditor(preset: .grid2x2)), taken: taken,
                                  onSave: { [weak self] in self?.save($0, isNew: true, workspace: workspace) },
                                  onCancel: { [weak self] in self?.close() }, onCopy: Self.copy))
            return
        }
        let duplicate = { [weak self] in self?.duplicate(def, workspace: workspace) ?? () }
        guard let grid = GridEditor(editing: def) else {
            show(LayoutEditorView(mode: .readOnly(def, canDuplicate: def.isBuiltin),
                                  removal: removal(for: def.id, catalogue: catalogue),
                                  onRemove: { [weak self] in self?.remove(def.id) },
                                  onDuplicate: duplicate,
                                  onCancel: { [weak self] in self?.close() }, onCopy: Self.copy))
            return
        }
        show(LayoutEditorView(mode: .edit(grid), removal: removal(for: def.id, catalogue: catalogue), taken: taken,
                              onSave: { [weak self] in self?.save($0, isNew: false, workspace: workspace) },
                              onRemove: { [weak self] in self?.remove(def.id) },
                              onCancel: { [weak self] in self?.close() }, onCopy: Self.copy))
    }

    private func duplicate(_ def: LayoutDef, workspace: UUID?) {
        var grid = GridEditor(duplicating: def)
        // "Split copy", then "Split copy 2"…: the suggested id must be free or Save starts disabled.
        let taken = Set(catalogue.all.map(\.id))
        var n = 2
        let base = grid.name
        while taken.contains(LayoutID(rawValue: grid.id)) { grid.setName("\(base) \(n)"); n += 1 }
        show(LayoutEditorView(mode: .edit(grid), taken: taken,
                              onSave: { [weak self] in self?.save($0, isNew: true, workspace: workspace) },
                              onCancel: { [weak self] in self?.close() }, onCopy: Self.copy))
    }

    /// Built-ins cannot be removed; a file layout can only lose the editor's override of it (Reset);
    /// a drawn one is deleted, with the count of workspaces that will fall back (design §8).
    private func removal(for id: LayoutID, catalogue: LayoutCatalogue) -> LayoutEditorView.Removal {
        let overridden = overrides.layouts?.contains { $0.id == id } ?? false
        if catalogue.fileIDs.contains(id) { return overridden ? .reset : .none }
        guard overridden else { return .none }
        return .delete(warning: GridEditor.deleteWarning(usage: world?.workspaces(using: id) ?? 0,
                                                         fallback: catalogue.fallback(afterDeleting: id)))
    }

    /// Save writes settings.json. A new layout joins the bar if there is room and is applied to
    /// the workspace the popover was opened on — the approved walkthrough's step 7.
    private func save(_ def: LayoutDef, isNew: Bool, workspace: UUID?) {
        let bar = catalogue.bar
        edit { o in
            o.saveLayout(def)
            if isNew { o.setLayout(def.id, onBar: true, current: bar) }
        }
        if isNew, let workspace { send(.setWorkspaceLayout(workspace, def.id)) }
        close()
    }

    private func remove(_ id: LayoutID) {
        edit { $0.removeLayout(id) }
        close()
    }

    private static func copy(_ toml: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(toml, forType: .string)
    }

    private func show(_ view: LayoutEditorView) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: LayoutEditorView.size),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Layout editor"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        // A fresh host each time: the view's @State is the draft, and a reopened editor must not
        // resume the one that was cancelled.
        window?.contentView = NSHostingView(rootView: view)
        // Like the settings window: an LSUIElement app is not activated by ordering a window
        // front, and an unactivated window cannot take the typing that naming needs.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func close() { window?.close() }
}
