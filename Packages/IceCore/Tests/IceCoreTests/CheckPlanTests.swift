import Testing
@testable import IceCore

/// `CheckPlan.make` implements D14 (references) and D15 (adjacent items and
/// the fold region) purely from frames, before any capture runs (plan
/// section 4.1.7). Every candidate and target rule here traces to a
/// documented reason: `.positional` items never name a detector target
/// (D14/D15's boundary), a stacked item cannot be trusted to explain its own
/// ink, and a candidate must sit strictly between the divider and Ice's own
/// icon or it risks being the very thing whose image changes with state.
@Suite("CheckPlan.make: divider selection and availability")
struct CheckPlanDividerTests {
    let bounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)

    private func usable(_ frame: BarRect) -> DividerReading { DividerReading.make(frame: frame, in: bounds) }

    private func set(items: [DiscoveredItem] = [], hiddenDivider: DividerReading? = nil, alwaysHiddenDivider: DividerReading? = nil, ownRead: OwnReadStatus = .ok, visibleControlItem: DiscoveredItem? = nil) -> DiscoveredItemSet {
        fixtureSet(items: items, visibleControlItem: visibleControlItem, hiddenDivider: hiddenDivider, alwaysHiddenDivider: alwaysHiddenDivider, ownRead: ownRead)
    }

    @Test("sections containing .hidden uses the hidden divider; missing -> skip(.dividerUnavailable)")
    func hiddenSectionNeedsHiddenDivider() {
        let s = set(hiddenDivider: nil, alwaysHiddenDivider: usable(BarRect(minX: 900, minY: 0, width: 16, height: 33)))
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: nil)
        #expect(result == .skip(.dividerUnavailable))
    }

    @Test("sections not containing .hidden uses the always-hidden divider; missing -> skip(.dividerUnavailable)")
    func nonHiddenSectionNeedsAlwaysHiddenDivider() {
        let s = set(hiddenDivider: usable(BarRect(minX: 1100, minY: 0, width: 16, height: 33)), alwaysHiddenDivider: nil)
        let result = CheckPlan.make(sections: [.alwaysHidden], set: s, sectionMap: [:], explicitCandidates: nil)
        #expect(result == .skip(.dividerUnavailable))
    }

    @Test("an unusable divider reading -> skip(.dividerUnavailable)")
    func unusableDividerIsUnavailable() {
        let offBar = DividerReading.make(frame: BarRect(minX: 1100, minY: 40, width: 16, height: 33), in: bounds)
        let s = set(hiddenDivider: offBar)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: nil)
        #expect(result == .skip(.dividerUnavailable))
    }

    @Test("own read not ok -> skip(.dividerUnavailable), even with a usable divider reading")
    func ownReadNotOkIsUnavailable() {
        let s = set(hiddenDivider: usable(BarRect(minX: 1100, minY: 0, width: 16, height: 33)), ownRead: .failed)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: nil)
        #expect(result == .skip(.dividerUnavailable))
    }
}

