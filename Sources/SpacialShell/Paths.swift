import Foundation

/// Every path and identifier the app is pinned to. `bundleID` is also the TCC identity for the
/// bundled app; the loose debug binary is identified by its *path* instead — see `Scripts/README`.
enum Paths {
    /// **Sandbox-critical, and deliberately this accessor** (#19). Under the App Sandbox macOS
    /// redirects `homeDirectoryForCurrentUser` to the app's container, so every path below follows
    /// the container in a sandboxed build and stays exactly where it is today in an unsandboxed
    /// one — one code path, no `isSandboxed` check. Probed on macOS 26.5; the table is in
    /// `Scripts/README`. Do not "fix" this to `getpwuid`, which is the one accessor that reports
    /// the *real* home under the sandbox and would therefore point at a directory the app cannot
    /// read.
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let configDir = home.appendingPathComponent(".config/spacial-shell", isDirectory: true)
    static let configFile = configDir.appendingPathComponent("config.toml")
    static let stateDir = home.appendingPathComponent("Library/Application Support/SpacialShell", isDirectory: true)
    static let stateFile = stateDir.appendingPathComponent("state.json")
    /// What the settings window has set. App-owned and app-written, unlike `configFile`, which
    /// belongs to the user and is only ever read — see `Settings`.
    static let settingsFile = stateDir.appendingPathComponent("settings.json")
    static let bundleID = "sh.emu.SpacialShell"
}
