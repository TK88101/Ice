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
    /// A line and the limits after it.
    static let joinTemplate = "%@ %@"

    static let verified = "Ice Bar: the chosen items are hidden (checked)."
    static let nothingLeft = "Ice Bar: nothing is left of Ice's divider, so nothing is hidden."
    static let gettingReady = "Ice Bar: getting ready to hide the chosen items."
    static let notVerified = "Ice Bar: hiding requested, not verified (%@)."
    static let stillDrawn = "Ice Bar: an item meant to be hidden is still drawn on the menu bar."
    static let iconUnreadable = "Ice's icon is not on the menu bar, so Ice hides nothing. Turn on Show Ice icon, or make room for it."
    static let dividerUnusable = "Ice's hidden-section divider is not on the menu bar, so Ice hides nothing."
    static let incomplete = "Ice could not read every menu bar item, so it hides nothing until it can."
    static let positionalOne = "Ice cannot tell %@ from another item of the same app, so it hides nothing. "
        + "Hold Command and drag it to the right of Ice's divider."
    static let positionalMany = "Ice cannot tell %@ from another item of the same app, so it hides nothing. "
        + "Hold Command and drag them to the right of Ice's divider."
    static let anItem = "an item"
    static let whys = [
        "nothing to check", "checking once more", "no item to compare with", "the menu bar could not be captured",
        "the last check is more than ten minutes old", "an item may be folded behind «", "an item could not be checked",
        "an item cannot be reached right now", "an item overlaps another", "the layout changed; checking again",
    ]

    /// Every template of this type (`OwnerMessage.allTemplates`).
    static var templates: [String] {
        [
            verified, nothingLeft, gettingReady, notVerified, stillDrawn, iconUnreadable, dividerUnusable, incomplete,
            positionalOne, positionalMany, anItem,
        ] + whys
    }

    /// The layout pane's line, as data; it may name items.
    public var ownerMessage: OwnerMessage? {
        switch self {
        case .off:
            return nil
        case .state(.blocked(let reasons)):
            return reasons.first.map(Self.blockedLine)
        case .state(.verifiedHidden):
            return Self.withLimits(OwnerMessage(Self.verified))
        case .state(.requestedNotVerified(let reasons)):
            if reasons.contains(.lengthNotApplied) {
                return Self.withLimits(OwnerMessage(reasons.contains(.noMembers) ? Self.nothingLeft : Self.gettingReady))
            }
            let why = reasons.first.map(Self.why) ?? Self.why(.noMembers)
            return Self.withLimits(OwnerMessage(Self.notVerified, .message(OwnerMessage(why))))
        case .state(.visibleFailed):
            return Self.withLimits(OwnerMessage(Self.stillDrawn))
        }
    }

    /// The layout pane's line in English (`ownerMessage` looked up as itself).
    public var message: String? {
        ownerMessage?.rendered()
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

    private static func withLimits(_ line: OwnerMessage) -> OwnerMessage {
        OwnerMessage(joinTemplate, .message(line), .message(OwnerMessage(limits)))
    }

    private static func blockedLine(_ reason: PreferenceHidingBlockReason) -> OwnerMessage {
        switch reason {
        case .iceIconNotRightOfDivider(.iconLeftOfDivider):
            return IcePlacementNotice.iconLeftOfDivider.ownerMessage
        case .iceIconNotRightOfDivider(.iconUnreadable):
            return OwnerMessage(iconUnreadable)
        case .iceIconNotRightOfDivider(.dividerUnusable):
            return OwnerMessage(dividerUnusable)
        case .discoveryIncomplete, .ownReadNotOk:
            return OwnerMessage(incomplete)
        case .positionalItemsLeftOfDivider(let blockers):
            let names = blockers.map { blocker -> OwnerMessage.Argument in
                blocker.name.map(OwnerMessage.Argument.verbatim) ?? .message(OwnerMessage(anItem))
            }
            return OwnerMessage(blockers.count == 1 ? positionalOne : positionalMany, .list(names))
        }
    }

    private static func why(_ reason: PreferenceHidingNotVerifiedReason) -> String {
        switch reason {
        case .lengthNotApplied, .noMembers: whys[0]
        case .confirming: whys[1]
        case .noReference: whys[2]
        case .captureRefused: whys[3]
        case .baselineStale: whys[4]
        case .foldSeen: whys[5]
        case .membersUnchecked: whys[6]
        case .staleMembers: whys[7]
        case .stackedMembers: whys[8]
        case .layoutChangePending: whys[9]
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
        case .confirming: "confirming"
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
