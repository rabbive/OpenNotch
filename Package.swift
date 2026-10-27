// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OpenNotchCore", path: "Core"),
        .target(name: "OpenNotchSystem", dependencies: ["OpenNotchCore"], path: "System"),
        .executableTarget(name: "OpenNotch", dependencies: ["OpenNotchCore", "OpenNotchSystem"], path: "App"),
        .testTarget(
            name: "OpenNotchTests",
            dependencies: ["OpenNotchCore", "OpenNotchSystem"],
            path: "Tests",
            resources: [.copy("Goldens")]
        ),
    ]
)
