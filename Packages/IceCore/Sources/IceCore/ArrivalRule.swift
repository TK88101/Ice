/// On a system that lists no pushed-off item (`BlindAtLength`) an item that
/// appears left of the lengthened divider is in no read: a new app's item, or
/// the item of a member's app that started again. It is read at the next
/// trusted pass at standard length (plan 2026-11-15-blind-at-length, D4).
public enum ArrivalRule {
    /// How long after its start an app may take to put its item on the bar.
    /// INFERRED; a pass sooner than this may have missed it.
    public static let grace = 3.0

    /// Whether a re-read at standard length is owed before the IceBar lists
    /// the members: an app was started, and no trusted standard-length pass
    /// has begun `grace` or more after the last start. Times are uptimes.
    /// A pass begun sooner does not pay: it may have missed that app's item,
    /// and the next asking reads again.
    public static func isRereadOwed(lastLaunchAt: Double?, trustedPassBeganAt: Double?, grace: Double = grace) -> Bool {
        guard let lastLaunchAt else { return false }
        guard let trustedPassBeganAt else { return true }
        return trustedPassBeganAt < lastLaunchAt + grace
    }
}
