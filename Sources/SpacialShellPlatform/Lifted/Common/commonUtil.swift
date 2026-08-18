// Adapted from AeroSpace (MIT) — Sources/Common/util/commonUtil.swift @ c548c7f
import AppKit
import Darwin
import Foundation

public func bugPrompt(
    _ __message: String = "",
    isDie: Bool = false,
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> String {
    """
    SpacialShell internal error at \(file):\(line): \(__message)
    Please report at https://github.com/AskAlice/alice-material/issues
    """
}

public func dieT<T>(
    _ __message: String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> T {
    let message = bugPrompt(__message, isDie: true, file: file, line: line, column: column, function: function)
    fatalError("\n" + message)
}

// periphery:ignore
public func throwT<T, E: Error>(_ error: E) throws(E) -> T { throw error }

public func getStringStacktrace() -> String { Thread.callStackSymbols.joined(separator: "\n") }

@inlinable public func die(
    _ message: String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> Never {
    dieT(message, file: file, line: line, column: column, function: function)
}

public func check(
    _ condition: Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) {
    if !condition {
        die(message(), file: file, line: line, column: column, function: function)
    }
}

public var isUnitTest: Bool { NSClassFromString("XCTestCase") != nil }

extension CaseIterable where Self: RawRepresentable, RawValue == String {
    public static var cliArgsCases: [String] { allCases.map(\.rawValue) }
    public static var unionLiteral: String { cliArgsCases.joinedCliArgs }
}

extension [String] {
    public var joinedCliArgs: String { "(" + self.joined(separator: "|") + ")" }
}

extension Int {
    public func toDouble() -> Double { Double(self) }
}

public func + <K, V>(lhs: [K: V], rhs: [K: V]) -> [K: V] {
    lhs.merging(rhs) { _, r in r }
}

extension String {
    public func removePrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    public func prependLines(_ prefix: String) -> String {
        split(separator: "\n").map { prefix + $0 }.joined(separator: "\n")
    }
}

extension Bool {
    /// Implication
    /// | a     | b     | a.implies(b) |
    /// |-------|-------|--------------|
    /// | false | false | true         |
    /// | false | true  | true         |
    /// | true  | false | false        |
    /// | true  | true  | true         |
    public func implies(_ mustHold: @autoclosure () -> Bool) -> Bool { !self || mustHold() }
}

extension URL {
    public func open(with url: URL) {
        NSWorkspace.shared.open([self], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// 'id' stands for 'identity'. It's a common name in functional programming
public func id<T>(_ t: T) -> T { t }

@inlinable public func zipIfCountsAreEqual<C1, C2>(_ c1: C1, _ c2: C2) -> Zip2Sequence<C1, C2>? where C1: Collection, C2: Collection {
    switch c1.count == c2.count {
        case true: zip(c1, c2)
        case false: nil
    }
}
