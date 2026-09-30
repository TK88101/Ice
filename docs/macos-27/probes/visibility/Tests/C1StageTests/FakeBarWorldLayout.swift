// I7's fake bar layout split out of FakeBarWorld.swift (rework #8, to stay
// under the 800-line cap): every fixed X/Y position, identity (key/pid) and
// glyph shape the world draws, as `static` members of `FakeBarWorld` itself
// (an extension, not a new type -- these are still exactly
// `FakeBarWorld.targetRestX` etc. to every call site). See
// `FakeBarWorld.swift`'s own header for what the world as a whole models.
import Darwin
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDiscovery

extension FakeBarWorld {
    static let widthPt = 320
    static let heightPt = 12
    static let scale = 2
    static let backdrop = RGBA(40, 40, 40)
    static let ink = RGBA(255, 255, 255)

    static var geometry: BarGeometry {
        BarGeometry(widthPt: Double(widthPt), heightPt: Double(heightPt), scale: Double(scale), notch: nil)
    }

    static let bounds = BarBounds(minX: 0, maxX: Double(widthPt), minY: 0, barHeight: Double(heightPt))

    // MARK: - Fixed layout (points)

    static let targetRestX = 150.0
    static let spacerX = 190.0
    static let protectedX = 230.0
    /// The one owner item the pixel baseline accepts as a template.
    static let ownerX = 270.0
    /// Left of `ownerX` (Amendment v6: "at least one untemplated item LEFT
    /// of the leftmost templated one"), each 3 pt apart so every pair's AX
    /// frame (7 pt wide) overlaps its neighbour -- the same
    /// `overlapsAnotherItem` rejection the owner's own bar hits
    /// (`StripAssessor.baseline`, line ~136), never a shape the ink/template
    /// rules would simply fail to cut.
    static let extraBaseX = 250.0
    static let extraSpacingPt = 3.0
    /// Clear of everything else on the strip (Target's rest position is
    /// 150), for the "fold without expansion" knob's own chevron-width
    /// agent frame and ink.
    static let foldGhostX = 50.0
    /// Far enough off the left edge (`widthPt` starts at 0) that none of
    /// the glyph's pixels ever land inside the rendered strip -- "pushed
    /// into the undrawn band," not merely covered.
    static let targetHiddenX = -5000.0
    static let indicatorX = 300.0
    static let indicatorWidth = 20.0 // clear of chevronWidthPt (17.5) and pillWidthPt (16)

    /// Amendment v8's first bullet: the owner's own bar always lists 2-3
    /// parked items (frames below the bar) in every recorded census --
    /// modelled here as `minX`/`minY` pairs matching those recordings
    /// (numbers only, per the hard rule against third-party app names).
    /// Always present, in both discovery and AX reads -- never gated by a
    /// fault knob, since the real ones are not a fault, they are this
    /// bar's own resting state.
    static let parkedMinXs: [Double] = [7.0, 7.0, -1.0]
    static let parkedMinYs: [Double] = [1105.0, 1105.0, 1104.0]

    /// Amendment v8's second bullet (the placement gate): a layout where
    /// 1-3 owner items are drawn *left* of every helper -- the recorded
    /// live placement (section 2's "each new item lands at the left end"
    /// is false on this bar), modelling Amendment v8a's own "default
    /// realistic layout = owner items left of where helpers would land
    /// unplaced." Left of `targetRestX` (150, the *unplaced* fixed
    /// position -- what "ignored" mode keeps rendering) but with enough
    /// room for `PlacementPlan` to still find a valid pre-launch plan
    /// (Amendment v8a's own new pre-launch step): rework #8's original
    /// `40.0` sat closer to the bar's own left edge than the three
    /// helpers' combined width, so it left no room at all once that
    /// pre-launch check existed -- moved to `120.0` (rework #8a) so the
    /// "ignored" scenario still reaches the post-launch gate instead of
    /// being refused before any launch.
    static let ownerLeftOfHelpersBaseX = 120.0
    static let ownerLeftOfHelpersSpacingPt = 8.0

