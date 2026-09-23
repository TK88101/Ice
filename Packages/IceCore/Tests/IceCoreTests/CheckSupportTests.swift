import Testing
@testable import IceCore

/// `CheckFrames.trim` is D15's 1 pt-per-side AX padding correction (the
/// measured 2 pt overlap between adjacent drawn items at rest, plan section
/// 0's MEASURED table); `SectionItemCheck`/`CheckSkipReason` are the
/// verifier's per-item result and every reason it can decline to check one;
/// `VerificationSummary.make` reduces a whole pass's results to counts a
/// status line can show.
@Suite("CheckFrames.trim")
struct CheckFramesTests {
    @Test("trim shrinks minX by `by` and width by 2 * by")
    func trimShrinksBothSides() {
        let frame = BarRect(minX: 100, minY: 4.5, width: 20, height: 24)
        let trimmed = CheckFrames.trim(frame)
        #expect(trimmed.minX == 101)
        #expect(trimmed.width == 18)
        #expect(trimmed.minY == 4.5)
        #expect(trimmed.height == 24)
    }

    @Test("trim never produces a negative width")
    func trimNeverNegative() {
        let narrow = BarRect(minX: 100, minY: 4.5, width: 1, height: 24)
        let trimmed = CheckFrames.trim(narrow, by: 5)
        #expect(trimmed.width == 0)
        #expect(trimmed.width >= 0)
    }

    @Test("the census's 2 pt adjacent overlap no longer overlaps after trimming (strict overlap: lo < other.hi)")
    func census2PtPairsStopOverlappingAfterTrim() {
        // 2026-09-23 census: adjacent drawn items' AX frames overlap by 2.0 pt
        // at rest. Two adjacent frames sharing exactly a 2 pt overlap:
        let left = BarRect(minX: 1176, minY: 4.5, width: 33, height: 24) // maxX 1209
        let right = BarRect(minX: 1207, minY: 4.5, width: 34, height: 24) // minX 1207 -- 2 pt overlap with left's maxX
        let leftSpan = PtSpan(lo: left.minX, hi: left.maxX)
        let rightSpan = PtSpan(lo: right.minX, hi: right.maxX)
        #expect(leftSpan.overlaps(rightSpan)) // pinning the overlap exists before trimming

        let trimmedLeft = CheckFrames.trim(left)
        let trimmedRight = CheckFrames.trim(right)
        let trimmedLeftSpan = PtSpan(lo: trimmedLeft.minX, hi: trimmedLeft.maxX)
        let trimmedRightSpan = PtSpan(lo: trimmedRight.minX, hi: trimmedRight.maxX)
        #expect(!trimmedLeftSpan.overlaps(trimmedRightSpan))
    }

    @Test("agent frames are untouched by trim -- callers simply never trim them")
    func agentFramesAreNotPassedToTrim() {
        // There is nothing in CheckFrames that special-cases an agent frame;
        // the 17.5 pt chevron rule stays unaffected only because callers
        // (CheckPlan) never call trim on a systemElements frame. This test
        // pins that trim itself has no agent-awareness to accidentally rely
        // on: it trims whatever BarRect it is given, uniformly.
        let chevronLikeAgentFrame = BarRect(minX: 1012.5, minY: 0, width: 17.5, height: 33)
        let trimmed = CheckFrames.trim(chevronLikeAgentFrame)
        #expect(trimmed.minX == 1013.5)
        #expect(trimmed.width == 15.5)
    }

    @Test("a custom trim amount is honoured")
    func customTrimAmount() {
        let frame = BarRect(minX: 100, minY: 0, width: 20, height: 33)
        let trimmed = CheckFrames.trim(frame, by: 2)
        #expect(trimmed.minX == 102)
        #expect(trimmed.width == 16)
    }
}

@Suite("SectionItemCheck, CheckSkipReason")
struct SectionItemCheckTests {
    @Test("SectionItemCheck wraps checked, refusedAtBaseline, and skipped")
    func sectionItemCheckCases() {
        let checked = SectionItemCheck.checked(.stillDrawn)
        let refused = SectionItemCheck.refusedAtBaseline(.tooNarrow)
        let skipped = SectionItemCheck.skipped(.noReference)
        #expect(checked == .checked(.stillDrawn))
        #expect(refused == .refusedAtBaseline(.tooNarrow))
        #expect(skipped == .skipped(.noReference))
        #expect(checked != refused)
    }

