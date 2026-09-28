import AppKit
import Sparkle
import SpacialShellKit

/// #58: Sparkle's standard updater — automatic daily checks (`SUEnableAutomaticChecks`) against the
/// appcast on the latest GitHub Release (`SUFeedURL`), plus the settings window's
/// "Check for Updates…". The app target only: Kit stays pure.
///
/// Relaunching after an update goes through `NSApp.terminate`, so `applicationWillTerminate`
/// restores every parked window first (spec §7.4), exactly like a quit.
@MainActor
enum Updates {
    /// Sparkle holds its user driver delegate weakly.
    private static let reminders = GentleReminders()

    /// `nil` when running loose (`Scripts/dev.sh` — there is no bundle to replace) or when
    /// Info.plist has no `SUPublicEDKey` (dev bundles drop it; see `Scripts/bundle.sh`). Without a key
    /// Sparkle refuses to start and says so in an alert — at every login, for a window manager.
    static func makeController() -> SPUStandardUpdaterController? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty
        else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: reminders)
    }
}

/// #192: Sparkle's gentle reminders (https://sparkle-project.org/documentation/gentle-reminders).
/// SpacialShell is an accessory app, so a scheduled check's alert would open behind every other
/// window. Unless Sparkle means to show it in utmost focus (just after launch), a scheduled update
/// is listed under the rail cog instead (`Problem.updateAvailable`), whose button sends
/// `.checkForUpdates` and so brings the alert up. A manual check is Sparkle's, untouched.
@MainActor
private final class GentleReminders: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            ProblemCenter.shared.report(.updateAvailable(version: update.displayVersionString))
        } else if !state.userInitiated {
            // Sparkle shows this one itself; an accessory app's window comes forward only if it is active.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        ProblemCenter.shared.clear(Problem.Key.update)
    }

    func standardUserDriverWillFinishUpdateSession() {
        ProblemCenter.shared.clear(Problem.Key.update)
    }
}
