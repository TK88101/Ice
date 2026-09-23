// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MenuBarCapture",
    platforms: [
        // Matches Ice's deployment target (Packages/IceCore/Package.swift).
        // CGWindowListCreateImage is only usable at this target: it is
        // obsoleted starting macOS 15 (see LiveStripCapturer.swift).
        .macOS(.v14),
    ],
    products: [
        .library(name: "MenuBarCapture", targets: ["MenuBarCapture"]),
    ],
    dependencies: [
        .package(name: "IceCore", path: "../IceCore"),
    ],
    targets: [
        // AppKit / CoreGraphics / ApplicationServices adapter: turns real
        // captures of the bar into the plain values IceCore's decision layer
        // reads. Not referenced by Ice.xcodeproj -- see the plan, section 4.
        .target(
            name: "MenuBarCapture",
            dependencies: [
                .product(name: "IceCore", package: "IceCore"),
            ]
        ),
        .testTarget(
            name: "MenuBarCaptureTests",
            dependencies: ["MenuBarCapture"]
        ),
        // Read-only sanity check (plan section "SANITY CHECK"): one capture
        // of the real bar, one AX read of MenuBarAgent's own extras, printed
        // and exited. Launches nothing, moves nothing, writes no attribute.
        .executableTarget(
            name: "MBCaptureSanity",
            dependencies: ["MenuBarCapture"]
        ),
    ]
)
