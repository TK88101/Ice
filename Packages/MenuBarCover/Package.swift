// swift-tools-version: 6.0

import PackageDescription

// Plan 2026-11-15-cover: covers the hidden section's items where the spacer
// does not hide them (a bar without a notch). MenuBarCover is the AppKit and
// Accessibility half (the pure rules are IceCore's `CoverPlan`); `mbcover` is
// the live check of T3, linked into nothing.
//
// Swift 5 language mode: the Accessibility and CoreGraphics values this code
// passes between its one background queue and the main thread (AXUIElement,
// CGImage) are not Sendable; the queue discipline is the controller's.
let package = Package(
    name: "MenuBarCover",
    platforms: [
        // Matches Ice's deployment target. CGWindowListCreateImage is usable
        // only here: obsoleted from macOS 15 (see Packages/MenuBarCapture).
        .macOS(.v14),
    ],
    products: [
        .library(name: "MenuBarCover", targets: ["MenuBarCover"]),
    ],
    dependencies: [
        .package(name: "IceCore", path: "../IceCore"),
    ],
    targets: [
        .target(
            name: "MenuBarCover",
            dependencies: [.product(name: "IceCore", package: "IceCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "mbcover",
            dependencies: ["MenuBarCover", .product(name: "IceCore", package: "IceCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MenuBarCoverTests",
            dependencies: ["MenuBarCover", .product(name: "IceCore", package: "IceCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
