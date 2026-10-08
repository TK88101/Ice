//
//  MenuBarItemManager+IceBar27.swift
//  Ice
//

import Darwin
import IceCore
import MenuBarDiscovery
import OSLog

/// What the IceBar shows of the roster on macOS 27 (plan
/// 2026-10-07-icebar-preference-hiding, T3b design): the pure roster, and the
/// last item read for each member, from which the cells are derived.
struct IceBarRoster: Equatable {
    var rules = PreferenceHidingRoster()
    /// The last item read for each member's tag.
    var lastItems = [TagKey: MenuBarItem]()

    /// The IceBar's cells, in the roster's order.
    var items: [MenuBarItem] {
        rules.membership.members.compactMap { lastItems[$0.tag] }
    }

    /// Whether the member behind this cell is not pressable now (D-a, D-f):
    /// disabled before a press can fail.
    func isUnpressable(_ id: MenuBarItem.ID) -> Bool {
        rules.membership.members.first { lastItems[$0.tag]?.id == id }.map { !$0.isPressable } ?? false
    }
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
        unpressableItems.contains(item.id) || iceBarRoster.isUnpressable(item.id)
    }

    /// Advances the roster by one completed pass (T3b design). Outside
    /// IceBar mode it is emptied: no promise that membership survives a mode
    /// change (D-a). A press that failed is retried once the IceBar's cells
    /// change.
    func updateIceBarRoster(discovery: DiscoveryResult, hiddenDividerState: DividerState) {
        guard appState?.settings.general.useIceBar == true else {
            // Also reset by the coordinator when the mode goes off; this one
            // covers a pass that was already under way then.
            resetIceBarRoster()
            return
        }
        var next = iceBarRoster
        next.rules = next.rules.advanced(
            set: discovery.set,
            hiddenDividerState: hiddenDividerState,
            childIdentifiersByPID: discovery.childIdentifiersByPID,
            iconPlacement: iconPlacement,
            hasExited: Self.hasExited
        )
        let tags = Set(next.rules.lastKeys.keys)
        next.lastItems = next.lastItems.filter { tags.contains($0.key) }
        let itemsByKey = Dictionary(discovery.set.items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for (tag, key) in next.rules.lastKeys {
            if let item = itemsByKey[key] {
                next.lastItems[tag] = MenuBarItem(discovered: item, origin: discovery.origin)
            }
        }
        guard next != iceBarRoster else {
            return
        }
        if !unpressableItems.isEmpty, Set(next.items.map(\.id)) != Set(iceBarRoster.items.map(\.id)) {
            unpressableItems = []
        }
        iceBarRoster = next
    }

    /// Empties the roster and the failed presses: called the moment IceBar
    /// mode goes off, so a mode turned on again before the next pass starts
    /// from nothing (Codex review, T3b round 2).
    func resetIceBarRoster() {
        if iceBarRoster != IceBarRoster() {
            iceBarRoster = IceBarRoster()
        }
        if !unpressableItems.isEmpty || !pendingPresses.isEmpty {
            pressGeneration += 1
            pendingPresses = []
            unpressableItems = []
        }
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
        let generation = pressGeneration
        Task {
            let outcome = await MenuBarItemPresser.press(key)
            // The roster was reset meanwhile: this press speaks for no cell.
            guard generation == pressGeneration else {
                return
            }
            pendingPresses.remove(item.id)
            if outcome == .failed {
                Self.iceBarLogger.info("Press failed, disabling the IceBar cell for \(item.logString, privacy: .public)")
                unpressableItems.insert(item.id)
            }
        }
    }
}
