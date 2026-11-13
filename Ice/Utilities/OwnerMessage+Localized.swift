//
//  OwnerMessage+Localized.swift
//  Ice
//

import Foundation
import IceCore

extension OwnerMessage {
    /// The message in the app's language: each template IceCore names is
    /// looked up in the app's `Localizable` catalog, English when missing
    /// (plan 2026-11-13-zh-hant, D3).
    var localized: String {
        rendered { Bundle.main.localizedString(forKey: $0, value: $0, table: nil) }
    }

    /// The templates the app itself builds messages from (`HidingCheckStatus`),
    /// listed for the completeness check (plan D6).
    static let appTemplates = [
        HidingCheckStatus.notEffective, HidingCheckStatus.hidden, HidingCheckStatus.notChecked,
        HidingCheckStatus.noItems, HidingCheckStatus.joinTemplate,
    ]
}
