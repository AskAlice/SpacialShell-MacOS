import Foundation

/// Every path and identifier the app is pinned to. `bundleID` is also the TCC identity for the
/// bundled app; the loose debug binary is identified by its *path* instead — see `Scripts/README`.
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let configDir = home.appendingPathComponent(".config/spacial-shell", isDirectory: true)
    static let configFile = configDir.appendingPathComponent("config.toml")
    static let stateDir = home.appendingPathComponent("Library/Application Support/SpacialShell", isDirectory: true)
    static let stateFile = stateDir.appendingPathComponent("state.json")
    static let bundleID = "me.askalice.SpacialShell"
}
