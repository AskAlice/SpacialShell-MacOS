import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellPlatform
import SpacialShellProtocol

/// #188: the app window switcher — every window of the focused app as a preview, its title and
/// its workspace under it, the selected one on #179's highlight. The app's icon and name head it.
/// A window without a picture yet (or without the Screen Recording grant) shows its app's icon.
///
/// Props in, a window out: `AppWindowSwitcher` is the state, `thumbnails` the cached pictures.
struct AppWindowSwitcherView: View {
    let state: AppWindowSwitcher
    let appName: String
    let appIcon: NSImage?
    var thumbnails: [SpacialShellProtocol.WindowRef: NSImage] = [:]
    var columns = 4
    var onSelect: (SpacialShellProtocol.WindowRef) -> Void = { _ in }
    var reduceMotion = false

    static let previewSize = CGSize(width: 192, height: 120)
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 16

    /// As many previews a row as fit in `width` (the display's), at least one.
    static func columns(count: Int, fitting width: CGFloat) -> Int {
        let fit = Int((width - 2 * padding + spacing) / (previewSize.width + spacing))
        return max(1, min(count, fit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let appIcon {
                    Image(nsImage: appIcon).resizable().frame(width: 20, height: 20)
                }
                Text(appName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("\(state.items.count) windows").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.previewSize.width), spacing: Self.spacing),
                                     count: columns),
                      alignment: .leading, spacing: Self.spacing) {
                ForEach(state.items) { tile($0) }
            }
        }
        .padding(Self.padding)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }

    private func tile(_ item: AppWindowSwitcher.Item) -> some View {
        let selected = item.ref == state.selectedRef
        return VStack(alignment: .leading, spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.6))
                if let image = thumbnails[item.ref] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else if let appIcon {
                    Image(nsImage: appIcon).resizable().frame(width: 40, height: 40).opacity(0.6)
                } else {
                    Image(systemName: "app.dashed").font(.system(size: 28)).foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.previewSize.width, height: Self.previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(item.title ?? appName).font(.system(size: 12)).lineLimit(1)
            Text(item.workspace ?? "Not in a workspace").font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: Self.previewSize.width, alignment: .leading)
        // #179's highlight, drawn past the item so the selection never moves the grid.
        .background(
            RoundedRectangle(cornerRadius: RailHoverCard.highlightRadius, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.10 : 0))
                .padding(-RailHoverCard.highlightOutset)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected))
        .contentShape(Rectangle())
        .onTapGesture { onSelect(item.ref) }
    }
}

/// #188: owns the switcher panel, the ⌘Tab way `SpatialController` owns a held-open spatial view.
/// `Fn+`` / `⌃⌥`` / `⌘`` (`switchAppWindow`) opens it when the app has another window, with the
/// modifiers then down as the ones that hold it; `` ` `` again steps, `⇧`` steps back, Esc cancels
/// (the hotkey tap binds it through `onModal` while open), and letting go of any held modifier —
/// through the tap's `onFlags` — sends the selected window's `.focusWindowRef` to the store. A click
/// on a preview sends it at once. The panel never takes key focus.
///
/// It keeps the recently focused windows across every workspace (`AppWindowSwitcher.noting`) from
/// each published world: the model's #137 history is per row.
@MainActor
public final class AppWindowSwitcherController {
    private let panel = PanelWindow()
    private var host: NSHostingView<AppWindowSwitcherView>?
    private let appMeta: AppMetaCache
    private let send: @Sendable (Command) -> Void
    private var world: World?
    private var titles: [SpacialShellProtocol.WindowRef: String] = [:]
    private var recent: [SpacialShellProtocol.WindowRef] = []
    private var switcher: AppWindowSwitcher?
    /// The modifiers holding it open; see `AppWindowSwitcher.holdModifiers`.
    private var held: CGEventFlags = []
    /// The last modifiers the tap reported, whether or not it is open.
    private var flags: CGEventFlags = []
    public var isOpen: Bool { switcher != nil }
    /// Told when it opens, so the cheat sheet gets out of its way (#185).
    public var onOpen: () -> Void = {}
    /// The chords the hotkey tap binds while it is open (Esc), and `[:]` once it closes.
    public var onModal: ([Chord: Command]) -> Void = { _ in }
    /// Puts the panel on screen. A test passes a no-op, so no run ever leaves a real panel on the
    /// user's display (#182's stuck card).
    private let present: (NSWindow) -> Void
    /// The modifiers physically down right now. Tests pass `{ [] }`: read live, a unit test depended
    /// on whatever the person at the keyboard was holding while it ran.
    private let keyboard: () -> CGEventFlags
    /// Its own thumbnail refresh is running: only that one is cancelled on close.
    private var refreshing = false

