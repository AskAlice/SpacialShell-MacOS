import Testing
import Foundation
@testable import SpacialShellKit

/// #138 (G34): warn when another window manager runs.
@Suite struct OtherWindowManagersTests {
    let processes = [
        RunningProcess(bundleID: "com.apple.Safari", name: "Safari", displayName: "Safari"),
        RunningProcess(bundleID: "com.knollsoft.Rectangle", name: "Rectangle", displayName: "Rectangle"),
        RunningProcess(bundleID: nil, name: "yabai"),
        RunningProcess(bundleID: "bobko.aerospace", name: "AeroSpace", displayName: "AeroSpace"),
    ]

    @Test func defaultsNameTheKnownTilers() {
        #expect(Config().otherWindowManagers == OtherWindowManagers.defaults)
        for entry in ["bobko.aerospace", "yabai", "com.amethyst.Amethyst", "com.knollsoft.Rectangle",
                      "com.crowdcafe.windowmagnet"] {
            #expect(OtherWindowManagers.defaults.contains(entry))
        }
    }

    @Test func matchesByBundleIDOrProcessNameInListOrder() {
        let hits = OtherWindowManagers.running(["YABAI", "com.knollsoft.Rectangle", "com.amethyst.Amethyst", "yabai", "AeroSpace"],
                                               in: processes)
        // A daemon by name, ignoring case; an app by bundle id, named by its display name; an app
        // by executable name; each entry once, and absent ones not at all.
        #expect(hits.map(\.entry) == ["YABAI", "com.knollsoft.Rectangle", "yabai", "AeroSpace"])
        #expect(hits.map(\.name) == ["yabai", "Rectangle", "yabai", "AeroSpace"])
        #expect(OtherWindowManagers.running([], in: processes).isEmpty)
        #expect(OtherWindowManagers.running([""], in: [RunningProcess(bundleID: nil, name: "")]).isEmpty)
    }

    @Test func problemsAreWarningsThatAlertAndCanBeSilenced() {
        let all = OtherWindowManagers.problems(list: OtherWindowManagers.defaults, processes: processes, silenced: [])
        #expect(all.map(\.key) == ["other-wm:bobko.aerospace", "other-wm:yabai", "other-wm:com.knollsoft.Rectangle"])
        #expect(all.allSatisfy { $0.severity == .warning && $0.interrupts && $0.canSilence })
        #expect(all[2].message.hasPrefix("Rectangle is running"))
        #expect(all[2].title == "Another window manager is running")
        // Silenced: neither listed nor alerted.
        let left = OtherWindowManagers.problems(list: OtherWindowManagers.defaults, processes: processes,
                                                silenced: ["other-wm:yabai"])
        #expect(left.map(\.key) == ["other-wm:bobko.aerospace", "other-wm:com.knollsoft.Rectangle"])
        // Errors are never silenceable.
        #expect(!Problem.hotkeysInactive("x").canSilence && !Problem.controlSocketInactive("x").canSilence)
    }

    @Test func configKeyParsesAndIsKnown() throws {
        let toml = #"other-window-managers = ["com.example.Tiler", "yabai"]"#
        #expect(try Config.parse(toml: toml).otherWindowManagers == ["com.example.Tiler", "yabai"])
        #expect(Config.unknownKeys(toml: toml).isEmpty)
        #expect(try Config.parse(toml: "other-window-managers = []").otherWindowManagers.isEmpty)
        #expect(try Config.parse(toml: "").otherWindowManagers == OtherWindowManagers.defaults)
    }

    @Test func dontWarnAgainIsRememberedOnceAndOldSettingsStillDecode() throws {
        var o = SettingsOverrides()
        o.silence("other-wm:yabai")
        o.silence("other-wm:yabai")
        #expect(o.silencedWarnings == ["other-wm:yabai"])
        let back = try JSONDecoder().decode(SettingsOverrides.self, from: JSONEncoder().encode(o))
        #expect(back.silencedWarnings == ["other-wm:yabai"])
        #expect(try JSONDecoder().decode(SettingsOverrides.self, from: Data("{}".utf8)).silencedWarnings == nil)
        // Not a config knob: the effective config does not change.
        #expect(Settings.effective(config: Config(), overrides: o) == Config())
    }
}
