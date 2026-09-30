// Rule 4, the claim: U17 and U4's claim half (pre-registration section 7), and
// U11 against the frozen assessor (claim plan R17, R19).
@testable import IceBarClaim
import IceCore
import Testing

@Suite("Rule 4: the claim")
struct ClaimTests {
    var clean: [StripImage] { Array(repeating: Bar.strip().image, count: 6) }

    var dirty: [StripImage] {
        var s = Bar.strip()
        s.stamp(Shapes.bracket(), at: 400)
        return Array(repeating: s.image, count: 6)
    }

    func baseline() throws -> BaselineOutcome { .accepted(try #require(Bar.accepted())) }

    @Test("U17: fold absent and clear is granted")
    func granted() throws {
        let outcome = Claim.decide(fold: .absent, baseline: try baseline(), captures: clean)
        #expect(outcome.granted)
        #expect(outcome.reasons.isEmpty)
        #expect(outcome.regionClear == .clear(largestCluster: 0))
    }

    @Test("U17: fold unreadable or present with clear is not granted; RegionClear is still recorded", arguments: [Fold.unreadable, .present])
    func fold(fold: Fold) throws {
        let outcome = Claim.decide(fold: fold, baseline: try baseline(), captures: clean)
        #expect(!outcome.granted)
        #expect(outcome.reasons == [.fold(fold)])
        #expect(outcome.regionClear == .clear(largestCluster: 0))
    }

    @Test("U17: fold absent with not clear is not granted")
    func notClear() throws {
        let outcome = Claim.decide(fold: .absent, baseline: try baseline(), captures: dirty)
        #expect(!outcome.granted)
        #expect(outcome.reasons == [.notClear])
    }

    @Test("U17: both causes are recorded")
    func both() throws {
        let outcome = Claim.decide(fold: .unreadable, baseline: try baseline(), captures: dirty)
        #expect(outcome.reasons == [.fold(.unreadable), .notClear])
    }

    @Test("U17 / U4: no baseline is not granted and RegionClear is never evaluated",
          arguments: [BaselineRefusal.disagree, .foldNotAbsent(.unreadable), .contrast])
    func noBaseline(refusal: BaselineRefusal) {
        let outcome = Claim.decide(fold: .absent, baseline: .refused(refusal), captures: clean)
        #expect(!outcome.granted)
        #expect(outcome.reasons == [.noBaseline(refusal)])
        #expect(outcome.regionClear == nil)
    }

    @Test("R16: an attempt of five captures is not granted")
    func partialAttempt() throws {
        let outcome = Claim.decide(fold: .absent, baseline: try baseline(), captures: Array(clean.prefix(5)))
        #expect(outcome.reasons == [.notClear])
        #expect(outcome.regionClear == .notClear(.captureCount(5)))
    }

    // MARK: U11

    func observation(_ image: StripImage) -> [ObservationSample] {
        (0..<3).map {
            ObservationSample(time: 10 + 0.5 * Double($0), before: image, after: image, agentFrames: Bar.agentFrames, itemFrames: Bar.itemFrames)
        }
    }

    func chain(_ image: StripImage) -> (Fold, ClaimOutcome) {
        let samples = Bar.samples(Bar.strip().image)
        let frozen = Bar.frozen(samples)
        let verdict = HiddenBaseline.evaluate(kept: Array(samples.dropFirst()), frozen: frozen, references: Bar.references, visible: Bar.visible)
        let obs = observation(image)
        let reading = StripAssessor.observe(baseline: frozen, targets: [], references: Bar.references, samples: obs, parameters: .preRegistered)
        return (reading.fold, Claim.decide(fold: reading.fold, baseline: verdict.outcome, captures: obs.flatMap { [$0.before, $0.after] }))
    }

    @Test("U11: a red glyph in the region is not clear, while the frozen observe reads the fold absent")
    func u11() {
        var red = Bar.strip()
        red.stamp(Shapes.bracket(), at: 400, ink: (255, 0, 0))
        let (fold, outcome) = chain(red.image)
        #expect(fold == .absent)
        #expect(!outcome.granted)
        #expect(outcome.reasons == [.notClear])
    }

    @Test("U11 control: the same chain without the glyph is granted")
    func u11Control() {
        let (fold, outcome) = chain(Bar.strip().image)
        #expect(fold == .absent)
        #expect(outcome.granted)
    }
}
