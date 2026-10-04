//
//  IceBarAccessibilityCell.swift
//  Ice
//

import SwiftUI

/// An IceBar cell for an item without a window, on macOS 27 (plan
/// 2026-10-03-icebar-build, 9.4-9.5): its fallback picture, a left click that
/// presses the item where it is, pushed off the bar, and nothing on a right
/// click (only the press was measured). A cell whose press failed is dimmed
/// and no longer clickable.
@available(macOS 27, *)
struct IceBarAccessibilityCell: View {
    private static let disabledOpacity = 0.4

    @ObservedObject var itemManager: MenuBarItemManager
    let menuBarManager: MenuBarManager
    let item: MenuBarItem
    let section: MenuBarSection.Name

    /// Hiding the section closes the IceBar and, in IceBar mode, leaves the
    /// hidden length alone.
    private var pressAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            menuBarManager?.section(withName: section)?.hide()
            itemManager?.pressFromIceBar(item)
        }
    }

    var body: some View {
        let isDisabled = itemManager.unpressableItems.contains(item.id)
        IceBarFallbackGlyph(item: item)
            .contentShape(Rectangle())
            .opacity(isDisabled ? Self.disabledOpacity : 1)
            .overlay {
                if !isDisabled {
                    IceBarItemClickView(item: item, leftClickAction: pressAction, rightClickAction: { })
                }
            }
            .help(isDisabled ? "Cannot open on macOS 27" : item.displayName)
            .accessibilityLabel(item.displayName)
            .accessibilityAction(named: "left click", isDisabled ? { } : pressAction)
    }
}
