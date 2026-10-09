// swift-tools-version:5.9
// TrackCore: Track's data and training logic, with no UI, so it builds and tests anywhere Swift runs (the GitHub
// Linux runner checks it on every push). The iPhone app depends on it.
import PackageDescription

let package = Package(
    name: "TrackCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TrackCore", targets: ["TrackCore"])],
    targets: [
        // Resources/lifts.json: exercise names to lifts, the website's lib/lifts.json word for word.
        .target(name: "TrackCore", path: "Sources/TrackCore", resources: [.copy("Resources/lifts.json")]),
        .testTarget(
            name: "TrackCoreTests",
            dependencies: ["TrackCore"],
            path: "Tests/TrackCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