    public init(appMeta: AppMetaCache, send: @escaping @Sendable (Command) -> Void,
                present: @escaping (NSWindow) -> Void = { $0.orderFrontRegardless() },
                keyboard: @escaping () -> CGEventFlags = { CGEventSource.flagsState(.combinedSessionState) }) {
        self.appMeta = appMeta
        self.send = send
        self.present = present
        self.keyboard = keyboard
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)   // over the rail and the bar
    }

    public func update(world: World, snapshot: ShellSnapshot) {
        self.world = world
        titles = snapshot.titles
        recent = AppWindowSwitcher.noting(world, in: recent)
    }

    /// `switchAppWindow` and `cancelAppWindowSwitch`, from the tap or `spacialctl`.
    public func handle(_ command: Command) {
        switch command {
        case .switchAppWindow(let reverse):
            guard switcher != nil else { return open(reverse: reverse) }
            switcher?.step(forward: !reverse)
            render()
        case .cancelAppWindowSwitch:
            close(committing: false)
        default:
            break
        }
    }

    /// Fed from the tap's `onFlags`: letting go of a held modifier switches.
    public func flagsChanged(_ flags: CGEventFlags) {
        self.flags = flags
        guard isOpen, !AppWindowSwitcher.isHeld(flags, by: held) else { return }
        close(committing: true)
    }

    private func open(reverse: Bool) {
        guard let world, let s = AppWindowSwitcher(world: world, recent: recent, titles: titles,
                                                   categoryOf: { [appMeta] in appMeta.meta(for: $0).category },
                                                   reverse: reverse)
        else { return }
        // What the tap last reported, or what the session says now: a flags event still queued
        // behind this command (the modifier already let go) then commits at once, and a quick tap
        // and release, or `spacialctl run switch-app-window`, never leaves the panel stranded.
        held = AppWindowSwitcher.holdModifiers(flags.union(keyboard()))
        guard !held.isEmpty else {
            if let c = s.end(committing: true) { send(c) }
            return
        }
        switcher = s
        onModal(Dictionary(uniqueKeysWithValues: AppWindowSwitcher.cancelChords(held: held).map { ($0, .cancelAppWindowSwitch) }))
        onOpen()
        render()
        present(panel)
        // #181's refresh: the missing and stale previews, taken now and swapped in as they land.
        // ponytail: one on-demand capture queue, shared with the spatial view; opened over a
        // spatial view, this replaces its pending captures. A queue each if that proves common.
        let due = s.items.map(\.ref).filter { WindowThumbnails.shared.isStale($0.id) }
        guard !due.isEmpty else { return }
        refreshing = true
        ThumbnailRefresher.shared.refresh([due]) { [weak self] in
            guard let self, self.isOpen else { return }
            self.render()
        }
    }

    private func choose(_ ref: SpacialShellProtocol.WindowRef) {
        switcher?.select(ref)
        close(committing: true)
    }

    private func close(committing: Bool) {
        guard let s = switcher else { return }
        switcher = nil
        held = []
        onModal([:])
        if refreshing { ThumbnailRefresher.shared.cancelRefresh() }
        refreshing = false
        panel.orderOut(nil)
        panel.contentView = nil
        host = nil
        if let c = s.end(committing: committing) { send(c) }
    }

    private func render() {
        guard let s = switcher, let world else { return }
        let screen = NSScreen.screens.first { DisplayTopology.uuid(for: $0) == world.focus.screen }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let vf = screen?.visibleFrame else { return }
        let meta = appMeta.meta(for: s.pid), thumbs = WindowThumbnails.shared
        var images: [SpacialShellProtocol.WindowRef: NSImage] = [:]
        for item in s.items { images[item.ref] = thumbs.image(for: item.ref.id) }
        let view = AppWindowSwitcherView(
            state: s, appName: meta.name, appIcon: meta.icon, thumbnails: images,
            columns: AppWindowSwitcherView.columns(count: s.items.count, fitting: vf.width * 0.9),
            onSelect: { [weak self] in self?.choose($0) },
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if let host {
            host.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            self.host = host
            panel.contentView = host
        }
        let size = host!.fittingSize
        panel.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
    }
}
