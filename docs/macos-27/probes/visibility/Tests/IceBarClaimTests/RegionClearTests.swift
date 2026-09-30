// Rules 2-3, `RegionClear`: U10, U12-U16 (pre-registration section 7) and the
// capture count of claim plan R16.
@testable import IceBarClaim
import IceCore
import Testing

@Suite("Rules 2-3: RegionClear")
struct RegionClearTests {
    func grey(_ d: Int) -> RGB3 { (UInt8(40 + d), UInt8(40 + d), UInt8(40 + d)) }

    func block(_ count: Int, at x0: Int, _ y0: Int, _ c: RGB3) -> StripImage {
        var s = Bar.strip()
        for i in 0..<count { s.set(x0 + i % 4, y0 + i / 4, c) }
        return s.image
    }

    func clear(_ captures: [StripImage], baseline: HiddenBaseline? = Bar.accepted()) throws -> RegionClearOutcome {
        RegionClear.evaluate(baseline: try #require(baseline), captures: captures)
    }

    @Test("six captures equal to the stored image are clear")
    func unchanged() throws {
        #expect(try clear(Array(repeating: Bar.strip().image, count: 6)) == .clear(largestCluster: 0))
    }

    @Test("R16: other than six captures is not clear", arguments: [0, 5, 7])
    func count(n: Int) throws {
        #expect(try clear(Array(repeating: Bar.strip().image, count: n)) == .notClear(.captureCount(n)))
    }

    @Test("U10: a capture of a different width, height or scale is not clear")
    func u10() throws {
        let base = Bar.strip().image
        let others = [Strip(widthPt: 401).image, Strip(heightPt: 25).image,
                      StripImage(width: base.width, height: base.height, scale: 1, bytes: base.bytes)]
        for other in others {
            var captures = Array(repeating: base, count: 6)
            captures[2] = other
            #expect(try clear(captures) == .notClear(.shapeMismatch(index: 2)))
        }
    }

    @Test("U12: a glyph inside an agent frame at observation is not clear")
    func u12() throws {
        let reads = Array(repeating: Bar.agentFrames + [AgentFrame(minX: 200, minY: 0, width: 20)], count: 5)
        let baseline = Bar.accepted(reads: reads)
        var glyph = Bar.strip()
        glyph.stamp(Shapes.bracket(), at: 400)
        let outcome = try clear(Array(repeating: glyph.image, count: 6), baseline: baseline)
        guard case .notClear(.changed(index: 0, clusterPx: let size)) = outcome else {
            Issue.record("\(outcome)")
            return
        }
        #expect(size >= 16)
    }

    @Test("U13: >= 16 changed px right of the notch is not clear; all changed px in notch columns is clear")
    func u13() throws {
        var straddle = Bar.strip()
        straddle.stamp(Shapes.bracket(), at: 312)
        guard case .notClear(.changed(index: 0, _)) = try clear(Array(repeating: straddle.image, count: 6)) else {
            Issue.record("straddle read as clear")
            return
        }
        var inside = Bar.strip()
        inside.stamp(Shapes.bracket(), at: 290)
        #expect(try clear(Array(repeating: inside.image, count: 6)) == .clear(largestCluster: 0))
    }

    @Test("U14: one discrepant capture of six is not clear")
    func u14() throws {
        var captures = Array(repeating: Bar.strip().image, count: 6)
        captures[4] = block(16, at: 400, 20, Bar.white)
        #expect(try clear(captures) == .notClear(.changed(index: 4, clusterPx: 16)))
    }

    @Test("U15: an observation equal to a kept capture T_agree off the stored image is clear")
    func u15Agree() throws {
        var off = Bar.strip()
        off.set(400, 30, grey(8))
        let base = Bar.strip().image
        let images = (0..<10).map { $0 == 5 ? off.image : base }
        guard case let .accepted(baseline) = Bar.verdict(Bar.samples(base, images: images)).outcome else {
            Issue.record("baseline refused")
            return
        }
        #expect(try clear(Array(repeating: off.image, count: 6), baseline: baseline) == .clear(largestCluster: 0))
    }

    @Test("U15: a 16-px cluster at T_diff is clear, at T_diff + 1 not; a 15-px cluster at 255 is clear", arguments: [
        (16, 32, true), (16, 33, false), (15, 215, true),
    ])
    func u15Limits(count: Int, delta: Int, isClear: Bool) throws {
        let outcome = try clear(Array(repeating: block(count, at: 400, 20, grey(delta)), count: 6))
        if isClear {
            #expect(outcome == .clear(largestCluster: delta > 32 ? count : 0))
        } else {
            #expect(outcome == .notClear(.changed(index: 0, clusterPx: count)))
        }
    }

    @Test("U16: a uniform +40 shift of the whole region is not clear")
    func u16() throws {
        var shifted = Bar.strip()
        shifted.fill(Bar.regionColumns, grey(40))
        guard case .notClear(.changed(index: 0, _)) = try clear(Array(repeating: shifted.image, count: 6)) else {
            Issue.record("a backdrop change read as clear")
            return
        }
    }
}
