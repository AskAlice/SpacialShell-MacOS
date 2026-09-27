import Testing
import Foundation
@testable import SpacialShellKit

/// #168: what `config.toml` and `settings.json` do, pinned before the key table replaced the
/// hand-written decoders. Every key is set here to something other than its default, so a key the
/// table drops, misnames or decodes differently fails one of these.
@Suite struct ConfigCharacterizationTests {
    /// Every key the file can set, each away from its default. The out-of-range values are
    /// clamped, the loose colours normalised.
    static let fullToml = """
    keybinding-preset = "ctrl-alt"
    gap = 4
    screen-gap = 12
    default-layout = "code-3"
    ax-timeout-ms = 500
    refresh-interval-ms = 3000
    start-at-login = true
    panel-width = 60
    panel-height = 40
    rail-side = "right"
    tab-sizing = "equal"
    tab-style = "icon"
    rail-icon-style = "hybrid"
    dock-attention = false
    launcher-url = "alfred://"
    show-panels = false
    crowd-threshold = 3
    category-order = ["media", "web"]
    max-workspaces = 0
    other-window-managers = ["yabai"]
    persist-state = false
    animations = false
    animate-retile = true
    empty-cheatsheet = false
    rail-autohide = true
    pointer-warp = false
    workspace-wrap = true
    gestures = false
    gesture-fingers = 9
    gesture-invert = true
    gesture-layout = false
    focus-follows-mouse = true
    focus-follows-mouse-delay-ms = 5
    panel-color = "11223399"
    panel-opacity = -0.5
    layout-bar = ["maximize", "code-3"]

    [category-colors]
    web = "#3478f6"

    [app-categories]
    "com.example.a" = "media"

    [[workspace]]
    name = "Code"
    symbol = "terminal"
    layout = "half"

    [[layout]]
    id = "code-3"
    name = "Code, three"
    zones = [{ x = 0.0, y = 0.0, w = 0.5, h = 1.0 }, { x = 0.5, y = 0.0, w = 0.5, h = 1.0 }]

    [[ephemeral]]
    bundle-id = "com.example.e"

    [[float]]
    bundle-id = "com.example.f"
    title-regex = "PiP"

    [[ignore]]
    bundle-id = "com.example.i"

    [[tile]]
    bundle-id = "com.example.t"

    [keybindings]
    "fn-shift-g" = "toggle-float"

    [keybinding-overrides]
    "cycle-layout" = "fn-shift-l"

    [telemetry]
    enabled = true
    endpoint = "https://otlp.example.net"
    user = "u"
    token = "t"
    """

    static var fullConfig: Config {
        var e = Config()
        e.keybindingPreset = .ctrlAlt
        e.gap = 4
        e.screenGap = 12
        e.defaultLayout = "code-3"
        e.axTimeoutMs = 500
        e.refreshIntervalMs = 3000
        e.startAtLogin = true
        e.panelWidth = 60
        e.panelHeight = 40
        e.railSide = .right
        e.tabSizing = .equal
        e.tabStyle = .icon
        e.railIconStyle = .hybrid
        e.dockAttention = false
        e.launcherURL = "alfred://"
        e.showPanels = false
        e.crowdThreshold = 3
        e.categoryOrder = [.media, .web]
        e.maxWorkspaces = 1
        e.otherWindowManagers = ["yabai"]
        e.persistState = false
        e.animations = false
        e.animateRetile = true
        e.emptyCheatsheet = false
        e.railAutohide = true
        e.pointerWarp = false
        e.workspaceWrap = true
        e.gestures = false
        e.gestureFingers = 5
        e.gestureInvert = true
        e.gestureLayout = false
        e.focusFollowsMouse = true
        e.focusFollowsMouseDelayMs = 50
        e.panelColor = "#11223399"
        e.panelOpacity = 0
        e.layoutBar = [.maximize, "code-3"]
        e.categoryColors = [.web: "#3478F6"]
        e.appCategories = ["com.example.a": .media]
        e.workspaces = [WorkspaceSeed(name: "Code", symbol: "terminal", layout: .half)]
        e.layouts = [LayoutDef(id: "code-3", name: "Code, three",
                               body: .zones([LayoutZone(x: 0, y: 0, w: 0.5, h: 1), LayoutZone(x: 0.5, y: 0, w: 0.5, h: 1)]))]
        e.fileLayoutIDs = ["code-3"]
        e.ephemeral = [AppRule(bundleId: "com.example.e")]
        e.float = [AppRule(bundleId: "com.example.f", titleRegex: "PiP")]
        e.ignore = [AppRule(bundleId: "com.example.i")]
        e.tile = [AppRule(bundleId: "com.example.t")]
        e.keybindings = ["fn-shift-g": "toggle-float"]
        e.keybindingOverrides = ["cycle-layout": "fn-shift-l"]
        var t = TelemetryConfig(); t.enabled = true; t.endpoint = "https://otlp.example.net"; t.user = "u"; t.token = "t"
        e.telemetry = t
        return e
    }

