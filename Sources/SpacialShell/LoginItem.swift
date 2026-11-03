import ServiceManagement
import os

/// #210: `start-at-login` as the app's own login item (`SMAppService.mainApp`, macOS 13+).
enum LoginItem {
    static func set(_ on: Bool, log: Logger) {
        let item = SMAppService.mainApp
        do {
            if on, item.status != .enabled { try item.register() }
            if !on, item.status == .enabled { try item.unregister() }
            log.info("login item \(on ? "on" : "off", privacy: .public) (status \(item.status.rawValue, privacy: .public))")
        } catch {
            // `requiresApproval` lands here too: System Settings > General > Login Items has the switch.
            log.error("login item \(on ? "on" : "off", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
