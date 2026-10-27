// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RoteCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RoteCore", targets: ["RoteCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/4rays/swift-fsrs", from: "0.9.2")
    ],
    targets: [
        .target(
            name: "RoteCore",
            dependencies: [.product(name: "SwiftFSRS", package: "swift-fsrs")],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "RoteCoreTests",
            dependencies: ["RoteCore"],
            path: "Tests",
            sources: ["RoteCoreTests"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
