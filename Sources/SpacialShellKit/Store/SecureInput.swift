import Foundation

/// #193: while any app holds Secure Event Input, macOS delivers no key-down to any event tap, so
/// every hotkey is dead and nothing says why. macOS names no culprit: the session dictionary's
/// `kCGSSessionSecureInputPID` follows the frontmost app, not the one that turned it on. So the
/// platform looks for a window asking for a password, and this turns what it saw into Problems.
///
/// A window the platform found asking for a password, while secure input was on.
public struct SecureInputCandidate: Equatable, Sendable {
    public var ref: WindowRef
    /// The app's name, when the platform could say.
    public var app: String?
    public var title: String
    /// The app's focused element is an `AXSecureTextField` in this window. False: no such field
    /// was seen (Electron apps often expose none), but the app's focused window is titled like a
    /// password prompt (`looksLikePasswordPrompt`).
    public var secureField: Bool

    public init(ref: WindowRef, app: String?, title: String, secureField: Bool) {
        self.ref = ref; self.app = app; self.title = title; self.secureField = secureField
    }

    /// "Enter Password", "Passphrase required", not "1Password": the word, not a substring.
    public static func looksLikePasswordPrompt(_ title: String) -> Bool {
        title.range(of: #"\b(password|passphrase)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// Successive observations → the Problems to list. Pure; the platform polls and feeds it.
public struct SecureInputWatch: Equatable, Sendable {
    public private(set) var listed: [Problem] = []
    public init() {}

    /// The entries under `Problem.Key.secureInput` now, or nil when they are what was listed last.
    /// `world` names the workspace each window is on, and says whether it can be shown.
    public mutating func observe(on: Bool, candidates: [SecureInputCandidate], world: World) -> [Problem]? {
        let next = !on ? [] : candidates.isEmpty ? [Problem.secureInputUnknown]
            : candidates.map { Problem.secureInput($0, world: world) }
        guard next != listed else { return nil }
        listed = next
        return next
    }
}

extension Problem.Key {
    /// #193: alone when no window could be blamed; otherwise followed by `window:<pid>:<id>` for
    /// one the shell can show (it is in a row, or a visitor), or `app:<pid>:<id>` for one it can't.
    public static let secureInput = "secure-input"
    static let secureInputWindow = secureInput + ":window:"
}

extension Problem {
    public static let secureInputUnknown = Problem(
        key: Key.secureInput, severity: .error,
        message: "An app has secure keyboard entry on, so SpacialShell's hotkeys can't work until it's off. Usually a focused password field: click out of it, or close the window asking for a password. Terminal's and iTerm's Secure Keyboard Entry do the same.")

    public static func secureInput(_ c: SecureInputCandidate, world: World) -> Problem {
        let loc = world.location(of: c.ref)
        var whereabouts: [String] = []
        if !c.title.isEmpty { whereabouts.append("'\(c.title)'") }
        if let loc, let screen = world.screens[loc.screen] {
            let ws = screen.workspaces[loc.index]
            let label = AppCategories.rowTitle(name: ws.name, category: ws.category, isTrailingEmpty: false)
            whereabouts.append("on workspace \(loc.index + 1)" + (label.hasPrefix("Workspace") ? "" : " '\(label)'"))
        }
        let showable = loc != nil || world.ephemeral.contains(c.ref)
        let app = c.app ?? "An app"
        let detail = whereabouts.isEmpty ? "" : " (\(whereabouts.joined(separator: ", ")))"
        return Problem(key: Key.secureInput + (showable ? ":window:" : ":app:") + "\(c.ref.pid):\(c.ref.id)",
                       severity: .error,
                       message: "\(app) is waiting for a password\(detail). SpacialShell's hotkeys are blocked until it's answered or closed.")
    }

    /// #193: the window a `secure-input:window:` entry names, for its Show window button.
    var secureInputWindow: WindowRef? {
        guard key.hasPrefix(Key.secureInputWindow) else { return nil }
        let parts = key.dropFirst(Key.secureInputWindow.count).split(separator: ":")
        guard parts.count == 2, let pid = Int32(parts[0]), let id = WindowID(parts[1]) else { return nil }
        return WindowRef(id: id, pid: pid)
    }
}
