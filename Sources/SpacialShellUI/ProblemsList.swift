import SwiftUI
import SpacialShellKit

/// #109: the rail cog's hover list — one row per current problem, errors first. Every entry clears
/// itself once its condition is fixed, so there is nothing to dismiss. #192: an entry the shell can
/// act on (`Problem.action`) carries a button that sends its command.
struct ProblemsList: View {
    let problems: [Problem]
    var onAction: (Command) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(problems) { p in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: Self.symbol(p.severity))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.message)
                            .font(.system(size: 11))
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                        if let action = p.action {
                            Button(action.title) { onAction(action.command) }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    /// Multicolor SF Symbols, the design system's badge treatment: no palette of our own.
    static func symbol(_ severity: Problem.Severity) -> String {
        severity == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"
    }
}
