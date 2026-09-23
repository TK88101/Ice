import Testing
@testable import SafeWidthCore

// MARK: - Fixtures

private func span(_ lo: Double, _ hi: Double) -> Span {
    Span(lo: lo, hi: hi)
}

private func signature(
    markerSpan: (Double, Double) = (10, 20),
    itemOffsets: [String: Double?] = [:]
) -> Signature {
    Signature(markers: ["P": .unique(span(markerSpan.0, markerSpan.1))], itemOffsets: itemOffsets)
}

// MARK: - Signature.matches

@Suite("Signature.matches")
struct SignatureMatchesTests {
    @Test("identical signatures match")
    func identicalMatch() {
        let a = signature()
        let b = signature()
        #expect(a.matches(b, tolerance: 0.5))
    }

    @Test("both markers absent for the same key match")
    func bothAbsentMatch() {
        let a = Signature(markers: ["P": .absent], itemOffsets: [:])
        let b = Signature(markers: ["P": .absent], itemOffsets: [:])
        #expect(a.matches(b, tolerance: 0.5))
    }

    @Test("marker case mismatch does not match")
    func markerCaseMismatch() {
        let a = Signature(markers: ["P": .absent], itemOffsets: [:])
        let b = Signature(markers: ["P": .unique(span(10, 20))], itemOffsets: [:])
        #expect(!a.matches(b, tolerance: 0.5))
    }

    @Test("unique span exactly at the tolerance boundary matches")
    func uniqueSpanBoundaryMatches() {
        let a = Signature(markers: ["P": .unique(span(10, 20))], itemOffsets: [:])
        let b = Signature(markers: ["P": .unique(span(10.5, 20.5))], itemOffsets: [:])
        #expect(a.matches(b, tolerance: 0.5))
    }

    @Test("unique span just past the tolerance boundary does not match")
    func uniqueSpanBoundaryExceeded() {
        let a = Signature(markers: ["P": .unique(span(10, 20))], itemOffsets: [:])
        let b = Signature(markers: ["P": .unique(span(10.51, 20))], itemOffsets: [:])
        #expect(!a.matches(b, tolerance: 0.5))
    }

    @Test("a unique span whose hi alone exceeds tolerance does not match, even with lo unchanged")
    func uniqueSpanHiAloneExceedsTolerance() {
        let a = Signature(markers: ["P": .unique(span(10, 20))], itemOffsets: [:])
        let b = Signature(markers: ["P": .unique(span(10, 20.51))], itemOffsets: [:])
        #expect(!a.matches(b, tolerance: 0.5))
    }

    @Test("ambiguous count mismatch does not match")
    func ambiguousCountMismatch() {
        let a = Signature(markers: ["P": .ambiguous([span(0, 1), span(2, 3)])], itemOffsets: [:])
        let b = Signature(markers: ["P": .ambiguous([span(0, 1)])], itemOffsets: [:])
        #expect(!a.matches(b, tolerance: 0.5))
    }

    @Test("ambiguous spans compared pairwise in order within tolerance match")
    func ambiguousPairwiseWithinTolerance() {
        let a = Signature(markers: ["P": .ambiguous([span(0, 1), span(10, 11)])], itemOffsets: [:])
        let b = Signature(markers: ["P": .ambiguous([span(0.3, 1.3), span(10.2, 10.8)])], itemOffsets: [:])
        #expect(a.matches(b, tolerance: 0.5))
    }

    @Test("ambiguous spans pairwise exceeding tolerance do not match")
    func ambiguousPairwiseExceedsTolerance() {
        let a = Signature(markers: ["P": .ambiguous([span(0, 1), span(10, 11)])], itemOffsets: [:])
        let b = Signature(markers: ["P": .ambiguous([span(0, 1), span(12, 13)])], itemOffsets: [:])
        #expect(!a.matches(b, tolerance: 0.5))
    }

