// Derived from AeroSpace (MIT) — Sources/AppBundleTests/AxUiElementWindowTypeTest.swift @ c548c7f
import Testing
import Foundation
import AppKit
@testable import SpacialShellPlatform
import SpacialShellKit

@Suite struct ClassifierCorpusTests {
    /// Tests/SpacialShellPlatformTests/ClassifierCorpusTests.swift -> repo root
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func allFixturesClassifyAsRecorded() throws {
        var count = 0
        try walk(Self.root.appendingPathComponent("axDumps")) { file in
            let raw = try JSONSerialization.jsonObject(
                with: Data(contentsOf: file),
                options: [.json5Allowed],
            ) as! [String: Any]
            let json = Json.newOrDieRecursive(raw).asDictOrDie
            let app = json["Aero.AXApp"]!.asDictOrDie
            let bundle = (raw["Aero.App.appBundleId"] as? String).flatMap { KnownBundleId(rawValue: $0) }
            let level = json["Aero.windowLevel"].map { MacOsWindowLevel.fromJson($0) ?? dieT() }
            let policy = NSApplication.ActivationPolicy.from(string: raw["Aero.App.nsApp.activationPolicy"] as! String)
            let expected = AxUiElementWindowType(rawValue: raw["Aero.AxUiElementWindowType"] as! String)!
            #expect(json.getWindowType(axApp: app, bundle, policy, level) == expected, "\(file.lastPathComponent)")
            #expect(
                json.isDialogHeuristic(bundle, level) == (raw["Aero.AxUiElementWindowType_isDialogHeuristic"] as! Bool),
                "\(file.lastPathComponent)",
            )
            // Pin the public entry point too: it must agree with the raw heuristic + kind mapping.
            #expect(
                WindowClassifier.kind(
                    axWindow: json,
                    axApp: app,
                    bundleID: raw["Aero.App.appBundleId"] as? String,
                    activationPolicy: policy,
                    windowLevel: level,
                ) == WindowClassifier.kind(for: expected),
                "\(file.lastPathComponent)",
            )
            count += 1
        }
        #expect(count >= 119)
    }

    func walk(_ dir: URL, _ f: (URL) throws -> Void) throws {
        for u in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) {
            if (try u.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true { try walk(u, f) }
            else if u.pathExtension != "md" { try f(u) }
        }
    }

    /// #176: Brave's other channels (Origin, Beta, Nightly) are Brave. Under `com.brave.Browser.origin`
    /// the recorded PiP window was a floating tab that could not be focused; it must stay ignored,
    /// and an ordinary window must still tile.
    @Test(arguments: ["com.brave.Browser.origin", "com.brave.Browser.beta", "com.brave.Browser.nightly"])
    func braveChannelsClassifyAsBrave(bundleID: String) throws {
        func kind(_ dump: String) throws -> WindowKind {
            let file = Self.root.appendingPathComponent("axDumps/\(dump).json5")
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file), options: [.json5Allowed]) as! [String: Any]
            let json = Json.newOrDieRecursive(raw).asDictOrDie
            return WindowClassifier.kind(
                axWindow: json,
                axApp: json["Aero.AXApp"]!.asDictOrDie,
                bundleID: bundleID,
                activationPolicy: .regular,
                windowLevel: json["Aero.windowLevel"].map { MacOsWindowLevel.fromJson($0) ?? dieT() },
            )
        }
        #expect(try kind("brave_pip") == .ignore, "Picture in Picture is not a window")
        #expect(try kind("brave") == .tile)
    }

    @Test func kindMappingIsFixed() {
        #expect(WindowClassifier.kind(for: .window) == .tile)
        #expect(WindowClassifier.kind(for: .dialog) == .float)
        #expect(WindowClassifier.kind(for: .popup) == .ignore)
    }
}