    @Test func aFullConfigParsesToExactlyThis() throws {
        #expect(try Config.parse(toml: Self.fullToml) == Self.fullConfig)
        #expect(Config.unknownKeys(toml: Self.fullToml).isEmpty)
    }

    /// The full example really does move every stored property off its default, so the test above
    /// covers every key (a new property with no line in `fullToml` fails here).
    @Test func theFullConfigLeavesNoPropertyAtItsDefault() throws {
        let full = Mirror(reflecting: try Config.parse(toml: Self.fullToml)).children
        let base = Mirror(reflecting: Config()).children
        for (f, b) in zip(full, base) {
            #expect(String(describing: f.value) != String(describing: b.value), "\(f.label ?? "?") is still its default")
        }
    }

    /// The names #133 warns about: top-level and dotted, each once, sorted; free-form maps are data.
    @Test func unknownKeysAreNamedTheSameWay() {
        let toml = """
        gapp = 4
        rail-sde = "left"
        [category-colors]
        webb = "#3478F6"
        [app-categories]
        "anything.at.all" = "web"
        [keybindings]
        "not-a-key" = "focus-window-left"
        [keybinding-overrides]
        "whatever" = "fn-a"
        [[workspace]]
        name = "A"
        symbl = "x"
        [[layout]]
        id = "l"
        zones = [{ x = 0.0, y = 0.0, w = 1.0, h = 1.0 }]
        zone = 1
        [[ephemeral]]
        bundle-id = "a"
        bundle = "a"
        [[float]]
        bundle-id = "a"
        title = "a"
        [[float]]
        bundle-id = "b"
        title = "b"
        [[ignore]]
        bundle-id = "a"
        regex = "a"
        [[tile]]
        bundle-id = "a"
        tile = true
        [telemetry]
        tokn = "x"
        [focus-ring]
        on = true
        """
        #expect(Config.unknownKeys(toml: toml) == [
            "category-colors.webb", "ephemeral.bundle", "float.title", "focus-ring", "gapp", "ignore.regex",
            "layout.zone", "rail-sde", "telemetry.tokn", "tile.tile", "workspace.symbl",
        ])
    }

    /// Bad values reject the file; they are not skipped.
    @Test func badValuesStillReject() {
        for toml in [#"rail-side = "middle""#, #"tab-style = "tiny""#, #"panel-color = "red""#, "gap = \"wide\"",
                     "[category-colors]\nweb = \"blue\"", #"keybinding-preset = "cmd""#, "animations = 1",
                     "[[workspace]]\nsymbol = \"x\""] {
            #expect(throws: (any Error).self, "\(toml)") { try Config.parse(toml: toml) }
        }
    }

    /// A rejected value names its key the way it always has: the message is shown in the problems
    /// list, so its wording is part of the behaviour.
    @Test func rejectionsNameTheKey() {
        func message(_ toml: String) -> String {
            do { _ = try Config.parse(toml: toml); return "" } catch { return String(describing: error) }
        }
        #expect(message(#"panel-color = "red""#) == """
            DecodingError.dataCorrupted: Data was corrupted. Path: panel-color. Debug description: panel-color must be "system" or #RRGGBB
            """)
        #expect(message("[category-colors]\nweb = \"blue\"") == """
            DecodingError.dataCorrupted: Data was corrupted. Path: category-colors. Debug description: category-colors.web must be #RRGGBB
            """)
        #expect(message(#"rail-side = "middle""#) == """
            DecodingError.dataCorrupted: Data was corrupted. Path: rail-side. Debug description: Cannot initialize RailSide from invalid String value middle
            """)
        #expect(message("gap = \"wide\"") == """
            DecodingError.valueNotFound: Expected value of type OffsetDateTime but found null instead. Path: gap. \
            Debug description: (Line 1) Invalid date-time value for key 'gap': expected valid time.. \
            Underlying error: (Line 1) Invalid date-time value for key 'gap': expected valid time.
            """)
    }

    // MARK: settings.json

    /// Every knob the settings window can set, each set.
    static var fullOverrides: SettingsOverrides {
        var o = SettingsOverrides()
        o.panelWidth = 70; o.panelHeight = 44; o.gap = 16; o.screenGap = 2; o.panelColor = "#AABBCC"
        o.railSide = .left; o.tabSizing = .fit; o.tabStyle = .name; o.railIconStyle = .category
        o.dockAttention = true; o.keybindingPreset = .fn; o.animations = true; o.animateRetile = false
        o.emptyCheatsheet = true; o.railAutohide = false; o.pointerWarp = true; o.workspaceWrap = false
        o.gestures = true; o.gestureInvert = false; o.gestureLayout = true; o.focusFollowsMouse = false
        o.persistState = true; o.keybindingOverrides = ["toggle-float": "fn-shift-f", "cycle-layout": "fn-shift-k"]
        o.categoryOrder = []; o.maxWorkspaces = -3
        o.layouts = [LayoutDef(id: "code-3", name: "Drawn", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 1)])),
                     LayoutDef(id: "gui-only", name: "GUI", body: .zones([LayoutZone(x: 0, y: 0, w: 1, h: 0.5)]))]
        o.layoutBar = [.grid]; o.defaultLayout = .split; o.silencedWarnings = ["other-wm:yabai"]
        return o
    }

    /// The window wins on every knob it sets; merges merge; the file keeps the rest.
    @Test func everyOverrideWinsOverTheFile() {
        var e = Self.fullConfig
        e.panelWidth = 70; e.panelHeight = 44; e.gap = 16; e.screenGap = 2; e.panelColor = "#AABBCC"
        e.railSide = .left; e.tabSizing = .fit; e.tabStyle = .name; e.railIconStyle = .category
        e.dockAttention = true; e.keybindingPreset = .fn; e.animations = true; e.animateRetile = false
        e.emptyCheatsheet = true; e.railAutohide = false; e.pointerWarp = true; e.workspaceWrap = false
        e.gestures = true; e.gestureInvert = false; e.gestureLayout = true; e.focusFollowsMouse = false
        e.persistState = true; e.keybindingOverrides = ["toggle-float": "fn-shift-f", "cycle-layout": "fn-shift-k"]
        e.categoryOrder = []; e.maxWorkspaces = 1
        e.layouts = Self.fullOverrides.layouts!      // the drawn code-3 replaces the file's, in its place
        e.layoutBar = [.grid]; e.defaultLayout = .split
        #expect(Settings.effective(config: Self.fullConfig, overrides: Self.fullOverrides) == e)
        #expect(Settings.effective(config: Self.fullConfig, overrides: SettingsOverrides()) == Self.fullConfig)
    }

    /// The JSON names are what earlier builds wrote; renaming one silently drops that setting.
    @Test func settingsJSONKeepsItsKeyNames() throws {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        let data = try e.encode(Self.fullOverrides)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        #expect(keys == [
            "animateRetile", "animations", "categoryOrder", "defaultLayout", "dockAttention", "emptyCheatsheet",
            "focusFollowsMouse", "gap", "gestureInvert", "gestureLayout", "gestures", "keybindingOverrides",
            "keybindingPreset", "layoutBar", "layouts", "maxWorkspaces", "panelColor", "panelHeight", "panelWidth",
            "persistState", "pointerWarp", "railAutohide", "railIconStyle", "railSide", "screenGap",
            "silencedWarnings", "tabSizing", "tabStyle", "workspaceWrap",
        ])
        #expect(try JSONDecoder().decode(SettingsOverrides.self, from: data) == Self.fullOverrides)
    }

    /// A bad layout in settings.json is dropped, not the file.
    @Test func aBadDrawnLayoutIsDroppedNotTheFile() throws {
        let json = #"{"gap":3,"layouts":[{"id":"ok","zones":[{"x":0,"y":0,"w":1,"h":1}]},{"id":"bad","zones":[]}]}"#
        let o = try JSONDecoder().decode(SettingsOverrides.self, from: Data(json.utf8))
        #expect(o.gap == 3 && o.layouts?.map(\.id) == ["ok"])
    }
}
