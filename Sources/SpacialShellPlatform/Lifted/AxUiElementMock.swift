// Adapted from AeroSpace (MIT) — Sources/AppBundle/util/AxUiElementMock.swift @ c548c7f
import AppKit

/// Alternative name: AttrAddressibleStorage
protocol AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T?
    func containingWindowId() -> CGWindowID?
}

extension AxUiElementMock {
    var cast: AXUIElement { self as! AXUIElement }
}
