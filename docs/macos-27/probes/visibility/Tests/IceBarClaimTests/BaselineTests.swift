// Rule 1, the hidden-state baseline: U1-U7, U9 (pre-registration section 7) and
// the structural refusals of claim plan R1, R3, R4. Each case asserts the
// clause it names; where the texture bound also refuses the input, the whole
// verdict is asserted too (claim plan R15).
@testable import IceBarClaim
import IceBarOracle
import IceCore
import Testing

@Suite("Rule 1: hidden-state baseline")
struct BaselineTests {
    func cluster(_ count: Int, at x0: Int, _ y0: Int, _ c: RGB3) -> Strip {
        var s = Bar.strip()
        s.block(count, at: x0, y0, c)
        return s
    }


    // MARK: U1

    @Test("U1: identical kept captures of a uniform region are accepted; the stored image is the first kept capture")
    func u1() {
        let image = Bar.strip().image
        let verdict = Bar.verdict(Bar.samples(image))
        guard case let .accepted(baseline) = verdict.outcome else {
            Issue.record("refused: \(verdict.outcome)")
            return
        }
        #expect(baseline.stored == image)
        #expect(baseline.region == PtSpan(lo: 160, hi: 300))
        #expect(baseline.canonicalAgentFrames == Bar.agentFrames)
        #expect(verdict.failedClauses.isEmpty)
        #expect(verdict.measurements.maxAgreementDistance == 0)
    }

    @Test("U1: the stored image is the earliest kept sample's before capture, whatever the input order")
    func storedIsEarliest() {
        var marked = Bar.strip()
        marked.set(400, 30, Bar.grey(4))
        let base = Bar.strip().image
        let samples = Bar.samples(base, images: Bar.captures(base, replacing: 2, with: marked.image))
        let verdict = HiddenBaseline.evaluate(kept: Array(samples.dropFirst()).reversed(), frozen: Bar.frozen(samples),
                                              references: Bar.references, visible: Bar.visible)
        guard case let .accepted(baseline) = verdict.outcome else {
            Issue.record("refused: \(verdict.outcome)")
            return
        }
        #expect(baseline.stored == marked.image)
    }

    // MARK: U2

    @Test("U2: one pixel of one kept capture off by T_agree is accepted, by T_agree + 1 refused", arguments: [(8, true), (9, false)])
    func u2(delta: Int, accepted: Bool) {
        var off = Bar.strip()
        off.set(400, 30, Bar.grey(delta))
        let base = Bar.strip().image
        let verdict = Bar.verdict(Bar.samples(base, images: Bar.captures(base, replacing: 5, with: off.image)))
        #expect(verdict.measurements.maxAgreementDistance == delta)
        if accepted {
            #expect(verdict.failedClauses.isEmpty)
        } else {
            #expect(verdict.failedClauses == [.disagree])
            #expect(verdict.outcome == .refused(.disagree))
        }
    }

    @Test("U2: agent frames are included in the agreement check")
    func u2AgentFramesIncluded() {
        let reads = Array(repeating: Bar.agentFrames + [AgentFrame(minX: 200, minY: 0, width: 20)], count: 5)
        var off = Bar.strip()
        off.set(410, 30, Bar.grey(9))
        let base = Bar.strip().image
        let verdict = Bar.verdict(Bar.samples(base, images: Bar.captures(base, replacing: 7, with: off.image), reads: reads))
        #expect(verdict.outcome == .refused(.disagree))
    }

    // MARK: U3

    @Test("U3: a kept capture of a different width, height or scale is refused")
    func u3() {
        let base = Bar.strip().image
        let good = Bar.samples(base)
        let wider = Strip(widthPt: 401).image
        let taller = Strip(heightPt: 25).image
        let rescaled = StripImage(width: base.width, height: base.height, scale: 1, bytes: base.bytes)
        for other in [wider, taller, rescaled] {
            let verdict = Bar.verdict(Bar.samples(base, images: Bar.captures(base, replacing: 6, with: other)), frozenFrom: good)
            #expect(verdict.outcome == .refused(.capturesDiffer))
        }
    }

    @Test("R3: captures agreeing with each other but not with the frozen geometry are refused")
    func r3() {
        let good = Bar.samples(Bar.strip().image)
        let verdict = Bar.verdict(Bar.samples(Strip(widthPt: 401).image), frozenFrom: good)
        #expect(verdict.outcome == .refused(.capturesDiffer))
    }

    // MARK: U4

    @Test("U4: a frozen baseline fold that is not absent refuses, before anything is measured")
    func u4() {
        let strip = cluster(16, at: 400, 20, Bar.white)
        let verdict = Bar.verdict(Bar.samples(strip.image))
        #expect(verdict.outcome == .refused(.foldNotAbsent(.unreadable)))
        #expect(verdict.measurements == BaselineMeasurements())
        #expect(verdict.failedClauses.isEmpty)
    }

    // MARK: U5

    @Test("U5: a 16-px cluster at T_bg + 1 from its row median is refused by the row-median clause")
    func u5Refused() {
        let verdict = Bar.verdict(Bar.samples(cluster(16, at: 400, 20, Bar.grey(33)).image))
        #expect(verdict.failedClauses.first == .rowDeviation)
        #expect(verdict.outcome == .refused(.rowDeviation))
        #expect(verdict.measurements.largestRowCluster == 16)
    }