@Suite("CheckPlan.make: targets")
struct CheckPlanTargetsTests {
    let bounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)
    let dividerFrame = BarRect(minX: 1000, minY: 0, width: 16, height: 33)

    private func item(identifier: String, pid: Int32, minX: Double, basis: IdentityBasis = .declared, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: identifier, pid: pid, childIndex: basis == .positional ? 0 : nil, basis: basis, frame: barFrame(minX: minX, width: 14), position: position)
    }

    /// A reference candidate right of the divider, present in every test so
    /// the overall plan reaches `.observe` -- these tests are about how one
    /// section-eligible item is classified into targets/skipped, not about
    /// D14's reference search (covered separately).
    private func referenceItem() -> DiscoveredItem { item(identifier: "reference", pid: 99, minX: 1100) }

    private func set(items: [DiscoveredItem]) -> DiscoveredItemSet {
        fixtureSet(items: items + [referenceItem()], hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds))
    }

    @Test("an item whose section is in `sections` and not parked becomes a target")
    func inSectionItemIsATarget() {
        let inSection = item(identifier: "a", pid: 1, minX: 800)
        let s = set(items: [inSection])
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [inSection.tagKey: .hidden], explicitCandidates: nil)
        guard case .observe(let targets, _, _, let skipped) = result else { Issue.record("expected observe"); return }
        #expect(targets == [inSection.key])
        #expect(skipped.isEmpty)
    }

    @Test("an item whose section is not in `sections` is left out entirely")
    func notInSectionIsLeftOut() {
        let outOfSection = item(identifier: "a", pid: 1, minX: 800)
        let s = set(items: [outOfSection])
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [outOfSection.tagKey: .visible], explicitCandidates: nil)
        guard case .observe(let targets, let alsoObserved, _, let skipped) = result else { Issue.record("expected observe"); return }
        #expect(targets.isEmpty)
        #expect(skipped.isEmpty)
        // Not a target (wrong section) -- but it is still a real, on-bar,
        // non-positional item left of the reference, so its ink must still
        // be explained (D15): it belongs in alsoObserved, not nowhere.
        #expect(alsoObserved.contains(outOfSection.key))
    }

    @Test("a parked item is left out entirely, even if its section is in `sections`")
    func parkedItemIsLeftOut() {
        let parked = item(identifier: "a", pid: 1, minX: 800, position: .parked)
        let s = set(items: [parked])
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [parked.tagKey: .hidden], explicitCandidates: nil)
        guard case .observe(let targets, _, _, let skipped) = result else { Issue.record("expected observe"); return }
        #expect(targets.isEmpty)
        #expect(skipped.isEmpty)
    }

    @Test("a positional item in-section is skipped(.positional), never a target")
    func positionalItemIsSkipped() {
        let positional = item(identifier: "a", pid: 1, minX: 800, basis: .positional)
        let s = set(items: [positional])
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [positional.tagKey: .hidden], explicitCandidates: nil)
        guard case .observe(let targets, _, _, let skipped) = result else { Issue.record("expected observe"); return }
        #expect(targets.isEmpty)
        #expect(skipped[positional.key] == .positional)
    }

    @Test("a stacked item in-section is skipped(.stacked), never a target")
    func stackedItemIsSkipped() {
        let stacked = item(identifier: "a", pid: 1, minX: 800, position: .stacked)
        let s = set(items: [stacked])
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [stacked.tagKey: .hidden], explicitCandidates: nil)
        guard case .observe(let targets, _, _, let skipped) = result else { Issue.record("expected observe"); return }
        #expect(targets.isEmpty)
        #expect(skipped[stacked.key] == .stacked)
    }
}

