// I7 (Amendment v9): sort-key placement values, real pitch, the stricter
// gate and signal precedence -- H5's own fixture list (Codex round 9b):
// a sort-key ordering mode with a stale on-bar owner value (the plan must
// still pass the gate), the 28-pt pitch, a misorder case, the
// signal-in-step1b case, and the unreadable-owner-value refusal.
import C1Core
import C1Stage
import Foundation
import Testing

@Suite("I7 -- Amendment v9 (sort-key values, real pitch, gate, signal precedence)", .serialized)
struct I7AmendmentV9Tests {
    // MARK: - Sort-key mode with a stale on-bar owner value -> still PASS

    /// crosscheck-rework8.json #0/#4: the owner's own recorded stored
    /// values do not fit a right-edge-distance reading and instead follow
    /// the items' own left-to-right order. `.sortKey` mode models macOS
    /// honouring the key that way; the stale owner item carries the
    /// recorded 5703 (below `PlacementPlan.historicalMaximumStoredValue`,
    /// 5772), so the plan's own floor stays at the historical maximum and
    /// the three helpers -- all written well above it -- still rank, and
    /// land, left of the stale owner. Also H5's own "28-pt pitch" fixture:
    /// the three helpers pack at exactly `FakeBarWorld.sortKeyPitchPt`
    /// apart.
    @Test("sort-key honoured with a stale on-bar owner value (5703) -> the plan still passes the gate, PASS, at the 28-pt pitch")
    func sortKeyHonouredWithStaleOwnerValueStillPasses() {
        let world = FakeBarWorld(placementHonoring: .sortKey, staleOwnerPresent: true)
        let run = I7.run(world: world)

        #expect(run.code == 0)
        #expect(run.evidence.lastVerdict() == "pass")
        #expect(!run.evidence.allRecords().contains { $0.kind == "placement.gateFailed" })
        #expect(!run.evidence.allRecords().contains { $0.kind == "placement.scanUncertain" })

        let planRecord = run.evidence.allRecords().first { $0.kind == "placement.plan" }
        #expect(planRecord?.fields["floorValue"] as? Double == PlacementPlan.historicalMaximumStoredValue)

        // `Self.frame(atPt:)`'s own AX-frame convention trims 1 pt off the
        // left of whatever x the world renders at.
        let gateRead = run.evidence.allRecords().first { $0.kind == "placement.gateRead" }
        #expect(gateRead?.fields["targetMinX"] as? Double == FakeBarWorld.sortKeyAnchorX - 1)
        #expect(gateRead?.fields["spacerMinX"] as? Double == FakeBarWorld.sortKeyAnchorX + FakeBarWorld.sortKeyPitchPt - 1)
        #expect(gateRead?.fields["protectedMinX"] as? Double == FakeBarWorld.sortKeyAnchorX + 2 * FakeBarWorld.sortKeyPitchPt - 1)
        #expect(world.commandLog.contains { $0.hasPrefix("spacer.length ") })
        #expect(world.commandLog.contains("protected.quit"))
        #expect(world.commandLog.contains("spacer.quit"))
        #expect(world.commandLog.contains("target.quit"))
    }

    // MARK: - Misorder (crosscheck-rework8.json #1's own gate fix)

    /// The plan's own geometry is always correctly ordered (Target <
    /// spacer < Protected, at the real occupied pitch); this fixture
    /// models the live bar *not* honouring that order regardless --
    /// `forceHelperMisorder` swaps Target's and Protected's own rendered
    /// positions -- so the gate must catch it as its own distinct reason,
    /// not the generic "preflight never passed."
    @Test("helpers packed in the wrong order (misorder) -> INCONCLUSIVE \"helpers misordered\", before any length, all three reaped")
    func helperMisorderEndsInconclusiveBeforeAnyLength() {
        let world = FakeBarWorld(placementHonoring: .distance, forceHelperMisorder: true)
        let run = I7.run(world: world)

        #expect(run.code == 2)
        #expect(run.evidence.lastVerdict()?.hasPrefix("inconclusive(\"helpers misordered") == true)
        #expect(!world.commandLog.contains { $0.hasPrefix("spacer.length ") })
        #expect(world.commandLog.contains("protected.quit"))
        #expect(world.commandLog.contains("spacer.quit"))
        #expect(world.commandLog.contains("target.quit"))
        let gateFailed = run.evidence.allRecords().first { $0.kind == "placement.gateFailed" }
        #expect((gateFailed?.fields["reason"] as? String)?.hasPrefix("helpers misordered") == true)
    }

    // MARK: - An on-bar owner's own scan is unreadable -> refuse before any launch

    /// Amendment v9's own "refuse rather than guess" rule: an on-bar
    /// owner's own preference domain that cannot be read at all must
    /// refuse the whole plan before any helper ever launches -- nothing
    /// launched, no helper-default write, same shape as the existing
    /// "no room" fixture.
    @Test("an on-bar owner's own preference scan is unreadable -> INCONCLUSIVE before any launch, no helper launched, no default written")
    func unreadableOwnerScanRefusesBeforeAnyLaunch() {
        let world = FakeBarWorld(ownerPreferenceUnreadable: true)
        let run = I7.run(world: world)

        #expect(run.code == 2)
        #expect(run.evidence.lastVerdict()?.hasPrefix("inconclusive") == true)
        #expect(run.evidence.lastVerdict()?.contains("unreadable") == true)
        #expect(run.evidence.allRecords().contains { $0.kind == "placement.scanUncertain" })
        #expect(world.commandLog.isEmpty)
        #expect(world.defaultsLog.isEmpty)
    }

    // MARK: - Signal precedence (crosscheck-rework8.json #5)

    /// The F5 comment on `StageC1.run()`'s first step loop promises that a
    /// pre-launch terminal event is "reported straight from `safetyStop`,
    /// never a re-runnable INCONCLUSIVE" -- but `step1bPlacementPlan` was
    /// the first step whose own body could turn a terminal state (a signal
    /// landing during its own discovery pass) into a plain `.abort`,
    /// breaking that promise (exit 2 instead of 3). Fixed by re-checking
    /// `safetyStop` after every step's own abort, not only before the next
    /// step begins.
    @Test("a signal during step1b's own discovery -> SAFETY STOP NEEDING ATTENTION, not a re-runnable INCONCLUSIVE, nothing launched")
    func signalDuringStep1bNeedsAttention() {
        let world = FakeBarWorld()
        let run = I7.run(world: world, signalDuringStep1bDiscovery: true)

        #expect(run.code == 3)
        #expect(run.evidence.terminalReasons().first == "signal")
        #expect(run.evidence.lastVerdict() == "safetyStopNeedingAttention")
        #expect(world.commandLog.isEmpty)
        #expect(world.defaultsLog.isEmpty)
    }
}
