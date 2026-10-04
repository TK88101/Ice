//
//  IceBarFallbackGlyph.swift
//  Ice
//

import IceCore
import SwiftUI

/// An IceBar cell's picture on macOS 27, where items have no windows to
/// capture (plan 2026-10-03-icebar-build, D2 and 9.4): the owning app's icon,
/// desaturated (route C F2), else the item's title, else a generic glyph.
@available(macOS 27, *)
struct IceBarFallbackGlyph: View {
    private static let iconSize: CGFloat = 18
    private static let maxTitleLength = 12
    private static let horizontalPadding: CGFloat = 4

    let item: MenuBarItem

    var body: some View {
        let icon = NSRunningApplication(processIdentifier: item.ownerPID)?.icon
        let choice = IceBarIconChoice.choose(
            hasCachedImage: false,
            isAccessibilitySource: true,
            hasAppIcon: icon != nil,
            title: item.title
        )
        Group {
            switch choice {
            case .appIcon:
                if let icon {
                    // Desaturated, not a template: a template of an app icon is a
                    // filled square.
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .saturation(0)
                        .frame(width: Self.iconSize, height: Self.iconSize)
                }
            case .title(let title):
                Text(Self.truncated(title))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            case .genericGlyph:
                Image(systemName: "app.dashed")
                    .font(.system(size: 13))
            case .cachedImage, .none:
                EmptyView()
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(maxHeight: .infinity)
    }

    private static func truncated(_ title: String) -> String {
        guard title.count > maxTitleLength else {
            return title
        }
        return String(title.prefix(maxTitleLength - 1)) + "…"
    }
}
