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
    /// - Parameter warmUpCount: the captures that settle the strip before a
    ///   session reads it; the hiding check keeps the default, IceBar's
    ///   hidden-length observer passes fewer (plan 2026-10-03-icebar-build, 9.3).
    public static func live(screen: NSScreen, ownIdentifiers: OwnIdentifiers, warmUpCount: Int = 24) -> HidingVerification {
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
            },
            warmUpCount: warmUpCount
        )
    }
}

extension ChevronReader {
    /// `MenuBarAgent`'s frames on `screen`'s bar, read as the detector reads
    /// them; `nil` without a bar geometry.
    public static func live(screen: NSScreen) -> ChevronReader? {
        guard let geometry = BarGeometry(screen: screen) else { return nil }
        let originPoint = CGDisplayBounds(screen.directDisplayID ?? CGMainDisplayID()).origin
        let reader = DiscoveredFrameReader(
            extras: LiveExtrasReader(readsLabels: false),
            apps: LiveRunningApps(),
            origin: DiscoveryOrigin(x: Double(originPoint.x), y: Double(originPoint.y))
        )
        return ChevronReader(reader: reader, barHeight: geometry.heightPt)
    }
}

extension HiddenLengthObserver {
    /// One second of warm-up instead of the hiding check's six: a calibration
    /// takes about fifteen observations. INFERRED, judged in T7 (plan 9.3, R6).
    public static let liveWarmUpCount = 4

    /// The live observer for `screen`; `nil` without a bar geometry.
    public static func live(screen: NSScreen, ownIdentifiers: OwnIdentifiers) -> HiddenLengthObserver? {
        guard let chevron = ChevronReader.live(screen: screen) else { return nil }
        let verification = HidingVerification.live(screen: screen, ownIdentifiers: ownIdentifiers, warmUpCount: liveWarmUpCount)
        return HiddenLengthObserver(verification: verification, chevron: chevron)
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
