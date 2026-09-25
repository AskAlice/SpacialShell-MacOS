import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// The layout editor (#10, design §2 "Editor model"): presets down the side, the grid on a canvas,
/// name and id, Copy as TOML, Save/Cancel, and Delete or Reset. Every rule lives in Kit's
/// `GridEditor`; this draws it and forwards drags, ⇧-clicks and keystrokes.
///
/// It is the one layout surface that takes key focus, because naming needs typing.
struct LayoutEditorView: View {
    enum Mode {
        case edit(GridEditor)
        /// A built-in (a function of the window count, nothing to draw), or a drawn layout whose
        /// zones are not a clean grid. `canDuplicate` is false for the latter: a copy of zones the
        /// grid cannot express could not be edited either — config.toml is where it is edited.
        case readOnly(LayoutDef, canDuplicate: Bool)
    }
    /// What removing the saved layout means: nothing (built-in, or not saved yet), Delete (drawn
    /// only in the editor), or Reset (a config.toml layout the editor has overridden).
    enum Removal: Equatable { case none, delete(warning: String), reset }

    let mode: Mode
    var removal: Removal = .none
    /// Every id the catalogue has; a new layout may not reuse one.
    var taken: Set<LayoutID> = []
    var onSave: (LayoutDef) -> Void = { _ in }
    var onRemove: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onCancel: () -> Void = {}
    var onCopy: (String) -> Void = { _ in }

    @State private var editor: GridEditor
    @State private var preset: GridEditor.Preset?
    @State private var hint: String?
    @State private var confirmingDelete = false

    static let size = CGSize(width: 780, height: 560)

    init(mode: Mode, removal: Removal = .none, taken: Set<LayoutID> = [],
         onSave: @escaping (LayoutDef) -> Void = { _ in }, onRemove: @escaping () -> Void = {},
         onDuplicate: @escaping () -> Void = {}, onCancel: @escaping () -> Void = {},
         onCopy: @escaping (String) -> Void = { _ in }) {
        self.mode = mode; self.removal = removal; self.taken = taken
        self.onSave = onSave; self.onRemove = onRemove; self.onDuplicate = onDuplicate
        self.onCancel = onCancel; self.onCopy = onCopy
        if case .edit(let e) = mode {
            _editor = State(initialValue: e)
            _preset = State(initialValue: GridEditor.Preset.allCases.first { $0.cells == e.cells })
        } else {
            _editor = State(initialValue: GridEditor())
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190).padding(12)
            Divider()
            VStack(spacing: 12) {
                canvas
                footer
            }
            .padding(16)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("Delete \u{201C}\(editor.name)\u{201D}?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: onRemove)
        } message: {
            if case .delete(let warning) = removal { Text(warning) }
        }
    }

    // MARK: sidebar

