/// Section 5 step 2's scan and section 1's smoke midpoint. Standard library
/// only, like every decision in this module (I1): the stage (`vizprobe`)
/// reads the real bar and hands the plain readings in here.
public enum ScanPlanner {
    /// `L = 600, 616, ..., 896` (plan section 5 step 2): 19 lengths, one
    /// every 16 pt. `stride(from:through:by:)` never overshoots its upper
    /// bound, so the 19th and last length is 888, not 896 -- the plan's own
    /// "896" names the range's ceiling, not a length actually scanned.
    public static let lengths: [Double] = Array(stride(from: 600.0, through: 896.0, by: 16.0))

    /// One scanned length's target reading, aligned index-for-index with
    /// `lengths` by whoever builds the array (the planner itself never
    /// assumes a particular count, so a test can shape any run it likes).
    public struct Reading: Equatable, Sendable {
        public let length: Double
        public let hidden: Bool

        public init(length: Double, hidden: Bool) {
            self.length = length
            self.hidden = hidden
        }
    }

    /// Section 1: "the midpoint of its widest contiguous run" of
    /// `hidden(folded: false)` lengths -- ties broken toward the run that
    /// starts at the lower length. `nil` when no length is hidden.
    ///
    /// A run's own midpoint is its lower-index run's lower middle element
    /// when its width is even (index `start + (width - 1) / 2`, integer
    /// division): the same "ties -> lower" rule the plan states for runs
    /// applies one level down, to which of a run's own two middle lengths is
    /// reported.
    public static func midpointOfWidestHiddenRun(_ readings: [Reading]) -> Double? {
        var bestStart = -1
        var bestWidth = 0
        var currentStart = -1
        var currentWidth = 0

        for (index, reading) in readings.enumerated() {
            if reading.hidden {
                if currentWidth == 0 { currentStart = index }
                currentWidth += 1
            } else {
                currentWidth = 0
            }
            // Strict `>`, not `>=`: the first run to reach a given width
            // keeps the title on a tie, which is exactly the lower (earlier)
            // run since `readings` is scanned in ascending length order.
            if currentWidth > bestWidth {
                bestWidth = currentWidth
                bestStart = currentStart
            }
        }

        guard bestWidth > 0 else { return nil }
        let midIndex = bestStart + (bestWidth - 1) / 2
        return readings[midIndex].length
    }
}
