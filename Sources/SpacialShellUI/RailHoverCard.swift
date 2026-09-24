import AppKit
import SwiftUI
import SpacialShellKit
import SpacialShellProtocol

/// What the rail shows when you hover a workspace tile: the detail a 48 pt rail has no room for.
///
/// The tile can only say "four apps, six windows". The card says *which* windows, as live
/// miniatures in row order — the same order the tab bar draws them — so a workspace is
/// recognisable by what is in it rather than by remembering what you put there.
///
/// Pure props in, closures out, like every other view here: the capture happens in
/// `RailHoverController`, and this draws whatever it was handed, including nothing.
struct RailHoverCard: View {
    /// The three things a hovered tile can have to say. `needsScreenRecording` is not an error
    /// state bolted on — without the grant every capture returns wallpaper, so it is the *normal*
    /// state until someone grants and restarts, and it has to explain itself rather than draw six
    /// grey rectangles.
    enum Content {
        case previews([WindowPreviewItem])
        case message(String)
        case needsScreenRecording
    }

    let title: String
    let subtitle: String?
    let content: Content
    let onGrantAccess: () -> Void
    /// The pointer crossing the gap from tile to card must not dismiss the card, or the
    /// "Open Screen Recording settings…" button could never be clicked.
    var onHoverCard: (Bool) -> Void = { _ in }
    /// A preview was clicked. The controller turns it into `.focusWindowRef`, the same command a
    /// tab click sends, so the store switches workspace and focuses the tab (#51).
    var onSelect: (SpacialShellProtocol.WindowRef) -> Void = { _ in }

    /// Past six the card stops being a glance and starts being a window list; the count on the
    /// tile already carries "a lot".
    // ponytail: fixed cap, not a scroller — revisit if 6+ window workspaces turn out to be normal.
    static let maxPreviews = 6
    static let width: CGFloat = 324

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            body(for: content)
        }
        .padding(10)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.separator.opacity(0.6)))
        .onHover { onHoverCard($0) }
    }

    @ViewBuilder
    private func body(for content: Content) -> some View {
        switch content {
        case .message(let text):
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .needsScreenRecording:
            VStack(alignment: .leading, spacing: 8) {
                Label("Previews need Screen Recording", systemImage: "lock.display")
                    .font(.system(size: 12, weight: .medium))
                Text("macOS shows window contents only to apps with that permission. "
                     + "Grant it, then restart SpacialShell — the grant takes effect on the next launch.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Screen Recording settings…", action: onGrantAccess)
                    .controlSize(.small)
            }
        case .previews(let items):
            let shown = Array(items.prefix(Self.maxPreviews))
            VStack(alignment: .leading, spacing: 6) {
                if shown.count == 1, let only = shown.first {
                    tile(only, width: 304, height: 190)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(148), spacing: 8), count: 2),
                              spacing: 6) {
                        ForEach(shown) { tile($0, width: 148, height: 92) }
                    }
                }
                if items.count > shown.count {
                    Text("+\(items.count - shown.count) more")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The miniature, with the app's name under it. Before the capture lands (and for a window
    /// ScreenCaptureKit declines) the frame holds the app icon instead of a blank — a placeholder
    /// that still says which window this is.
    private func tile(_ item: WindowPreviewItem, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.6))
                if let image = item.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else if let icon = item.icon {
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24).opacity(0.5)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            HStack(spacing: 4) {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                }
                Text(item.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(item.ref) }
    }
}
