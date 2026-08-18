// Adapted from AeroSpace (MIT) — Sources/Common/util/StringEx.swift @ c548c7f
// Trimmed to the self-contained String helpers used by the lifted AX code.
import Foundation

extension String {
    public func trim() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func prefixLines(with: String) -> String {
        split(separator: "\n", omittingEmptySubsequences: false).map { with + $0 }.joined(separator: "\n")
    }

    public var singleQuoted: String { "'" + self + "'" }
    public var doubleQuoted: String { "\"" + self + "\"" }
}
