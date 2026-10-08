/// What Ice says of its hiding on macOS 27 in IceBar mode (plan
/// 2026-10-07-icebar-preference-hiding, D-c and the T3b design): one of the
/// four states, a line for the layout pane, and a line for the log that a lab
/// runner can parse.
public enum IceBarHidingStatus: Equatable, Sendable {
    /// Not IceBar mode.
    case off
    case state(PreferenceHidingState)

    /// The known limits, said with every line but a blocked one.
    static let limits = "Ice Bar on macOS 27 shows app icons and opens items with a left click."

    /// The layout pane's line; it may name items.
    public var message: String? {
        switch self {
        case .off:
            return nil
        case .state(.blocked(let reasons)):
            return reasons.first.map(Self.blockedLine)
        case .state(.verifiedHidden):
            return Self.withLimits("Ice Bar: the chosen items are hidden (checked).")
        case .state(.requestedNotVerified(let reasons)):
            if reasons.contains(.lengthNotApplied) {
                return Self.withLimits(reasons.contains(.noMembers)
                    ? "Ice Bar: nothing is left of Ice's divider, so nothing is hidden."
                    : "Ice Bar: getting ready to hide the chosen items.")
            }
            let why = reasons.first.map(Self.why) ?? Self.why(.noMembers)
            return Self.withLimits("Ice Bar: hiding requested, not verified (\(why)).")
        case .state(.visibleFailed):
            return Self.withLimits("Ice Bar: an item meant to be hidden is still drawn on the menu bar.")
        }
    }

    /// The log's line: case names and counts only, never an item's name.
    /// Pinned by `IceBarHidingStatusTests` for the lab runner (S4).
    public var logSummary: String {
        switch self {
        case .off: "off"
        case .state(.blocked(let reasons)): "blocked(\(reasons.map(Self.name).joined(separator: ",")))"
        case .state(.verifiedHidden): "verified"
        case .state(.requestedNotVerified(let reasons)): "notVerified(\(reasons.map(Self.name).joined(separator: ",")))"
        case .state(.visibleFailed(let drawn)): "failed(drawn:\(drawn.count))"
        }
    }

    private static func withLimits(_ line: String) -> String {
        "\(line) \(limits)"
    }

    private static func blockedLine(_ reason: PreferenceHidingBlockReason) -> String {
        switch reason {
        case .iceIconNotRightOfDivider(.iconLeftOfDivider):
            return IcePlacementNotice.iconLeftOfDivider.message
        case .iceIconNotRightOfDivider(.iconUnreadable):
            return "Ice's icon is not on the menu bar, so Ice hides nothing. Turn on Show Ice icon, or make room for it."
        case .iceIconNotRightOfDivider(.dividerUnusable):
            return "Ice's hidden-section divider is not on the menu bar, so Ice hides nothing."
        case .discoveryIncomplete, .ownReadNotOk:
            return "Ice could not read every menu bar item, so it hides nothing until it can."
        case .positionalItemsLeftOfDivider(let blockers):
            let names = blockers.map { $0.name ?? "an item" }.joined(separator: ", ")
            let pronoun = blockers.count == 1 ? "it" : "them"
            return "Ice cannot tell \(names) from another item of the same app, so it hides nothing. "
                + "Hold Command and drag \(pronoun) to the right of Ice's divider."
        }
    }

    private static func why(_ reason: PreferenceHidingNotVerifiedReason) -> String {
        switch reason {
        case .lengthNotApplied, .noMembers: "nothing to check"
        case .noReference: "no item to compare with"
        case .captureRefused: "the menu bar could not be captured"
        case .baselineStale: "the last check is more than ten minutes old"
        case .foldSeen: "an item may be folded behind «"
        case .membersUnchecked: "an item could not be checked"
        case .staleMembers: "an item cannot be reached right now"
        case .stackedMembers: "an item overlaps another"
        case .layoutChangePending: "the layout changed; checking again"
        }
    }

    private static func name(_ reason: PreferenceHidingBlockReason) -> String {
        switch reason {
        case .iceIconNotRightOfDivider(let placement): "\(placement)"
        case .discoveryIncomplete(.permissionDenied): "permissionDenied"
        case .discoveryIncomplete: "discoveryIncomplete"
        case .ownReadNotOk: "ownReadNotOk"
        case .positionalItemsLeftOfDivider(let blockers): "positional:\(blockers.count)"
        }
    }

    private static func name(_ reason: PreferenceHidingNotVerifiedReason) -> String {
        switch reason {
        case .lengthNotApplied: "lengthNotApplied"
        case .noMembers: "noMembers"
        case .noReference: "noReference"
        case .captureRefused: "captureRefused"
        case .baselineStale: "baselineStale"
        case .foldSeen(let tags): "folded:\(tags.count)"
        case .membersUnchecked(let tags): "unchecked:\(tags.count)"
        case .staleMembers(let tags): "stale:\(tags.count)"
        case .stackedMembers(let tags): "stacked:\(tags.count)"
        case .layoutChangePending(let change): "layoutChanged:\(change)"
        }
    }
}