    @Test("differing marker key sets do not match")
    func markerKeySetsDiffer() {
        let a = Signature(markers: ["P": .absent], itemOffsets: [:])
        let b = Signature(markers: ["Q": .absent], itemOffsets: [:])
        #expect(!a.matches(b, tolerance: 0.5))
    }

    @Test("a superset of marker keys does not match, in either direction")
    func markerKeySetsSupersetDiffers() {
        // Every key in `a` is present and matching in `b`, so the per-key loop
        // alone cannot catch this: only the key-set equality guard can.
        let a = Signature(markers: ["P": .unique(span(10, 20))], itemOffsets: [:])
        let b = Signature(
            markers: ["P": .unique(span(10, 20)), "Q": .absent],
            itemOffsets: [:]
        )
        #expect(!a.matches(b, tolerance: 0.5))
        #expect(!b.matches(a, tolerance: 0.5))
    }

    @Test("differing itemOffsets key sets do not match")
    func itemOffsetsKeySetsDiffer() {
        let a = Signature(markers: [:], itemOffsets: ["x": 1.0])
        let b = Signature(markers: [:], itemOffsets: ["y": 1.0])
        #expect(!a.matches(b, tolerance: 0.5))
    }

    @Test("a superset of itemOffsets keys does not match, in either direction")
    func itemOffsetsKeySetsSupersetDiffers() {
        let a = Signature(markers: [:], itemOffsets: ["x": 1.0])
        let b = Signature(markers: [:], itemOffsets: ["x": 1.0, "y": 2.0])
        #expect(!a.matches(b, tolerance: 0.5))
        #expect(!b.matches(a, tolerance: 0.5))
    }

    @Test("nil offset vs a value for the same key does not match")
    func itemOffsetsNilVsValue() {
        let a = Signature(markers: [:], itemOffsets: ["x": nil])
        let b = Signature(markers: [:], itemOffsets: ["x": 1.0])
        #expect(!a.matches(b, tolerance: 0.5))
    }

    @Test("both nil offsets for the same key match")
    func itemOffsetsBothNilMatch() {
        let a = Signature(markers: [:], itemOffsets: ["x": nil])
        let b = Signature(markers: [:], itemOffsets: ["x": nil])
        #expect(a.matches(b, tolerance: 0.5))
    }

    @Test("offsets within tolerance match, past it do not")
    func itemOffsetsToleranceBoundary() {
        let a = Signature(markers: [:], itemOffsets: ["x": 1.0])
        let within = Signature(markers: [:], itemOffsets: ["x": 1.5])
        let past = Signature(markers: [:], itemOffsets: ["x": 1.51])
        #expect(a.matches(within, tolerance: 0.5))
        #expect(!a.matches(past, tolerance: 0.5))
    }
}

// MARK: - SettleDetector

@Suite("SettleDetector")
struct SettleDetectorTests {
    @Test("settles once a run of two matching captures spans the settle span")
    func settlesAfterTwoMatchingCapturesSpanningSpan() {
        var detector = SettleDetector(span: 1.0, tolerance: 0.5, timeout: 10.0, start: 0.0)
        let sig = signature()
        #expect(detector.add(sig, at: 0.0) == .settling)
        #expect(detector.add(sig, at: 1.0) == .settled)
    }

    @Test("just short of the settle span the run is still settling")
    func justBelowSpanIsStillSettling() {
        var detector = SettleDetector(span: 2.0, tolerance: 0.5, timeout: 100.0, start: 0.0)
        let sig = signature()
        #expect(detector.add(sig, at: 0.0) == .settling)
        #expect(detector.add(sig, at: 1.999) == .settling)
    }

