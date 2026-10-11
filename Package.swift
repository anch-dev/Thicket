// swift-tools-version:5.9
// Pure-Swift modules for Thicket. These build and test on macOS *and* Linux;
// the iOS app (see project.yml) compiles the same sources as frameworks.
import PackageDescription

let package = Package(
    name: "Thicket",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ThicketCore", targets: ["ThicketCore"]),
        .library(name: "ThicketKit", targets: ["ThicketKit"]),
    ],
    targets: [
        // Game rules: board, matches, gravity, chains, phases, scoring, RNG. No platform imports.
        .target(name: "ThicketCore"),
        // Platform-agnostic support: input model, control layout, persistence model,
        // chiptune synthesis, pixel-art sprite data. No UIKit/SpriteKit/AVFoundation.
        .target(name: "ThicketKit", dependencies: ["ThicketCore"]),
        .testTarget(name: "ThicketCoreTests", dependencies: ["ThicketCore"]),
        .testTarget(name: "ThicketKitTests", dependencies: ["ThicketKit", "ThicketCore"]),
    ]
)
