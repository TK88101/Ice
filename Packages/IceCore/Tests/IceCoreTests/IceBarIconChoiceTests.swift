import Testing
@testable import IceCore

/// What an IceBar cell shows (plan 2026-10-03-icebar-build, D2 and section 8 T3).
@Suite("IceBarIconChoice")
struct IceBarIconChoiceTests {
    func choose(cached: Bool = false, accessibility: Bool = true, appIcon: Bool = false, title: String? = nil) -> IceBarIconChoice {
        IceBarIconChoice.choose(hasCachedImage: cached, isAccessibilitySource: accessibility, hasAppIcon: appIcon, title: title)
    }

    @Test("a cached image wins for either source", arguments: [true, false])
    func cachedImageWins(accessibility: Bool) {
        #expect(choose(cached: true, accessibility: accessibility, appIcon: true, title: "Clock") == .cachedImage)
    }

    @Test("a window-sourced item without a cached image gets no cell, as on macOS 26")
    func windowSourceUnchanged() {
        #expect(choose(accessibility: false, appIcon: true, title: "Clock") == .none)
    }

    @Test("an accessibility-sourced item falls back to its app's icon")
    func appIconFallback() {
        #expect(choose(appIcon: true, title: "Clock") == .appIcon)
    }

    @Test("without an app icon the trimmed title is shown")
    func titleFallbackTrimmed() {
        #expect(choose(title: "  Clock \n") == .title("Clock"))
    }

    @Test("a missing or blank title falls to the generic glyph", arguments: [nil, "", "   ", "\n\t"] as [String?])
    func blankTitleGivesGlyph(title: String?) {
        #expect(choose(title: title) == .genericGlyph)
    }
}
