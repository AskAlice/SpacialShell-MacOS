// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpacialShell",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpacialShellKit", targets: ["SpacialShellKit"]),
        .executable(name: "SpacialShell", targets: ["SpacialShell"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.0"),
    ],
    targets: [
        .target(name: "PrivateApi", path: "Sources/PrivateApi"),
        .target(name: "SpacialShellProtocol"),
        .target(
            name: "SpacialShellKit",
            dependencies: ["SpacialShellProtocol", .product(name: "TOMLDecoder", package: "TOMLDecoder")]
        ),
        .target(name: "SpacialShellPlatform", dependencies: ["SpacialShellKit", "SpacialShellProtocol", "PrivateApi"]),
        .executableTarget(name: "SpacialShell", dependencies: ["SpacialShellKit", "SpacialShellPlatform", "SpacialShellProtocol"]),
        .testTarget(name: "SpacialShellKitTests", dependencies: ["SpacialShellKit"]),
        .testTarget(name: "SpacialShellProtocolTests", dependencies: ["SpacialShellProtocol"]),
        .testTarget(name: "SpacialShellPlatformTests", dependencies: ["SpacialShellPlatform"]),
        .testTarget(name: "PlatformIntegrationTests", dependencies: ["SpacialShellPlatform", "SpacialShellKit"]),
    ]
)
