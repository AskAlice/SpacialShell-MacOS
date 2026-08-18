// Adapted from AeroSpace (MIT) — Sources/Common/util/ComparableEx.swift @ c548c7f
import AppKit

extension Comparable {
    public func until(incl bound: Self) -> ClosedRange<Self>? { self <= bound ? self ... bound : nil }
    public func until(excl bound: Self) -> Range<Self>? { self < bound ? self ..< bound : nil }
}