    /// Amendment v8a: the dedicated "no room for the helpers" fixture --
    /// close enough to the bar's own left edge (well under the three
    /// helpers' combined width plus `PlacementPlan.marginPt`) that no
    /// plan can ever fit left of it.
    static let noRoomOwnerPID: pid_t = 800
    static let noRoomOwnerKey = key("noRoomOwner", pid: noRoomOwnerPID, identifier: "owner.noRoom")

    /// Amendment v9, "Sort-key values": the dedicated on-bar owner item
    /// carrying its own stale stored preferred-position value (H5's own
    /// "one on-bar owner item with a large stale value" fixture) -- fixed
    /// far enough right that `.sortKey` mode's packed helper slots
    /// (`sortKeyAnchorX` + up to 2 x `sortKeyPitchPt`) never reach it.
    static let staleOwnerPID: pid_t = 801
    static let staleOwnerKey = key("staleOwner", pid: staleOwnerPID, identifier: "owner.stale")
    static let staleOwnerMinX = 280.0
    /// The recorded stale value itself
    /// (`~/IceReverse-evidence/20260925-092244-icerun/before/app-statusitem-keys.txt`)
    /// -- well below `PlacementPlan.historicalMaximumStoredValue` (5772),
    /// so the plan's own floor never comes from this fixture; it exists to
    /// prove the plan still lands the helpers left of it regardless.
    static let staleOwnerRecordedValue = 5703.0

    /// Amendment v9, ".sortKey" mode: where the three helpers pack, left to
    /// right, once their own written values outrank the stale owner's
    /// (always true: the plan's own floor is at least `historicalMaximumStoredValue`,
    /// always above `staleOwnerRecordedValue`). The pitch matches the real,
    /// measured 28 pt (crosscheck-rework8.json #1) -- H5's own "28-pt
    /// pitch" fixture. The anchor itself clears `IceCore.RoomGuard
    /// .minimumFreeRoom` (41 pt free right of a `0`-wide fake notch) with a
    /// few points to spare, once the AX-frame convention's own 1 pt trim
    /// (`Self.frame(atPt:)`) is subtracted.
    static let sortKeyAnchorX = 45.0
    static let sortKeyPitchPt = 28.0

    // MARK: - Identity

    static let protectedPID: pid_t = 9001
    static let spacerPID: pid_t = 9002
    static let targetPID: pid_t = 9003
    static let ownerPID: pid_t = 501

    static let protectedIdentifier = "vz-reference"
    static let spacerIdentifier = "vz-spacer"
    static let targetIdentifier = "vz-target"
    static let ownerIdentifier = "owner.a"

    static func key(_ role: String, pid: pid_t, identifier: String) -> ItemKey {
        ItemKey(namespace: "com.fakebar.\(role)", identifier: identifier, pid: pid, childIndex: nil)
    }

    static let protectedKey = key("protected", pid: protectedPID, identifier: protectedIdentifier)
    static let spacerKey = key("spacer", pid: spacerPID, identifier: spacerIdentifier)
    static let targetKey = key("target", pid: targetPID, identifier: targetIdentifier)
    static let ownerKey = key("owner", pid: ownerPID, identifier: ownerIdentifier)

    /// Never a real third-party app name (the hard rule): neutral,
    /// numbered ids, like `ownerIdentifier` above.
    static func extraPID(_ i: Int) -> pid_t { pid_t(502 + i) }
    static func extraKey(_ i: Int) -> ItemKey { key("owner", pid: extraPID(i), identifier: "owner.b\(i)") }
    static func extraX(_ i: Int) -> Double { extraBaseX + Double(i) * extraSpacingPt }