    @Test("U5: 15 px at T_bg + 1, or 16 px at T_bg, pass the row-median clause; the texture bound still refuses (R15)",
          arguments: [(15, 33), (16, 32)])
    func u5Accepted(count: Int, delta: Int) {
        let verdict = Bar.verdict(Bar.samples(cluster(count, at: 400, 20, Bar.grey(delta)).image))
        #expect(!verdict.failedClauses.contains(.rowDeviation))
        #expect(verdict.failedClauses == [.texture])
        #expect(verdict.outcome == .refused(.texture))
        #expect(verdict.measurements.maxRowDeviation == delta)
    }

    // MARK: U6

    let inRegionAgent = Array(repeating: Bar.agentFrames + [AgentFrame(minX: 200, minY: 0, width: 20)], count: 5)

    @Test("U6: a deviating cluster wholly inside a baseline agent frame is accepted")
    func u6Inside() {
        let verdict = Bar.verdict(Bar.samples(cluster(16, at: 410, 20, Bar.grey(60)).image, reads: inRegionAgent))
        #expect(verdict.failedClauses.isEmpty)
        #expect(Bar.isAccepted(verdict))
        #expect(verdict.measurements.largestRowCluster == 0)
    }

    @Test("U6: the same cluster extending 16 px outside the frame is refused")
    func u6Outside() {
        var strip = Bar.strip()
        for x in 432..<448 {
            for y in 20..<22 { strip.set(x, y, Bar.grey(60)) }
        }
        let verdict = Bar.verdict(Bar.samples(strip.image, reads: inRegionAgent))
        #expect(verdict.failedClauses.first == .rowDeviation)
        #expect(verdict.measurements.largestRowCluster == 16)
    }

    // MARK: U7

    @Test("U7: a deviation inside notch columns only is accepted")
    func u7() {
        var strip = Bar.strip()
        strip.fill(250..<270, rows: 10..<30, Bar.white)
        let verdict = Bar.verdict(Bar.samples(strip.image))
        #expect(verdict.failedClauses.isEmpty)
        #expect(Bar.isAccepted(verdict))
    }

    // MARK: U9

    func reads(changingSample index: Int, to frames: [AgentFrame]) -> [[AgentFrame]] {
        (0..<5).map { $0 == index ? frames : Bar.agentFrames }
    }

    @Test("U9: one frame shifted 1.5 pt, one added, one removed in a kept read is refused", arguments: [
        [AgentFrame(minX: 371.5, minY: 0, width: 12), AgentFrame(minX: 386, minY: 0, width: 8)],
        Bar.agentFrames + [AgentFrame(minX: 396, minY: 0, width: 3)],
        [AgentFrame(minX: 370, minY: 0, width: 12)],
    ])
    func u9Moved(frames: [AgentFrame]) {
        let verdict = Bar.verdict(Bar.samples(Bar.strip().image, reads: reads(changingSample: 2, to: frames)))
        #expect(verdict.outcome == .refused(.agentFramesMoved))
    }

    @Test("U9: an off-bar frame added is accepted, a chevron-width one included", arguments: [
        AgentFrame(minX: 396, minY: 30, width: 3), AgentFrame(minX: 396, minY: -30, width: 3), AgentFrame(minX: 380, minY: 24, width: 17.5),
    ])
    func u9OffBar(extra: AgentFrame) {
        let verdict = Bar.verdict(Bar.samples(Bar.strip().image, reads: reads(changingSample: 2, to: Bar.agentFrames + [extra])))
        #expect(verdict.failedClauses.isEmpty)
        #expect(Bar.isAccepted(verdict))
    }

    @Test("U9: a chevron-width on-bar frame in any kept read is refused")
    func u9Chevron() {
        let base = Bar.strip().image
        let chevron = Bar.agentFrames + [AgentFrame(minX: 340, minY: 0, width: 17.5)]
        let verdict = Bar.verdict(Bar.samples(base, reads: reads(changingSample: 2, to: chevron)), frozenFrom: Bar.samples(base))
        #expect(verdict.outcome == .refused(.chevronFrame))
    }

    // MARK: R1, R4

    @Test("R1: other than four kept samples is refused", arguments: [3, 5])
    func r1Count(count: Int) {
        let samples = Bar.samples(Bar.strip().image)
        let extra = ObservationSample(time: 5, before: samples[0].before, after: samples[0].after,
                                      agentFrames: Bar.agentFrames, itemFrames: Bar.itemFrames)
        let kept = Array((samples + [extra]).dropFirst().prefix(count))
        let verdict = HiddenBaseline.evaluate(kept: kept, frozen: Bar.frozen(samples), references: Bar.references, visible: Bar.visible)
        #expect(verdict.outcome == .refused(.keptCount(count)))
    }

    @Test("R1: a frozen baseline whose agent frames are not the latest kept read's is refused")
    func r1Frozen() {
        let image = Bar.strip().image
        let other = Bar.samples(image, reads: reads(changingSample: 4, to: [AgentFrame(minX: 370, minY: 0, width: 12)]))
        let verdict = Bar.verdict(Bar.samples(image), frozenFrom: other)
        #expect(verdict.outcome == .refused(.frozenMismatch))
    }

    @Test("R4: no references, an unknown reference, or no eligible pixel refuses as region undefined")
    func r4() {
        let samples = Bar.samples(Bar.strip().image)
        #expect(Bar.verdict(samples, references: []).outcome == .refused(.regionUndefined))
        #expect(Bar.verdict(samples, references: ["reference", "nope"]).outcome == .refused(.regionUndefined))
        let covering = Array(repeating: Bar.agentFrames + [AgentFrame(minX: 160, minY: 0, width: 140)], count: 5)
        #expect(Bar.verdict(Bar.samples(Bar.strip().image, reads: covering)).outcome == .refused(.regionUndefined))
    }
}
