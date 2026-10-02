import AppKit
import Testing
@testable import SpacialShellUI

/// #206: Shift (or #98's Option) held on a tab drop moves the window's whole app.
@Suite struct WholeAppDropTests {
    @Test func shiftOrOptionMeansTheWholeApp() {
        #expect(WholeAppDrop.held([.shift]))
        #expect(WholeAppDrop.held([.option]))
        #expect(WholeAppDrop.held([.shift, .command]))
        #expect(!WholeAppDrop.held([]))
        #expect(!WholeAppDrop.held([.command]))
    }
}
