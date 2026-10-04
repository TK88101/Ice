/// D2 (plan 2026-10-03-icebar-build, section 8 T3): on macOS 27 there are no
/// per-item windows to capture, so an accessibility-sourced IceBar cell falls
/// back to its app's icon (drawn as a template by the view), then its title,
/// then a generic glyph. Window-sourced items keep today's behaviour.

/// What an IceBar cell shows.
public enum IceBarIconChoice: Equatable, Sendable {
    case cachedImage
    case appIcon
    /// The item's Accessibility title, trimmed; the view truncates it.
    case title(String)
    case genericGlyph
    /// No cell, as on macOS 26 for an item without a captured image.
    case none

    public static func choose(
        hasCachedImage: Bool,
        isAccessibilitySource: Bool,
        hasAppIcon: Bool,
        title: String?
    ) -> IceBarIconChoice {
        if hasCachedImage { return .cachedImage }
        guard isAccessibilitySource else { return .none }
        if hasAppIcon { return .appIcon }
        let trimmed = title.map(IdentifierText.trimmed) ?? ""
        return trimmed.isEmpty ? .genericGlyph : .title(trimmed)
    }
}