    @Test("a capture that differs from the run's reference restarts the run at that time")
    func differingCaptureRestartsRun() {
        var detector = SettleDetector(span: 1.0, tolerance: 0.5, timeout: 100.0, start: 0.0)
        let sig1 = signature(markerSpan: (10, 20))
        let sig2 = signature(markerSpan: (100, 110))

        #expect(detector.add(sig1, at: 0.0) == .settling)
        // Differs from sig1: restarts the run with sig2 as the new reference at t=0.3.
        #expect(detector.add(sig2, at: 0.3) == .settling)
        // Would have spanned 1.0s from the ORIGINAL run's start (0.0) but the run
        // restarted at 0.3, so only 0.7s of the new run has elapsed: not settled yet.
        #expect(detector.add(sig2, at: 1.0) == .settling)
        // Now a full 1.0s has elapsed since the restarted run began at 0.3.
        #expect(detector.add(sig2, at: 1.3) == .settled)
    }

    @Test("slow drift that never exceeds tolerance against its immediate neighbour, but always exceeds it against the run's fixed reference, never settles")
    func slowDriftAgainstReferenceNeverSettles() {
        // Each step drifts 0.3 from its predecessor (within the 0.5 tolerance),
        // so a detector that (incorrectly) compared only to the previous capture
        // would never restart and would settle once 2+ captures spanned `span`.
        // The span (2.0) is short enough that the correct, reference-anchored
        // detector restarts before that ever happens: every step drifts more
        // than 0.5 from the run's fixed reference within two ticks, so the run
        // keeps restarting and 2 captures never span 2.0s before a mismatch.
        var detector = SettleDetector(span: 2.0, tolerance: 0.5, timeout: 100.0, start: 0.0)
        let drift = stride(from: 10.0, through: 11.2, by: 0.3).enumerated()
        var states: [SettleState] = []
        for (i, lo) in drift {
            let sig = signature(markerSpan: (lo, lo + 10))
            states.append(detector.add(sig, at: Double(i)))
        }
        #expect(!states.contains(.settled))
    }

    @Test("times out once the overall timeout elapses without ever settling")
    func timesOutWithoutSettling() {
        var detector = SettleDetector(span: 100.0, tolerance: 0.5, timeout: 5.0, start: 0.0)
        let sig = signature()
        #expect(detector.add(sig, at: 0.0) == .settling)
        #expect(detector.add(sig, at: 5.0) == .timedOut)
    }

    @Test("settled takes precedence over timedOut when both conditions are met on the same call")
    func settledTakesPrecedenceOverTimedOut() {
        var detector = SettleDetector(span: 2.0, tolerance: 0.5, timeout: 2.0, start: 0.0)
        let sig = signature()
        #expect(detector.add(sig, at: 0.0) == .settling)
        // At t=2: run duration is 2.0 (>= span) AND time since start is 2.0 (>= timeout).
        #expect(detector.add(sig, at: 2.0) == .settled)
    }

    @Test("the first add always starts a run, even if it lands past the overall timeout")
    func firstAddStartsARun() {
        var detector = SettleDetector(span: 1.0, tolerance: 0.5, timeout: 1.0, start: 0.0)
        let sig = signature()
        // A single capture can never satisfy count >= 2, so settled is impossible here
        // regardless of how late it lands; timedOut fires instead.
        #expect(detector.add(sig, at: 5.0) == .timedOut)
    }

    @Test("with a zero settle span, a single capture is still not enough, and a mismatch restarts the count at one rather than keeping it")
    func zeroSpanStillRequiresTwoCapturesInTheCurrentRun() {
        var detector = SettleDetector(span: 0.0, tolerance: 0.5, timeout: 10.0, start: 0.0)
        let sigA = signature(markerSpan: (10, 20))
        let sigB = signature(markerSpan: (100, 110))
        // First call always starts a run: one capture is not enough to settle.
        #expect(detector.add(sigA, at: 0.0) == .settling)
        // Mismatches the reference: restarts the run with count reset to 1, which
        // is still not enough even though span is 0 and time has not advanced.
        #expect(detector.add(sigB, at: 0.0) == .settling)
        // Matches the restarted run's reference: now 2 captures in the current
        // run, and span 0 is trivially already spanned.
        #expect(detector.add(sigB, at: 0.0) == .settled)
    }
}
