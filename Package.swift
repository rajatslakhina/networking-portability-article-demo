// swift-tools-version: 6.0
import PackageDescription

// Library products only — deliberately no `.executableTarget`.
// Running a Swift Package executable directly as an iOS app relies on a
// synthesized Bundle Identifier that Xcode stores per-checkout and never commits,
// which crashes on launch with
// __BKSHIDEvent__BUNDLE_IDENTIFIER_FOR_CURRENT_PROCESS_IS_NIL__.
// The runnable app lives in Demo.xcodeproj instead.
let package = Package(
    name: "NetworkPortability",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PortabilityCore", targets: ["PortabilityCore"]),
        .library(name: "PortabilityKitUI", targets: ["PortabilityKitUI"])
    ],
    targets: [
        .target(name: "PortabilityCore"),
        .target(name: "PortabilityKitUI", dependencies: ["PortabilityCore"]),
        .testTarget(name: "PortabilityCoreTests", dependencies: ["PortabilityCore"])
    ]
)
