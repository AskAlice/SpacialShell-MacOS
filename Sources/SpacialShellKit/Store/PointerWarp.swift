import CoreGraphics

/// #107 (G22): whether the pointer follows a command's focus change, and where to.
enum PointerWarp {
    /// The point to warp to after `command` moved focus off `from`, or nil for no warp.
    ///
    /// Only named commands warp — the ones a key or `spacialctl run` can issue. The by-reference
    /// ones (`focusWindowRef`, `focusWorkspaceID`, drops) come from a click, and a click already
    /// has the pointer where the user wants it. Native focus reports never reach here at all.
    static func target(after command: Command, from: DisplayID, world: World,
                       frames: [WindowRef: CGRect], displays: [DisplayInfo], pointer: CGPoint?) -> CGPoint? {
        guard world.focus.screen != from, KeyBindings.name(of: command) != nil,
              let display = displays.first(where: { $0.id == world.focus.screen }) else { return nil }
        let rect = world.focus.window.flatMap { frames[$0] } ?? display.frame
        if let pointer, rect.contains(pointer) { return nil }
        return CGPoint(x: rect.midX, y: rect.midY)
    }
}
