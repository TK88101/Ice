// Which MenuBarAgent item is the microphone pill, and whether it is drawn.
//
// The overflow chevron `«` is also a MenuBarAgent item left of every third-party
// item, so position cannot tell the two apart. Colour cannot either: requiring
// the pill's orange before calling an item the pill hides exactly the pill the
// guard exists to catch — one pushed out of the bar draws no orange at all. So
// the chevron is identified positively, by its AX width, and every other
// candidate is the pill.

/// One MenuBarAgent item standing where the pill would: left of every
/// third-party item on the bar.
public struct PillCandidate: Equatable, Sendable {
    public let width: Double
    /// Pixels of the pill's orange inside the item's own AX span.
    public let orange: Int

    public init(width: Double, orange: Int) {
        self.width = width
        self.orange = orange
    }
}

public enum PillIdentity {
    /// The chevron's AX width: 17.5 pt in every one of the ≈ 8 900
    /// new-MenuBarAgent readings of the 2026-09-18 runs. The pill's own AX
    /// width has never been recorded; it only has to differ from this.
    public static let chevronWidth = 17.5
    public static let chevronWidthTolerance = 1.0

    /// The pill as the guard should read it, or nil when no candidate is the pill.
    /// Any candidate showing the orange is a drawn pill; otherwise any candidate
    /// that is not chevron-wide is a pill AX knows about and the screen does not show.
    public static func reading(_ candidates: [PillCandidate], orangeMinimum: Int) -> PillReading? {
        if candidates.contains(where: { $0.orange >= orangeMinimum }) {
            return PillReading(axPresent: true, pixelPresent: true)
        }
        if candidates.contains(where: { abs($0.width - chevronWidth) > chevronWidthTolerance }) {
            return PillReading(axPresent: true, pixelPresent: false)
        }
        return nil
    }
}
