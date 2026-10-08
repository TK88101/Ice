//
//  MenuBarItemManager+IceBar27.swift
//  Ice
//

import Darwin
import IceCore
import MenuBarDiscovery
import OSLog

/// Who IceBar keeps hidden on macOS 27, and whether it may hide at all (plan
/// 2026-10-07-icebar-preference-hiding, S3 D-a, D-c and the T3b design): the
/// roster, the preconditions, and what the IceBar shows for each member.
struct PreferenceHidingRoster: Equatable {
    var membership = PreferenceHidingMembership(members: [], blockers: [])
    var preconditions = PreferenceHidingPreconditionResult.ok
    /// Every third-party item tag of the pass, for the layout signature.
    var itemTags = [String]()
    /// The IceBar's cells, in the roster's order: each member's item from
    /// the current pass, else the last one read for its tag.
    var items = [MenuBarItem]()
    /// Cells of members that are not pressable now (D-a, D-f): disabled
    /// before a press can fail.
    var unpressable = Set<MenuBarItem.ID>()
    /// The key and item each member was last read with.
    var lastKeys = [TagKey: ItemKey]()
    var lastItems = [TagKey: MenuBarItem]()
}

/// IceBar on macOS 27 (plan 2026-10-03-icebar-build, 9.3 and 9.5): the hiding
/// coordinator's lifetime, the roster, and opening items by Accessibility.
@available(macOS 27, *)
extension MenuBarItemManager {
    private static let iceBarLogger = Logger(category: "IceBarPress")

    /// Starts IceBar's hiding; called once, from the manager's setup.
    func configureIceBarHiding(with appState: AppState) {
        let coordinator = IceBarHidingCoordinator(appState: appState)
        coordinator.start()
        iceBarHidingStorage = coordinator
    }

    /// Whether the IceBar may be shown: Ice rests at a length (T3b design:
    /// not at standard length, where the members are on the bar).
    var isIceBarOffered: Bool {
        (iceBarHidingStorage as? IceBarHidingCoordinator)?.isLengthApplied ?? false
    }

    /// Whether the IceBar cell of `item` takes no click.
    func isIceBarCellDisabled(_ item: MenuBarItem) -> Bool {
        unpressableItems.contains(item.id) || preferenceHidingRoster.unpressable.contains(item.id)
    }

    /// Resolves the roster and the preconditions from one completed pass
    /// (T3b design). Outside IceBar mode the roster is emptied: no promise
    /// that membership survives a mode change (D-a).
    func updatePreferenceHidingRoster(discovery: DiscoveryResult, hiddenDividerState: DividerState) {
        guard appState?.settings.general.useIceBar == true else {
            if preferenceHidingRoster != PreferenceHidingRoster() {
                preferenceHidingRoster = PreferenceHidingRoster()
            }
            return
        }
        var next = preferenceHidingRoster
        let set = discovery.set
        // A pass without permission read nothing: the roster stays, the
        // preconditions block (review round 2).
        if set.completeness != .permissionDenied {
            let previous = PreferenceHidingMembership.carried(
                previous: next.membership.members.map(\.tag),
                lastKeys: next.lastKeys,
                hasExited: Self.hasExited
            )
            next.membership = PreferenceHidingMembership.resolve(
                set: set,
                hiddenDividerState: hiddenDividerState,
                previousMembers: previous,
                childIdentifiersByPID: discovery.childIdentifiersByPID
            )
            next.itemTags = set.items.map { String(describing: $0.tagKey) }.sorted()
            remember(set: set, origin: discovery.origin, in: &next)
        }
        next.preconditions = PreferenceHidingPreconditions.evaluate(
            iconPlacement: iconPlacement,
            completeness: set.completeness,
            ownRead: set.ownRead,
            blockers: next.membership.blockers
        )
        if next != preferenceHidingRoster {
            preferenceHidingRoster = next
        }
    }

    /// The members' latest keys and items, and the cells built from them;
    /// entries of tags that left the roster go.
    private func remember(set: DiscoveredItemSet, origin: DiscoveryOrigin, in roster: inout PreferenceHidingRoster) {
        let itemsByKey = Dictionary(set.items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let members = roster.membership.members
        let tags = Set(members.map(\.tag))
        roster.lastKeys = roster.lastKeys.filter { tags.contains($0.key) }
        roster.lastItems = roster.lastItems.filter { tags.contains($0.key) }
        for member in members {
            guard let key = member.key, let item = itemsByKey[key] else { continue }
            roster.lastKeys[member.tag] = key
            roster.lastItems[member.tag] = MenuBarItem(discovered: item, origin: origin)
        }
        roster.items = members.compactMap { roster.lastItems[$0.tag] }
        roster.unpressable = Set(members.filter { !$0.isPressable }.compactMap { roster.lastItems[$0.tag]?.id })
    }

    /// No process has this pid any more (T3b design G1). Any other answer,
    /// a permission error included, is "alive": the member stays, stale.
    private static func hasExited(_ pid: Int32) -> Bool {
        kill(pid, 0) == -1 && errno == ESRCH
    }

    /// Presses the item while it stays pushed off the bar. One press per item
    /// at a time; a failed press disables the item's cell.
    func pressFromIceBar(_ item: MenuBarItem) {
        guard !pendingPresses.contains(item.id), !unpressableItems.contains(item.id) else {
            return
        }
        guard case .accessibility(let encoded) = item.id, let key = ItemKey.decode(encoded) else {
            unpressableItems.insert(item.id)
            return
        }
        pendingPresses.insert(item.id)
        Task {
            let outcome = await MenuBarItemPresser.press(key)
            pendingPresses.remove(item.id)
            if outcome == .failed {
                Self.iceBarLogger.info("Press failed, disabling the IceBar cell for \(item.logString, privacy: .public)")
                unpressableItems.insert(item.id)
            }
        }
    }
}
