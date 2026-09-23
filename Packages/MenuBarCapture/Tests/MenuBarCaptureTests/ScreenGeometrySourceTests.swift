import CoreGraphics
import Testing
@testable import MenuBarCapture
import IceCore

private struct FakeScreen: ScreenGeometrySource {
    var boundsPt: CGRect
    var backingScaleFactor: CGFloat
    var menuBarHeightPt: CGFloat
    var notchLeftMaxX: CGFloat?
    var notchRightMinX: CGFloat?
}

@Suite("BarGeometry(screen:)")
struct ScreenGeometrySourceTests {
    @Test("reads width, height and scale from the screen")
    func readsBasics() {
        let screen = FakeScreen(
            boundsPt: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            backingScaleFactor: 2,
            menuBarHeightPt: 32,
            notchLeftMaxX: nil,
            notchRightMinX: nil
        )

        let geometry = BarGeometry(screen: screen)

        #expect(geometry?.widthPt == 1728)
        #expect(geometry?.heightPt == 32)
        #expect(geometry?.scale == 2)
        #expect(geometry?.notch == nil)
    }

    @Test("computes the notch span relative to the screen's own left edge")
    func computesNotchRelativeToScreen() {
        let screen = FakeScreen(
            boundsPt: CGRect(x: 100, y: 0, width: 1728, height: 1117),
            backingScaleFactor: 2,
            menuBarHeightPt: 32,
            notchLeftMaxX: 100 + 800,
            notchRightMinX: 100 + 928
        )

        let geometry = BarGeometry(screen: screen)

        #expect(geometry?.notch == PtSpan(lo: 800, hi: 928))
    }

    @Test("nil notch when the notch's own span is inverted")
    func rejectsInvertedNotch() {
        let screen = FakeScreen(
            boundsPt: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            backingScaleFactor: 2,
            menuBarHeightPt: 32,
            notchLeftMaxX: 900,
            notchRightMinX: 800
        )

        #expect(BarGeometry(screen: screen)?.notch == nil)
    }

    @Test("nil geometry when the screen reports no menu bar height")
    func nilWhenNoBarHeight() {
        let screen = FakeScreen(
            boundsPt: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            backingScaleFactor: 2,
            menuBarHeightPt: 0,
            notchLeftMaxX: nil,
            notchRightMinX: nil
        )

        #expect(BarGeometry(screen: screen) == nil)
    }

    @Test("nil geometry when the screen reports zero width")
    func nilWhenNoWidth() {
        let screen = FakeScreen(
            boundsPt: CGRect(x: 0, y: 0, width: 0, height: 1117),
            backingScaleFactor: 2,
            menuBarHeightPt: 32,
            notchLeftMaxX: nil,
            notchRightMinX: nil
        )

        #expect(BarGeometry(screen: screen) == nil)
    }

    @Test("nil geometry when the backing scale factor is zero")
    func nilWhenNoScale() {
        let screen = FakeScreen(
            boundsPt: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            backingScaleFactor: 0,
            menuBarHeightPt: 32,
            notchLeftMaxX: nil,
            notchRightMinX: nil
        )

        #expect(BarGeometry(screen: screen) == nil)
    }
}
