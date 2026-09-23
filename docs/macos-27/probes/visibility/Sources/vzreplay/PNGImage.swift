import CoreGraphics
import Foundation
import ImageIO
import IceCore
import MenuBarCapture

/// Decodes a capture PNG into IceCore's `StripImage`: sRGB RGBA8,
/// premultiplied-last, top row first, cut to 32 pt of bar height (scale 2 here,
/// so the first 64 rows; the captures are 66 px tall — the 33rd point-row
/// belongs to the window underneath, per the task brief and the plan's
/// `probes/safewidth` deviation 3).
enum PNGImage {
    /// Decodes an evidence capture into the same `StripImage` the live adapter
    /// produces — by calling the live adapter's own initializer.
    ///
    /// This file used to decode the PNG itself, with a vertical flip. MEASURED
    /// 2026-09-19: the flip inverts the rows, and cutting to the bar's height
    /// afterwards therefore kept the wrong 32 pt — the row belonging to the
    /// window under the bar, minus the bar's own top row. Every replayed
    /// verdict before this fix was taken from such a strip.
    static func decode(_ url: URL, geometry: BarGeometry) -> StripImage? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return StripImage(cgImage: image, geometry: geometry)
    }
}