    @ViewBuilder private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch mode {
            case .edit:
                heading("Start from")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 6), count: 3), alignment: .leading, spacing: 6) {
                    ForEach(GridEditor.Preset.allCases, id: \.self) { p in presetButton(p) }
                }
                .padding(.bottom, 8)
                heading("Name")
                TextField("Name", text: Binding(get: { editor.name }, set: { editor.setName($0) }))
                    .textFieldStyle(.roundedBorder).labelsHidden()
                heading("ID").padding(.top, 4)
                TextField("id", text: Binding(get: { editor.id }, set: { editor.setID($0) }))
                    .textFieldStyle(.roundedBorder).labelsHidden()
                    .disabled(!editor.isNew)
                    .help(editor.isNew ? "What config.toml and spacialctl call it" : "Workspaces hold the id, so it stays")
                heading("Zones").padding(.top, 4)
                Text("\(editor.cells.count) \u{00B7} fill order 1 \u{2192} \(editor.cells.count)")
                    .font(.system(size: 12))
                if let problem = editor.problem(taken: taken) {
                    Text(problem).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }
            case .readOnly(let def, _):
                heading("Name")
                Text(def.name).font(.system(size: 12))
                heading("ID").padding(.top, 4)
                Text(def.id.rawValue).font(.system(size: 12, design: .monospaced))
                Text(def.isBuiltin
                     ? "Built-in layouts adapt to the number of windows and cannot be changed. Drawn layouts have a fixed number of zones and page when there are more windows."
                     : "These zones are not a grid the editor can draw: they overlap, leave holes, or fall between its 1/48 steps. Edit them in config.toml.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            Spacer(minLength: 0)
            switch removal {
            case .none: EmptyView()
            case .delete: Button("Delete layout\u{2026}", role: .destructive) { confirmingDelete = true }
            case .reset:
                Button("Reset to config.toml", action: onRemove)
                    .help("Drop the editor's changes and use the layout as config.toml defines it")
            }
        }
    }

    private func heading(_ s: String) -> some View {
        Text(s).textCase(.uppercase).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func presetButton(_ p: GridEditor.Preset) -> some View {
        Button { editor.apply(p); preset = p } label: {
            ZoneOutline(zones: p.zones).fill(.secondary.opacity(0.35))
                .padding(3)
                .frame(width: 48, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(preset == p ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                                  lineWidth: preset == p ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: canvas

    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.6))
                switch mode {
                case .edit: grid(size)
                case .readOnly(let def, _):
                    if case .zones(let zones) = def.body {
                        ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                            zoneView(number: i + 1, picked: false)
                                .frame(width: z.w * size.width - 8, height: z.h * size.height - 8)
                                .offset(x: z.x * size.width + 4, y: z.y * size.height + 4)
                        }
                    } else {
                        LayoutGlyph(def: def).scaleEffect(4).frame(width: size.width, height: size.height)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func grid(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(editor.cells.enumerated()), id: \.offset) { i, cell in
                let z = cell.zone
                zoneView(number: editor.number(of: i), picked: editor.selected == i)
                    .frame(width: z.w * size.width - 8, height: z.h * size.height - 8)
                    .offset(x: z.x * size.width + 4, y: z.y * size.height + 4)
                    .onTapGesture {
                        guard NSEvent.modifierFlags.contains(.shift) else { hint = "\u{21E7}-click two cells to merge them"; return }
                        editor.shiftClick(i)
                        hint = editor.selected.map { "\u{21E7}-click a cell beside \(editor.number(of: $0)) to merge them" }
                    }
            }
            ForEach(Array(editor.splitters.enumerated()), id: \.offset) { _, s in splitterView(s, size) }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(splitterDrag(size))
    }

    private func zoneView(number: Int, picked: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor.opacity(picked ? 0.45 : 0.18))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.5))
            .overlay(Text("\(number)").font(.system(size: 30, weight: .bold)).foregroundStyle(.secondary))
    }

    private func splitterView(_ s: GridEditor.Splitter, _ size: CGSize) -> some View {
        let vertical = s.axis == .vertical
        let along = (s.span.upperBound - s.span.lowerBound) * (vertical ? size.height : size.width)
        let at = s.position * (vertical ? size.width : size.height)
        let start = s.span.lowerBound * (vertical ? size.height : size.width)
        return Capsule().fill(Color.accentColor)
            .frame(width: vertical ? 6 : 28, height: vertical ? 28 : 6)
            .position(x: vertical ? at : start + along / 2, y: vertical ? start + along / 2 : at)
            .allowsHitTesting(false)
    }

    /// One drag for every splitter: it picks the splitter under the press, then keeps moving those
    /// same cells, so dragging past another edge does not hand the drag to it.
    @State private var dragging: GridEditor.Splitter?
    private func splitterDrag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let unit = (x: Double(value.location.x / size.width), y: Double(value.location.y / size.height))
                if dragging == nil {
                    let start = (x: Double(value.startLocation.x / size.width), y: Double(value.startLocation.y / size.height))
                    dragging = editor.splitter(near: start, tolerance: (x: Double(8 / size.width), y: Double(8 / size.height)))
                }
                guard let s = dragging else { return }
                dragging = editor.move(s, to: s.axis == .vertical ? unit.x : unit.y)
                preset = nil
                hint = "Splitter at \(dragging!.percent) (snaps to 1/48)"
            }
            .onEnded { _ in dragging = nil }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let toml = currentTOML {
                Button("Copy as TOML") { onCopy(toml); hint = "Copied \u{2014} paste it into config.toml" }
            }
            Text(hint ?? defaultHint).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            switch mode {
            case .edit:
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(editor.def) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editor.problem(taken: taken) != nil)
            case .readOnly(_, let canDuplicate):
                Button("Close", action: onCancel).keyboardShortcut(.cancelAction)
                if canDuplicate { Button("Duplicate to edit", action: onDuplicate).keyboardShortcut(.defaultAction) }
            }
        }
    }

    private var defaultHint: String {
        if case .readOnly = mode { return "" }
        return "Drag a splitter \u{00B7} \u{21E7}-click two cells to merge"
    }

    private var currentTOML: String? {
        switch mode {
        case .edit: editor.def.toml
        case .readOnly(let def, _): def.toml
        }
    }
}
