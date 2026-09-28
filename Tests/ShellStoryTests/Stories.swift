import AppKit
import SwiftUI
import Foundation
import SpacialShellKit
import SpacialShellProtocol
@testable import SpacialShellUI

/// The story catalog — Storybook for the shell. One entry per interesting state of each view,
/// rendered at the view's true geometry. Every story is (a) image-snapshotted in light and dark
/// and (b) run through `LayoutLint` (no overlapping text, nothing escaping its container).
/// Adding a UI state? Add its story here and it is covered by both, and becomes PR-media source.
@MainActor
struct Story {
    let name: String
    let size: CGSize?          // nil = use the view's fitting size
    let view: AnyView
    /// Stories that model a condition the design knows it does not handle yet (e.g. tab overflow
    /// before T19's "+N" badge). Their lint runs under `withKnownIssue` so the gap is recorded
    /// without a red suite; remove the flag when the handling lands.
    var knownOverflow: Bool = false
    /// The story's ideal width legitimately exceeds its container because its text truncates —
    /// which is handling, not a gap, and the opposite of `knownOverflow`. `fittingSize` reports
    /// the untruncated ideal, so LayoutLint's must-fit check cannot tell the two apart; this says
    /// which one it is. The escape check still runs, so real clipping is still caught.
    var truncates: Bool = false
    /// The view focuses a text field as it appears (the overview's search field, from `onAppear`).
    /// SwiftUI applies that some passes later, so the harness waits for it before snapshotting (#159).
    var awaitsFocus: Bool = false
}

/// An `NSMenu` drawn as the system draws it — section headers, separators, a check on the current
/// item, template glyphs — from the menu's own items, so the story shows what `LayoutMenu` built.
struct MenuPreview: View {
    let menu: NSMenu
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(menu.items.enumerated()), id: \.offset) { _, item in
                if item.isSeparatorItem {
                    Divider().padding(.vertical, 5).padding(.horizontal, 6)
                } else if item.isSectionHeader {
                    Text(item.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 2)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                            .opacity(item.state == .on ? 1 : 0).frame(width: 12)
                        if let image = item.image { Image(nsImage: image).renderingMode(.template).frame(width: 18) }
                        else { Color.clear.frame(width: 18, height: 1) }
                        Text(item.title).font(.system(size: 13))
                        if item.hasSubmenu {
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 22)
                    .opacity(item.isEnabled ? 1 : 0.4)
                }
            }
        }
        .padding(5)
        .frame(width: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.regularMaterial))
    }
}

@MainActor
enum Stories {
    // MARK: fixtures

