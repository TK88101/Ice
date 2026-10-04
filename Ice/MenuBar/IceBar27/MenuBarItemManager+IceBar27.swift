//
//  MenuBarItemManager+IceBar27.swift
//  Ice
//

import IceCore
import OSLog

/// IceBar on macOS 27 (plan 2026-10-03-icebar-build, 9.3 and 9.5): the hiding
/// coordinator's lifetime and opening items by Accessibility.
@available(macOS 27, *)
extension MenuBarItemManager {
    private static let iceBarLogger = Logger(category: "IceBarPress")

    /// Starts IceBar's hiding; called once, from the manager's setup.
    func configureIceBarHiding(with appState: AppState) {
        let coordinator = IceBarHidingCoordinator(appState: appState)
        coordinator.start()
        iceBarHidingStorage = coordinator
    }

    /// Whether the IceBar may be shown: the hidden section is hidden cleanly.
    var isIceBarOffered: Bool {
        (iceBarHidingStorage as? IceBarHidingCoordinator)?.isResting ?? false
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
