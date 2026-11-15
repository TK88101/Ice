import Testing
@testable import IceCore

/// What a press opened and whether it still shows (plan
/// 2026-11-15-blind-at-length, D3, the `showing` phase): upstream's rule for an
/// item it shows for a click, bound to the press's own interval.
@Suite("OpenedInterfaceRule")
struct OpenedInterfaceRuleTests {
    typealias Window = OpenedInterfaceRule.Window
    /// The system's levels: a menu 101, a status window 25, the main menu 24.
    static let levels = OpenedInterfaceRule.Levels(popUpMenu: 101, status: 25, mainMenu: 24)

    // MARK: - Which window

    @Test("the first window of the pressed app that was not on screen before the press")
    func firstNewWindowOfThePid() {
        let windows = [Window(id: 9, pid: 7), Window(id: 12, pid: 5), Window(id: 11, pid: 5), Window(id: 3, pid: 5)]
        #expect(OpenedInterfaceRule.opened(by: 5, in: windows, before: [3, 9]) == 12)
    }

    @Test("a window that was on screen before the press is not what the press opened")
    func oldWindowIsNotOpened() {
        #expect(OpenedInterfaceRule.opened(by: 5, in: [Window(id: 3, pid: 5)], before: [3]) == nil)
    }

    @Test("another app's new window is not what the press opened")
    func otherAppsWindow() {
        #expect(OpenedInterfaceRule.opened(by: 5, in: [Window(id: 12, pid: 7)], before: []) == nil)
    }

    @Test("nothing on screen: nothing was opened")
    func noWindows() {
        #expect(OpenedInterfaceRule.opened(by: 5, in: [], before: [1, 2]) == nil)
    }

    // MARK: - Whether it shows

    @Test("at a menu's level, the one below it, the status level or the main menu's: shows while on screen, whoever is active", arguments: [101, 100, 25, 24])
    func menuLevels(layer: Int) {
        #expect(OpenedInterfaceRule.isShowing(layer: layer, isOnScreen: true, isAppActive: false, levels: Self.levels))
        #expect(OpenedInterfaceRule.isShowing(layer: layer, isOnScreen: true, isAppActive: true, levels: Self.levels))
        #expect(!OpenedInterfaceRule.isShowing(layer: layer, isOnScreen: false, isAppActive: true, levels: Self.levels))
    }

    @Test("at any other level: shows while on screen and its app is active", arguments: [0, 3, 8, 102, 500])
    func otherLevels(layer: Int) {
        #expect(OpenedInterfaceRule.isShowing(layer: layer, isOnScreen: true, isAppActive: true, levels: Self.levels))
        #expect(!OpenedInterfaceRule.isShowing(layer: layer, isOnScreen: true, isAppActive: false, levels: Self.levels))
        #expect(!OpenedInterfaceRule.isShowing(layer: layer, isOnScreen: false, isAppActive: true, levels: Self.levels))
    }
}
