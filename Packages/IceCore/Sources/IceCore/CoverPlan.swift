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

/// What a hit test at one point of a bar answered. `silent` is the call
/// failing with `kAXErrorNotImplemented`: nothing there that answers -- empty
/// bar, a gap between slots, another app's window above, one of Ice's own
/// panels while it takes mouse events, or an item whose app answers no hit
/// test on that bar (MEASURED 2026-11-15: an app without a main menu, on a bar
/// other than the one its own status window lies on). `failed` is any other
/// error, a timeout included: it says nothing either way.
public enum CoverHit: Equatable, Sendable {
    case owner(Int32)
    case silent
    case failed
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

    /// A candidate stands by the hit test when its owner is hit at some point
    /// and no other item is hit at any; a point that is silent or failed
    /// neither confirms nor vetoes.
    public static func isVerified(owner: Int32, hits: [CoverHit]) -> Bool {
        hits.contains(.owner(owner)) && !hits.contains { hit in
            if case .owner(let other) = hit { other != owner } else { false }
        }
    }

    /// Nothing answered at any of a candidate's points: its app may be one
    /// that answers no hit test there (`CoverSilentTrack`).
    public static func isSilent(_ hits: [CoverHit]) -> Bool {
        !hits.isEmpty && hits.allSatisfy { $0 == .silent }
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

/// Amendment B of plan 2026-11-15-cover: a member whose app answers no hit
/// test on a bar cannot be confirmed there, and stayed drawn (MEASURED, T5 runs
/// 3-5). Such a candidate stands on the tree's word instead: listed with the
/// same owner and the same frame, silent at every point, in `passesToStand`
/// consecutive passes `passSpacing` or more apart, and overlapped by no
/// distinct slot of the read. Silence
/// is not emptiness, so this is a bounded guess, not a confirmation: another
/// item hit there, a failed call, a moved frame or an overlap ends it at once.
public struct CoverSilentTrack: Equatable, Sendable {
    public static let passesToStand = 3
    /// Passes closer together than this count once: two reads of one moment
    /// are one observation (the controller's ticks are a second apart, and it
    /// passes again at once when a capture is owed).
    public static let passSpacing = 0.9
    /// A frame within this of the last pass's is the same slot.
    public static let frameTolerance = 1.0
    /// The width the tree gives Ice's hidden divider at the applied length.
    public static let ownDividerWidth = 16.0

    private struct Entry: Equatable, Sendable {
        let slot: CoverSlot
        let passes: Int
        /// When the last pass that counted was made.
        let countedAt: Double
    }

    private let entries: [Entry]

    public init() {
        entries = []
    }

    private init(entries: [Entry]) {
        self.entries = entries
    }

    /// The slots that stand, as the last pass listed them, left to right.
    public var standing: [CoverSlot] {
        entries.filter { $0.passes >= Self.passesToStand }.map(\.slot)
    }

    /// Whether `slot` stands as this read lists things: it stood, and no
    /// distinct slot overlaps it now. A slot that stands lies under its panel
    /// and is hit-tested only when the panels are opened for it.
    public func stands(_ slot: CoverSlot, among slots: [CoverSlot], own: Int32) -> Bool {
        passes(of: slot) >= Self.passesToStand && !Self.isOverlapped(slot, among: slots, own: own)
    }

    /// The track after one pass made at `now`. `hits` holds what a hit test
    /// answered at the points of each candidate tested in it; a candidate
    /// without an entry was not tested, which only one that stands may be.
    /// `own` is Ice's pid.
    public func advanced(
        candidates: [CoverSlot], hitVerified: [CoverSlot], slots: [CoverSlot], hits: [CoverSlot: [CoverHit]], own: Int32, now: Double
    ) -> CoverSilentTrack {
        let confirmed = Set(hitVerified)
        let next = candidates.compactMap { candidate -> Entry? in
            guard !confirmed.contains(candidate), !Self.isOverlapped(candidate, among: slots, own: own) else { return nil }
            let before = entry(of: candidate)
            guard let answers = hits[candidate] else {
                guard let before, before.passes >= Self.passesToStand else { return nil }
                return Entry(slot: candidate, passes: before.passes, countedAt: before.countedAt)
            }
            guard CoverPlan.isSilent(answers) else { return nil }
            guard let before else { return Entry(slot: candidate, passes: 1, countedAt: now) }
            guard now - before.countedAt >= Self.passSpacing else {
                return Entry(slot: candidate, passes: before.passes, countedAt: before.countedAt)
            }
            return Entry(slot: candidate, passes: min(before.passes + 1, Self.passesToStand), countedAt: now)
        }
        return CoverSilentTrack(entries: next)
    }

    private func entry(of slot: CoverSlot) -> Entry? {
        entries.first { Self.isSame($0.slot, slot) }
    }

    private func passes(of slot: CoverSlot) -> Int {
        entry(of: slot)?.passes ?? 0
    }

    private static func isSame(_ one: CoverSlot, _ other: CoverSlot) -> Bool {
        one.owner == other.owner && abs(one.minX - other.minX) <= frameTolerance && abs(one.maxX - other.maxX) <= frameTolerance
    }

    /// Whether a distinct slot of the read reaches into it. The same slot
    /// listed again by another window with that bar's frame is no other slot.
    private static func isOverlapped(_ slot: CoverSlot, among slots: [CoverSlot], own: Int32) -> Bool {
        slots.contains { other in
            other != slot && other.minX < slot.maxX && slot.minX < other.maxX && !isOwnDivider(other, inside: slot, own: own)
        }
    }

    /// Ice's hidden divider as the tree lists it at the applied length: a
    /// slot of Ice's own, `ownDividerWidth` wide, inside the last member's
    /// slot at its right edge (MEASURED, T5: `[624, 640]` within `[602, 640]`).
    /// Only that shape is no overlap; any other slot of Ice's is one, its icon
    /// (33 pt) among them.
    private static func isOwnDivider(_ other: CoverSlot, inside slot: CoverSlot, own: Int32) -> Bool {
        other.owner == own && other.minX >= slot.minX && abs(other.maxX - slot.maxX) <= frameTolerance
            && abs((other.maxX - other.minX) - ownDividerWidth) <= frameTolerance
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
