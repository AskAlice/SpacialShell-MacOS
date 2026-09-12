// Adapted from AeroSpace (MIT) — Sources/AppBundle/util/AxUiElementMock.swift @ c548c7f
import SpacialShellProtocol
import AppKit

/// Alternative name: AttrAddressibleStorage
protocol AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T?
    /// This element's window identity, or nil when it is not a live window.
    ///
    /// Was `containingWindowId()`, backed by `_AXUIElementGetWindow`. It is deliberately not named
    /// for `CGWindowID` any more: the value is minted by `WindowIdentities` and is not a
    /// window-server handle. Nil still means the same two things it always did — "not a window"
    /// (Finder's desktop) and "no longer alive" — which is what the callers actually test.
    func windowIdentity() -> WindowID?
}

extension AxUiElementMock {
    var cast: AXUIElement { self as! AXUIElement }
}
