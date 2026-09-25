import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDiscovery

/// The live composition (plan section 4.3): a real `MenuBarDiscoverer`, a
/// real `CGWindowListStripCapturer`, a `DiscoveredFrameReader` wired to the
/// live AX seams, `BarGeometry(screen:)`, and `Preflight.run` exactly as
/// `MenuBarCapture`'s own live callers use it.
///
/// Kept in its own file, alongside `MenuBarDiscovery`'s own
/// `LiveExtrasReader.swift`/`DisplayProviding.swift` and `mbdiscover`, so it
/// can be excluded from coverage the same way (A2b: "excluding the live
/// factory") -- untested here, touching a real screen, real Accessibility,
/// or real AppKit; exercised only by T8b's live run.
extension HidingVerification {
    public static func live(screen: NSScreen, ownIdentifiers: OwnIdentifiers) -> HidingVerification {
        // `NSScreen` is not `Sendable`; every seam below only ever reads its
        // frame/scale/notch geometry, which does not change across a run, so
        // boxing it `@unchecked` is safe here.
        let screenBox = UncheckedBox(screen)
        let capturer = CGWindowListStripCapturer(screenProvider: { screenBox.value })
        // Frames only: the check never needs an item's labels.
        let extras = LiveExtrasReader(readsLabels: false)
        let discoverer = MenuBarDiscoverer(
            apps: LiveRunningApps(),
            reader: extras,
            display: LiveDisplay(screen: { screenBox.value }),
            isTrusted: { AXIsProcessTrusted() },
            ownIdentifiers: ownIdentifiers,
            now: { ProcessInfo.processInfo.systemUptime }
        )
        let originPoint = CGDisplayBounds(screen.directDisplayID ?? CGMainDisplayID()).origin
        let liveOrigin = DiscoveryOrigin(x: Double(originPoint.x), y: Double(originPoint.y))

        return HidingVerification(
            discoverer: discoverer,
            capturer: capturer,
            readerFactory: { origin in
                DiscoveredFrameReader(extras: extras, apps: LiveRunningApps(), origin: origin)
            },
            geometry: {
                BarGeometry(screen: screenBox.value)
            },
            preflight: {
                guard let geometry = BarGeometry(screen: screenBox.value) else {
                    return .unavailable(.captureUnavailable)
                }
                let reader = DiscoveredFrameReader(extras: extras, apps: LiveRunningApps(), origin: liveOrigin)
                return Preflight.run(capturer: capturer, axReader: reader, geometry: geometry)
            }
        )
    }
}

/// A minimal `@unchecked Sendable` box for a value this file needs to move
/// across the `@Sendable` closures above without asserting the value's own
/// type is Sendable -- used only for `NSScreen` here, which is read-only
/// from every seam that touches it.
private final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
