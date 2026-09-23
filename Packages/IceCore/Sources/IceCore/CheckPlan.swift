/// D14 (references) and D15 (adjacent items and the fold region), decided
/// purely from frames, before any capture runs (plan section 4.1.7).

/// What `CheckPlan.make` decided: either the section cannot be checked at
/// all, or exactly what to observe.
public enum CheckPlanResult: Equatable, Sendable {
    case skip(CheckSkipReason)
    /// `targets` are the items whose result will be reported; `alsoObserved`
    /// are the other listed items whose ink must be explained so it cannot
    /// be mistaken for a target's (D15); `referenceCandidates` are the
    /// static items the baseline will try to template; `skipped` names why
    /// an item that belongs to `sections` was left out of `targets`.
    case observe(targets: [ItemKey], alsoObserved: [ItemKey], referenceCandidates: [ItemKey], skipped: [ItemKey: CheckSkipReason])
}

public enum CheckPlan {
    public static func make(
        sections: Set<ItemSection>,
        set: DiscoveredItemSet,
        sectionMap: [TagKey: ItemSection],
        iceIconKey: ItemKey?,
        explicitCandidates: [ItemKey]?
    ) -> CheckPlanResult {
        let useHidden = sections.contains(.hidden)
        let dividerReading = useHidden ? set.hiddenDivider : set.alwaysHiddenDivider
        guard set.ownRead == .ok, let dividerReading, dividerReading.isUsable, let dividerFrame = dividerReading.frame else {
            return .skip(.dividerUnavailable)
        }
        let dividerMinX = dividerFrame.minX

        let itemsByKey = Dictionary(uniqueKeysWithValues: set.items.map { ($0.key, $0) })

        var targets = [ItemKey]()
        var skipped = [ItemKey: CheckSkipReason]()
        var sectionEligibleKeys = Set<ItemKey>()

        for item in set.items {
            guard item.position != .parked else { continue }
            guard let section = sectionMap[item.tagKey], sections.contains(section) else { continue }
            sectionEligibleKeys.insert(item.key)
            if item.basis == .positional {
                skipped[item.key] = .positional
            } else if item.position == .stacked {
                skipped[item.key] = .stacked
            } else {
                targets.append(item.key)
            }
        }

        let iceIconFrame: BarRect? = {
            guard let iceIconKey, let visible = set.visibleControlItem, visible.key == iceIconKey else { return nil }
            return visible.frame
        }()

        let rawCandidateKeys: [ItemKey]
        if let explicitCandidates {
            rawCandidateKeys = explicitCandidates
        } else {
            rawCandidateKeys = set.items
                .filter { item in
                    item.basis != .positional && item.position == .onBar
                        && item.frame.map { frame in
                            frame.midX > dividerMinX && (iceIconFrame.map { frame.midX < $0.midX } ?? true)
                        } == true
                }
                .sorted { $0.frame!.midX < $1.frame!.midX }
                .map(\.key)
        }

        let trimmedTargets: [BarRect] = targets.compactMap { itemsByKey[$0]?.frame.map { CheckFrames.trim($0) } }

        var accepted = [ItemKey]()
        var acceptedTrimmed = [BarRect]()
        for candidateKey in rawCandidateKeys {
            guard accepted.count < 2 else { break }
            guard let frame = itemsByKey[candidateKey]?.frame else { continue }
            let trimmed = CheckFrames.trim(frame)
            guard !acceptedTrimmed.contains(where: { overlaps($0, trimmed) }) else { continue }
            guard !trimmedTargets.contains(where: { overlaps($0, trimmed) }) else { continue }
            accepted.append(candidateKey)
            acceptedTrimmed.append(trimmed)
        }

        guard let leftmostTrimmed = acceptedTrimmed.min(by: { $0.minX < $1.minX }) else {
            return .skip(.noReference)
        }

        let acceptedSet = Set(accepted)
        let allListed = set.items + (set.visibleControlItem.map { [$0] } ?? [])
        var alsoObserved = [ItemKey]()
        for item in allListed {
            guard item.position == .onBar, item.basis != .positional, let frame = item.frame else { continue }
            guard !sectionEligibleKeys.contains(item.key), !acceptedSet.contains(item.key) else { continue }
            let trimmed = CheckFrames.trim(frame)
            guard trimmed.maxX <= leftmostTrimmed.minX else { continue }
            alsoObserved.append(item.key)
        }

        return .observe(targets: targets, alsoObserved: alsoObserved, referenceCandidates: accepted, skipped: skipped)
    }

    /// Keeps `accepted` candidates in `candidates`'s own order, at most
    /// `maxCount` -- used to reconcile the geometric candidate list against
    /// whichever ones a capture's baseline actually accepted.
    public static func references(candidates: [ItemKey], accepted: Set<ItemKey>, maxCount: Int = 2) -> [ItemKey] {
        Array(candidates.filter { accepted.contains($0) }.prefix(maxCount))
    }

    private static func overlaps(_ a: BarRect, _ b: BarRect) -> Bool {
        PtSpan(lo: a.minX, hi: a.maxX).overlaps(PtSpan(lo: b.minX, hi: b.maxX))
    }
}
