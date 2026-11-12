import Testing
@testable import IceCore

@Suite("SmartRehideRule")
struct SmartRehideRuleTests {
    let screen = BarRect(minX: 0, minY: 0, width: 1728, height: 1117)

    @Test("the system's full-screen windows above every app are overlays, not what was clicked")
    func overlays() {
        // As listed on 26A434: Notification Centre at 21, the Dock's at 20.
        #expect(SmartRehideRule.isSystemOverlay(layer: 21, frame: screen, screen: screen))
        #expect(SmartRehideRule.isSystemOverlay(layer: 20, frame: screen, screen: screen))
    }

    @Test("the Dock itself is not: it is at that level but not the screen's size")
    func theDock() {
        #expect(!SmartRehideRule.isSystemOverlay(layer: 20, frame: BarRect(minX: 400, minY: 1056, width: 900, height: 61), screen: screen))
    }

    @Test("an app's window is not, however large")
    func appWindows() {
        #expect(!SmartRehideRule.isSystemOverlay(layer: 0, frame: screen, screen: screen))
        #expect(!SmartRehideRule.isSystemOverlay(layer: 3, frame: BarRect(minX: 120, minY: 597, width: 320, height: 228), screen: screen))
    }

    @Test("a second display's overlay covers that display")
    func secondDisplay() {
        let second = BarRect(minX: 1728, minY: 0, width: 1920, height: 1080)
        #expect(SmartRehideRule.isSystemOverlay(layer: 20, frame: second, screen: second))
        #expect(!SmartRehideRule.isSystemOverlay(layer: 20, frame: screen, screen: second))
    }
}
