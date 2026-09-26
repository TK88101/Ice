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
//   C1Core    docs/plans/2026-09-26-c1-protocol.md section 7, I1: the C1
//             protocol's pure decisions (scan planner, preflight order and
//             roster-snapshot checks, baseline-equivalence, the latch, run
//             accounting, the spacer command parser). Standard library
//             only, like IceWatchCore -- 100% line coverage.
//   C1Live    section 7, I3/I4/I5's testable seams (the latching capturer,
//             the C1 discoverer, the stage's dry-run/trip command
//             sequencing) -- the live protocol pieces that need
//             MenuBarCapture/MenuBarDetectorFeed to state their contracts
//             but must still be reachable from a test target with fakes.
//   C1Stage   rework #5, step A: the C1 stage orchestration itself
//             (`StageC1*.swift`) moved out of the `vizprobe` executable so a
//             test target can reach it. Driven entirely through
//             `C1StageEnvironment` (capturer, discoverer, AX reader
//             factories, geometry, helper launcher, helper defaults, pump,
//             caffeinate, evidence sink, trust check) -- no AppKit, no
//             concrete live process/screen types. `vizprobe c1` builds the
//             one real `C1StageEnvironment` and hands it to `StageC1`.
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
            // I2: the spacer role's `length <pt>`/`rest` commands are
            // parsed by C1Core's own pure parser, not reimplemented here.
            dependencies: ["VZGlyphs", "C1Core"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // T13/T14: the live protocol's controller.
        .executableTarget(
            name: "vizprobe",
            dependencies: [
                "VZGlyphs",
                "C1Core",
                "C1Live",
                "C1Stage",
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
        // C1 protocol (I1): pure decisions only, standard library only.
        .target(name: "C1Core"),
        .testTarget(name: "C1CoreTests", dependencies: ["C1Core"]),
        // C1 protocol (I3/I4/I5): the live seams, testable with fakes.
        .target(
            name: "C1Live",
            dependencies: [
                "C1Core",
                .product(name: "IceCore", package: "IceCore"),
                .product(name: "MenuBarCapture", package: "MenuBarCapture"),
                .product(name: "MenuBarDiscovery", package: "MenuBarDiscovery"),
                .product(name: "MenuBarDetectorFeed", package: "MenuBarDiscovery"),
            ]
        ),
        .testTarget(name: "C1LiveTests", dependencies: ["C1Live"]),
        // C1 protocol rework #5, step A: the stage orchestration itself,
        // moved out of `vizprobe` so `C1StageTests` can drive the real code
        // (I7) through a fake `C1StageEnvironment`.
        .target(
            name: "C1Stage",
            dependencies: [
                "C1Core",
                "C1Live",
                .product(name: "IceCore", package: "IceCore"),
                .product(name: "MenuBarCapture", package: "MenuBarCapture"),
                .product(name: "MenuBarDiscovery", package: "MenuBarDiscovery"),
                .product(name: "MenuBarDetectorFeed", package: "MenuBarDiscovery"),
            ],
            // This is a verbatim migration of code written under
            // `vizprobe`'s own v5 mode (Sendable was never enforced at
            // those call sites) -- v5 here too, so step A stays a pure
            // move with no incidental Sendable-conformance changes to
            // `StageC1`'s own types. `C1StageEnvironment`'s seam protocols
            // are still fully usable from a Swift 6 test target either way.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Amendment v8a: C1Core is added directly so the fake bar can
        // reach `PlacementPlan`/`PreferredPositionKey` when modelling the
        // "honoured preferred position" scenarios -- `C1Stage` already
        // depends on it, but Swift needs the direct import to see it too.
        .testTarget(name: "C1StageTests", dependencies: ["C1Stage", "C1Live", "C1Core"]),
    ]
)
