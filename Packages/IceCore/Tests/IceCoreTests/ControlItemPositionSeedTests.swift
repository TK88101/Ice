import Testing
@testable import IceCore

/// The preferred positions Ice seeds for its own items (plan
/// 2026-10-07-icebar-menu-frame-fix, section 13). MEASURED on macOS 27.0.1
/// (26A434) with sacrificial helpers: a preferred position of 0 is read as
/// none and the item lands leftmost, so Ice's icon (seeded 0 upstream) sat
/// left of its hidden divider (seeded 1); positive values order items from the
/// right, smallest rightmost (0.001, 0.1, 0.5, 1, 2).
@Suite("ControlItemPositionSeed")
struct ControlItemPositionSeedTests {
    @Test("before macOS 27 the seeds are upstream's, and only when nothing is stored")
    func upstream() {
        #expect(ControlItemPositionSeed.seed(for: .visible, stored: nil, isMacOS27: false) == 0)
        #expect(ControlItemPositionSeed.seed(for: .hidden, stored: nil, isMacOS27: false) == 1)
        #expect(ControlItemPositionSeed.seed(for: .visible, stored: 0, isMacOS27: false) == nil)
        #expect(ControlItemPositionSeed.seed(for: .visible, stored: 310, isMacOS27: false) == nil)
        #expect(ControlItemPositionSeed.seed(for: .hidden, stored: 1, isMacOS27: false) == nil)
    }

    @Test("on macOS 27 the icon is seeded rightmost and the hidden divider not at all, so it lands leftmost")
    func macOS27() throws {
        // Plan 2026-10-07-icebar-preference-hiding, S2 design T2a. MEASURED
        // 26A434 (run 20261007-231100-cM6U06-trace): seeded 1, the divider
        // landed right of every other status item (x 1492, icon 1508), so
        // everything else was a hidden-section member; the unseeded
        // always-hidden divider landed left of everything (x 1009).
        let visible = try #require(ControlItemPositionSeed.seed(for: .visible, stored: nil, isMacOS27: true))
        #expect(visible > 0)
        #expect(visible == ControlItemPositionSeed.visibleOnMacOS27)
        #expect(ControlItemPositionSeed.seed(for: .hidden, stored: nil, isMacOS27: true) == nil)
    }

    @Test("on macOS 27 a stored value of the hidden divider is never touched, the old seed 1 and a 0 included", arguments: [0, 1, 465])
    func storedHiddenStays(stored: Double) {
        #expect(ControlItemPositionSeed.seed(for: .hidden, stored: stored, isMacOS27: true) == nil)
    }

    @Test("on macOS 27 a stored 0 for the icon is none, so it is seeded again; any other stored value stays")
    func storedZero() {
        #expect(ControlItemPositionSeed.seed(for: .visible, stored: 0, isMacOS27: true) == ControlItemPositionSeed.visibleOnMacOS27)
        #expect(ControlItemPositionSeed.seed(for: .visible, stored: 0.1, isMacOS27: true) == nil)
        #expect(ControlItemPositionSeed.seed(for: .visible, stored: 310, isMacOS27: true) == nil)
        #expect(ControlItemPositionSeed.seed(for: .hidden, stored: 1, isMacOS27: true) == nil)
    }

    @Test("the always-hidden divider is never seeded", arguments: [true, false])
    func alwaysHidden(isMacOS27: Bool) {
        #expect(ControlItemPositionSeed.seed(for: .alwaysHidden, stored: nil, isMacOS27: isMacOS27) == nil)
    }
}
