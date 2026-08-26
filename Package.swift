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
    ],
    targets: [
        .target(name: "PrivateApi", path: "Sources/PrivateApi"),
        .target(name: "SpacialShellProtocol"),
        .target(
            name: "SpacialShellKit",
            dependencies: ["SpacialShellProtocol", .product(name: "TOMLDecoder", package: "TOMLDecoder")]
        ),
        .target(name: "SpacialShellPlatform", dependencies: ["SpacialShellKit", "SpacialShellProtocol", "PrivateApi"]),
        // M2 T15: the drawn shell as a library so the story/snapshot tests can render it. Depends
        // on Platform only for DisplayTopology.uuid; drops to Kit-only when the T8 snapshot feed
        // carries display identity.
        .target(name: "SpacialShellUI", dependencies: ["SpacialShellKit", "SpacialShellPlatform", "SpacialShellProtocol"]),
        .executableTarget(name: "SpacialShell", dependencies: ["SpacialShellKit", "SpacialShellPlatform", "SpacialShellProtocol", "SpacialShellUI"]),
        .executableTarget(name: "SpacialCtl", dependencies: ["SpacialShellProtocol"]),
        .testTarget(name: "SpacialShellKitTests", dependencies: ["SpacialShellKit"]),
        .testTarget(name: "SpacialShellProtocolTests", dependencies: ["SpacialShellProtocol"]),
        .testTarget(name: "SpacialShellPlatformTests", dependencies: ["SpacialShellPlatform"]),
        .testTarget(name: "PlatformIntegrationTests", dependencies: ["SpacialShellPlatform", "SpacialShellKit"]),
        .testTarget(
            name: "ShellStoryTests",
            dependencies: ["SpacialShellUI", .product(name: "SnapshotTesting", package: "swift-snapshot-testing")],
            exclude: ["__Snapshots__"]
        ),
    ]
)
