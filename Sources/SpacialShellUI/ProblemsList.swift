import SwiftUI
import SpacialShellKit

/// #109: the rail cog's hover list — one row per current problem, errors first. Read-only: every
/// entry clears itself once its condition is fixed, so there is nothing to dismiss.
struct ProblemsList: View {
    let problems: [Problem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(problems) { p in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: Self.symbol(p.severity))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                    Text(p.message)
                        .font(.system(size: 11))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Multicolor SF Symbols, the design system's badge treatment: no palette of our own.
    static func symbol(_ severity: Problem.Severity) -> String {
        severity == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"
    }
}