@Suite("CheckPlan.make: references (D14)")
struct CheckPlanReferencesTests {
    let bounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)

    private func item(identifier: String, pid: Int32, minX: Double, width: Double = 14, basis: IdentityBasis = .declared, position: ItemPosition = .onBar, isSelf: Bool = false) -> DiscoveredItem {
        fixtureItem(namespace: isSelf ? "IceApp" : "com.example.a", identifier: identifier, pid: pid, basis: basis, frame: barFrame(minX: minX, width: width), position: position, isSelf: isSelf)
    }

    private func set(items: [DiscoveredItem], dividerFrame: BarRect, visibleControlItem: DiscoveredItem? = nil) -> DiscoveredItemSet {
        fixtureSet(items: items, visibleControlItem: visibleControlItem, hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds))
    }

    @Test("default layout: only Ice's icon right of the divider -> skip(.noReference)")
    func defaultLayoutHasNoReference() {
        let dividerFrame = BarRect(minX: 1600, minY: 0, width: 16, height: 33)
        let iceIcon = item(identifier: "gear", pid: 900, minX: 1650, isSelf: true)
        let s = set(items: [], dividerFrame: dividerFrame, visibleControlItem: iceIcon)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: nil)
        #expect(result == .skip(.noReference))
    }

    @Test("step 5's geometry: divider minX = target maxX; a reference just right of it is a candidate by midX")
    func step5Geometry() {
        // Target chosen at (1074.5, 4.5, 14, 24) -> maxX 1088.5 = divider minX.
        // Reference raw frame (1086.5, 4.5, 14, 24) -> midX 1093.5, right of
        // the divider's minX (1088.5) even though its raw minX (1086.5) sits
        // left of it -- candidacy is judged by midX, not minX.
        let dividerFrame = BarRect(minX: 1088.5, minY: 0, width: 16, height: 33)
        let target = item(identifier: "target", pid: 1, minX: 1074.5) // maxX 1088.5 == divider minX, per the plan's recorded numbers
        let reference = item(identifier: "reference", pid: 2, minX: 1086.5)
        let s = set(items: [target, reference], dividerFrame: dividerFrame)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [target.tagKey: .hidden], explicitCandidates: nil)
        guard case .observe(_, _, let referenceCandidates, _) = result else { Issue.record("expected observe"); return }
        #expect(referenceCandidates == [reference.key])
    }

    @Test("candidates must sit left of Ice's icon's midX")
    func candidatesMustBeLeftOfIceIcon() {
        let dividerFrame = BarRect(minX: 1000, minY: 0, width: 16, height: 33)
        let beforeIcon = item(identifier: "ref", pid: 2, minX: 1100)
        let iceIcon = item(identifier: "gear", pid: 900, minX: 1200, isSelf: true) // midX 1207
        let pastIcon = item(identifier: "past", pid: 3, minX: 1300) // midX 1307, past the icon
        let s = set(items: [beforeIcon, pastIcon], dividerFrame: dividerFrame, visibleControlItem: iceIcon)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: nil)
        guard case .observe(_, _, let referenceCandidates, _) = result else { Issue.record("expected observe"); return }
        #expect(referenceCandidates == [beforeIcon.key])
    }

    @Test("two adjacent candidates that overlap after trim: only the nearer (to the divider) is kept")
    func overlappingCandidatesKeepOnlyTheNearer() {
        let dividerFrame = BarRect(minX: 1000, minY: 0, width: 16, height: 33)
        // near: minX 1050 w 14 -> maxX 1064, trimmed (1051, 1063)
        // far: minX 1062 w 14 -> maxX 1076, trimmed (1063, 1075) -- touches/overlaps near's trimmed span
        let near = item(identifier: "near", pid: 1, minX: 1050)
        let far = item(identifier: "far", pid: 2, minX: 1061) // trimmed (1062, 1074) overlaps near's trimmed (1051,1063)
        let s = set(items: [near, far], dividerFrame: dividerFrame)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: nil)
        guard case .observe(_, _, let referenceCandidates, _) = result else { Issue.record("expected observe"); return }
        #expect(referenceCandidates == [near.key])
    }

    @Test("two candidates whose trimmed frames are clear of each other are both kept, nearer first")
    func nonOverlappingCandidatesAreBothKept() {
        let dividerFrame = BarRect(minX: 1000, minY: 0, width: 16, height: 33)
        let near = item(identifier: "near", pid: 1, minX: 1050) // trimmed (1051, 1063)
        let far = item(identifier: "far", pid: 2, minX: 1100) // trimmed (1101, 1113) -- clear
        let s = set(items: [near, far], dividerFrame: dividerFrame)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: nil)
        guard case .observe(_, _, let referenceCandidates, _) = result else { Issue.record("expected observe"); return }
        #expect(referenceCandidates == [near.key, far.key])
    }

    @Test("a candidate overlapping a target after trim is excluded")
    func candidateOverlappingTargetIsExcluded() {
        let dividerFrame = BarRect(minX: 900, minY: 0, width: 16, height: 33)
        let target = item(identifier: "target", pid: 1, minX: 950) // in-section, right of divider by construction here for simplicity (sectionMap decides membership, not position)
        let overlappingCandidate = item(identifier: "cand", pid: 2, minX: 960) // trimmed (961,973) overlaps target's trimmed (951,963)
        // A clean, independent reference further out so the plan does not
        // fall through to .skip(.noReference) once the overlapping one and
        // the target itself (which also self-qualifies as a raw candidate
        // and is excluded by its own trimmed-overlap) are both rejected.
        let clean = item(identifier: "clean", pid: 3, minX: 1200)
        let s = set(items: [target, overlappingCandidate, clean], dividerFrame: dividerFrame)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [target.tagKey: .hidden], explicitCandidates: nil)
        guard case .observe(let targets, _, let referenceCandidates, _) = result else { Issue.record("expected observe"); return }
        #expect(targets == [target.key])
        #expect(!referenceCandidates.contains(overlappingCandidate.key))
        #expect(referenceCandidates.contains(clean.key))
    }

    @Test("explicitCandidates are used verbatim in place of the geometric search, still overlap-filtered")
    func explicitCandidatesAreUsed() {
        let dividerFrame = BarRect(minX: 1000, minY: 0, width: 16, height: 33)
        // This would normally not qualify (left of the divider), but explicit
        // candidates bypass the geometric eligibility search entirely.
        let explicit = item(identifier: "explicit", pid: 5, minX: 500)
        let s = set(items: [explicit], dividerFrame: dividerFrame)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: [explicit.key])
        guard case .observe(_, _, let referenceCandidates, _) = result else { Issue.record("expected observe"); return }
        #expect(referenceCandidates == [explicit.key])
    }

    @Test("at most 2 candidates are accepted even with more eligible")
    func atMostTwoCandidatesAccepted() {
        let dividerFrame = BarRect(minX: 1000, minY: 0, width: 16, height: 33)
        let a = item(identifier: "a", pid: 1, minX: 1050)
        let b = item(identifier: "b", pid: 2, minX: 1100)
        let c = item(identifier: "c", pid: 3, minX: 1150)
        let s = set(items: [a, b, c], dividerFrame: dividerFrame)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: nil)
        guard case .observe(_, _, let referenceCandidates, _) = result else { Issue.record("expected observe"); return }
        #expect(referenceCandidates.count == 2)
        #expect(referenceCandidates == [a.key, b.key])
    }
}

