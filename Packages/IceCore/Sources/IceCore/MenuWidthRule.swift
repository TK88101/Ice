/// D1's long-menu rule (plan 2026-10-03-icebar-build, section 8 T2): when the
/// frontmost app's menus cross the notch, the fold cannot be read (C2,
/// MEASURED `20260929-234942-c2A`), so the hidden section is shown and the
/// IceBar is not offered until the menus are short again.

/// Whether the frontmost app's menus leave the notch alone.
public enum MenuWidthVerdict: String, Equatable, Sendable {
    case fits
    case crossesNotch
    /// No menu frame, no notch, or a value that is not a number. Ice shows the
    /// section for anything but `fits`.
    case unreadable
}

public enum MenuWidthRule {
    /// Compares the application menu's right edge with the notch's left edge,
    /// both in screen points. No margin: menus ending at 758 pt with the notch
    /// at 771.5 hid cleanly (FINDINGS "The safe width"), so reaching the edge
    /// still fits.
    public static func verdict(menuMaxX: Double?, notchMinX: Double?) -> MenuWidthVerdict {
        guard let menuMaxX, let notchMinX, menuMaxX.isFinite, notchMinX.isFinite else {
            return .unreadable
        }
        return menuMaxX > notchMinX ? .crossesNotch : .fits
    }
}
