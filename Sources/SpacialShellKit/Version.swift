import Foundation

public enum SpacialShellKit {
    /// #191: the running release — what `spacialctl version` and telemetry report. A release `.app`
    /// carries its tag in `CFBundleShortVersionString` (`Scripts/bundle.sh`), the same key the
    /// standard About panel reads.
    public static let version = SpacialShellKit.version(
        bundleURL: Bundle.main.bundleURL,
        shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)

    /// What a loose binary (`swift run`, `Scripts/dev.sh`, tests) reports: it has no bundle.
    public static let fallbackVersion = "0.1.0"

    /// The bundle's version when running as an `.app`, else `fallbackVersion`.
    static func version(bundleURL: URL, shortVersion: String?) -> String {
        guard bundleURL.pathExtension == "app", let shortVersion, !shortVersion.isEmpty
        else { return fallbackVersion }
        return shortVersion
    }
}