    static func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        return image
    }

    static let meta: (Int32) -> AppMeta = { pid in
        // #128: a placeholder's pid is negative; the stories use -n for app n.
        let pid = abs(pid)
        let names: [Int32: String] = [
            1: "Safari", 2: "Notes", 3: "Terminal", 4: "Mail",
            5: "A Very Long Application Name That Must Truncate", 6: "X",
        ]
        let colors: [NSColor] = [.systemBlue, .systemYellow, .systemGray, .systemTeal, .systemPink, .systemGreen]
        // Real bundle ids, so the stories go through the same table the shell does: Safari is
        // `web` only because the table overrules the `productivity` it declares about itself.
        let bundles: [Int32: String] = [
            1: "com.apple.Safari", 2: "com.apple.Notes", 3: "com.apple.Terminal",
            4: "com.apple.mail", 5: "com.microsoft.VSCode", 6: "com.hnc.Discord",
        ]
        let bundle = bundles[pid]
        return AppMeta(name: names[pid] ?? "App \(pid)", icon: swatch(colors[Int(pid - 1) % colors.count]),
                       bundleID: bundle,
                       category: AppCategories.category(bundleID: bundle,
                                                        systemCategory: "public.app-category.productivity"))
    }

    /// A stand-in for a captured window: a landscape swatch, so the miniature has an aspect
    /// ratio the card has to letterbox like a real screenshot.
    static func shot(_ color: NSColor) -> NSImage {
        NSImage(cgImage: capture(color), size: NSSize(width: 320, height: 200))
    }
    /// `shot`'s pixels: a 320 × 200 pt window captured at a fixed 2×, as ScreenCaptureKit hands one
    /// over on a Retina display (#159). `NSImage.lockFocus` drew at the main screen's backing
    /// scale: 640 × 400 px on a Retina Mac, 320 × 200 on a 1× display. Only the first is past
    /// `WindowThumbnails.longSide`, so `rail-hover-cached` went through the downscale on one
    /// machine and skipped it on another. The CTM hint pins the pixel count. Colours are drawn as
    /// before, so every other hover story renders byte-for-byte as it did.
    static func capture(_ color: NSColor) -> CGImage {
        let image = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { rect in
            color.setFill()
            rect.fill()
            NSColor.white.withAlphaComponent(0.35).setFill()
            NSRect(x: 0, y: 170, width: 320, height: 30).fill()
            return true
        }
        var rect = NSRect(x: 0, y: 0, width: 320, height: 200)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: 2)])!
    }

    static func rail(_ items: [WorkspaceRailItem], tray: [SpacialShellProtocol.WindowRef] = []) -> ScreenShellState {
        ScreenShellState(display: "D1", isFocusedScreen: true, rail: items, tabs: [], layout: .split, layouts: .builtins, tray: tray)
    }
    /// `pids` are the apps actually in the row — the rail draws one icon each and derives the
    /// category label from them, so a story without pids is a workspace of unknown apps.
    static func railItem(_ i: Int, name: String, symbol: String, count: Int, pids: [Int32] = [],
                         active: Bool = false, pinned: Bool = false, trailing: Bool = false,
                         category: AppCategory? = nil, attention: Bool = false) -> WorkspaceRailItem {
        WorkspaceRailItem(id: UUID(), index: i, name: name, symbol: symbol, windowCount: count,
                          windows: pids.map { WindowRef(id: WindowID($0) * 10, pid: $0) },
                          isActive: active, isPinned: pinned, isTrailingEmpty: trailing, category: category,
                          wantsAttention: attention)
    }
    static func tabs(_ items: [WindowTabItem], layout: SpacialShellProtocol.LayoutID = .split,
                     layouts: LayoutCatalogue = .builtins) -> ScreenShellState {
        ScreenShellState(display: "D1", isFocusedScreen: true,
                         rail: [railItem(0, name: "Web", symbol: "globe", count: items.count, active: true)],
                         tabs: items, layout: layout, layouts: layouts)
    }

    /// #10: the approved mockup's catalogue — one layout from config.toml, two drawn in the editor.
    static func customLayouts(bar extra: [SpacialShellProtocol.LayoutID] = []) -> LayoutCatalogue {
        func drawn(_ id: SpacialShellProtocol.LayoutID, _ name: String, _ z: [(Double, Double, Double, Double)]) -> LayoutDef {
            LayoutDef(id: id, name: name, body: .zones(z.map { LayoutZone(x: $0.0, y: $0.1, w: $0.2, h: $0.3) }))
        }
        var c = Config()
        c.layouts = [drawn("wide-4", "Ultrawide four", [(0, 0, 0.25, 1), (0.25, 0, 0.5, 1), (0.75, 0, 0.25, 0.5), (0.75, 0.5, 0.25, 0.5)]),
                     drawn("code-3", "Code, three", [(0, 0, 0.625, 1), (0.625, 0, 0.375, 0.5), (0.625, 0.5, 0.375, 0.5)]),
                     drawn("focus-c", "Focus centre", [(0, 0, 0.25, 1), (0.25, 0, 0.5, 1), (0.75, 0, 0.25, 1)])]
        c.fileLayoutIDs = ["wide-4"]
        c.layoutBar += extra
        return LayoutCatalogue(config: c)
    }

    /// The code-3 of the walkthrough's step 6: a 2×2, the left column merged, the splitter at 60 %.
    static var codeThree: GridEditor {
        var e = GridEditor(preset: .grid2x2)
        e.merge(0, 2)
        if let v = e.splitters.first(where: { $0.axis == .vertical }) { e.move(v, to: 0.6) }
        e.setName("Code, three")
        e.setID("code-3")
        return e
    }
    /// `window` distinguishes several windows of one app — tabs are keyed by their ref.
    static func tab(_ pid: Int32, window: Int = 0, focused: Bool = false, floating: Bool = false, hidden: Bool = false,
                    fullscreen: Bool = false, offSpace: Bool = false, title: String = "",
                    attention: Bool = false, pinned: Bool = false) -> WindowTabItem {
        WindowTabItem(ref: WindowRef(id: WindowID(pid) * 10 + WindowID(window) * 1000, pid: pid),
                      isFocused: focused, isFloating: floating, isHidden: hidden, isFullscreen: fullscreen,
                      isOffSpace: offSpace, title: title, wantsAttention: attention, isPinned: pinned)
    }

    /// #132: the spatial view's fixture world, `active` being the row the camera centres.
    static func spatial(active: Int) -> SpatialState {
        func w(_ id: Int, _ pid: Int32) -> SpacialShellProtocol.WindowRef { WindowRef(id: WindowID(id), pid: pid) }
        let (s1, s2, v, t1, t2, chat, mail, n1, n2, n3) = (w(1, 1), w(2, 1), w(3, 5), w(4, 3), w(5, 3), w(6, 6), w(7, 4),
                                                         w(8, 2), w(9, 2), w(10, 2))
        let d: SpacialShellProtocol.DisplayID = "D1"
        let rows = [
            Workspace(name: "Web", layout: .split, windows: [s1, s2], anchor: s1, category: .web),
            Workspace(name: "Code", layout: .half, windows: [v, t1, t2], anchor: t1, category: .coding),
            Workspace(name: "Chat", layout: .maximize, windows: [chat, mail], floating: [mail], anchor: chat),
            Workspace(name: "Notes", layout: .grid, windows: [n1, n2, n3], anchor: n1),
            Workspace(name: "Workspace", layout: .maximize),
        ]
        let world = World(screens: [d: Screen(display: d, workspaces: rows, activeIndex: active)], screenOrder: [d],
                          focus: Focus(screen: d, window: rows[active].anchor), ephemeral: [], ignored: [], hidden: [],
                          parents: [:], defaultLayout: .maximize)
        let titles = [s1: "Pull requests · AskAlice/SpacialShell-MacOS", s2: "developer.apple.com — AXUIElement",
                      v: "SpatialView.swift — spacial-shell", t1: "~/code/spacial-shell — zsh", t2: "~/Downloads — zsh",
                      chat: "#general", n1: "Shopping list", n2: "Ideas"]
        return SpatialView.state(for: d, in: world, layouts: .builtins, titles: titles, viewport: CGSize(width: 1440 - 48 - 16, height: 900 - 34 - 16))!
    }
    /// #181: cached pictures for some of `state`'s chips, keyed by window id, the rest left to the
    /// icon-and-title fallback. Each is a stand-in window at its chip's own aspect (a tiled window
    /// fills its tile), `WindowThumbnails.longSide` px on the long side as the cache holds them: a
    /// title bar, then lines of "text". Drawn straight into a bitmap, so the pixels are the same on
    /// any display, and in fixed colours, as a capture's are in either appearance.
    static func spatialThumbnails(_ state: SpatialState,
                                  _ looks: [WindowID: (bg: UInt32, bar: UInt32, ink: UInt32)])
        -> [SpacialShellProtocol.WindowRef: NSImage] {
        var out: [SpacialShellProtocol.WindowRef: NSImage] = [:]
        for chip in state.rows.flatMap(\.chips) {
            guard let look = looks[chip.ref.id] else { continue }
            out[chip.ref] = windowShot(aspect: chip.frame.width * state.aspect / chip.frame.height, look)
        }
        return out
    }
    /// A stand-in window of `aspect` (width / height) as the thumbnail cache holds one,
    /// `WindowThumbnails.longSide` px on the long side: a title bar, then lines of "text".
    static func windowShot(aspect: CGFloat, _ look: (bg: UInt32, bar: UInt32, ink: UInt32)) -> NSImage {
        func color(_ hex: UInt32) -> CGColor {
            CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let long = WindowThumbnails.longSide
        let w = Int((aspect >= 1 ? long : long * aspect).rounded()), h = Int((aspect >= 1 ? long / aspect : long).rounded())
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(color(look.bg)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(color(look.bar)); ctx.fill(CGRect(x: 0, y: h - 28, width: w, height: 28))   // bottom-left origin
        ctx.setFillColor(color(look.ink))
        for (i, y) in stride(from: h - 56, to: 16, by: -22).enumerated() {
            let length = CGFloat(w - 40) * [0.9, 0.6, 0.75, 0.45, 0.8][i % 5]
            ctx.fill(CGRect(x: 20, y: CGFloat(y), width: length, height: 8))
        }
        let image = ctx.makeImage()!
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    /// #188: Safari (pid 1) with two windows on Web and two on Code, beside the editor; the first is
    /// focused, and the third was used before it.
    static func appWindowSwitcher() -> AppWindowSwitcher {
        func w(_ id: Int, _ pid: Int32) -> SpacialShellProtocol.WindowRef { WindowRef(id: WindowID(id), pid: pid) }
        let (s1, s2, s3, s4, code) = (w(1, 1), w(2, 1), w(3, 1), w(4, 1), w(5, 5))
        let d: SpacialShellProtocol.DisplayID = "D1"
        let rows = [
            Workspace(name: "Web", layout: .split, windows: [s1, s2], anchor: s1, category: .web),
            Workspace(name: "Code", layout: .half, windows: [code, s3, s4], anchor: code, category: .coding),
            Workspace(name: "Workspace", layout: .maximize),
        ]
        let world = World(screens: [d: Screen(display: d, workspaces: rows, activeIndex: 0)], screenOrder: [d],
                          focus: Focus(screen: d, window: s1), ephemeral: [], ignored: [], hidden: [],
                          parents: [:], defaultLayout: .maximize)
        let titles = [s1: "Pull requests · AskAlice/SpacialShell-MacOS", s2: "developer.apple.com — AXUIElement",
                      s3: "Swift Forums — Strict concurrency", s4: "ScreenCaptureKit | Apple Developer Documentation"]
        return AppWindowSwitcher(world: world, recent: [s1, s3, s2], titles: titles)!
    }
    /// #128: a placeholder tab for app `pid` — a negative pid, as `WindowRef.placeholderPid` gives.
    static func placeholder(_ pid: Int32, window: Int = 0, title: String = "", pinned: Bool = false) -> WindowTabItem {
        WindowTabItem(ref: WindowRef(id: WindowID(pid) * 10 + WindowID(window) * 1000, pid: -pid),
                      isFocused: false, isFloating: false, isHidden: false, title: title, isPlaceholder: true,
                      isPinned: pinned)
    }
    /// A menu's submenu by its item's title, so a new item above it does not move the story.
    static func submenu(_ menu: NSMenu, _ title: String) -> NSMenu { menu.items.first { $0.title == title }!.submenu! }

    static let railGeometry = CGSize(width: 48, height: 800)
    static let barGeometry = CGSize(width: 1200, height: 34)

    // MARK: catalog

    static var all: [Story] {
        var out: [Story] = []
        func add(_ name: String, _ size: CGSize?, _ v: some View,
                 knownOverflow: Bool = false, truncates: Bool = false, awaitsFocus: Bool = false) {
            out.append(Story(name: name, size: size, view: AnyView(v),
                             knownOverflow: knownOverflow, truncates: truncates, awaitsFocus: awaitsFocus))
        }
        let send: (Command) -> Void = { _ in }

        // Rail
        add("rail-default", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 3, pids: [5, 3, 5]),
                         railItem(1, name: "Web", symbol: "globe", count: 2, pids: [1, 1], active: true),
                         railItem(2, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send))
        add("rail-pinned-empty", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Chat", symbol: "bubble.left.and.bubble.right", count: 0, pinned: true),
                         railItem(1, name: "Web", symbol: "globe", count: 1, pids: [1], active: true),
                         railItem(2, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send))
        // Five distinct apps in one row: four icons then "+1", and a category label that has to
        // pick one answer out of a mixed row.
        add("rail-many-apps", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Everything", symbol: "square.grid.2x2", count: 6,
                                  pids: [5, 3, 1, 6, 4, 2], active: true),
                         railItem(1, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send))
        // #115 (G14): the other two `rail-icon-style`s over one rail — a coding row the user set
        // (VS Code, Terminal ×2), web (derived from Safari), a pinned chat row still empty, a row
        // of apps nobody can place (falls back to its icons), and a seed's chosen glyph.
        let styled = [railItem(0, name: "Code", symbol: "square.grid.2x2", count: 3, pids: [5, 3, 3], category: .coding),
                      railItem(1, name: "Web", symbol: "square.grid.2x2", count: 2, pids: [1, 1], active: true),
                      railItem(2, name: "Chat", symbol: "square.grid.2x2", count: 0, pinned: true, category: .communication),
                      railItem(3, name: "Workspace 4", symbol: "square.grid.2x2", count: 2, pids: [7, 8]),
                      railItem(4, name: "Notes", symbol: "star", count: 2, pids: [2, 4]),
                      railItem(5, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]
        let unplaced: (Int32) -> AppMeta = { pid in
            let m = meta(pid)
            return pid >= 7 ? AppMeta(name: m.name, icon: m.icon, bundleID: nil, category: nil) : m
        }
        for style in [RailIconStyle.category, .hybrid] {
            add("rail-icons-\(style.rawValue)", railGeometry, ScreenPanelView(
                state: rail(styled), launcherURL: "raycast://", metaFor: unplaced, send: send, iconStyle: style))
        }
        // …and `category-colors` tinting the glyphs (not the active tile's: the accent says "here").
        add("rail-icons-colours", railGeometry, ScreenPanelView(
            state: rail(styled), launcherURL: "raycast://", metaFor: unplaced, send: send, iconStyle: .hybrid,
            categoryColors: [.coding: "#BF5AF2", .web: "#0A84FF", .communication: "#30D158", .productivity: "#FF9F0A"]))
        // #126 (G35): Mail (in the active row) has a Dock badge and Discord (in "Chat") is bouncing:
        // a dot on both tiles — the active one too, over its accent — and on the icon-grid tile.
        add("rail-attention", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 3, pids: [5, 3, 5]),
                         railItem(1, name: "Mail", symbol: "envelope", count: 2, pids: [4, 1], active: true, attention: true),
                         railItem(2, name: "Chat", symbol: "bubble.left.and.bubble.right", count: 1, pids: [6], attention: true),
                         railItem(3, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send))
        // …the same in the category style, where the dot sits on a glyph instead of an icon.
        add("rail-attention-category", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "square.grid.2x2", count: 3, pids: [5, 3, 5], category: .coding),
                         railItem(1, name: "Chat", symbol: "square.grid.2x2", count: 1, pids: [6], active: true,
                                  category: .communication, attention: true),
                         railItem(2, name: "Web", symbol: "square.grid.2x2", count: 1, pids: [1], attention: true),
                         railItem(3, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send, iconStyle: .category))
        // #75: "Chat" mid-drag over "Code" — the insertion line in the gap above where it lands.
        let reorder = [railItem(0, name: "Code", symbol: "terminal", count: 3, pids: [5, 3, 5]),
                       railItem(1, name: "Web", symbol: "globe", count: 2, pids: [1, 1], active: true),
                       railItem(2, name: "Chat", symbol: "bubble.left.and.bubble.right", count: 1, pids: [6]),
                       railItem(3, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]
        add("rail-reorder-insertion", railGeometry, ScreenPanelView(
            state: rail(reorder), launcherURL: "raycast://", metaFor: meta, send: send,
            dropTarget: reorder[0].id, reordering: reorder[2].id))
        // No cog on a secondary display — one way into settings, not one per monitor.
        add("rail-secondary-screen", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 1, pids: [5], active: true),
                         railItem(1, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send))
        add("rail-twelve-workspaces", railGeometry, ScreenPanelView(
            state: rail((0..<11).map { railItem($0, name: "Workspace \($0 + 1)", symbol: "square.grid.2x2",
                                               count: ($0 * 3) % 7, pids: [Int32($0 % 6) + 1], active: $0 == 4) }
                        + [railItem(11, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send),
            knownOverflow: true)   // 12 rows can exceed a short rail; overflow handling is unbuilt

        // Rail hover card — what a tile says when you point at it. The fixtures stand in for
        // ScreenCaptureKit frames: the card is a pure view, so the stories cover every state
        // including the one no test machine can reach (a granted Screen Recording capture).
        func preview(_ pid: Int32, image: NSImage?) -> WindowPreviewItem {
            let m = meta(pid)
            return WindowPreviewItem(ref: WindowRef(id: WindowID(pid) * 10, pid: pid),
                                     name: m.name, icon: m.icon, image: image)
        }
        add("rail-hover-previews", nil, RailHoverCard(
            title: "Coding", subtitle: "3 windows",
            content: .previews([preview(5, image: shot(.systemPink)),
                                preview(3, image: shot(.systemGray)),
                                preview(1, image: shot(.systemBlue))]),
            onGrantAccess: {}), truncates: true)
        // #179: the pointer resting on the second preview — ringed in the accent, its name at full
        // strength; its real window is what the screen shows meanwhile (the peek).
        add("rail-hover-peek", nil, RailHoverCard(
            title: "Code (1)", subtitle: "3 windows · coding",
            content: .previews([preview(5, image: shot(.systemPink)),
                                preview(3, image: shot(.systemGray)),
                                preview(1, image: shot(.systemBlue))]),
            onGrantAccess: {}, highlighted: preview(3, image: nil).ref), truncates: true)
        // #90: the first frame of a hover — thumbnails from the cache, at the cache's downscaled
        // size, and the icon placeholder only for the window the shell has never seen.
        func cached(_ color: NSColor) -> NSImage? {
            WindowThumbnails.downscale(capture(color)).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
        add("rail-hover-cached", nil, RailHoverCard(
            title: "Coding", subtitle: "3 windows",
            content: .previews([preview(5, image: cached(.systemPink)),
                                preview(3, image: cached(.systemGray)),
                                preview(1, image: nil)]),
            onGrantAccess: {}), truncates: true)
        // #182: a window whose app has quit — no picture, no icon, no name — still draws an app
        // glyph, never a blank grey box.
        add("rail-hover-app-gone", nil, RailHoverCard(
            title: "Coding", subtitle: "2 windows",
            content: .previews([preview(5, image: nil),
                                WindowPreviewItem(ref: WindowRef(id: 990, pid: 99), name: "App", icon: nil, image: nil)]),
            onGrantAccess: {}))
        // One window gets the big frame; the capture has not landed yet on the second tile, so
        // this also covers the icon placeholder. #183: every card is titled by the row's category,
        // as the spatial view titles it, and the subtitle is just the count.
        add("rail-hover-one-window", nil, RailHoverCard(
            title: "Web browsing", subtitle: "1 window",
            content: .previews([preview(1, image: shot(.systemBlue))]),
            onGrantAccess: {}))
        // More than the card draws, plus a name that has to truncate under its miniature.
        add("rail-hover-overflow", nil, RailHoverCard(
            title: "Coding", subtitle: "8 windows",
            content: .previews((0..<8).map { preview(Int32($0 % 6) + 1, image: $0 < 4 ? shot(.systemTeal) : nil) }),
            onGrantAccess: {}), truncates: true)
        // The state every Mac without the grant is in — never blank boxes.
        add("rail-hover-needs-screen-recording", nil, RailHoverCard(
            title: "Coding", subtitle: "3 windows",
            content: .needsScreenRecording, onGrantAccess: {}))
        add("rail-hover-empty", nil, RailHoverCard(
            title: "Chat", subtitle: "0 windows",
            content: .message("Nothing here yet. Drop a tab on this tile, or open something from the launcher."),
            onGrantAccess: {}))
        add("rail-hover-new-workspace", nil, RailHoverCard(
            title: "New workspace", subtitle: nil,
            content: .message("Opens a new workspace — or drop a tab here to move its window into one."),
            onGrantAccess: {}))

        // #73: the tray — hidden windows and popups, counted, pinned above the cog.
        let hiddenAway: [SpacialShellProtocol.WindowRef] = [WindowRef(id: 20, pid: 2), WindowRef(id: 40, pid: 4),
                                                            WindowRef(id: 60, pid: 6)]
        add("rail-tray", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 3, pids: [5, 3, 5]),
                         railItem(1, name: "Web", symbol: "globe", count: 2, pids: [1, 1], active: true),
                         railItem(2, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)],
                        tray: hiddenAway),
            launcherURL: "raycast://", metaFor: meta, send: send))
        // …and its list: icon + title rows, a title that has to truncate, one AX would not name
        // (the app's name stands in), and a popup.
        func row(_ pid: Int32, _ title: String?) -> WindowPreviewItem {
            let m = meta(pid)
            return WindowPreviewItem(ref: WindowRef(id: WindowID(pid) * 10, pid: pid), name: title ?? m.name,
                                     icon: m.icon, image: nil)
        }
        add("rail-tray-open", nil, RailHoverCard(
            title: "Hidden windows and popups", subtitle: "4 windows · click one to bring it back",
            content: .windows([row(2, "Shopping list"),
                               row(4, "Re: the quarterly numbers, and a subject line long enough that it has to truncate"),
                               row(6, nil),
                               row(1, "Downloads")]),
            onGrantAccess: {}), truncates: true)

        // #109: the error channel — a badge on the cog (the worst severity), and the list its
        // hover opens. Warnings only on the rail, so the story shows the triangle; the card mixes.
        add("rail-problems", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 2, pids: [5, 3], active: true),
                         railItem(1, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta, send: send,
            problems: [.screenRecordingMissing]))
        let problems: [Problem] = [
            .configInvalid("unknown key \"gapp\" on line 12"),
            .screenRecordingMissing,
            .axWriteFailing(app: "us.zoom.xos"),
            .telemetryFailing(host: "otel.example.com"),
        ]
        add("rail-problems-open", nil, RailHoverCard(
            title: "\(problems.count) problems", subtitle: "Each clears itself once it is fixed",
            content: .problems(problems), onGrantAccess: {}))

        // #130 (M3 B7): the first-launch grant wait — a window, not a silent hang — fresh, and
        // once a stale TCC row is the likelier story.
        add("grant-wait", nil, GrantWaitView(wait: GrantWait(elapsed: .seconds(4)), openSettings: {}, quit: {}))
        add("grant-wait-stale", nil, GrantWaitView(wait: GrantWait(elapsed: .seconds(47)), openSettings: {}, quit: {}))
        // …and the alert a failed hotkey tap opens, with the socket's queued behind it.
        add("problem-alert", nil, ProblemAlertView(
            problem: .hotkeysInactive("the event tap could not be created"), queued: 1, dismiss: { _ in }))
        // #138: another window manager is running — a warning the user may keep, so it offers
        // "Don't warn again".
        add("problem-alert-other-wm", nil, ProblemAlertView(
            problem: .otherWindowManager(entry: "com.knollsoft.Rectangle", name: "Rectangle"), queued: 0,
            dismiss: { _ in }))

        // panel-color / panel-opacity actually reaching the panels. These existed as config keys,
        // as persisted values and as settings-window controls while nothing read them, so the
        // point of these two stories is that a tinted panel is *visibly* tinted.
        add("rail-tinted", railGeometry, ScreenPanelView(
            state: rail([railItem(0, name: "Code", symbol: "terminal", count: 2, pids: [5, 3], active: true),
                         railItem(1, name: "Workspace", symbol: "square.grid.2x2", count: 0, trailing: true)]),
            launcherURL: "raycast://", metaFor: meta,
            chrome: PanelChrome(color: "#9D0B7F", opacity: 0.9), send: send))
        add("bar-tinted", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true), tab(3)]), metaFor: meta, sizing: .fit,
            chrome: PanelChrome(color: "#9D0B7F", opacity: 0.9), send: send))

        // Tab bar
        add("bar-one-tab", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true)], layout: .maximize), metaFor: meta, sizing: .fit, send: send))
        add("bar-five-tabs", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true), tab(2), tab(3), tab(4), tab(6)]), metaFor: meta, sizing: .fit, send: send))
        add("bar-long-names", barGeometry, WorkspacePanelView(
            state: tabs([tab(5, focused: true), tab(5), tab(5), tab(5)]), metaFor: meta, sizing: .fit, send: send), truncates: true)
        // #110: window titles. Two Terminal windows told apart by title; Notes has no title yet and
        // shows its app name, as every tab did before the feed.
        add("bar-titles", barGeometry, WorkspacePanelView(
            state: tabs([tab(3, focused: true, title: "~/code/spacial-shell — zsh"),
                         tab(3, window: 1, title: "~/Downloads — zsh"),
                         tab(1, title: "Pull requests · AskAlice/SpacialShell-MacOS"), tab(2)]),
            metaFor: meta, sizing: .fit, send: send))
        // #116: the same row as `bar-titles` in the other two tab styles.
        for style in [TabStyle.name, .icon] {
            add("bar-style-\(style.rawValue)", barGeometry, WorkspacePanelView(
                state: tabs([tab(3, focused: true, title: "~/code/spacial-shell — zsh"),
                             tab(3, window: 1, title: "~/Downloads — zsh"),
                             tab(1, title: "Pull requests · AskAlice/SpacialShell-MacOS"), tab(2)]),
                metaFor: meta, sizing: .fit, style: style, send: send))
        }
        // #126: the app's tabs carry the mark too — on the icon's corner, or beside the title in
        // the `name` style, which has no icon.
        let attentionRow = [tab(3, focused: true, title: "~/code/spacial-shell — zsh"),
                            tab(4, title: "Inbox — 3 unread", attention: true),
                            tab(4, window: 1, title: "Re: the quarterly numbers", attention: true), tab(2)]
        add("bar-attention", barGeometry, WorkspacePanelView(
            state: tabs(attentionRow), metaFor: meta, sizing: .fit, send: send))
        add("bar-attention-name", barGeometry, WorkspacePanelView(
            state: tabs(attentionRow), metaFor: meta, sizing: .fit, style: .name, send: send))
        // A title longer than the 220 pt tab ceiling keeps its beginning and ends in "…" (#175).
        add("bar-long-title", barGeometry, WorkspacePanelView(
            state: tabs([tab(4, focused: true,
                             title: "Re: Quarterly planning — the long thread everyone was copied on (37 messages)"),
                         tab(1, title: "developer.apple.com/documentation/applicationservices/axuielement_h/1462085-axuielementcopyattributevalue"),
                         tab(3, title: "zsh")]),
            metaFor: meta, sizing: .fit, send: send), truncates: true)
        // #180: an unfocused tab under the pointer shows its close button over the end of its
        // title; every tab keeps its width.
        let hoverRow = [tab(3, focused: true, title: "~/code/spacial-shell — zsh"),
                        tab(4, title: "Inbox — 3 unread"), tab(2)]
        add("bar-hover-close", barGeometry, WorkspacePanelView(
            state: tabs(hoverRow), metaFor: meta, sizing: .fit, send: send,
            hoverPreview: hoverRow[1].ref))
        // #180: the pointer on the focused tab's × lights it, like any other button.
        add("bar-close-hover-focused", barGeometry, WorkspacePanelView(
            state: tabs(hoverRow), metaFor: meta, sizing: .fit, send: send,
            closeHoverPreview: hoverRow[0].ref))
        add("bar-floating-hidden", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true), tab(2, floating: true), tab(3, hidden: true), tab(4)]),
            metaFor: meta, sizing: .fit, send: send))
        add("bar-fullscreen", barGeometry, WorkspacePanelView(
            state: tabs([tab(3, focused: true), tab(1, fullscreen: true), tab(4)]),
            metaFor: meta, sizing: .fit, send: send))
        // #128: placeholders — saved windows whose apps have not brought them back — among live
        // tabs: dashed and dimmed, with the saved title or (none saved) the app's name. Beside a
        // minimized tab, the state it must not be mistaken for.
        add("bar-placeholders", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true, title: "Pull requests · AskAlice/SpacialShell-MacOS"),
                         placeholder(3, title: "~/code/spacial-shell — zsh"),
                         tab(2, hidden: true, title: "Groceries"),
                         placeholder(4, title: "Re: Quarterly planning"),
                         placeholder(6)]),
            metaFor: meta, sizing: .fit, send: send))
        // #129: pinned tabs — a live one (focused), a pinned placeholder whose window closed, and
        // an unpinned floating tab beside them, whose pin glyph the pinned marker must not read as.
        add("bar-pinned", barGeometry, WorkspacePanelView(
            state: tabs([tab(3, focused: true, title: "~/code/spacial-shell — zsh", pinned: true),
                         placeholder(4, title: "Inbox", pinned: true),
                         tab(1, title: "Pull requests · AskAlice/SpacialShell-MacOS"),
                         tab(2, floating: true, title: "Groceries")]),
            metaFor: meta, sizing: .fit, send: send))
        // #55: on another Space, beside the two states it must not be mistaken for.
        add("bar-off-space", barGeometry, WorkspacePanelView(
            state: tabs([tab(3, focused: true), tab(1, offSpace: true), tab(2, hidden: true), tab(4, fullscreen: true)]),
            metaFor: meta, sizing: .fit, send: send))
        // Tab overflow (#14), at 800 pt: the tab row gets 628 pt, and each tab at its 88 pt floor
        // costs 91 with spacing (+16 for the focused tab's close button, +8 end-of-row gap). Six tabs
        // (570) squeeze toward the floor and still fit; seven (661) are past it and the row scrolls;
        // twenty scroll to keep the focused tab in view.
        func row(_ n: Int, focus: Int) -> ScreenShellState {
            tabs((1...n).map { tab(Int32(($0 % 6) + 1), window: $0, focused: $0 == focus) }, layout: .column)
        }
        let narrowBar = CGSize(width: 800, height: 34)
        add("bar-six-tabs-at-floor", narrowBar, WorkspacePanelView(
            state: row(6, focus: 1), metaFor: meta, sizing: .fit, send: send))
        add("bar-seven-tabs-scrolls", narrowBar, WorkspacePanelView(
            state: row(7, focus: 1), metaFor: meta, sizing: .fit, send: send))
        add("bar-twenty-tabs", narrowBar, WorkspacePanelView(
            state: row(20, focus: 1), metaFor: meta, sizing: .fit, send: send))
        add("bar-twenty-tabs-focus-last", narrowBar, WorkspacePanelView(
            state: row(20, focus: 20), metaFor: meta, sizing: .fit, send: send))

        // Layouts (#10). The bar: the set, plus the active layout from outside it, then ⋯ and the cog.
        add("bar-layouts-custom", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true), tab(3)], layout: "focus-c", layouts: customLayouts(bar: ["code-3"])),
            metaFor: meta, sizing: .fit, send: send))
        // Design §8: the workspace holds a deleted layout; the fallback is highlighted and badged.
        add("bar-layout-missing", barGeometry, WorkspacePanelView(
            state: tabs([tab(1, focused: true)], layout: "code-3"), metaFor: meta, sizing: .fit, send: send))
        // The cog's popover: every layout by name, the current one checked, Show-on-bar switches.
        add("layout-popover", nil, LayoutPopoverView(
            state: tabs([tab(1, focused: true)], layout: .maximize, layouts: customLayouts()), send: send))
        // The ⋯ menu — the real NSMenu the bar pops up, drawn item by item (a menu cannot be
        // snapshotted closed, and an open one is a separate process's window).
        add("layout-menu", nil, MenuPreview(menu: LayoutMenu.make(
            tabs([tab(1, focused: true)], layout: "code-3", layouts: customLayouts(bar: ["code-3"])),
            send: send, editLayouts: {})))
        // #111: the rail's app menu (no clock, #24 P4). #112: a tile's right-click menu, and its
        // "Set category" and "Set symbol" submenus — a row routing made for web, checked.
        add("rail-app-menu", nil, MenuPreview(menu: RailMenu.app(send: send)))
        let webRow = WorkspaceRailItem(id: UUID(), index: 0, name: "Workspace", symbol: "globe", windowCount: 2,
                                       windows: [], isActive: true, isPinned: false, isTrailingEmpty: false,
                                       category: .web, layout: .split)
        let workspaceMenu = RailMenu.workspace(webRow, layouts: tabs([]).layouts,
                                               categories: Config.defaultCategoryOrder, send: send)
        add("rail-workspace-menu", nil, MenuPreview(menu: workspaceMenu))
        add("rail-workspace-menu-category", nil, MenuPreview(menu: workspaceMenu.items[0].submenu!))
        add("rail-workspace-menu-symbol", nil, MenuPreview(menu: workspaceMenu.items[1].submenu!))
        add("rail-workspace-menu-layout", nil, MenuPreview(menu: workspaceMenu.items[2].submenu!))
        // #127: a tab's right-click menu (a floating tab, so "Tile"), and "Move to workspace":
        // every other row on the display, by category or name, then "+" as "New workspace".
        let tabMenu = RailMenu.tab(tab(3, floating: true), rail: [
            railItem(0, name: "Workspace", symbol: "globe", count: 2, active: true),
            WorkspaceRailItem(id: UUID(), index: 1, name: "Workspace", symbol: "terminal", windowCount: 1,
                              isActive: false, isPinned: false, isTrailingEmpty: false, category: .terminal),
            railItem(2, name: "Workspace", symbol: "square.grid.2x2", count: 1),
            railItem(3, name: "Workspace", symbol: "plus", count: 0, trailing: true),
        ], metaFor: meta, send: send)
        add("tab-menu", nil, MenuPreview(menu: tabMenu))
        add("tab-menu-move", nil, MenuPreview(menu: submenu(tabMenu, "Move to workspace")))
        // #129: a pinned placeholder's menu — Unpin, and Close disabled until it is unpinned.
        add("tab-menu-pinned-placeholder", nil, MenuPreview(menu: RailMenu.tab(placeholder(3, title: "~/code — zsh", pinned: true), rail: [
            railItem(0, name: "Workspace", symbol: "globe", count: 2, active: true),
            railItem(1, name: "Workspace", symbol: "plus", count: 0, trailing: true),
        ], metaFor: meta, send: send)))
        // #128: a placeholder's menu leads with Open; it has no window to float.
        add("tab-menu-placeholder", nil, MenuPreview(menu: RailMenu.tab(placeholder(3, title: "~/code — zsh"), rail: [
            railItem(0, name: "Workspace", symbol: "globe", count: 2, active: true),
            railItem(1, name: "Workspace", symbol: "plus", count: 0, trailing: true),
        ], metaFor: meta, send: send)))
        // The editor, at the walkthrough's step 6; an existing drawn layout (Delete); a built-in
        // (read-only, Duplicate to edit).
        add("layout-editor", LayoutEditorView.size, LayoutEditorView(mode: .edit(codeThree)))
        add("layout-editor-existing", LayoutEditorView.size, LayoutEditorView(
            mode: .edit(GridEditor(editing: customLayouts()["code-3"]!)!),
            removal: .delete(warning: GridEditor.deleteWarning(usage: 3, fallback: .maximize)), taken: ["code-3"]))
        add("layout-editor-builtin", LayoutEditorView.size, LayoutEditorView(
            mode: .readOnly(LayoutDef.builtins[1], canDuplicate: true)))

        // Overview
        let windows = [
            // #110: cells show the window title; Notes has none and falls back to its app name.
            OverviewWindowItem(ref: WindowRef(id: 10, pid: 1), name: "Start Page", app: "Safari", detail: "Web",
                               icon: swatch(.systemBlue)),
            OverviewWindowItem(ref: WindowRef(id: 20, pid: 2), name: "Notes", app: "Notes", detail: "Web",
                               icon: swatch(.systemYellow)),
            OverviewWindowItem(ref: WindowRef(id: 30, pid: 3), name: "~/code/spacial-shell — zsh", app: "Terminal",
                               detail: "Code", icon: swatch(.systemGray)),
            OverviewWindowItem(ref: WindowRef(id: 40, pid: 5),
                               name: "A Very Long Application Name That Must Truncate",
                               app: "A Very Long Application Name That Must Truncate",
                               detail: "a workspace with a very long name", icon: swatch(.systemPink)),
        ]
        let apps = ["Mail", "Files", "Music", "Calendar", "Photos",
                    "A Very Long Application Name That Must Truncate"].enumerated().map { i, n in
            OverviewAppItem(url: URL(fileURLWithPath: "/Applications/\(n).app"), name: n,
                            icon: swatch([.systemTeal, .systemGreen, .systemOrange, .systemRed, .systemPurple, .systemBrown][i]))
        }
        add("overview-results", CGSize(width: 640, height: 440),
            OverviewView(windows: windows, apps: apps, onSelectWindow: { _ in }, onLaunchApp: { _ in }),
            awaitsFocus: true)
        // #189: once the captures have landed — each window's picture fitted into its frame, the
        // app icon on the corner. Notes is still the icon: its capture is pending or failed. The
        // long-named window is portrait, so it is letterboxed sideways; the apps stay icons.
        add("overview-thumbnails", CGSize(width: 640, height: 440),
            OverviewView(windows: windows, apps: apps, thumbnails: [
                windows[0].ref: windowShot(aspect: 1.6, (0xF5F5F7, 0xDCDCE0, 0x8E8E93)),    // a web page
                windows[2].ref: windowShot(aspect: 1.4, (0x101010, 0x2A2A2A, 0x3FC56B)),    // a terminal
                windows[3].ref: windowShot(aspect: 0.75, (0x1E1F24, 0x2B2D33, 0x6C9EF8)),   // an editor
            ], onSelectWindow: { _ in }, onLaunchApp: { _ in }),
            awaitsFocus: true)
        add("overview-empty", CGSize(width: 640, height: 440),
            OverviewView(windows: [], apps: [], onSelectWindow: { _ in }, onLaunchApp: { _ in }),
            awaitsFocus: true)

        // Cheat sheet (fitting size — the panel sizes itself)
        add("cheatsheet-fn", nil,
            CheatSheetView(groups: CheatSheetController.grouped(CheatSheet.rows(for: Config()))))
        var ctrlAlt = Config(); ctrlAlt.keybindingPreset = .ctrlAlt
        add("cheatsheet-ctrl-alt", nil,
            CheatSheetView(groups: CheatSheetController.grouped(CheatSheet.rows(for: ctrlAlt))))
        // #29: the passive background behind an empty workspace — same sheet, dimmed.
        add("cheatsheet-empty-workspace", nil,
            CheatSheetView(groups: CheatSheetController.grouped(CheatSheet.rows(for: Config())), dimmed: true))
        // #87: fitted to a 1024 pt display. The sheets above are wider than that; these wrap to fit
        // — the Fn sheet the whole width, the empty-workspace one the area beside the 48 pt rail.
        // Fitting size, as the panel sizes itself; `cheatSheetWrapsToFitItsArea` checks the width.
        add("cheatsheet-fn-1024", nil,
            CheatSheetView.fitting(CheatSheetController.grouped(CheatSheet.rows(for: Config())), in: 1024).view)
        add("cheatsheet-empty-workspace-1024", nil,
            CheatSheetView.fitting(CheatSheetController.grouped(CheatSheet.rows(for: Config())),
                                   dimmed: true, in: 1024 - 48).view)

        // #132 (M3 B9): the spatialisation view on a 1440 × 900 display — the model's rows as
        // mini-desktops, the active one centred. Web (split, two Safari windows), Code (half, the
        // active row, a Terminal focused), Chat (maximize, Mail floating beside it), Notes (grid),
        // then the trailing "+". Chips are titled where they have room.
        add("spatial-view", CGSize(width: 1440, height: 900),
            SpatialStripView(state: spatial(active: 1), metaFor: meta, send: send, reduceMotion: true),
            truncates: true)
        // The first row active: the camera at the top of the stack, nothing above it.
        add("spatial-view-top", CGSize(width: 1440, height: 900),
            SpatialStripView(state: spatial(active: 0), metaFor: meta, send: send, reduceMotion: true),
            truncates: true)
        // #181: the same view once some captures have landed. Pictured: the first Safari, the
        // editor, the focused terminal, #general and two notes. Still the icon and title: the
        // second Safari, the other terminal and the middle note, whose captures are pending or
        // failed. The aside's Mail stays an icon.
        let pictured = spatial(active: 1)
        add("spatial-view-thumbnails", CGSize(width: 1440, height: 900),
            SpatialStripView(state: pictured, metaFor: meta, send: send,
                             thumbnails: spatialThumbnails(pictured, [
                                 1: (0xF5F5F7, 0xDCDCE0, 0x8E8E93),     // a web page
                                 3: (0x1E1F24, 0x2B2D33, 0x6C9EF8),     // an editor
                                 4: (0x101010, 0x2A2A2A, 0x3FC56B),     // a terminal
                                 6: (0x36393F, 0x2F3136, 0xB9BBBE),     // a chat
                                 8: (0xFFF8DC, 0xF2E6A6, 0xA08C3C),     // a note
                                 10: (0xFFF8DC, 0xF2E6A6, 0xA08C3C),
                             ]),
                             reduceMotion: true),
            truncates: true)

        // #188: Fn+` in Safari, four windows over two workspaces. The focused one first, then the
        // one used before it (on Code), then the rest; the selection on the second, as a tap and
        // release would land. The last window's capture is pending: its app's icon stands in.
        add("app-window-switcher", nil, AppWindowSwitcherView(
            state: appWindowSwitcher(), appName: "Safari", appIcon: meta(1).icon,
            thumbnails: [WindowRef(id: 1, pid: 1): shot(.systemBlue), WindowRef(id: 3, pid: 1): shot(.systemIndigo),
                         WindowRef(id: 2, pid: 1): shot(.systemTeal)],
            columns: 4, reduceMotion: true), truncates: true)

        // #108: the tile a dragged window would swap with, at a half-split tile's size.
        add("drop-target", CGSize(width: 480, height: 320), DropTargetView())

        // The settings window's General pane, with #138's silenced warnings and the way back, and
        // #139's persistence switch and reset.
        var silenced = SettingsOverrides()
        silenced.silence("other-wm:com.knollsoft.Rectangle")
        silenced.silence("other-wm:yabai")
        add("settings-general", nil, SettingsView(
            file: Config(), overrides: .constant(silenced), configPath: "~/.config/spacial-shell/config.toml",
            openConfigFile: {}, checkForUpdates: nil, resetState: {}, standalone: .general))

        return out
    }
}
