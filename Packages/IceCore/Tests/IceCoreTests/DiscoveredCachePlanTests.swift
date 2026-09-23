import Testing
@testable import IceCore

/// `DiscoveredCachePlan.make` implements D10 exactly as v5.1 section 3 writes
/// it: sections are computed only while a divider is collapsed, each
/// boundary judged independently, and every item that neither boundary
/// decides keeps its previous section by tag. Every scenario here traces to
/// a numbered case in plan section 5's T4 row -- especially the recorded
/// jump, which is the one case that would silently pass if `midX` were ever
/// compared against an *expanded* divider's frame.
@Suite("DiscoveredCachePlan.make")
struct DiscoveredCachePlanTests {
    let bounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)

    private func item(identifier: String, minX: Double?, pid: Int32 = 1) -> DiscoveredItem {
        let key = ItemKey(namespace: "com.example.a", identifier: identifier, pid: pid, childIndex: nil)
        return DiscoveredItem(
            key: key, basis: .declared,
            process: ProcessInfoRecord(pid: pid, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
            frame: minX.map { BarRect(minX: $0, minY: 4.5, width: 20, height: 24) },
            position: .onBar, title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
        )
    }

    private func parkedItem(identifier: String, pid: Int32 = 1) -> DiscoveredItem {
        let key = ItemKey(namespace: "com.example.a", identifier: identifier, pid: pid, childIndex: nil)
        return DiscoveredItem(
            key: key, basis: .declared,
            process: ProcessInfoRecord(pid: pid, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
            frame: BarRect(minX: 7, minY: 1105, width: 24, height: 24),
            position: .parked, title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
        )
    }

    private func set(items: [DiscoveredItem], hiddenDivider: DividerReading?, alwaysHiddenDivider: DividerReading?, ownRead: OwnReadStatus = .ok, visibleControlItem: DiscoveredItem? = nil) -> DiscoveredItemSet {
        DiscoveredItemSet(
            items: items, visibleControlItem: visibleControlItem, hiddenDivider: hiddenDivider, alwaysHiddenDivider: alwaysHiddenDivider,
            ownRead: ownRead, systemElements: [], dropped: [], completeness: .complete
        )
    }

    private func collapsed(_ frame: BarRect, for collapsedFor: Double = 5, changedDuringPass: Bool = false, isEnabled: Bool = true) -> DividerState {
        DividerState(isEnabled: isEnabled, isCollapsed: true, collapsedFor: collapsedFor, changedDuringPass: changedDuringPass)
    }

    private func expanded(isEnabled: Bool = true) -> DividerState {
        DividerState(isEnabled: isEnabled, isCollapsed: false, collapsedFor: 0, changedDuringPass: false)
    }

    @Test("untrusted / permissionDenied -> keepPrevious")
    func permissionDeniedKeepsPrevious() {
        let untrustedSet = DiscoveredItemSet(items: [], visibleControlItem: nil, hiddenDivider: nil, alwaysHiddenDivider: nil, ownRead: .notRead, systemElements: [], dropped: [], completeness: .permissionDenied)
        let result = DiscoveredCachePlan.make(set: untrustedSet, dividerStates: DividerStates(hidden: expanded(), alwaysHidden: expanded()), previous: [:])
        #expect(result == .keepPrevious(.permissionDenied))
    }

    @Test("complete-but-empty publishes with empty sections")
    func completeButEmptyPublishesEmpty() {
        let s = set(items: [], hiddenDivider: DividerReading.make(frame: BarRect(minX: 1100, minY: 0, width: 16, height: 33), in: bounds), alwaysHiddenDivider: nil)
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(BarRect(minX: 1100, minY: 0, width: 16, height: 33)), alwaysHidden: expanded()), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.visible.isEmpty && pub.hidden.isEmpty && pub.alwaysHidden.isEmpty)
    }

    @Test("a collapsed chevron-size divider splits items by midX; both boundaries known routes visible/hidden/alwaysHidden")
    func collapsedDividerSplitsByMidX() {
        let hiddenFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let alwaysHiddenFrame = BarRect(minX: 900, minY: 0, width: 16, height: 33)
        let rightOfHidden = item(identifier: "right", minX: 1100, pid: 1) // midX 1110 >= 1100 -> visible
        let betweenBoundaries = item(identifier: "between", minX: 950, pid: 2) // midX 960: < 1100, >= 900 -> hidden (undecided by either, falls to previous/new)
        let leftOfAlwaysHidden = item(identifier: "left", minX: 850, pid: 3) // midX 860 < 900 -> alwaysHidden
        let s = set(items: [rightOfHidden, betweenBoundaries, leftOfAlwaysHidden], hiddenDivider: DividerReading.make(frame: hiddenFrame, in: bounds), alwaysHiddenDivider: DividerReading.make(frame: alwaysHiddenFrame, in: bounds))
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(hiddenFrame), alwaysHidden: collapsed(alwaysHiddenFrame)), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[rightOfHidden.tagKey] == .visible)
        #expect(pub.sectionMap[leftOfAlwaysHidden.tagKey] == .alwaysHidden)
        // betweenBoundaries: the known hidden boundary says it is not visible
        // (midX < hidden.minX); the known always-hidden boundary says it is not
        // always-hidden (midX >= alwaysHidden.minX). Both boundaries decide it:
        // hidden. (D10: "not visible iff midX < hidden.minX; among those,
        // alwaysHidden iff midX < alwaysHidden.minX".)
        #expect(pub.sectionMap[betweenBoundaries.tagKey] == .hidden)
    }

    @Test("the recorded jump: item minX 984 -> 1016 (w 14) against an EXPANDED divider at 1012 (w 5002) keeps its previous section")
    func recordedJumpKeepsPreviousSection() {
        // 2026-09-18 measurement (plan section 0): the item settled at AX
        // x=1016, w=14 -- to the RIGHT of the expanded divider's own minX
        // (1012). If midX were ever compared against an expanded divider's
        // frame, this item (midX 1023 >= 1012) would misread visible; D10
        // requires the boundary to be unknown while expanded, so it must
        // instead keep whatever section it held before the jump.
        let key = ItemKey(namespace: "com.example.a", identifier: "jumped", pid: 1, childIndex: nil)
        let jumped = DiscoveredItem(
            key: key, basis: .declared,
            process: ProcessInfoRecord(pid: 1, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: 10, isSelf: false),
            frame: BarRect(minX: 1016, minY: 4.5, width: 14, height: 24), position: .onBar,
            title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
        )
        let dividerFrame = BarRect(minX: 1012, minY: 0, width: 5002, height: 33)
        let s = set(items: [jumped], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let previous: [TagKey: ItemSection] = [jumped.tagKey: .hidden]
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: expanded(), alwaysHidden: expanded()), previous: previous)
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[jumped.tagKey] == .hidden)
        #expect(pub.hidden.map(\.key.identifier) == ["jumped"])
        #expect(pub.visible.isEmpty)
    }

    @Test("collapsedFor 0.9 s (< settleSeconds 1.0) -> settling, boundary unknown, item keeps previous section")
    func settlingBelowThreshold() {
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let it = item(identifier: "x", minX: 1200) // would be visible if known
        let s = set(items: [it], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let previous: [TagKey: ItemSection] = [it.tagKey: .hidden]
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame, for: 0.9), alwaysHidden: expanded()), previous: previous)
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[it.tagKey] == .hidden)
        #expect(pub.notes.contains(.hidden(.settling)))
    }

    @Test("changedDuringPass -> boundary unknown, item keeps previous section, note .changedDuringPass")
    func changedDuringPassKeepsPrevious() {
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let it = item(identifier: "x", minX: 1200)
        let s = set(items: [it], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let previous: [TagKey: ItemSection] = [it.tagKey: .alwaysHidden]
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame, changedDuringPass: true), alwaysHidden: expanded()), previous: previous)
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[it.tagKey] == .alwaysHidden)
        #expect(pub.notes.contains(.hidden(.changedDuringPass)))
    }

    @Test("midX exactly equal to the hidden divider's minX -> visible (>=, not >)")
    func midXEqualToMinXIsVisible() {
        let dividerFrame = BarRect(minX: 1000, minY: 0, width: 16, height: 33)
        let it = item(identifier: "x", minX: 990) // width 20 -> midX 1000, equal to divider minX
        let s = set(items: [it], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: expanded()), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[it.tagKey] == .visible)
    }

    @Test("hidden boundary unknown, always-hidden boundary known: every item tested against always-hidden's minX")
    func hiddenUnknownAlwaysHiddenKnown() {
        let alwaysHiddenFrame = BarRect(minX: 900, minY: 0, width: 16, height: 33)
        let leftOfAH = item(identifier: "left", minX: 850) // midX 860 < 900 -> alwaysHidden
        let rightOfAH = item(identifier: "right", minX: 950) // midX 960 >= 900 -> not decided by AH; hidden unknown too -> new -> visible
        let s = set(items: [leftOfAH, rightOfAH], hiddenDivider: nil, alwaysHiddenDivider: DividerReading.make(frame: alwaysHiddenFrame, in: bounds))
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: expanded(), alwaysHidden: collapsed(alwaysHiddenFrame)), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[leftOfAH.tagKey] == .alwaysHidden)
        #expect(pub.sectionMap[rightOfAH.tagKey] == .visible)
        #expect(pub.notes.contains(.hidden(.missing)))
    }

    @Test("always-hidden disabled: previous alwaysHidden items become hidden")
    func alwaysHiddenDisabledMovesPreviousItemsToHidden() {
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let it = item(identifier: "x", minX: 1200) // decided visible by hidden boundary actually (midX 1210 >= 1100)
        let leftIt = item(identifier: "left", minX: 1000, pid: 2) // midX 1010 < 1100 -> not decided visible; AH disabled -> falls to previous
        let s = set(items: [it, leftIt], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let previous: [TagKey: ItemSection] = [leftIt.tagKey: .alwaysHidden]
        let result = DiscoveredCachePlan.make(
            set: s,
            dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: DividerState(isEnabled: false, isCollapsed: false, collapsedFor: 0, changedDuringPass: false)),
            previous: previous
        )
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[leftIt.tagKey] == .hidden)
        #expect(pub.alwaysHidden.isEmpty)
        #expect(pub.notes.contains(.alwaysHidden(.disabled)))
    }

    @Test("a new item (no previous section) with both boundaries undecided -> visible")
    func newItemBothUndecidedIsVisible() {
        let it = item(identifier: "brand-new", minX: 500)
        let s = set(items: [it], hiddenDivider: nil, alwaysHiddenDivider: nil)
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: expanded(), alwaysHidden: expanded()), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[it.tagKey] == .visible)
    }

    @Test("a no-frame item keeps its previous section; without one it is visible")
    func noFrameItemKeepsPreviousOrIsVisible() {
        let noFrame = item(identifier: "no-frame", minX: nil)
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let s = set(items: [noFrame], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)

        let resultNoPrevious = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: expanded()), previous: [:])
        guard case .publish(let pub1) = resultNoPrevious else { Issue.record("expected publish"); return }
        #expect(pub1.sectionMap[noFrame.tagKey] == .visible)

        // A frame that could not be read must not move an item the user placed.
        let resultWithPrevious = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: expanded()), previous: [noFrame.tagKey: .hidden])
        guard case .publish(let pub2) = resultWithPrevious else { Issue.record("expected publish"); return }
        #expect(pub2.sectionMap[noFrame.tagKey] == .hidden)
    }

    @Test("left of a known hidden boundary is never visible: a new item there is hidden (always-hidden disabled)")
    func newItemLeftOfKnownHiddenBoundaryIsHidden() {
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let left = item(identifier: "new-left", minX: 1000) // midX 1010 < 1100
        let s = set(items: [left], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let disabled = DividerState(isEnabled: false, isCollapsed: false, collapsedFor: 0, changedDuringPass: false)
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: disabled), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[left.tagKey] == .hidden)
    }

    @Test("left of a known hidden boundary with the always-hidden boundary unknown: previous alwaysHidden kept, previous visible or none -> hidden")
    func leftOfKnownHiddenWithUnknownAlwaysHidden() {
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let wasAH = item(identifier: "was-ah", minX: 900, pid: 1)
        let wasVisible = item(identifier: "was-visible", minX: 950, pid: 2)
        let isNew = item(identifier: "new", minX: 1000, pid: 3)
        let s = set(items: [wasAH, wasVisible, isNew], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let previous: [TagKey: ItemSection] = [wasAH.tagKey: .alwaysHidden, wasVisible.tagKey: .visible]
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: expanded()), previous: previous)
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[wasAH.tagKey] == .alwaysHidden)
        #expect(pub.sectionMap[wasVisible.tagKey] == .hidden)
        #expect(pub.sectionMap[isNew.tagKey] == .hidden)
    }

    @Test("right of a known always-hidden boundary is never always-hidden, even if it was before")
    func rightOfKnownAlwaysHiddenIsNotAlwaysHidden() {
        let alwaysHiddenFrame = BarRect(minX: 900, minY: 0, width: 16, height: 33)
        let wasAH = item(identifier: "was-ah", minX: 950) // midX 960 >= 900
        let s = set(items: [wasAH], hiddenDivider: nil, alwaysHiddenDivider: DividerReading.make(frame: alwaysHiddenFrame, in: bounds))
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: expanded(), alwaysHidden: collapsed(alwaysHiddenFrame)), previous: [wasAH.tagKey: .alwaysHidden])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[wasAH.tagKey] == .hidden)
    }

    @Test("a previous map from a carried pass is honoured the same as any other previous map")
    func previousMapFromCarriedPassIsHonoured() {
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let it = item(identifier: "carried-item", minX: 1000) // midX 1010 -- not decided visible
        let s = set(items: [it], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let previous: [TagKey: ItemSection] = [it.tagKey: .alwaysHidden] // as if this came from a pass where the item was carried
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: expanded(isEnabled: false)), previous: previous)
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        // always-hidden disabled -> previous alwaysHidden becomes hidden
        #expect(pub.sectionMap[it.tagKey] == .hidden)
    }

    @Test("both dividers missing -> both boundaries unknown, items keep previous or default to visible if new")
    func bothDividersMissing() {
        let known = item(identifier: "known", minX: 500)
        let unknown = item(identifier: "unknown", minX: 600, pid: 2)
        let s = set(items: [known, unknown], hiddenDivider: nil, alwaysHiddenDivider: nil)
        let previous: [TagKey: ItemSection] = [known.tagKey: .hidden]
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: expanded(), alwaysHidden: expanded()), previous: previous)
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[known.tagKey] == .hidden)
        #expect(pub.sectionMap[unknown.tagKey] == .visible) // new item
        #expect(pub.notes.contains(.hidden(.missing)))
        #expect(pub.notes.contains(.alwaysHidden(.missing)))
    }

    @Test("own read failed -> both boundaries unknown with .ownReadFailed")
    func ownReadFailedMakesBoundariesUnknown() {
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let it = item(identifier: "x", minX: 1200)
        let s = set(items: [it], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil, ownRead: .failed)
        let previous: [TagKey: ItemSection] = [it.tagKey: .hidden]
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: expanded()), previous: previous)
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.sectionMap[it.tagKey] == .hidden) // kept previous
        #expect(pub.notes.contains(.hidden(.ownReadFailed)))
    }

    @Test("own read identifiersMissing -> both boundaries unknown with .identifiersMissing")
    func ownReadIdentifiersMissing() {
        let it = item(identifier: "x", minX: 1200)
        let s = set(items: [it], hiddenDivider: nil, alwaysHiddenDivider: nil, ownRead: .identifiersMissing)
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: expanded(), alwaysHidden: expanded()), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.notes.contains(.hidden(.identifiersMissing)))
    }

    @Test("an unusable divider reading (off the bar vertically) -> boundary unknown with .unusable")
    func unusableDividerReading() {
        let offBar = BarRect(minX: 1100, minY: 40, width: 16, height: 33) // minY past barHeight
        let it = item(identifier: "x", minX: 1200)
        let s = set(items: [it], hiddenDivider: DividerReading.make(frame: offBar, in: bounds), alwaysHiddenDivider: nil)
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(offBar), alwaysHidden: expanded()), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.notes.contains(.hidden(.unusable)))
    }

    @Test("an expanded divider -> boundary unknown with .expanded")
    func expandedDividerNote() {
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let it = item(identifier: "x", minX: 1200)
        let s = set(items: [it], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: expanded(), alwaysHidden: expanded()), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.notes.contains(.hidden(.expanded)))
    }

    @Test("parked items and dropped items are left out of every section")
    func parkedItemsAreLeftOut() {
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let parked = parkedItem(identifier: "parked")
        let s = set(items: [parked], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: expanded()), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.visible.isEmpty && pub.hidden.isEmpty && pub.alwaysHidden.isEmpty)
        #expect(pub.sectionMap[parked.tagKey] == nil)
    }

    @Test("the visibleControlItem is placed like any other item")
    func visibleControlItemIsPlacedLikeAnyItem() {
        let dividerFrame = BarRect(minX: 1100, minY: 0, width: 16, height: 33)
        let ownKey = ItemKey(namespace: "IceApp", identifier: "gear", pid: 900, childIndex: nil)
        let ownItem = DiscoveredItem(
            key: ownKey, basis: .declared,
            process: ProcessInfoRecord(pid: 900, bundleID: "IceApp", localizedName: nil, executableName: nil, launchTime: 10, isSelf: true),
            frame: BarRect(minX: 1600, minY: 4.5, width: 20, height: 24), position: .onBar,
            title: nil, description: nil, help: nil, carriedPasses: 0, lastConfirmedAt: 0
        )
        let s = set(items: [], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil, visibleControlItem: ownItem)
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: expanded()), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.visible.map(\.key) == [ownItem.key])
        #expect(pub.sectionMap[ownItem.tagKey] == .visible)
    }

    @Test("each section's output is ordered by minX, no-frame last")
    func sectionOutputIsOrderedByMinX() {
        let dividerFrame = BarRect(minX: 0, minY: 0, width: 16, height: 33) // everything is visible
        let a = item(identifier: "a", minX: 500)
        let b = item(identifier: "b", minX: 100, pid: 2)
        let c = item(identifier: "c", minX: nil, pid: 3)
        let s = set(items: [a, b, c], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds), alwaysHiddenDivider: nil)
        let result = DiscoveredCachePlan.make(set: s, dividerStates: DividerStates(hidden: collapsed(dividerFrame), alwaysHidden: expanded()), previous: [:])
        guard case .publish(let pub) = result else { Issue.record("expected publish"); return }
        #expect(pub.visible.map(\.key.identifier) == ["b", "a", "c"])
    }
}
