import AppKit
import CoreGraphics
import IceCore

/// The screen facts `BarGeometry` needs, abstracted so the geometry logic can
/// be exercised without a real display. A live `NSScreen` conforms via the
/// extension in `LiveStripCapturer.swift`; tests use a plain fake instead of
/// standing up AppKit.
public protocol ScreenGeometrySource {
    /// The screen's own frame, in its own coordinate space, points.
    var boundsPt: CGRect { get }
    var backingScaleFactor: CGFloat { get }
    /// The menu bar's height on this screen -- `NSScreen.safeAreaInsets.top`,
    /// the notch's height on a notched display, and the plan's chosen source
    /// for the bar's height (docs/plans/2026-09-19-visibility-adapter.md
    /// section 4) rather than a hard-coded constant.
    var menuBarHeightPt: CGFloat { get }
    /// `auxiliaryTopLeftArea?.maxX` / `auxiliaryTopRightArea?.minX`: the
    /// notch's x-span, in the same coordinate space as `boundsPt`. `nil` on a
    /// display with no notch.
    var notchLeftMaxX: CGFloat? { get }
    var notchRightMinX: CGFloat? { get }
}

extension BarGeometry {
    /// Reads the bar's geometry from a screen: width and scale from its
    /// bounds and backing scale factor, height from the safe-area top inset,
    /// and the notch's x-span translated onto the bar's own axis (0 at the
    /// screen's own left edge, matching a capture cropped to that screen).
    ///
    /// `nil` when the screen reports no usable bar height or width. The plan
    /// does not name this case outright: an external, non-notched display's
    /// `safeAreaInsets.top` is zero, and handing that straight to
    /// `BarGeometry`'s memberwise initializer would trip its own
    /// precondition instead of failing cleanly.
    public init?(screen: some ScreenGeometrySource) {
        let heightPt = Double(screen.menuBarHeightPt)
        let widthPt = Double(screen.boundsPt.width)
        guard heightPt > 0, widthPt > 0, screen.backingScaleFactor > 0 else {
            return nil
        }

        let notch: PtSpan?
        if let leftMaxX = screen.notchLeftMaxX, let rightMinX = screen.notchRightMinX {
            let originX = Double(screen.boundsPt.minX)
            let lo = Double(leftMaxX) - originX
            let hi = Double(rightMinX) - originX
            notch = lo < hi ? PtSpan(lo: lo, hi: hi) : nil
        } else {
            notch = nil
        }

        self.init(widthPt: widthPt, heightPt: heightPt, scale: Double(screen.backingScaleFactor), notch: notch)
    }
}


public extension NSScreen {
    /// The display this screen is, as CoreGraphics numbers them. Read in one
    /// place: the capture rect and the Accessibility origin both need it, and
    /// two spellings of the same lookup fail differently on a second display.
    var directDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
