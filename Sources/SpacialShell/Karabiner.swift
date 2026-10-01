import AppKit
import SpacialShellKit

/// #196: the Karabiner-Elements bridge's file IO; the rules themselves are `KarabinerRules` (Kit).
/// Writes only Karabiner's import file, and only when asked (the settings button,
/// `spacialctl karabiner-rules --write`) or when it already exists. Never karabiner.json.
enum Karabiner {
    static let app = URL(fileURLWithPath: "/Applications/Karabiner-Elements.app")
    static let rulesFile = Paths.home.appendingPathComponent(KarabinerRules.relativePath)
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: app.path) }
    static var rulesExist: Bool { FileManager.default.fileExists(atPath: rulesFile.path) }

    /// The `spacialctl` beside this executable: Contents/MacOS in the bundle, `.build/<config>` loose.
    static var spacialctl: String {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("spacialctl").path
    }

    static func rules(for config: Config) -> Data {
        KarabinerRules.export(table: KeyBindings.table(for: config), spacialctlPath: spacialctl)
    }

    /// Returns whether the file changed: the same bytes are not written again.
    @discardableResult
    static func write(for config: Config) throws -> Bool {
        let data = rules(for: config)
        if (try? Data(contentsOf: rulesFile)) == data { return false }
        try FileManager.default.createDirectory(at: rulesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: rulesFile, options: .atomic)
        return true
    }

    static func open() { NSWorkspace.shared.open(app) }

    static let enableHint = "Now enable it in Karabiner-Elements → Settings → Complex Modifications → Add predefined rule → SpacialShell."
}
