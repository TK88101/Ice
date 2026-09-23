// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MenuBarDiscovery",
    platforms: [
        // Matches Ice's deployment target (Packages/IceCore/Package.swift).
        .macOS(.v14),
    ],
    products: [
        .library(name: "MenuBarDiscovery", targets: ["MenuBarDiscovery"]),
        .library(name: "MenuBarDetectorFeed", targets: ["MenuBarDetectorFeed"]),
    ],
    dependencies: [
        .package(name: "IceCore", path: "../IceCore"),
        .package(name: "MenuBarCapture", path: "../MenuBarCapture"),
    ],
    targets: [
        // The AX walk (plan section 4.2): read-only adapters that turn a live
        // menu bar into IceCore's plain values, plus the pure-Swift
        // MenuBarDiscoverer orchestration around them. AppKit and
        // ApplicationServices only -- no CoreGraphics window-list or capture
        // API, and no dependency on MenuBarCapture (D5: that dependency
        // belongs to MenuBarDetectorFeed, a second library target this
        // package gains in T7, which will depend on ../MenuBarCapture).
        .target(
            name: "MenuBarDiscovery",
            dependencies: [
                .product(name: "IceCore", package: "IceCore"),
            ]
        ),
        .testTarget(
            name: "MenuBarDiscoveryTests",
            dependencies: ["MenuBarDiscovery"]
        ),
        // The detector's caller-side feed (plan section 4.3, T7): turns a
        // fresh AX discovery pass into the frames `MenuBarCapture`'s frozen
        // detector reads, and runs the prepare/verify sessions around it
        // (D16, D19). Depends on MenuBarDiscovery and MenuBarCapture; the
        // detector itself (IceCore, MenuBarCapture) is never modified here.
        .target(
            name: "MenuBarDetectorFeed",
            dependencies: [
                "MenuBarDiscovery",
                .product(name: "MenuBarCapture", package: "MenuBarCapture"),
                .product(name: "IceCore", package: "IceCore"),
            ]
        ),
        .testTarget(
            name: "MenuBarDetectorFeedTests",
            dependencies: [
                "MenuBarDetectorFeed",
                "MenuBarDiscovery",
                .product(name: "MenuBarCapture", package: "MenuBarCapture"),
                .product(name: "IceCore", package: "IceCore"),
            ]
        ),
        // Read-only CLI (plan section 4.2): prints one discovery pass, the
        // 27 cache plan, or checks a discovery against frozen labels (T6).
        // Never writes an AX attribute, performs an action, or captures the
        // screen.
        .executableTarget(
            name: "mbdiscover",
            dependencies: ["MenuBarDiscovery"]
        ),
    ]
)
