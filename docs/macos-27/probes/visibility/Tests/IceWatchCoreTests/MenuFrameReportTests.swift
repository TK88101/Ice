import Foundation
import Testing
@testable import IceWatchCore

/// `icewatch menu-frame` (plan 2026-10-07-icebar-menu-frame-fix, F4): one JSON
/// line that `t7-lib.zsh` checks strictly before anything starts. The display's
/// width and the bar's height are there for the helper placement check (F3).
@Suite("MenuFrameReport")
struct MenuFrameReportTests {
    func decoded(_ line: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    @Test("the five keys, sorted, numbers as numbers")
    func fits() throws {
        let line = MenuFrameReport.line(menuMaxX: 412.5, notchMinX: 771.5, displayWidth: 1728, barHeight: 32, verdict: "fits")
        #expect(line == #"{"barHeight":32,"displayWidth":1728,"menuMaxX":412.5,"notchMinX":771.5,"verdict":"fits"}"#)
        #expect(MenuFrameReport.exitCode(verdict: "fits") == 0)
    }

    @Test("a missing or non-finite value is null, never a number")
    func missing() throws {
        let line = MenuFrameReport.line(menuMaxX: nil, notchMinX: .nan, displayWidth: nil, barHeight: .infinity, verdict: "unreadable")
        let object = try decoded(line)
        for key in ["menuMaxX", "notchMinX", "displayWidth", "barHeight"] {
            #expect(object[key] is NSNull)
        }
        #expect(object["verdict"] as? String == "unreadable")
    }

    @Test("anything but fits fails the command", arguments: ["crossesNotch", "unreadable"])
    func notFits(verdict: String) {
        #expect(MenuFrameReport.exitCode(verdict: verdict) == 1)
    }
}
