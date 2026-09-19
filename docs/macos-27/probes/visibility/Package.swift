// swift-tools-version: 6.0
import PackageDescription

// The visibility detector's probes for macOS 27
// (docs/plans/2026-09-19-visibility-adapter.md). Not linked into Ice.
// ImageIO/CoreGraphics/AppKit are fine here — only IceCore itself must stay
// free of them (Packages/IceCore/Package.swift).
//
//   vzreplay  T9, offline replay over ~/IceReverse-evidence
//   vzhelper  T13, one sacrificial status item, controlled over stdin
//   vizprobe  T13/T14, the live harness (section 6): `--dry-run` for T13's
//             own DoD, `live` for the full protocol
let package = Package(
    name: "vzreplay",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../../../../Packages/IceCore"),
        .package(path: "../../../../Packages/MenuBarCapture"),
    ],
    targets: [
        .executableTarget(
            name: "vzreplay",
            dependencies: [
                .product(name: "IceCore", package: "IceCore"),
                .product(name: "MenuBarCapture", package: "MenuBarCapture"),
            ]
        ),
        // T13: the sacrificial status item. Needs its own AppKit
        // application-delegate + DispatchSource pattern, which strict Swift
        // 6 concurrency checking does not accept without a lot of extra
        // annotation for a short-lived probe binary — the same trade-off
        // docs/macos-27/probes/safewidth/Package.swift already makes for its
        // own swhelper/swctl/swfront targets.
        .executableTarget(
            name: "vzhelper",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // T13/T14: the live protocol's controller.
        .executableTarget(
            name: "vizprobe",
            dependencies: [
                .product(name: "IceCore", package: "IceCore"),
                .product(name: "MenuBarCapture", package: "MenuBarCapture"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
