import AppKit
import CoreGraphics
import IceCore

extension NSScreen: ScreenGeometrySource {
    public var boundsPt: CGRect { frame }
    public var menuBarHeightPt: CGFloat { safeAreaInsets.top }
    public var notchLeftMaxX: CGFloat? { auxiliaryTopLeftArea?.maxX }
    public var notchRightMinX: CGFloat? { auxiliaryTopRightArea?.minX }
}

/// Captures the bar's rect with `CGWindowListCreateImage`.
///
/// MEASURED 2026-09-19 on this machine
/// (docs/plans/2026-09-19-visibility-adapter.md section 4, T0): 5-9 ms warm,
/// against ScreenCaptureKit's `SCScreenshotManager` at 267-412 ms warm and
/// 2.1-2.6 s cold. The fold bracket (capture -> AX -> capture, racing a
/// ≈0.1 s AX lag) cannot afford the slow path.
///
/// `CGWindowListCreateImage` is deprecated as of macOS 14 and **obsoleted as
/// of macOS 15** (SDK `CGWindow.h:271-283`). It compiles here only because
/// this package's deployment target is `.macOS(.v14)`, matching Ice's;
/// raising either target to 15 removes the symbol and forces a move to
/// ScreenCaptureKit, which would need the fold bracket re-measured (plan,
/// section 8, risks).
///
/// Read-only: this never creates, moves, or focuses a window, and it never
/// launches anything.
public struct CGWindowListStripCapturer: StripCapturing {
    private let screenProvider: @Sendable () -> NSScreen?

    public init(screenProvider: @escaping @Sendable () -> NSScreen? = { NSScreen.main }) {
        self.screenProvider = screenProvider
    }

    public func capture() -> StripImage? {
        guard let screen = screenProvider(), let geometry = BarGeometry(screen: screen) else {
            return nil
        }
        guard let rect = Self.captureRect(for: screen, barHeightPt: geometry.heightPt) else {
            return nil
        }
        guard let cgImage = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else {
            return nil
        }
        return StripImage(cgImage: cgImage, geometry: geometry)
    }

    /// The bar's rect in the global display space `CGWindowListCreateImage`
    /// expects (top-left origin, points): the screen's actual pixel bounds
    /// via its `CGDirectDisplayID`, not a manual flip of `NSScreen.frame`,
    /// which uses AppKit's own bottom-left-origin space.
    static func captureRect(for screen: NSScreen, barHeightPt: Double) -> CGRect? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let bounds = CGDisplayBounds(number.uint32Value)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: barHeightPt)
    }
}