@Suite("CheckPlan.make: alsoObserved (D15)")
struct CheckPlanAlsoObservedTests {
    let bounds = BarBounds(minX: 0, maxX: 1728, minY: 0, barHeight: 33)

    private func item(identifier: String, pid: Int32, minX: Double, width: Double = 14, basis: IdentityBasis = .declared, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: identifier, pid: pid, basis: basis, frame: barFrame(minX: minX, width: width), position: position)
    }

    private func set(items: [DiscoveredItem], dividerFrame: BarRect) -> DiscoveredItemSet {
        fixtureSet(items: items, hiddenDivider: DividerReading.make(frame: dividerFrame, in: bounds))
    }

    @Test("everything left of the leftmost accepted candidate, not a target, is alsoObserved")
    func everythingLeftOfLeftmostCandidateIsObserved() {
        let dividerFrame = BarRect(minX: 1000, minY: 0, width: 16, height: 33)
        let farLeft = item(identifier: "far-left", pid: 1, minX: 100) // clearly left, not a target, not in-section
        let target = item(identifier: "target", pid: 2, minX: 950) // in-section
        let candidate = item(identifier: "cand", pid: 3, minX: 1100)
        let s = set(items: [farLeft, target, candidate], dividerFrame: dividerFrame)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [target.tagKey: .hidden], explicitCandidates: nil)
        guard case .observe(let targets, let alsoObserved, let referenceCandidates, _) = result else { Issue.record("expected observe"); return }
        #expect(targets == [target.key])
        #expect(referenceCandidates == [candidate.key])
        #expect(alsoObserved.contains(farLeft.key))
        #expect(!alsoObserved.contains(target.key)) // targets are tracked separately, not duplicated into alsoObserved
    }

    @Test("a stacked item is never alsoObserved")
    func stackedItemIsNeverAlsoObserved() {
        let dividerFrame = BarRect(minX: 1000, minY: 0, width: 16, height: 33)
        let stackedLeft = item(identifier: "stacked", pid: 1, minX: 100, position: .stacked)
        let candidate = item(identifier: "cand", pid: 2, minX: 1100)
        let s = set(items: [stackedLeft, candidate], dividerFrame: dividerFrame)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: nil)
        guard case .observe(_, let alsoObserved, _, _) = result else { Issue.record("expected observe"); return }
        #expect(!alsoObserved.contains(stackedLeft.key))
    }

    @Test("a positional item is never alsoObserved")
    func positionalItemIsNeverAlsoObserved() {
        let dividerFrame = BarRect(minX: 1000, minY: 0, width: 16, height: 33)
        let positionalLeft = item(identifier: "positional", pid: 1, minX: 100, basis: .positional)
        let candidate = item(identifier: "cand", pid: 2, minX: 1100)
        let s = set(items: [positionalLeft, candidate], dividerFrame: dividerFrame)
        let result = CheckPlan.make(sections: [.hidden], set: s, sectionMap: [:], explicitCandidates: nil)
        guard case .observe(_, let alsoObserved, _, _) = result else { Issue.record("expected observe"); return }
        #expect(!alsoObserved.contains(positionalLeft.key))
    }
}

@Suite("CheckPlan.references")
struct CheckPlanReferencesHelperTests {
    @Test("keeps accepted candidates in the given order, at most maxCount")
    func keepsAcceptedInOrder() {
        let a = ItemKey(namespace: "n", identifier: "a", pid: 1, childIndex: nil)
        let b = ItemKey(namespace: "n", identifier: "b", pid: 2, childIndex: nil)
        let c = ItemKey(namespace: "n", identifier: "c", pid: 3, childIndex: nil)
        let result = CheckPlan.references(candidates: [a, b, c], accepted: Set([c, a]))
        #expect(result == [a, c])
    }

    @Test("maxCount truncates even when more were accepted")
    func maxCountTruncates() {
        let a = ItemKey(namespace: "n", identifier: "a", pid: 1, childIndex: nil)
        let b = ItemKey(namespace: "n", identifier: "b", pid: 2, childIndex: nil)
        let c = ItemKey(namespace: "n", identifier: "c", pid: 3, childIndex: nil)
        let result = CheckPlan.references(candidates: [a, b, c], accepted: Set([a, b, c]), maxCount: 2)
        #expect(result == [a, b])
    }
}
