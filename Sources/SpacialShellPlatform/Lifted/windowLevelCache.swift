// Adapted from AeroSpace (MIT) — Sources/AppBundle/windowLevelCache.swift @ c548c7f
import SpacialShellProtocol
import CoreGraphics
import Foundation

@MainActor
private var cache: [WindowID: MacOsWindowLevel] = [:]

/// Levels for many windows in one `CGWindowList` pass.
///
/// Our ids are minted (`WindowIdentities`) and are not window-server handles any more, so each one
/// is resolved to a real `CGWindowID` first. That resolution is the weak public match the spike
/// measured, and it is allowed to fail: an unresolved window simply has no level, which is exactly
/// what this function already returned for a window the list did not mention. The classifier
/// treats a nil level as "not known to be always-on-top" and falls back to its other rules, so the
/// failure mode is a floating panel occasionally classified as a normal window — visible and
/// recoverable, never a mis-addressed write.
@MainActor
func getWindowLevels(for ids: [WindowID]) -> [WindowID: MacOsWindowLevel] {
    var out: [WindowID: MacOsWindowLevel] = [:]
    let uncached = ids.filter { id in
        if let existing = cache[id] { out[id] = existing; return false }
        return true
    }
    guard !uncached.isEmpty else { return out }

    var levelByCGID: [CGWindowID: MacOsWindowLevel] = [:]
    for listed in WindowIdentities.onScreenList() {
        levelByCGID[listed.id] = .new(windowLevel: listed.layer)
    }
    for (id, cgID) in WindowIdentities.captureIDs(for: uncached) {
        guard let level = levelByCGID[cgID] else { continue }
        // A window's level does not change while the window lives, so this is cached for good.
        cache[id] = level
        out[id] = level
    }
    return out
}

@MainActor
func getWindowLevel(for windowId: WindowID) -> MacOsWindowLevel? {
    getWindowLevels(for: [windowId])[windowId]
}

/// A closed window's id must not keep a level alive for a future id to collide with.
@MainActor
func forgetWindowLevel(_ id: WindowID) { cache.removeValue(forKey: id) }

enum MacOsWindowLevel: Sendable, Equatable {
    case normalWindow
    case alwaysOnTopWindow
    case unknown(windowLevel: Int)

    static func new(windowLevel: Int) -> MacOsWindowLevel {
        switch windowLevel {
            case 0: .normalWindow
            case 3: .alwaysOnTopWindow
            default: .unknown(windowLevel: windowLevel)
        }
    }

    static func fromJson(_ json: Json) -> MacOsWindowLevel? {
        switch json {
            case .string("normalWindow"): .normalWindow
            case .string("alwaysOnTopWindow"): .alwaysOnTopWindow
            case .int(let int): .new(windowLevel: Int(exactly: int).orDie())
            default: nil
        }
    }

    func toJson() -> Json {
        switch self {
            case .normalWindow: .string("normalWindow")
            case .alwaysOnTopWindow: .string("alwaysOnTopWindow")
            case .unknown(let layerNumber): .int(layerNumber)
        }
    }
}
