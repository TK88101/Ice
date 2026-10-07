import CoreGraphics
import Testing
import IceCore
@testable import MenuBarDiscovery

/// The bridge between IceCore's `BarRect` and CoreGraphics (plan
/// 2026-10-07-icebar-menu-frame-fix, Phase 3): one conversion for every caller.
@Suite("BarRect+CoreGraphics")
struct BarRectCoreGraphicsTests {
    @Test("a CGRect and back is the same rect, every field")
    func roundTrip() {
        let rect = CGRect(x: 10.5, y: 0, width: 563.5, height: 33)
        let bar = BarRect(rect)
        #expect(bar == BarRect(minX: 10.5, minY: 0, width: 563.5, height: 33))
        #expect(bar.cgRect == rect)
        #expect(bar.maxY == 33)
    }
}
