// swift-tools-version: 6.0

import PackageDescription

// Instruments for docs/plans/2026-09-18-safe-width.md. Not part of Ice's build.
//
// Build products must live outside ~/Documents (iCloud extended attributes make
// codesign reject them), so always pass --scratch-path; build.sh does.
let package = Package(
    name: "SafeWidth",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        // Pure logic, IceCore's rule: nothing here may import AppKit,
        // ApplicationServices, CoreGraphics or ImageIO. The executables gather
        // pixels and AX frames and hand them in as plain values.
        .target(name: "SafeWidthCore"),
        .testTarget(name: "SafeWidthCoreTests", dependencies: ["SafeWidthCore"]),
        .executableTarget(
            name: "swctl",
            dependencies: ["SafeWidthCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(name: "swhelper", dependencies: ["SafeWidthCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "swfront", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
