#!/bin/zsh
# Plan 2026-11-12-settings-cleanup, T5: every place that shows, reaches or
# loads a setting removed on macOS 27 asks SettingsOffer. A cheap guard against
# a later edit dropping one of the questions; the live check is the settings
# pass's T6 cases. Exit 0 when every line is there.
set -uo pipefail
here=${0:A:h}
root=${here:h:h:h}
cd "$root" || exit 2
failed=0
need() { # <file> <fixed string>
    grep -qF -- "$2" "$1" || { echo "check-settings: $1 lacks: $2"; failed=1; }
}
general=Ice/Settings/SettingsPanes/GeneralSettingsPane.swift
advanced=Ice/Settings/SettingsPanes/AdvancedSettingsPane.swift
need $general 'if SettingsOffer.offers(.showIceIcon) {'
need $general 'if SettingsOffer.offers(.useIceBar) {'
need $general 'if SettingsOffer.offers(.itemSpacing) {'
need $advanced 'if SettingsOffer.offers(.enableAlwaysHiddenSection) {'
need $advanced 'if SettingsOffer.offers(.showAllSectionsOnUserDrag) {'
need $advanced 'if SettingsOffer.offers(.sectionDividerStyle) {'
need $advanced 'if SettingsOffer.offers(.hideApplicationMenus) {'
need $advanced 'if SettingsOffer.offers(.tempShowInterval) {'
need Ice/Settings/SettingsPanes/HotkeysSettingsPane.swift 'if SettingsOffer.offers(.searchMenuBarItems) {'
need Ice/Settings/Models/HotkeysSettings.swift 'HotkeyAction.allCases.filter(SettingsOffer.offers)'
need Ice/Hotkeys/HotkeyAction.swift 'guard SettingsOffer.offers(self) else {'
need Ice/Settings/Models/GeneralSettings.swift 'showIceIcon = SettingsOffer.inEffect(.showIceIcon, stored: showIceIcon)'
need Ice/Settings/Models/GeneralSettings.swift 'useIceBar = SettingsOffer.inEffect(.useIceBar, stored: useIceBar)'
need Ice/Settings/Models/AdvancedSettings.swift 'SettingsOffer.inEffect(.enableAlwaysHiddenSection, stored: enableAlwaysHiddenSection)'
need Ice/Settings/Models/AdvancedSettings.swift 'SettingsOffer.inEffect(.showAllSectionsOnUserDrag, stored: showAllSectionsOnUserDrag)'
need Ice/Settings/Models/AdvancedSettings.swift 'SettingsOffer.inEffect(.hideApplicationMenus, stored: hideApplicationMenus)'
need Ice/Settings/Models/AdvancedSettings.swift 'SettingsOffer.effectiveDividerStyle('
need Ice/MenuBar/Appearance/MenuBarAppearanceManager.swift 'SettingsOffer.effectiveShapeKind('
need Ice/MenuBar/Appearance/MenuBarAppearanceEditor/MenuBarShapePicker.swift 'SettingsOffer.offers(.splitShape)'
need Ice/MenuBar/ControlItem/ControlItem.swift 'if SettingsOffer.offers(.searchMenuBarItems) {'
need Ice/Events/HIDEventManager.swift 'return appState.itemManager.isOnMenuBarItem(mouseLocation)'
need Ice/Events/HIDEventManager.swift 'SmartRehideRule.isSystemOverlay('
# The one place a control of a removed setting is built is its own property,
# which only the guarded body above uses.
for name in enableAlwaysHiddenSection showAllSectionsOnUserDrag sectionDividerStyle hideApplicationMenus tempShowInterval; do
    uses=$(grep -cE "^ +$name\$" $advanced)
    (( uses == 1 )) || { echo "check-settings: $advanced uses $name $uses times in a view body, want 1"; failed=1; }
done
(( failed == 0 )) && echo "check-settings: every question is asked"
exit $failed
