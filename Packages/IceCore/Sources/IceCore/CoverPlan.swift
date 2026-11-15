/// Plan 2026-11-15-cover. On macOS 27 one status item length is shared by every
/// display's bar, and on a bar without a notch no length hides the hidden
/// section's items (MEASURED 2026-11-15). Where `MenuBarAgent` still lays a
/// member out, Ice covers its slot with what lies below the menu bar there.
/// These are the pure rules: which slots a hit test must confirm (D1), the
/// blocks the confirmed ones make, and the budget of image calls (D2).

/// One item slot on a bar, as `MenuBarAgent`'s Accessibility tree lists it:
/// the owning app's pid and the slot's extent in display-local points.
public struct CoverSlot: Hashable, Sendable {
    public let owner: Int32
    public let minX: Double
    public let maxX: Double

    public init(owner: Int32, minX: Double, maxX: Double) {
        self.owner = owner
        self.minX = minX
        self.maxX = maxX
    }
}

public enum CoverPlan {
    /// Verified slots this close together make one block.
    public static let mergeGap = 4.0
    /// The system's capture dot moves every item 3 pt for 10-20 s.
    public static let padding = 4.0

    /// The pids all of whose discovered items are hidden-section members. The
    /// tree gives a slot's owner, not which of its items it is, so a pid that
    /// also owns a visible item is never covered.
    public static func coverable(memberOwners: [Int32], visibleOwners: [Int32]) -> Set<Int32> {
        Set(memberOwners).subtracting(visibleOwners)
    }

    /// The slots a hit test must confirm: every slot of a coverable owner,
    /// once, left to right. A stale window's slots are among them.
    public static func candidates(slots: [CoverSlot], coverable: Set<Int32>) -> [CoverSlot] {
        Set(slots.filter { coverable.contains($0.owner) }).sorted { ($0.minX, $0.maxX) < ($1.minX, $1.maxX) }
    }

    /// Where a slot is hit-tested: a slot half under another app's window is
    /// still found.
    public static func verificationPoints(_ slot: CoverSlot) -> [Double] {
        let width = slot.maxX - slot.minX
        return [0.25, 0.5, 0.75].map { slot.minX + width * $0 }
    }

    /// A candidate stands when its owner is hit at some point and no other
    /// item is hit at any; `nil` is empty bar or another app's window above.
    public static func isVerified(owner: Int32, hits: [Int32?]) -> Bool {
        hits.contains(owner) && hits.allSatisfy { $0 == nil || $0 == owner }
    }

    /// The blocks to cover: the verified slots, merged when `mergeGap` or
    /// less apart, each side padded by up to `padding` but never into a slot
    /// of `others` (every other slot of the same reading), clipped to the bar
    /// and kept out of the notch.
    public static func blocks(
        verified: [CoverSlot], others: [CoverSlot], barWidth: Double, notch: ClosedRange<Double>?
    ) -> [ClosedRange<Double>] {
        let members = Set(verified)
        var merged = [(lower: Double, upper: Double)]()
        for slot in members.sorted(by: { ($0.minX, $0.maxX) < ($1.minX, $1.maxX) }) {
            if let last = merged.last, slot.minX - last.upper <= mergeGap {
                merged[merged.count - 1].upper = max(last.upper, slot.maxX)
            } else {
                merged.append((slot.minX, slot.maxX))
            }
        }
        let outside = others.filter { !members.contains($0) }
        return merged.flatMap { block -> [ClosedRange<Double>] in
            let leftLimit = outside.map(\.maxX).filter { $0 <= block.lower }.max() ?? 0
            let rightLimit = outside.map(\.minX).filter { $0 >= block.upper }.min() ?? barWidth
            let lower = max(block.lower - padding, leftLimit, 0)
            let upper = min(block.upper + padding, rightLimit, barWidth)
            guard lower < upper else { return [] }
            return clip(lower...upper, outOf: notch)
        }
    }

    private static func clip(_ range: ClosedRange<Double>, outOf notch: ClosedRange<Double>?) -> [ClosedRange<Double>] {
        guard let notch, range.overlaps(notch) else { return [range] }
        var parts = [ClosedRange<Double>]()
        if range.lowerBound < notch.lowerBound { parts.append(range.lowerBound...notch.lowerBound) }
        if range.upperBound > notch.upperBound { parts.append(notch.upperBound...range.upperBound) }
        return parts
    }
}

/// D2: every WindowServer image call of the app is counted here. Single
/// captures do not summon the system's violet capture block; a session of
/// seconds does (FINDINGS 2026-10-09). At most `maxCalls` within `window`
/// seconds of a session's first call, then none until `rest` seconds after it.
public struct CoverCaptureBudget: Equatable, Sendable {
    public static let maxCalls = 4
    public static let window = 1.0
    public static let rest = 12.0

    private var sessionStart: Double?
    private var calls = 0

    public init() {}

    /// Whether `count` image calls may be made now; when they may, they are counted.
    public mutating func take(_ count: Int, now: Double) -> Bool {
        guard count > 0, count <= Self.maxCalls else { return false }
        if let sessionStart, now < sessionStart + Self.rest {
            guard now - sessionStart <= Self.window, calls + count <= Self.maxCalls else { return false }
            calls += count
            return true
        }
        sessionStart = now
        calls = count
        return true
    }

    /// The earliest time a call may be made.
    public func nextAllowed(now: Double) -> Double {
        guard let sessionStart, now < sessionStart + Self.rest else { return now }
        return now - sessionStart <= Self.window && calls < Self.maxCalls ? now : sessionStart + Self.rest
    }
}
