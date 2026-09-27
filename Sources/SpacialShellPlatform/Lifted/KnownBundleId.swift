// Adapted from AeroSpace (MIT) — Sources/AppBundle/model/KnownBundleId.swift @ c548c7f
enum KnownBundleId: String, Equatable {

    case _1password = "com.1password.1password"
    case activityMonitor = "com.apple.ActivityMonitor"
    case alacritty = "org.alacritty"
    case braveBrowser = "com.brave.Browser"
    case chrome = "com.google.Chrome"
    case cleanshotx = "pl.maketheweb.cleanshotx"
    case codex = "com.openai.codex"
    case emacs = "org.gnu.Emacs"
    case finder = "com.apple.finder"
    case ghostty = "com.mitchellh.ghostty"
    case gimp = "org.gimp.gimp-2.10"
    case iphonesimulator = "com.apple.iphonesimulator"
    case iterm2 = "com.googlecode.iterm2"
    case kitty = "net.kovidgoyal.kitty"
    case outlook = "com.microsoft.Outlook"
    case photoBooth = "com.apple.PhotoBooth"
    case qutebrowser = "org.qutebrowser.qutebrowser"
    case screenstudio = "com.timpler.screenstudio"
    case slack = "com.tinyspeck.slackmacgap"
    case steam = "com.valvesoftware.steam.helper"
    case wezterm = "com.github.wez.wezterm"
    case wisprFlow = "com.electron.wispr-flow"
    case xcode = "com.apple.dt.Xcode"
    case zenBrowser = "app.zen-browser.zen"
    case zoom = "us.zoom.xos"

    case mozillaFirefox = "org.mozilla.firefox"
    case mozillaFirefoxDeveloperEdition = "org.mozilla.firefoxdeveloperedition"
    case mozillaFirefoxNightly = "org.mozilla.nightly"

    case vscode = "com.microsoft.VSCode"
    case vscodium = "com.vscodium"

    /// A bundle id as the classifier should see it: an app's other release channels get its rules
    /// (#176: Brave Origin, `com.brave.Browser.origin`, was not Brave, so its Picture in Picture
    /// window became a floating tab).
    init?(bundleID: String) {
        if let known = KnownBundleId(rawValue: bundleID) { self = known; return }
        if bundleID.hasPrefix(Self.braveBrowser.rawValue + ".") { self = .braveBrowser; return }
        return nil
    }

    var isFirefox: Bool {
        self == .mozillaFirefox
            || self == .mozillaFirefoxDeveloperEdition
            || self == .mozillaFirefoxNightly
            || self == .zenBrowser
    }

    var isVscode: Bool {
        self == .vscode || self == .vscodium
    }
}
