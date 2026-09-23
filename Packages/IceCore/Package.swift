// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IceCore",
    platforms: [
        // Matches MACOSX_DEPLOYMENT_TARGET in Ice.xcodeproj.
        .macOS(.v14),
    ],
    products: [
        .library(name: "IceCore", targets: ["IceCore"]),
    ],
    targets: [
        // Pure decision logic, testable without a menu bar, a display, or a
        // running app. Nothing here may import AppKit, ApplicationServices,
        // CoreGraphics, or talk to the window server -- adapters in the app
        // gather the facts and hand them in as plain values.
        .target(name: "IceCore"),
        .testTarget(name: "IceCoreTests", dependencies: ["IceCore"]),
    ]
)
