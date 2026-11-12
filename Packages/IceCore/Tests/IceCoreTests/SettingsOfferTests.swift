import Testing
@testable import IceCore

@Suite("SettingsOffer")
struct SettingsOfferTests {
    /// What the settings pass of 2026-11-12 found dead on macOS 27 (plan
    /// 2026-11-12-settings-cleanup, appendix B).
    static let removedSettings: Set<SettingsOffer.Setting> = [
        .showIceIcon, .useIceBar, .itemSpacing, .enableAlwaysHiddenSection, .showAllSectionsOnUserDrag,
        .sectionDividerStyle, .hideApplicationMenus, .tempShowInterval, .splitShape,
    ]
    static let removedActions: Set<SettingsOffer.Action> = [.toggleAlwaysHiddenSection, .searchMenuBarItems, .enableIceBar]

    @Test("before macOS 27 every setting and every hotkey action is offered", arguments: SettingsOffer.Setting.allCases)
    func everythingBefore27(setting: SettingsOffer.Setting) {
        #expect(SettingsOffer.isOffered(setting, isMacOS27: false))
    }

    @Test("before macOS 27 every hotkey action is offered", arguments: SettingsOffer.Action.allCases)
    func everyActionBefore27(action: SettingsOffer.Action) {
        #expect(SettingsOffer.isOffered(action, isMacOS27: false))
    }

    @Test("on macOS 27 a setting is offered exactly when the pass saw it work", arguments: SettingsOffer.Setting.allCases)
    func settingsOn27(setting: SettingsOffer.Setting) {
        #expect(SettingsOffer.isOffered(setting, isMacOS27: true) == !Self.removedSettings.contains(setting))
    }

    @Test("on macOS 27 a hotkey action is offered exactly when the pass saw it work", arguments: SettingsOffer.Action.allCases)
    func actionsOn27(action: SettingsOffer.Action) {
        #expect(SettingsOffer.isOffered(action, isMacOS27: true) == !Self.removedActions.contains(action))
    }

    @Test("a hotkey action is found by the name Ice stores it under; an unknown name is not offered on 27")
    func actionNames() {
        #expect(SettingsOffer.isOffered(actionNamed: "ToggleHiddenSection", isMacOS27: true))
        #expect(SettingsOffer.isOffered(actionNamed: "ToggleApplicationMenus", isMacOS27: true))
        #expect(!SettingsOffer.isOffered(actionNamed: "SearchMenuBarItems", isMacOS27: true))
        #expect(!SettingsOffer.isOffered(actionNamed: "ToggleAlwaysHiddenSection", isMacOS27: true))
        #expect(!SettingsOffer.isOffered(actionNamed: "EnableIceBar", isMacOS27: true))
        #expect(!SettingsOffer.isOffered(actionNamed: "SomethingNew", isMacOS27: true))
        #expect(SettingsOffer.isOffered(actionNamed: "SearchMenuBarItems", isMacOS27: false))
        #expect(SettingsOffer.isOffered(actionNamed: "SomethingNew", isMacOS27: false))
    }

    @Test("on macOS 27 a removed switch has the one value that works, whatever was stored")
    func effectiveSwitches() {
        for stored in [true, false] {
            #expect(SettingsOffer.effective(.showIceIcon, stored: stored, isMacOS27: true))
            #expect(SettingsOffer.effective(.useIceBar, stored: stored, isMacOS27: true))
            #expect(SettingsOffer.effective(.showAllSectionsOnUserDrag, stored: stored, isMacOS27: true))
            #expect(!SettingsOffer.effective(.enableAlwaysHiddenSection, stored: stored, isMacOS27: true))
            #expect(!SettingsOffer.effective(.hideApplicationMenus, stored: stored, isMacOS27: true))
        }
    }

    @Test("a switch that is offered keeps its stored value, on 27 and before", arguments: [true, false])
    func offeredSwitchesKeepTheirValue(stored: Bool) {
        for setting in SettingsOffer.Setting.allCases where SettingsOffer.isOffered(setting, isMacOS27: true) {
            #expect(SettingsOffer.effective(setting, stored: stored, isMacOS27: true) == stored)
        }
        for setting in SettingsOffer.Setting.allCases {
            #expect(SettingsOffer.effective(setting, stored: stored, isMacOS27: false) == stored)
        }
    }

    @Test("on macOS 27 the divider style is none and a split shape is drawn as a full one, as measured")
    func effectiveChoices() {
        #expect(SettingsOffer.effectiveDividerStyle(stored: 1, isMacOS27: true) == 0)
        #expect(SettingsOffer.effectiveDividerStyle(stored: 1, isMacOS27: false) == 1)
        #expect(SettingsOffer.effectiveShapeKind(stored: 2, isMacOS27: true) == 1)
        #expect(SettingsOffer.effectiveShapeKind(stored: 1, isMacOS27: true) == 1)
        #expect(SettingsOffer.effectiveShapeKind(stored: 0, isMacOS27: true) == 0)
        #expect(SettingsOffer.effectiveShapeKind(stored: 2, isMacOS27: false) == 2)
    }
}
