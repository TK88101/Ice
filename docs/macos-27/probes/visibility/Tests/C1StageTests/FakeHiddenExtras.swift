// C2 T3 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 3): the fake bar's
// extra hidden-section items, hidden-2...4 -- fixed identities, rest
// positions strictly between Target (150) and the spacer (190), and a glyph
// each, distinct from every other shape on the fake bar so each gets its own
// unique template.
import C1Core
import C1Stage
import Darwin
import IceCore

extension FakeBarWorld {
    static let hiddenExtraNumbers = 2...4

    static func hiddenExtraPID(_ number: Int) -> pid_t { pid_t(9002 + number) }
    static func hiddenExtraIdentifier(_ number: Int) -> String { "vz-hidden-\(number)" }
    static func hiddenExtraKey(_ number: Int) -> ItemKey {
        key("hidden\(number)", pid: hiddenExtraPID(number), identifier: hiddenExtraIdentifier(number))
    }
    /// 160, 170, 180: left to right after Target, before the spacer.
    static func hiddenExtraRestX(_ number: Int) -> Double { targetRestX + Double(number - 1) * 10 }
    /// Far off the strip once the spacer expands, like Target.
    static func hiddenExtraHiddenX(_ number: Int) -> Double { targetHiddenX - Double(number) * 20 }
    static func hiddenExtraRole(_ number: Int) -> String { "hidden-\(number)" }

    static func hiddenExtraNumber(role: String) -> Int? {
        guard role.hasPrefix("hidden-"), let number = Int(role.dropFirst("hidden-".count)), hiddenExtraNumbers.contains(number) else { return nil }
        return number
    }

    static func shapeHidden(_ number: Int) -> [String] {
        switch number {
        case 2: [
            "##....####", "##....####", "##........", "##........", "######....",
            "######....", "....##....", "....##....", "....######", "....######",
        ]
        case 3: [
            "##......##", "##......##", "##......##", "##########", "##########",
            "##......##", "##......##", "##......##", "##......##", "##......##",
        ]
        default: [
            "##########", "##########", "........##", ".......##.", "......##..",
            ".....##...", "....##....", "...##.....", "..##......", ".##.......",
        ]
        }
    }
}
