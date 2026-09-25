import Foundation
import Sparkle

/// #58: Sparkle's standard updater — automatic daily checks (`SUEnableAutomaticChecks`) against the
/// appcast on the latest GitHub Release (`SUFeedURL`), plus the settings window's
/// "Check for Updates…". The app target only: Kit stays pure.
///
/// Relaunching after an update goes through `NSApp.terminate`, so `applicationWillTerminate`
/// restores every parked window first (spec §7.4), exactly like a quit.
@MainActor
enum Updates {
    /// `nil` when running loose (`Scripts/dev.sh` — there is no bundle to replace) or when
    /// Info.plist has no `SUPublicEDKey` yet (`Scripts/sparkle-keys.sh` adds it). Without a key
    /// Sparkle refuses to start and says so in an alert — at every login, for a window manager.
    static func makeController() -> SPUStandardUpdaterController? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty
        else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
}
