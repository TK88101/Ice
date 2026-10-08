//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import IceCore
import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var itemManager: MenuBarItemManager

    private var hasItems: Bool {
        itemManager.itemCache.isLoaded || !itemManager.itemCache.managedItems.isEmpty
    }

    var body: some View {
        if !ScreenCapture.cachedCheckPermissions() {
            missingScreenRecordingPermissions
        } else if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            IceForm(spacing: 20) {
                header
                hidingCheckStatusLine
                placementNoticeLine
                layoutBars
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        IceSection {
            VStack(spacing: 3) {
                Text("Drag to arrange your menu bar items into different sections.")
                    .font(.title3.bold())
                Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(15)
        }
    }

    @ViewBuilder
    private var layoutBars: some View {
        VStack(spacing: 20) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
        .opacity(hasItems ? 1 : 0.75)
        .blur(radius: hasItems ? 0 : 5)
        .allowsHitTesting(hasItems)
        .overlay {
            if !hasItems {
                loadingMenuBarItems
            } else if itemManager.itemCache.managedItems.isEmpty {
                noMenuBarItems
            }
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text("Ice cannot arrange menu bar items in automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var missingScreenRecordingPermissions: some View {
        VStack {
            Text("Menu bar layout requires screen recording permissions.")
                .font(.title2)

            Button {
                appState.navigationState.settingsNavigationIdentifier = .advanced
            } label: {
                Text("Go to Advanced Settings")
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private var loadingMenuBarItems: some View {
        VStack {
            Text("Loading menu bar items…")
            ProgressView()
        }
        .font(.title)
    }

    @ViewBuilder
    private var noMenuBarItems: some View {
        Text("No menu bar items")
            .font(.title)
    }

    /// On macOS 27: whether hiding a section took effect, as Ice last
    /// checked it (plan D7). Never set on earlier systems.
    @ViewBuilder
    private var hidingCheckStatusLine: some View {
        if let status = appState.hidingCheckStatus {
            statusLine(status.message)
        }
    }

    private func statusLine(_ message: String) -> some View {
        IceSection {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(10)
        }
    }

    /// On macOS 27 in IceBar mode: Ice's icon is left of its hidden divider,
    /// and how to repair it (plan 2026-10-07-icebar-preference-hiding, T2c).
    /// The hiding status line says the same once the hiding has put the
    /// section back; then this line is not repeated.
    @ViewBuilder
    private var placementNoticeLine: some View {
        let notice = IcePlacementNotice.notice(
            placement: itemManager.iconPlacement,
            isIceBarMode: appState.settings.general.useIceBar,
            isDragging: appState.isDraggingMenuBarItem
        )
        if let notice, appState.hidingCheckStatus?.message != notice.message {
            statusLine(notice.message)
        }
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: name),
            section.isEnabled
        {
            VStack(alignment: .leading) {
                Text(name.localized)
                    .font(.headline)
                    .padding(.leading, 8)

                LayoutBar(imageCache: appState.imageCache, section: name)
            }
        }
    }
}
