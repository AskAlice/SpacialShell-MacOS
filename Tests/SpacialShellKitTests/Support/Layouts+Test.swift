import Foundation
@testable import SpacialShellKit

/// #177: the tests' short forms for the values that read a layout catalogue. The `.builtins`
/// default lives here, in the test target, and nowhere in the Kit (as #171 did for
/// `CommandEnvironment.test`): production code has to say which catalogue it draws with. A test
/// that cares about user layouts passes `layouts:`.
extension LayoutConfig {
    static func test(gap: CGFloat, screenGap: CGFloat? = nil, layouts: LayoutCatalogue = .builtins) -> LayoutConfig {
        LayoutConfig(gap: gap, screenGap: screenGap, layouts: layouts)
    }
}

extension ShellUI {
    static func testState(for display: DisplayID, in world: World, layouts: LayoutCatalogue = .builtins,
                          titles: [WindowRef: String] = [:], attention: Set<Int32> = []) -> ScreenShellState? {
        state(for: display, in: world, layouts: layouts, titles: titles, attention: attention)
    }
}

extension WireState {
    static func test(world: World, bundleIDs: [WindowRef: String] = [:], parked: Set<WindowRef> = [],
                     observed: [WindowRef: CGRect] = [:], layouts: LayoutCatalogue = .builtins,
                     problems: [Problem] = []) -> WireState {
        WireState(world: world, bundleIDs: bundleIDs, parked: parked, observed: observed, layouts: layouts, problems: problems)
    }
}
