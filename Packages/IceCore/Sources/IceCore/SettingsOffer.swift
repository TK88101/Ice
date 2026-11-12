/// Which settings and hotkey actions Ice offers, and what a setting that is
/// not offered is worth (plan 2026-11-12-settings-cleanup, sections 4 and 9).
/// On macOS 27 only what the settings pass of 2026-11-12 saw work on a live
/// bar is offered (appendix B of that plan has each case and its run); before
/// macOS 27 everything is, as upstream. A setting that is not offered is not
/// shown, is reached by no menu entry or hotkey, and has the one value that
/// works whatever was stored.
public enum SettingsOffer {
    public enum Setting: CaseIterable, Sendable {
        case launchAtLogin
        case showIceIcon
        case iceIcon
        case customIceIconIsTemplate
        case useIceBar
        case iceBarLocation
        case showOnClick
        case showOnHover
        case showOnScroll
        case autoRehide
        case itemSpacing
        case enableAlwaysHiddenSection
        case showAllSectionsOnUserDrag
        case sectionDividerStyle
        case hideApplicationMenus
        case enableSecondaryContextMenu
        case showOnHoverDelay
        case tempShowInterval
        case menuBarAppearance
        case splitShape
    }

    /// The hotkey actions, by the names Ice stores them under.
    public enum Action: String, CaseIterable, Sendable {
        case toggleHiddenSection = "ToggleHiddenSection"
        case toggleAlwaysHiddenSection = "ToggleAlwaysHiddenSection"
        case searchMenuBarItems = "SearchMenuBarItems"
        case enableIceBar = "EnableIceBar"
        case toggleApplicationMenus = "ToggleApplicationMenus"
    }

    public static func isOffered(_ setting: Setting, isMacOS27: Bool) -> Bool {
        guard isMacOS27 else { return true }
        switch setting {
        case .launchAtLogin, .iceIcon, .customIceIconIsTemplate, .iceBarLocation, .showOnClick, .showOnHover,
             .showOnScroll, .autoRehide, .enableSecondaryContextMenu, .showOnHoverDelay, .menuBarAppearance:
            return true
        case .showIceIcon:
            // Without the icon Ice cannot read its place: blocked, nothing hidden (G0).
            return false
        case .useIceBar, .hideApplicationMenus:
            // Outside IceBar mode nothing is hidden (U1); the app menus are
            // hidden only outside it (V2).
            return false
        case .itemSpacing:
            // Its "Apply" quits every app with an item; never run (9.6).
            return false
        case .enableAlwaysHiddenSection:
            // Its divider reads at the hidden divider's frame (T2d).
            return false
        case .showAllSectionsOnUserDrag, .sectionDividerStyle:
            // In IceBar mode a drag gives everything back either way, and the
            // chevron is drawn as a sliver (V1, V5).
            return false
        case .tempShowInterval:
            // Temporary showing is refused on macOS 27.
            return false
        case .splitShape:
            // Drawn exactly as a full shape (A2).
            return false
        }
    }

    public static func isOffered(_ action: Action, isMacOS27: Bool) -> Bool {
        guard isMacOS27 else { return true }
        switch action {
        case .toggleHiddenSection, .toggleApplicationMenus:
            return true
        case .toggleAlwaysHiddenSection, .searchMenuBarItems, .enableIceBar:
            // No always-hidden section; a click on a search result does
            // nothing (H3); IceBar mode is the only mode (U1).
            return false
        }
    }

    /// For Ice's own action type, which has the same raw values. A name this
    /// table does not know is not offered on macOS 27: nothing was seen of it.
    public static func isOffered(actionNamed name: String, isMacOS27: Bool) -> Bool {
        guard let action = Action(rawValue: name) else { return !isMacOS27 }
        return isOffered(action, isMacOS27: isMacOS27)
    }

    /// A switch's value in effect: the stored one when it is offered, the one
    /// that works when it is not.
    public static func effective(_ setting: Setting, stored: Bool, isMacOS27: Bool) -> Bool {
        guard !isOffered(setting, isMacOS27: isMacOS27) else { return stored }
        switch setting {
        case .showIceIcon, .useIceBar, .showAllSectionsOnUserDrag:
            return true
        default:
            return false
        }
    }

    /// `SectionDividerStyle`'s raw value in effect: none (0) on macOS 27.
    public static func effectiveDividerStyle(stored: Int, isMacOS27: Bool) -> Int {
        isOffered(.sectionDividerStyle, isMacOS27: isMacOS27) ? stored : 0
    }

    /// `MenuBarShapeKind`'s raw value in effect: on macOS 27 a split shape (2)
    /// is the full one (1) it is drawn as.
    public static func effectiveShapeKind(stored: Int, isMacOS27: Bool) -> Int {
        !isOffered(.splitShape, isMacOS27: isMacOS27) && stored == 2 ? 1 : stored
    }
}
