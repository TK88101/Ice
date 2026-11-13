/// The language option in General settings (plan 2026-11-13-zh-hant, D4).
/// It is stored as the app's own `AppleLanguages`, the per-app language macOS
/// reads at launch; System removes the key so the system's list applies.
public enum AppLanguage: String, CaseIterable, Equatable, Sendable {
    case system
    case english
    case traditionalChinese

    /// What the app's `AppleLanguages` holds for this choice; `nil` removes it.
    public var storedLanguages: [String]? {
        switch self {
        case .system: nil
        case .english: ["en"]
        case .traditionalChinese: ["zh-Hant"]
        }
    }

    /// The choice a stored value means, by its first entry; anything this
    /// app was not localized for reads as System.
    public init(storedLanguages: [String]?) {
        guard let first = storedLanguages?.first else {
            self = .system
            return
        }
        if first == "en" || first.hasPrefix("en-") {
            self = .english
        } else if first == "zh-Hant" || first.hasPrefix("zh-Hant-") {
            self = .traditionalChinese
        } else {
            self = .system
        }
    }
}
