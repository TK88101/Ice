import Darwin
import Foundation
import Testing
import IceCore
import MenuBarCapture
import MenuBarDiscovery
@testable import MenuBarDetectorFeed

/// Plan Deviation 5's two open items: a session that never produced a
/// sample reports `captureFailed` (not `cancelled`), and a reused baseline
/// is only reused when it was built for exactly the roster the fresh plan
/// names. Same synthetic bar as `HidingVerificationTests`.
@Suite("HidingVerification -- Deviation 5")
struct HidingVerificationDeviation5Tests {
    // MARK: - captureFailed

    @Test("prepare whose every capture fails, without cancellation -> .skip(.captureFailed) over the full roster")
    func prepareWithNoSampleIsCaptureFailed() async {
        let (t1, t2, ref) = HidingVerificationTests.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])

        let (verification, _, capturer, _, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([t1, t2, ref])],
            capturerResults: [],
            axResults: []
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [ref.key], reusing: nil)

        #expect(prepared.state == .skip(.captureFailed))
        #expect(Set(prepared.targets) == [t1.key, t2.key])
        #expect(capturer.callCount == 5, "one failed capture per retry, no more")
    }

    @Test("verify whose every observation capture fails, without cancellation -> every target .skipped(.captureFailed)")
    func verifyWithNoSampleIsCaptureFailed() async {
        let (t1, t2, ref) = HidingVerificationTests.basicItems()
        let sectionMap = Scenario.sectionMap([t1, t2])
        let drawn = HidingVerificationTests.drawnImage()
        let drawnSnap = HidingVerificationTests.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)

        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [Scenario.discovery([t1, t2, ref])],
            capturerResults: Scenario.repeated(drawn, count: Scenario.baselineCaptureCount()),
            axResults: Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount())
        )

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [ref.key], reusing: nil)
        guard case .ready = prepared.state else { Issue.record("expected .ready, got \(prepared.state)"); return }

        let results = await verification.verify(prepared)
        #expect(results == [t1.key: .skipped(.captureFailed), t2.key: .skipped(.captureFailed)])
    }

    @Test("a discovery that returns nil without being cancelled (no display) -> .skip(.noGeometry), not .cancelled")
    func nilDiscoveryIsNoGeometry() async {
        let (verification, _, capturer, _, _) = Scenario.makeVerification(discoveryResults: [nil], capturerResults: [], axResults: [])

        let prepared = await verification.prepare(sections: [.hidden], sectionMap: [:], explicitCandidates: nil, reusing: nil)

        #expect(prepared.state == .skip(.noGeometry))
        #expect(capturer.callCount == 0)
    }

    // MARK: - Reuse only for the same roster

    /// A verification whose discoveries, captures and reads are scripted in
    /// order, and whose clock advances 1 s per read.
    private static func scripted(
        discoveries: [DiscoveryResult],
        captures: [StripImage?],
        reads: [MenuBarAXSnapshot?]
    ) -> (HidingVerification, FakeStripCapturer) {
        let (verification, _, capturer, _, _) = Scenario.makeVerification(
            discoveryResults: discoveries,
            capturerResults: captures,
            axResults: reads
        )
        return (verification, capturer)
    }

    @Test("a target that joined the section since the baseline -> recaptured, and verify accounts for it")
    func joinedTargetRecaptures() async {
        let (t1, t2, ref) = HidingVerificationTests.basicItems()
        let firstImage = Scenario.image([(TestBar.shapeA, 60), (TestBar.shapeB, 150)])
        let firstSnap = Scenario.snapshot([(t1.key.encoded, 60), (ref.key.encoded, 150)])
        let drawn = HidingVerificationTests.drawnImage()
        let drawnSnap = HidingVerificationTests.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)

        let (verification, capturer) = Self.scripted(
            discoveries: [Scenario.discovery([t1, ref]), Scenario.discovery([t1, t2, ref])],
            captures: Scenario.repeated(firstImage, count: Scenario.baselineCaptureCount())
                + Scenario.repeated(drawn, count: Scenario.baselineCaptureCount() + Scenario.observeCaptureCount()),
            reads: Scenario.repeated(firstSnap, count: Scenario.baselineReadCount())
                + Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount() + Scenario.observeReadCount())
        )

        let first = await verification.prepare(sections: [.hidden], sectionMap: Scenario.sectionMap([t1]), explicitCandidates: [ref.key], reusing: nil)
        guard case .ready = first.state else { Issue.record("expected .ready, got \(first.state)"); return }

        let second = await verification.prepare(sections: [.hidden], sectionMap: Scenario.sectionMap([t1, t2]), explicitCandidates: [ref.key], reusing: first)
        guard case .ready(let ready) = second.state else { Issue.record("expected .ready, got \(second.state)"); return }
        #expect(capturer.callCount == Scenario.baselineCaptureCount() * 2, "a changed roster must recapture")
        #expect(Set(ready.checkableTargets) == [t1.key, t2.key])
        #expect(second.createdAt != first.createdAt)

        let results = await verification.verify(second)
        #expect(Set(results.keys) == Set(second.targets))
        #expect(results[t2.key] == .checked(.stillDrawn))
    }

    @Test("a target that left the section since the baseline -> recaptured, never reported")
    func departedTargetRecaptures() async {
        let (t1, t2, ref) = HidingVerificationTests.basicItems()
        let drawn = HidingVerificationTests.drawnImage()
        let drawnSnap = HidingVerificationTests.drawnSnapshot(t1: t1.key, t2: t2.key, ref: ref.key)

        let (verification, capturer) = Self.scripted(
            discoveries: [Scenario.discovery([t1, t2, ref]), Scenario.discovery([t1, t2, ref])],
            captures: Scenario.repeated(drawn, count: Scenario.baselineCaptureCount() * 2),
            reads: Scenario.repeated(drawnSnap, count: Scenario.baselineReadCount() * 2)
        )

        let first = await verification.prepare(sections: [.hidden], sectionMap: Scenario.sectionMap([t1, t2]), explicitCandidates: [ref.key], reusing: nil)
        guard case .ready = first.state else { Issue.record("expected .ready, got \(first.state)"); return }

        let second = await verification.prepare(sections: [.hidden], sectionMap: Scenario.sectionMap([t1]), explicitCandidates: [ref.key], reusing: first)
        guard case .ready(let ready) = second.state else { Issue.record("expected .ready, got \(second.state)"); return }
        #expect(capturer.callCount == Scenario.baselineCaptureCount() * 2, "a changed roster must recapture")
        #expect(ready.checkableTargets == [t1.key])
        #expect(second.targets == [t1.key])
    }

    @Test("a new listed item left of the reference since the baseline -> recaptured, and observed")
    func newObservedItemRecaptures() async {
        let t1 = Scenario.discoveredItem(identifier: "t1", pid: 601, rawMinX: 59, rawWidth: 9)
        let ref = Scenario.discoveredItem(identifier: "ref", pid: 603, rawMinX: 150, rawWidth: 9)
        let other = Scenario.discoveredItem(identifier: "other", pid: 608, rawMinX: 99, rawWidth: 9)
        let firstImage = Scenario.image([(TestBar.shapeA, 60), (TestBar.shapeB, 150)])
        let firstSnap = Scenario.snapshot([(t1.key.encoded, 60), (ref.key.encoded, 150)])
        let secondImage = Scenario.image([(TestBar.shapeA, 60), (TestBar.shapeC, 100), (TestBar.shapeB, 150)])
        let secondSnap = Scenario.snapshot([(t1.key.encoded, 60), (other.key.encoded, 100), (ref.key.encoded, 150)])

        let (verification, capturer) = Self.scripted(
            discoveries: [Scenario.discovery([t1, ref]), Scenario.discovery([t1, other, ref])],
            captures: Scenario.repeated(firstImage, count: Scenario.baselineCaptureCount())
                + Scenario.repeated(secondImage, count: Scenario.baselineCaptureCount()),
            reads: Scenario.repeated(firstSnap, count: Scenario.baselineReadCount())
                + Scenario.repeated(secondSnap, count: Scenario.baselineReadCount())
        )
        let sectionMap = Scenario.sectionMap([t1])

        let first = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [ref.key], reusing: nil)
        guard case .ready = first.state else { Issue.record("expected .ready, got \(first.state)"); return }

        let second = await verification.prepare(sections: [.hidden], sectionMap: sectionMap, explicitCandidates: [ref.key], reusing: first)
        guard case .ready(let ready) = second.state else { Issue.record("expected .ready, got \(second.state)"); return }
        #expect(capturer.callCount == Scenario.baselineCaptureCount() * 2, "an item the baseline never saw must recapture")
        #expect(ready.alsoObserved == [other.key])
    }
}
