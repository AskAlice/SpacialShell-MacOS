import Foundation

/// #171: everything a command reads besides the world. The store builds one from its config,
/// displays and layouts, and `CommandRunner` passes it unchanged into every command and every
/// command one hands off to. There are no defaults anywhere on the way: a call that leaves part of
/// it out does not compile (#166 was five calls that did, silently).
///
/// A command that starts reading another config value adds it here and to `init(config:…)`, and
/// nothing else changes: not the store, not the recursions, not the tests.
public struct CommandEnvironment: Sendable, Equatable {
    /// #9: the layout ids' meaning, what `cycleLayout` rings through and how many windows a layout shows.
    public let layouts: LayoutCatalogue
    /// #118: the real display frames the directional display commands resolve against; with none,
    /// those commands are no-ops.
    public let displays: [DisplayInfo]
    /// #120: `workspace-wrap`.
    public let workspaceWrap: Bool
    /// #136: `category-order`, where a workspace moved to another display lands.
    public let categoryOrder: [AppCategory]

    public init(layouts: LayoutCatalogue, displays: [DisplayInfo], workspaceWrap: Bool, categoryOrder: [AppCategory]) {
        self.layouts = layouts; self.displays = displays
        self.workspaceWrap = workspaceWrap; self.categoryOrder = categoryOrder
    }

    /// The store's: `layouts` is passed in, not rebuilt, because the store already holds the
    /// catalogue it built from this same config.
    public init(config: Config, layouts: LayoutCatalogue, displays: [DisplayInfo]) {
        self.init(layouts: layouts, displays: displays, workspaceWrap: config.workspaceWrap,
                  categoryOrder: config.categoryOrder)
    }
}
