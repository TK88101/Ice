import Testing
@testable import C1Core

/// Section 4: an owner-only roster (Target and the spacer excluded) plus
/// Protected as a separate one-miss condition; one credible disappearance
/// trips at once; a capture failure or a late AX read is an immediate
/// abort; the miss state resets only after a passing reset check.
@Suite("Latch")
struct LatchTests {
    @Test("a quiet observation never trips")
    func quiet() {
        var latch = Latch()
        #expect(latch.observe(.init()) == nil)
        #expect(latch.isTripped == false)
    }

    @Test("a missing owner item trips at once, on the first miss")
    func ownerMissTripsAtOnce() {
        var latch = Latch()
        #expect(latch.observe(.init(missingOwnerItems: ["owner-1"])) == .ownerItemMissing("owner-1"))
        #expect(latch.isTripped)
    }

    @Test("Protected missing trips")
    func protectedMissTrips() {
        var latch = Latch()
        #expect(latch.observe(.init(protectedMissing: true)) == .protectedMissing)
    }

    @Test("unexplained residual ink change trips")
    func residualInkChangeTrips() {
        var latch = Latch()
        #expect(latch.observe(.init(residualInkChanged: true)) == .residualInkChanged)
    }

    @Test("the fold appearing with no expansion in progress trips")
    func foldAppearedTrips() {
        var latch = Latch()
        #expect(latch.observe(.init(foldAppearedWithoutExpansion: true)) == .foldAppeared)
    }

    @Test("a failed capture is an immediate abort, ahead of any other reading")
    func captureFailureAborts() {
        var latch = Latch()
        let observation = Latch.Observation(missingOwnerItems: ["owner-1"], protectedMissing: true, captureFailed: true)
        #expect(latch.observe(observation) == .captureFailed)
    }

    @Test("the Target's own disappearance is never in the owner roster the latch sees, so it cannot trip")
    func targetChangeIgnored() {
        // Target and the spacer are excluded by the caller before this ever
        // reaches the latch -- `missingOwnerItems` never carries them.
        var latch = Latch()
        #expect(latch.observe(.init(missingOwnerItems: [])) == nil)
    }

    @Test("once tripped, later observations report nothing more until reset")
    func staysTrippedUntilReset() {
        var latch = Latch()
        _ = latch.observe(.init(protectedMissing: true))
        #expect(latch.observe(.init(missingOwnerItems: ["owner-1"])) == nil)
        #expect(latch.isTripped)
    }

    @Test("a passing reset check clears the miss state")
    func resetClears() {
        var latch = Latch()
        _ = latch.observe(.init(protectedMissing: true))
        latch.resetAfterPassingCheck()
        #expect(latch.isTripped == false)
        #expect(latch.observe(.init(protectedMissing: true)) == .protectedMissing)
    }
}
