import Testing
@testable import IceCore

/// The language option (plan 2026-11-13-zh-hant, D4): what each choice stores
/// in the app's own `AppleLanguages`, and what a stored value reads back as.
@Suite("AppLanguage")
struct AppLanguageTests {
    @Test("each choice stores its list; System stores nothing (the key is removed)")
    func stored() {
        #expect(AppLanguage.system.storedLanguages == nil)
        #expect(AppLanguage.english.storedLanguages == ["en"])
        #expect(AppLanguage.traditionalChinese.storedLanguages == ["zh-Hant"])
    }

    @Test("a stored value reads back as the choice that wrote it", arguments: AppLanguage.allCases)
    func roundTrip(language: AppLanguage) {
        #expect(AppLanguage(storedLanguages: language.storedLanguages) == language)
    }

    @Test("by its first entry, region variants included")
    func firstEntryDecides() {
        #expect(AppLanguage(storedLanguages: ["zh-Hant-TW", "en"]) == .traditionalChinese)
        #expect(AppLanguage(storedLanguages: ["en-JP"]) == .english)
    }

    @Test("anything else reads as System", arguments: [nil, [], ["ja-JP"], ["zh-Hans"], ["zh"], [""]] as [[String]?])
    func otherIsSystem(stored: [String]?) {
        #expect(AppLanguage(storedLanguages: stored) == .system)
    }
}
