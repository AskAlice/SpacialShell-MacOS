// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpacialShell",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpacialShellKit", targets: ["SpacialShellKit"]),
        .executable(name: "SpacialShell", targets: ["SpacialShell"]),
        .executable(name: "spacialctl", targets: ["SpacialCtl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        // #83: tracing. Core carries the API (Kit) and the SDK; the other package the OTLP/HTTP
        // exporter, resource detection and the in-memory exporter the tests read spans from.
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", exact: "2.6.0"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift", exact: "2.5.2"),
        // #58: auto-update. The app target only — Kit stays pure. Its binary tools (generate_keys,
        // generate_appcast) land in .build/artifacts/sparkle/Sparkle/bin; see docs/release.md.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "SpacialShellProtocol"),
        .target(
            name: "SpacialShellKit",
            dependencies: ["SpacialShellProtocol", .product(name: "TOMLDecoder", package: "TOMLDecoder"),
                           // The API only: a no-op tracer until the app registers the SDK (#83).
                           .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core")]
        ),
        .target(name: "SpacialShellPlatform", dependencies: ["SpacialShellKit", "SpacialShellProtocol"]),
        // M2 T15: the drawn shell as a library so the story/snapshot tests can render it. Depends
        // on Platform only for DisplayTopology.uuid; drops to Kit-only when the T8 snapshot feed
        // carries display identity.
        .target(name: "SpacialShellUI", dependencies: ["SpacialShellKit", "SpacialShellPlatform", "SpacialShellProtocol",
                                                     .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core")]),
        .executableTarget(name: "SpacialShell", dependencies: [
            "SpacialShellKit", "SpacialShellPlatform", "SpacialShellProtocol", "SpacialShellUI",
            .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
            .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift"),
            .product(name: "ResourceExtension", package: "opentelemetry-swift"),
            .product(name: "Sparkle", package: "Sparkle"),
        ]),
        .executableTarget(name: "SpacialCtl", dependencies: ["SpacialShellProtocol"]),
        // Fixtures: pre-#9 config/state/wire payloads and built-in frames, captured before #9 changed
        // a line, decoded by every later build (custom grid layouts design §11).
        .testTarget(name: "SpacialShellKitTests", dependencies: [
            "SpacialShellKit",
            .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
            .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            .product(name: "InMemoryExporter", package: "opentelemetry-swift"),
        ], resources: [.copy("Fixtures")]),
        .testTarget(name: "SpacialShellProtocolTests", dependencies: ["SpacialShellProtocol"]),
        .testTarget(name: "SpacialShellPlatformTests", dependencies: ["SpacialShellPlatform"]),
        .testTarget(name: "PlatformIntegrationTests", dependencies: ["SpacialShellPlatform", "SpacialShellKit"]),
        .testTarget(
            name: "ShellStoryTests",
            dependencies: ["SpacialShellUI", "SpacialShellProtocol", .product(name: "SnapshotTesting", package: "swift-snapshot-testing")],
            exclude: ["__Snapshots__"]
        ),
    ]
)
