// swift-tools-version: 6.0
import PackageDescription

// The visibility detector's probes for macOS 27
// (docs/plans/2026-09-19-visibility-adapter.md). Not linked into Ice.
// ImageIO/CoreGraphics/AppKit are fine here — only IceCore itself must stay
// free of them (Packages/IceCore/Package.swift).
//
//   vzreplay  T9, offline replay over ~/IceReverse-evidence
//   vzhelper  T13, sacrificial status items, controlled over stdin (T8a of
//             docs/plans/2026-09-23-ax-discovery.md adds --items,
//             --identifiers, --glyphs, --mimic-nodivider, --autosave)
//   vizprobe  T13/T14, the live harness (section 6): `--dry-run` for T13's
//             own DoD, `live` for the full protocol; T8a adds the
//             `discover` and `verify` stages of the 2026-09-23 plan
//   VZGlyphs  the helpers' glyphs, shared so vizprobe's dry run can check
//             that they are pairwise distinct under IceCore's own rules
//   IceWatchCore / icewatch  docs/plans/2026-09-24-ice-first-run.md
//             section 5: the first run's supervisor, recorder, watchdog and
//             restorer. IceWatchCore holds the pure rules (Foundation only,
//             no AppKit, no Accessibility) and is the only tested target
let package = Package(
    name: "vzreplay",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../../../../Packages/IceCore"),
        .package(path: "../../../../Packages/MenuBarCapture"),
        .package(path: "../../../../Packages/MenuBarDiscovery"),
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
        .target(
            name: "VZGlyphs",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "vzhelper",
            dependencies: ["VZGlyphs"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // T13/T14: the live protocol's controller.
        .executableTarget(
            name: "vizprobe",
            dependencies: [
                "VZGlyphs",
                .product(name: "IceCore", package: "IceCore"),
                .product(name: "MenuBarCapture", package: "MenuBarCapture"),
                .product(name: "MenuBarDiscovery", package: "MenuBarDiscovery"),
                .product(name: "MenuBarDetectorFeed", package: "MenuBarDiscovery"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(name: "IceWatchCore"),
        .executableTarget(
            name: "icewatch",
            dependencies: [
                "IceWatchCore",
                .product(name: "IceCore", package: "IceCore"),
                .product(name: "MenuBarDiscovery", package: "MenuBarDiscovery"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "IceWatchCoreTests", dependencies: ["IceWatchCore"]),
    ]
)
