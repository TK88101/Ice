import AppKit
import CoreGraphics
import IceCore

/// The display half of one discovery pass (plan section 4.2): the bar's own
/// display-local extent, and where that display's origin sits in the global
/// Accessibility coordinate space. `MenuBarDiscoverer` subtracts `origin`
/// from every AX frame so IceCore only ever sees display-local frames --
/// exactly the mismatch `LiveMenuBarAXReader`'s own doc comment calls out
/// (plan section 0).
public protocol DisplayProviding: Sendable {
    func bar() -> (bounds: BarBounds, origin: (x: Double, y: Double))?
}

/// The screen `screen` returns -- `NSScreen.main` unless the caller passes
/// the one hosting the active menu bar, as Ice does, so discovery, the cache's
/// display and the check's captures all describe the same display (plan
/// section 4.2). Bounds are display-local (`minX` 0,
/// `maxX` the screen's own width); the origin is read the same way
/// `LiveMenuBarAXReader.init(screen:)` reads it, but computed locally rather
/// than by depending on MenuBarCapture (D5: that dependency belongs to
/// `MenuBarDetectorFeed`, not this target).
///
/// Untestable here (live `NSScreen`/`NSStatusBar`) -- exercised only by
/// `mbdiscover`'s smoke run.
public struct LiveDisplay: DisplayProviding {
    private let screen: @Sendable () -> NSScreen?

    public init(screen: @escaping @Sendable () -> NSScreen? = { NSScreen.main }) {
        self.screen = screen
    }

    public func bar() -> (bounds: BarBounds, origin: (x: Double, y: Double))? {
        guard let screen = screen() else { return nil }
        let displayID = Self.directDisplayID(for: screen) ?? CGMainDisplayID()
        let originPoint = CGDisplayBounds(displayID).origin

        let width = Double(screen.frame.width)
        guard width > 0 else { return nil }

        let safeAreaTop = Double(screen.safeAreaInsets.top)
        let barHeight = safeAreaTop > 0 ? safeAreaTop : Double(NSStatusBar.system.thickness)

        let bounds = BarBounds(minX: 0, maxX: width, minY: 0, barHeight: barHeight)
        return (bounds, (Double(originPoint.x), Double(originPoint.y)))
    }

    private static func directDisplayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