    /// Amendment v8: 3 fixed parked identities/pids, never gated -- neutral,
    /// numbered ids like `extraKey`'s, matching the hard rule.
    static func parkedPID(_ i: Int) -> pid_t { pid_t(600 + i) }
    static func parkedKey(_ i: Int) -> ItemKey { key("parked", pid: parkedPID(i), identifier: "parked.\(i)") }

    /// Amendment v8: the "helpers land right of owners" layout's own
    /// identities/pids/positions, up to 3.
    static func ownerLeftPID(_ i: Int) -> pid_t { pid_t(700 + i) }
    static func ownerLeftKey(_ i: Int) -> ItemKey { key("ownerLeft", pid: ownerLeftPID(i), identifier: "owner.left\(i)") }
    static func ownerLeftX(_ i: Int) -> Double { ownerLeftOfHelpersBaseX + Double(i) * ownerLeftOfHelpersSpacingPt }

    // MARK: - Shapes (10 px wide at scale 2 = 5 pt -- clears minTemplateWidthPt)

    static let shapeTarget: [String] = [
        "##########", "##........", "##........", "##........", "##########",
        "##########", "........##", "........##", "........##", "##########",
    ]
    static let shapeSpacer: [String] = [
        "##########", "##......##", "##......##", "##......##", "##......##",
        "##......##", "##......##", "##......##", "##......##", "##########",
    ]
    static let shapeProtected: [String] = [
        "...##.....", "...##.....", "...##.....", "##########", "##########",
        "##########", "##########", "...##.....", "...##.....", "...##.....",
    ]
    /// Asymmetric and non-periodic horizontally (unlike a checkered pattern,
    /// which can self-match at a shifted offset and read `.ambiguous`) --
    /// the owner's own item, distinct from the three helper shapes above.
    /// Reused for the untemplated cluster too: their shape is irrelevant
    /// (the baseline rejects them for overlapping, before any per-id ink
    /// cut is even attempted), only their AX frame and position matter.
    static let shapeOwner: [String] = [
        "........##", "........##", "........##", "##########", "##########",
        "##########", "##########", "##........", "##........", "##........",
    ]
    /// G3 (Amendment v7): a second, still-asymmetric owner glyph -- `shapeOwner`
    /// read top-to-bottom in reverse -- for the two "owner content changes"
    /// knobs below. It shares `shapeOwner`'s width and ink coverage (so a
    /// mismatch reads as a *content* change, not a vacated slot), but
    /// disagrees with it row-for-row, which is what makes
    /// `StripAssessor.baseline` (IceCore, frozen) refuse to call the two
    /// samples the same static template.
    static let shapeOwnerAlt: [String] = [
        "##........", "##........", "##........", "##########", "##########",
        "##########", "##########", "........##", "........##", "........##",
    ]
    /// A solid block, wide enough to clear `foldClusterMinPx` (16 px) many
    /// times over -- the "fold without expansion" knob's own ink.
    static let shapeFoldGhost: [String] = Array(repeating: "##########", count: 10)
    /// G3 (Amendment v7): `shapeOwner` with 16 cells flipped (rows 3-4).
    /// The baseline template's own cared region is 14x14 = 196 cells (a
    /// 2 pt margin around this 10x10 glyph, consistently background in
    /// every baseline sample, cared like the ink itself) -- empirically
    /// confirmed by printing `ItemTemplate.caredCount` -- so 16/196 = 0.082
    /// mismatch, inside `(DetectorParameters.maxMismatch (0.05),
    /// weakThreshold (0.12)]`. `TemplateMatcher.match` returns `.unique`
    /// with a mismatch *above* `maxMismatch` (a weak match), never
    /// `.absent` or `.ambiguous` -- `.ownerWeakMatchOnce`'s own
    /// single-capture glitch.
    static let shapeOwnerWeak: [String] = [
        "........##", "........##", "........##", "..........", "......####",
        "##########", "##########", "##........", "##........", "##........",
    ]

}
