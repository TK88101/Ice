/// What an item's own AX frame claims about where it sits, as a pure
/// function of frames (plan section 4.1.4). Diagnostic except `.parked`,
/// which callers must not list (plan section 2, "position"): `.stacked` and
/// `.noFrame` are still shown, because D8 revised "invalidate on stacked" —
/// an item overlapping another is still an item.
///
/// Position is never drawn-ness. AX frames on macOS 27 can describe an item
/// that was not actually painted that frame (the 2026-09-18 measurements
/// found exactly this: a helper's frame sat clear of every obstacle while the
/// item itself was not drawn) and can just as easily describe one that was
/// drawn stacked under another. Only `MenuBarItemVisibility`, reading pixels,
/// is allowed to say what was drawn.
public enum ItemPosition: Equatable, Sendable {
    case onBar
    case parked
    case stacked
    case noFrame
}

public enum PositionRule {
    /// An overlap must exceed this fraction of the *narrower* of the two
    /// frames to count as stacked. Set above the 2 pt (~6%) AX padding
    /// overlap measured between every adjacent pair of drawn items at rest
    /// on 2026-09-23 -- at 6%, a 25% threshold leaves ordinary neighbours
    /// alone -- and comfortably below the 54.3-67.9% overlap recorded for
    /// items caught behind the overflow chevron on 2026-09-18.
    public static let stackedFraction = 0.25

    /// `frame` is the item being placed; `bounds` is its own display's
    /// extent; `obstacles` must be the on-bar frames of *other* extras only
    /// -- **never Ice's own items**. Ice's control items are not "another
    /// extra" for this purpose: the divider that arranges the bar is not an
    /// obstacle to the items it arranges, and callers that fed it in would
    /// see items beside a collapsed divider misreported as stacked.
    public static func position(of frame: BarRect?, in bounds: BarBounds, obstacles: [BarRect]) -> ItemPosition {
        guard let frame else { return .noFrame }

        // Judged by minX alone, deliberately: an item that started on the bar
        // and was later expanded far past bounds.maxX (the 2026-09-18
        // 5002 pt spacer) is still an on-bar item that grew, not one parked
        // off it.
        let belowBar = frame.minY >= bounds.minY + bounds.barHeight
        let leftOfBar = frame.minX < bounds.minX
        let rightOfBar = frame.minX >= bounds.maxX
        if belowBar || leftOfBar || rightOfBar {
            return .parked
        }

        for obstacle in obstacles {
            let overlap = min(frame.maxX, obstacle.maxX) - max(frame.minX, obstacle.minX)
            guard overlap > 0 else { continue }
            let narrower = min(frame.width, obstacle.width)
            guard narrower > 0, overlap > stackedFraction * narrower else { continue }
            return .stacked
        }

        return .onBar
    }
}
