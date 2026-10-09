// swift-tools-version:5.9
import PackageDescription

// Swift 5 language mode (tools 5.9) on purpose: the app targets build with
// SWIFT_VERSION = 5.0, and strict concurrency checking would turn the shared
// Foundation types used here into build breaks rather than warnings.
let package = Package(
    name: "TokenMonitorKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        // Foundation-only core: Hub client, models, snapshot cache, formatting.
        // Builds and tests on Linux (`swift test`).
        .library(name: "TokenMonitorKit", targets: ["TokenMonitorKit"]),
        // Shared SwiftUI building blocks for the app, widgets and watch.
        .library(name: "TokenMonitorUI", targets: ["TokenMonitorUI"])
    ],
    targets: [
        .target(name: "TokenMonitorKit"),
        .target(name: "TokenMonitorUI", dependencies: ["TokenMonitorKit"]),
        .testTarget(
            name: "TokenMonitorKitTests",
            dependencies: ["TokenMonitorKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
