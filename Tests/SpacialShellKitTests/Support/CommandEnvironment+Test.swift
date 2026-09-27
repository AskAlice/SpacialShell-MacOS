import Foundation
@testable import SpacialShellKit

/// #171: the tests' one way to build a `CommandEnvironment`. The defaults live here, in the test
/// target, and nowhere in the Kit: production code has to say what it passes.
extension CommandEnvironment {
    static func test(layouts: LayoutCatalogue = .builtins, displays: [DisplayInfo] = [], workspaceWrap: Bool = false,
                     categoryOrder: [AppCategory] = []) -> CommandEnvironment {
        CommandEnvironment(layouts: layouts, displays: displays, workspaceWrap: workspaceWrap, categoryOrder: categoryOrder)
    }
}

/// #171: test-only. `run` without the report, as a pair to destructure. The environment is still
/// required: a test says which one, even when it is just `.test()`.
extension CommandRunner {
    static func apply(_ command: Command, to world: World, in env: CommandEnvironment) -> (World, [Effect]) {
        let o = run(command, on: world, in: env)
        return (o.world, o.effects)
    }
}
