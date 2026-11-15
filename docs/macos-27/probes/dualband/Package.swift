// swift-tools-version: 6.0
import PackageDescription

// T0 of docs/plans/2026-11-15-secondary-display.md: the hiding lengths of two
// bars at once, on the daily identity's Debug build (guards G1-G6). Not in any
// Xcode target. DualbandCore holds the pure rules and is the tested target.
let package = Package(
    name: "dualband",
    platforms: [
        // CGWindowListCreateImage is obsoleted from macOS 15; usable at 14
        // (Packages/MenuBarCapture/Sources/MenuBarCapture/LiveStripCapturer.swift).
        .macOS(.v14),
    ],
    dependencies: [
        // T5 of plan 2026-11-15-cover reads the bars with the cover's own reader.
        .package(name: "MenuBarCover", path: "../../../../Packages/MenuBarCover"),
        .package(name: "IceCore", path: "../../../../Packages/IceCore"),
    ],
    targets: [
        .target(name: "DualbandCore"),
        .executableTarget(
            name: "dualband",
            dependencies: [
                "DualbandCore", .product(name: "MenuBarCover", package: "MenuBarCover"), .product(name: "IceCore", package: "IceCore"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "DualbandCoreTests", dependencies: ["DualbandCore"]),
    ]
)