    @Test("CheckSkipReason carries payloads where documented")
    func checkSkipReasonPayloads() {
        #expect(CheckSkipReason.noBaseline(shownSeconds: 5) == .noBaseline(shownSeconds: 5))
        #expect(CheckSkipReason.noBaseline(shownSeconds: 5) != .noBaseline(shownSeconds: 6))
        #expect(CheckSkipReason.preflight("timed out") == .preflight("timed out"))
        #expect(CheckSkipReason.preflight("timed out") != .preflight("other"))
    }
}

@Suite("VerificationSummary.make")
struct VerificationSummaryTests {
    private func key(_ n: Int32) -> ItemKey {
        ItemKey(namespace: "com.example.a", identifier: "x\(n)", pid: n, childIndex: nil)
    }

    @Test("counts hidden and stillDrawn directly")
    func countsHiddenAndStillDrawn() {
        let results: [ItemKey: SectionItemCheck] = [
            key(1): .checked(.hidden(folded: true)),
            key(2): .checked(.hidden(folded: false)),
            key(3): .checked(.stillDrawn),
        ]
        let summary = VerificationSummary.make(results)
        #expect(summary.hidden == 2)
        #expect(summary.stillDrawn == 1)
    }

    @Test("groups unverifiable, refused, and skipped by their case name")
    func groupsByBareCaseName() {
        let results: [ItemKey: SectionItemCheck] = [
            key(1): .checked(.unverifiable(.foldUnreadable)),
            key(2): .checked(.unverifiable(.foldUnreadable)),
            key(3): .checked(.unverifiable(.weakMatch)),
            key(4): .refusedAtBaseline(.tooNarrow),
            key(5): .refusedAtBaseline(.overlapsAgentItem),
            key(6): .refusedAtBaseline(.overlapsAgentItem),
            key(7): .skipped(.noReference),
            key(8): .skipped(.stacked),
            key(9): .skipped(.stacked),
            key(10): .skipped(.stacked),
        ]
        let summary = VerificationSummary.make(results)
        #expect(summary.unverifiable["foldUnreadable"] == 2)
        #expect(summary.unverifiable["weakMatch"] == 1)
        #expect(summary.refused["tooNarrow"] == 1)
        #expect(summary.refused["overlapsAgentItem"] == 2)
        #expect(summary.skipped["noReference"] == 1)
        #expect(summary.skipped["stacked"] == 3)
        #expect(summary.hidden == 0)
        #expect(summary.stillDrawn == 0)
    }

    @Test("an empty result set summarizes to all zeros")
    func emptyResultsSummarizeToZero() {
        let summary = VerificationSummary.make([:])
        #expect(summary.hidden == 0)
        #expect(summary.stillDrawn == 0)
        #expect(summary.unverifiable.isEmpty)
        #expect(summary.refused.isEmpty)
        #expect(summary.skipped.isEmpty)
    }

    @Test("every CheckSkipReason case name is distinct and stable")
    func everySkipReasonCaseNameIsDistinct() {
        let reasons: [CheckSkipReason] = [
            .noReference, .dividerUnavailable, .noBaseline(shownSeconds: 1), .baselineStale, .noRoom, .noGeometry,
            .preflight("x"), .iceBarMode, .barHiddenBySystem, .stacked, .positional, .notInSection, .ownReadFailed, .cancelled,
            .captureFailed,
        ]
        var results = [ItemKey: SectionItemCheck]()
        for (i, reason) in reasons.enumerated() {
            results[key(Int32(i))] = .skipped(reason)
        }
        let summary = VerificationSummary.make(results)
        #expect(summary.skipped.count == reasons.count)
        #expect(summary.skipped.values.allSatisfy { $0 == 1 })
    }

    @Test("a pass that never produced a sample is counted as captureFailed, not cancelled")
    func captureFailedHasItsOwnName() {
        let summary = VerificationSummary.make([key(1): .skipped(.captureFailed), key(2): .skipped(.cancelled)])
        #expect(summary.skipped == ["captureFailed": 1, "cancelled": 1])
    }
}
