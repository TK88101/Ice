import Testing
@testable import IceCore

/// macOS 27.2 lists no status item that is pushed off the bar, Ice's own
/// lengthened divider included: a pass at a hiding length reads Ice's icon and
/// no hidden divider (plan 2026-11-15-blind-at-length, F2 and D1). Such a pass
/// is not an own read that failed.
@Suite("BlindAtLength")
struct BlindAtLengthTests {
    static let hiding = DividerState(isEnabled: true, isCollapsed: false, collapsedFor: 0, changedDuringPass: false)
    static let standard = DividerState(isEnabled: true, isCollapsed: true, collapsedFor: 5, changedDuringPass: false)
    static let icon = fixtureItem(
        namespace: "io.github.tk88101.Ice", identifier: "Ice.ControlItem.Visible", pid: 99,
        frame: barFrame(minX: 1344, width: 35), isSelf: true
    )

    /// What a pass reads of Ice itself at a hiding length on 27.2.
    static func read(
        icon: DiscoveredItem? = icon,
        ownRead: OwnReadStatus = .identifiersMissing,
        completeness: Completeness = .complete
    ) -> DiscoveredItemSet {
        fixtureSet(items: [], visibleControlItem: icon, ownRead: ownRead, completeness: completeness)
    }

    static func holds(
        _ set: DiscoveredItemSet = read(),
        state: DividerState = hiding,
        holdsWrittenLength: Bool = true,
        hasMembers: Bool = true
    ) -> Bool {
        BlindAtLength.holds(set: set, hiddenDividerState: state, holdsWrittenLength: holdsWrittenLength, hasMembers: hasMembers)
    }

    @Test("D1: the icon listed and the divider not, in a complete pass, at the length Ice holds, with members: blind")
    func allFiveHold() {
        #expect(Self.holds())
    }

    @Test("D1 (1): Ice's own state does not hold the written length: not blind")
    func lengthNotHeld() {
        #expect(!Self.holds(holdsWrittenLength: false))
    }

    @Test("D1: the divider at standard length for the whole pass, or disabled (changed or not): not blind", arguments: [
        standard,
        DividerState(isEnabled: false, isCollapsed: false, collapsedFor: 0, changedDuringPass: false),
        DividerState(isEnabled: false, isCollapsed: false, collapsedFor: 0, changedDuringPass: true),
    ])
    func dividerStateSaysOtherwise(state: DividerState) {
        #expect(!Self.holds(state: state))
    }

    @Test("D1: the divider's state changed while the pass ran: blind, at whatever length it began and whatever Ice holds now", arguments: [
        DividerState(isEnabled: true, isCollapsed: false, collapsedFor: 0, changedDuringPass: true),
        DividerState(isEnabled: true, isCollapsed: true, collapsedFor: 5, changedDuringPass: true),
    ])
    func straddlesAChange(state: DividerState) {
        #expect(Self.holds(state: state, holdsWrittenLength: true))
        #expect(Self.holds(state: state, holdsWrittenLength: false))
        #expect(!Self.holds(Self.read(icon: nil), state: state), "the icon must still be listed")
        #expect(!Self.holds(Self.read(ownRead: .failed), state: state), "a failed own read is a failed own read")
        #expect(!Self.holds(state: state, hasMembers: false))
    }

    @Test("D1 (3): a pass that is not complete: not blind", arguments: [
        Completeness.incomplete(failedPIDs: [7]), .permissionDenied,
    ])
    func passNotComplete(completeness: Completeness) {
        #expect(!Self.holds(Self.read(completeness: completeness)))
    }

    @Test("D1 (4): the own read failed, was not made, or lists the divider: not blind", arguments: [
        OwnReadStatus.failed, .notRead, .ok,
    ])
    func ownReadSaysOtherwise(ownRead: OwnReadStatus) {
        #expect(!Self.holds(Self.read(ownRead: ownRead)))
    }

    @Test("D1 (4): the own read does not list Ice's icon: not blind")
    func iconNotListed() {
        #expect(!Self.holds(Self.read(icon: nil)))
    }

    @Test("D1 (5): a roster without members: not blind")
    func noMembers() {
        #expect(!Self.holds(hasMembers: false))
    }

    // MARK: - The preconditions of a blind pass (D2)

    static func preconditions(
        placement: PreferenceHidingIconPlacement? = nil,
        completeness: Completeness = .complete,
        ownRead: OwnReadStatus = .identifiersMissing,
        isBlindAtLength: Bool
    ) -> PreferenceHidingPreconditionResult {
        PreferenceHidingPreconditions.evaluate(
            iconPlacement: placement, completeness: completeness, ownRead: ownRead, blockers: [], isBlindAtLength: isBlindAtLength
        )
    }

    @Test("D2: a blind pass's missing divider is no reason to block")
    func blindDoesNotBlock() {
        #expect(Self.preconditions(isBlindAtLength: true) == .ok)
    }

    @Test("D2: the same reading when the pass is not blind blocks as before")
    func notBlindBlocks() {
        #expect(Self.preconditions(isBlindAtLength: false) == .blocked([.ownReadNotOk(.identifiersMissing)]))
    }

    @Test("D2: a blind pass excuses nothing but the missing divider")
    func blindExcusesOnlyTheDivider() {
        #expect(Self.preconditions(placement: .iconUnreadable, isBlindAtLength: true)
            == .blocked([.iceIconNotRightOfDivider(.iconUnreadable)]))
        #expect(Self.preconditions(completeness: .incomplete(failedPIDs: [7]), isBlindAtLength: true)
            == .blocked([.discoveryIncomplete(.incomplete(failedPIDs: [7]))]))
        #expect(Self.preconditions(ownRead: .failed, isBlindAtLength: true) == .blocked([.ownReadNotOk(.failed)]))
    }
}
