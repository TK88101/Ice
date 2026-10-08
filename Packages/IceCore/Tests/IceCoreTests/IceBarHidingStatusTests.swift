import Testing
@testable import IceCore

/// What the layout pane says for each of the four states, and the log line a
/// lab runner parses (plan 2026-10-07-icebar-preference-hiding, D-c and the
/// T3b design). The log line carries case names and counts, never a name.
@Suite("IceBarHidingStatus")
struct IceBarHidingStatusTests {
    static let limits = " Ice Bar on macOS 27 shows app icons and opens items with a left click."

    static func tag(_ title: String) -> TagKey {
        TagKey(namespace: "com.example.\(title)", title: "\(title)/p1")
    }

    static func blocker(_ name: String?) -> PreferenceHidingBlocker {
        let key = ItemKey(namespace: "com.example.a", identifier: "shared", pid: 7, childIndex: 0)
        return PreferenceHidingBlocker(key: key, tag: key.tagKey(isSelf: false), name: name)
    }

    func message(_ state: PreferenceHidingState) -> String? {
        IceBarHidingStatus.state(state).message
    }

    func blocked(_ reason: PreferenceHidingBlockReason) -> String? {
        message(.blocked(reasons: [reason]))
    }

    @Test("off says nothing")
    func off() {
        #expect(IceBarHidingStatus.off.message == nil)
        #expect(IceBarHidingStatus.off.logSummary == "off")
    }

    @Test("blocked names the first failing precondition and, where there is one, the repair")
    func blockedLines() {
        #expect(blocked(.iceIconNotRightOfDivider(.iconLeftOfDivider)) == IcePlacementNotice.iconLeftOfDivider.message)
        #expect(blocked(.iceIconNotRightOfDivider(.iconUnreadable))
            == "Ice's icon is not on the menu bar, so Ice hides nothing. Turn on Show Ice icon, or make room for it.")
        #expect(blocked(.iceIconNotRightOfDivider(.dividerUnusable))
            == "Ice's hidden-section divider is not on the menu bar, so Ice hides nothing.")
        for reason in [PreferenceHidingBlockReason.discoveryIncomplete(.incomplete(failedPIDs: [3])), .discoveryIncomplete(.permissionDenied), .ownReadNotOk(.failed)] {
            #expect(blocked(reason) == "Ice could not read every menu bar item, so it hides nothing until it can.")
        }
        #expect(message(.blocked(reasons: [.discoveryIncomplete(.permissionDenied), .iceIconNotRightOfDivider(.iconUnreadable)]))
            == "Ice could not read every menu bar item, so it hides nothing until it can.")
    }

    @Test("a positional item is named so the owner can move it; one without a name is 'an item'")
    func positionalLines() {
        #expect(blocked(.positionalItemsLeftOfDivider([Self.blocker("Wi-Fi")]))
            == "Ice cannot tell Wi-Fi from another item of the same app, so it hides nothing. Hold Command and drag it to the right of Ice's divider.")
        #expect(blocked(.positionalItemsLeftOfDivider([Self.blocker("Wi-Fi"), Self.blocker(nil)]))
            == "Ice cannot tell Wi-Fi, an item from another item of the same app, so it hides nothing. Hold Command and drag them to the right of Ice's divider.")
    }

    @Test("verified, getting ready, nothing to hide, failed")
    func otherLines() {
        #expect(message(.verifiedHidden) == "Ice Bar: the chosen items are hidden (checked)." + Self.limits)
        #expect(message(.requestedNotVerified(reasons: [.lengthNotApplied])) == "Ice Bar: getting ready to hide the chosen items." + Self.limits)
        #expect(message(.requestedNotVerified(reasons: [.lengthNotApplied, .noMembers]))
            == "Ice Bar: nothing is left of Ice's divider, so nothing is hidden." + Self.limits)
        #expect(message(.visibleFailed(drawn: [Self.tag("a")])) == "Ice Bar: an item meant to be hidden is still drawn on the menu bar." + Self.limits)
    }

    @Test("not verified at a length says so, and why, by its first reason", arguments: [
        (PreferenceHidingNotVerifiedReason.noReference, "no item to compare with"),
        (.captureRefused, "the menu bar could not be captured"),
        (.baselineStale, "the last check is more than ten minutes old"),
        (.foldSeen([tag("a")]), "an item may be folded behind «"),
        (.membersUnchecked([tag("a")]), "an item could not be checked"),
        (.staleMembers([tag("a")]), "an item cannot be reached right now"),
        (.stackedMembers([tag("a")]), "an item overlaps another"),
        (.layoutChangePending(.frontmostAppChanged), "the layout changed; checking again"),
        (.noMembers, "nothing to check"),
    ])
    func notVerifiedLines(reason: PreferenceHidingNotVerifiedReason, why: String) {
        #expect(message(.requestedNotVerified(reasons: [reason, .layoutChangePending(.spaceChanged)]))
            == "Ice Bar: hiding requested, not verified (\(why))." + Self.limits)
    }

    @Test("the log line: case names and counts, in the rule's order")
    func logSummaries() {
        let positional = PreferenceHidingBlockReason.positionalItemsLeftOfDivider([Self.blocker("Wi-Fi"), Self.blocker(nil)])
        #expect(IceBarHidingStatus.state(.blocked(reasons: [
            .iceIconNotRightOfDivider(.iconLeftOfDivider), .iceIconNotRightOfDivider(.iconUnreadable), .iceIconNotRightOfDivider(.dividerUnusable),
            .discoveryIncomplete(.incomplete(failedPIDs: [3])), .discoveryIncomplete(.permissionDenied), .ownReadNotOk(.notRead), positional,
        ])).logSummary == "blocked(iconLeftOfDivider,iconUnreadable,dividerUnusable,discoveryIncomplete,permissionDenied,ownReadNotOk,positional:2)")
        #expect(IceBarHidingStatus.state(.verifiedHidden).logSummary == "verified")
        #expect(IceBarHidingStatus.state(.requestedNotVerified(reasons: [
            .lengthNotApplied, .noMembers, .noReference, .captureRefused, .baselineStale, .foldSeen([Self.tag("a")]),
            .membersUnchecked([Self.tag("a"), Self.tag("b")]), .staleMembers([Self.tag("c")]), .stackedMembers([Self.tag("d")]),
            .layoutChangePending(.menuWidthChanged),
        ])).logSummary == "notVerified(lengthNotApplied,noMembers,noReference,captureRefused,baselineStale,folded:1,unchecked:2,stale:1,stacked:1,layoutChanged:menuWidthChanged)")
        #expect(IceBarHidingStatus.state(.visibleFailed(drawn: [Self.tag("a"), Self.tag("b")])).logSummary == "failed(drawn:2)")
    }

    @Test("the log line never carries an item's name")
    func logSummaryHasNoNames() {
        let summary = IceBarHidingStatus.state(.blocked(reasons: [.positionalItemsLeftOfDivider([Self.blocker("Secret App")])])).logSummary
        #expect(!summary.contains("Secret"))
    }
}
