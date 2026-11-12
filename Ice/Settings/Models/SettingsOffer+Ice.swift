//
//  SettingsOffer+Ice.swift
//  Ice
//

import IceCore

/// `SettingsOffer` asked for the system Ice runs on (plan
/// 2026-11-12-settings-cleanup): the panes, the menus, the hotkeys and the
/// settings models all ask here, so what is not offered on macOS 27 is not
/// shown, not reachable and not in effect.
extension SettingsOffer {
    static let isMacOS27: Bool = if #available(macOS 27, *) { true } else { false }

    static func offers(_ setting: Setting) -> Bool {
        isOffered(setting, isMacOS27: isMacOS27)
    }

    static func offers(_ action: HotkeyAction) -> Bool {
        isOffered(actionNamed: action.rawValue, isMacOS27: isMacOS27)
    }

    /// A switch's value in effect on this system.
    static func inEffect(_ setting: Setting, stored: Bool) -> Bool {
        effective(setting, stored: stored, isMacOS27: isMacOS27)
    }
}
