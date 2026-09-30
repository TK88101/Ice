// T1 (docs/plans/2026-09-28-c2-protocol.md section 4): the band, range
// expansion, edge refinement, the intersection, L and the collar.
import C2Core
import Testing

@Suite("C2Band")
struct C2BandTests {
    private func readings(_ pairs: [(Int, C2Reading)]) -> [C2Point] {
        pairs.map { C2Point(length: Double($0.0), reading: $0.1) }
    }

    // MARK: - band

    @Test("no hidden point -> no band")
    func noHiddenNoBand() {
        #expect(C2Band.band(readings([(600, .stillDrawn), (616, .hiddenFolded)])) == nil)
    }

    @Test("one hidden point is a zero-width band")
    func oneHiddenPoint() {
        #expect(C2Band.band(readings([(600, .hiddenFolded), (616, .hiddenNoFold), (632, .stillDrawn)])) == C2Span(lo: 616, hi: 616))
    }

    @Test("a non-hidden point splits the run; the widest run wins, input order irrelevant")
    func splitWidestWins() {
        let points = readings([(680, .hiddenNoFold), (616, .hiddenNoFold), (632, .notShown), (648, .hiddenNoFold), (664, .hiddenNoFold)])
        #expect(C2Band.band(points) == C2Span(lo: 648, hi: 680))
    }

    @Test("equal-width runs: the lower one wins, deterministically")
    func tieLowerWins() {
        let points = readings([(600, .hiddenNoFold), (616, .hiddenNoFold), (632, .stillDrawn), (648, .hiddenNoFold), (664, .hiddenNoFold)])
        #expect(C2Band.band(points) == C2Span(lo: 600, hi: 616))
    }

    // MARK: - expansion

    @Test("the band touches neither end -> no expansion")
    func closedBandNoExpansion() {
        let points = readings([(520, .hiddenFolded), (536, .hiddenNoFold), (552, .stillDrawn)])
        #expect(C2Band.nextExpansion(points) == nil)
    }

    @Test("no hidden point -> expand downward first, 160 pt chunk at 16 pt steps")
    func noBandExpandsDown() {
        let points = readings([(520, .hiddenFolded), (960, .stillDrawn)])
        #expect(C2Band.nextExpansion(points) == Array(stride(from: 360.0, through: 504.0, by: 16.0)))
    }

    @Test("band open at the top -> expand upward, capped at 1000")
    func openTopExpandsUpCapped() {
        let points = readings([(520, .hiddenFolded), (944, .hiddenNoFold), (960, .hiddenNoFold)])
        #expect(C2Band.nextExpansion(points) == [976.0, 992.0, 1000.0])
    }

    @Test("band open at the bottom -> expand downward, floored at 0")
    func openBottomExpandsDownFloored() {
        let points = readings([(96, .hiddenNoFold), (112, .stillDrawn)])
        #expect(C2Band.nextExpansion(points) == [0.0, 16.0, 32.0, 48.0, 64.0, 80.0])
    }

    @Test("open at 1000 and closed below -> no further expansion")
    func openAtCapStops() {
        let points = readings([(984, .hiddenFolded), (1000, .hiddenNoFold)])
        #expect(C2Band.nextExpansion(points) == nil)
    }

    @Test("less than one step above 0 still reaches 0 -- never an empty chunk")
    func nearZeroReachesZero() {
        #expect(C2Band.nextExpansion(readings([(8, .stillDrawn), (960, .stillDrawn)])) == [0.0])
    }

    @Test("no hidden point and already scanned down to 0 -> expand upward; everything scanned -> nil")
    func noBandUpwardThenExhausted() {
        #expect(C2Band.nextExpansion(readings([(0, .stillDrawn), (960, .stillDrawn)])) == [976.0, 992.0, 1000.0])
        #expect(C2Band.nextExpansion(readings([(0, .stillDrawn), (1000, .stillDrawn)])) == nil)
    }

    // MARK: - refinement

    @Test("refinement: three 4 pt points in each 16 pt gap that straddles an edge")
    func refinementPoints() {
        let points = readings([(600, .hiddenFolded), (616, .hiddenNoFold), (632, .hiddenNoFold), (648, .stillDrawn)])
        #expect(C2Band.refinementPoints(points) == [604, 608, 612, 636, 640, 644])
    }

    @Test("refinement: an edge at the scan's end has no gap to refine; no band -> none")
    func refinementAtEnds() {
        #expect(C2Band.refinementPoints(readings([(1000, .hiddenNoFold), (984, .stillDrawn)])) == [988, 992, 996])
        #expect(C2Band.refinementPoints(readings([(600, .stillDrawn)])).isEmpty)
    }

    // MARK: - intersection, L, collar

    @Test("intersection of bands; empty when any is disjoint or the list is empty")
    func intersection() {
        #expect(C2Band.intersection([C2Span(lo: 600, hi: 800), C2Span(lo: 650, hi: 900)]) == C2Span(lo: 650, hi: 800))
        #expect(C2Band.intersection([C2Span(lo: 600, hi: 640), C2Span(lo: 650, hi: 900)]) == nil)
        #expect(C2Band.intersection([]) == nil)
    }

    @Test("L: the midpoint rounded, only when the intersection is at least 32 pt wide")
    func lengthPick() {
        #expect(C2Band.length(C2Span(lo: 650, hi: 683)) == 667)
        #expect(C2Band.length(C2Span(lo: 650, hi: 682)) == 666)
        #expect(C2Band.length(C2Span(lo: 650, hi: 681)) == nil)
    }

    @Test("collar: nine 4 pt points from L-16 to L+16")
    func collar() {
        #expect(C2Band.collar(700) == [684, 688, 692, 696, 700, 704, 708, 712, 716])
    }
}
