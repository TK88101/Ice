import Testing
@testable import C1Core

/// Section 5: "Baseline-equivalent (the reset check and the teardown):
/// every templated owner item drawn within 2 pt of its baseline x; the
/// residual strip ... without unexplained ink change against the baseline;
/// the capture indicator at its baseline frame; the fold absent; for the
/// reset check also Target, the spacer (at rest) and Protected at their
/// baseline x."
@Suite("BaselineEquivalence")
struct BaselineEquivalenceTests {
    let indicator = BarFrame(minX: 1000, minY: 0, width: 20, height: 22)

    func input(
        owners: [(String, Double)] = [("owner-1", 500)],
        baselineOwners: [(String, Double)] = [("owner-1", 500)],
        residualChanged: Bool = false,
        indicatorFrame: BarFrame? = nil,
        baselineIndicatorFrame: BarFrame? = nil,
        fold: FoldState = .absent,
        helpers: [(String, Double)]? = nil,
        baselineHelpers: [(String, Double)]? = nil
    ) -> BaselineEquivalence.Input {
        BaselineEquivalence.Input(
            templatedOwnerItems: owners.map { .init(id: $0.0, x: $0.1) },
            baselineTemplatedOwnerItems: baselineOwners.map { .init(id: $0.0, x: $0.1) },
            residualStripChanged: residualChanged,
            indicatorFrame: indicatorFrame ?? indicator,
            baselineIndicatorFrame: baselineIndicatorFrame ?? indicator,
            fold: fold,
            helpers: helpers?.map { .init(id: $0.0, x: $0.1) },
            baselineHelpers: baselineHelpers?.map { .init(id: $0.0, x: $0.1) }
        )
    }

    @Test("every check passes -> no failures")
    func allPass() {
        #expect(BaselineEquivalence.check(input()) == [])
    }

    @Test("an owner item exactly at the 2 pt tolerance boundary still passes")
    func ownerAtToleranceBoundary() {
        #expect(BaselineEquivalence.check(input(owners: [("owner-1", 502)])) == [])
    }

    @Test("an owner item just past the 2 pt tolerance drifted")
    func ownerPastTolerance() {
        #expect(BaselineEquivalence.check(input(owners: [("owner-1", 502.1)])) == [.ownerItemDrifted("owner-1")])
    }

    @Test("a baseline owner item missing from the current reading")
    func ownerMissing() {
        #expect(BaselineEquivalence.check(input(owners: [])) == [.ownerItemMissing("owner-1")])
    }

    @Test("an unexplained residual-strip change")
    func residualChanged() {
        #expect(BaselineEquivalence.check(input(residualChanged: true)) == [.residualStripChanged])
    }

    @Test("the capture indicator missing entirely")
    func indicatorMissing() {
        // Built directly, not through `input(...)`: that helper's own
        // `indicatorFrame ?? indicator` default would turn an explicit nil
        // back into a frame.
        let missing = BaselineEquivalence.Input(
            templatedOwnerItems: [.init(id: "owner-1", x: 500)],
            baselineTemplatedOwnerItems: [.init(id: "owner-1", x: 500)],
            residualStripChanged: false,
            indicatorFrame: nil,
            baselineIndicatorFrame: indicator,
            fold: .absent
        )
        #expect(BaselineEquivalence.check(missing) == [.indicatorMissing])
    }

    @Test("the capture indicator moved from its baseline frame")
    func indicatorMoved() {
        let moved = BarFrame(minX: 1005, minY: 0, width: 20, height: 22)
        #expect(BaselineEquivalence.check(input(indicatorFrame: moved)) == [.indicatorMoved])
    }

    @Test("the fold present")
    func foldPresent() {
        #expect(BaselineEquivalence.check(input(fold: .present)) == [.foldNotAbsent])
    }

    @Test("the fold unreadable")
    func foldUnreadable() {
        #expect(BaselineEquivalence.check(input(fold: .unreadable)) == [.foldNotAbsent])
    }

    @Test("multiple failures are all reported")
    func multipleFailures() {
        let failures = BaselineEquivalence.check(input(owners: [], residualChanged: true, fold: .present))
        #expect(Set(failures) == Set([.ownerItemMissing("owner-1"), .residualStripChanged, .foldNotAbsent]))
    }

    @Test("the reset check's three helpers, all at their baseline x -> pass")
    func helpersAtBaseline() {
        let helpers: [(String, Double)] = [("target", 10), ("spacer", 30), ("protected", 50)]
        #expect(BaselineEquivalence.check(input(helpers: helpers, baselineHelpers: helpers)) == [])
    }

    @Test("a helper off its baseline x (no tolerance stated for helpers) fails")
    func helperDrifted() {
        let baseline: [(String, Double)] = [("target", 10), ("spacer", 30), ("protected", 50)]
        let current: [(String, Double)] = [("target", 10), ("spacer", 30.5), ("protected", 50)]
        #expect(BaselineEquivalence.check(input(helpers: current, baselineHelpers: baseline)) == [.helperDrifted("spacer")])
    }

    @Test("a helper missing from the current reading")
    func helperMissing() {
        let baseline: [(String, Double)] = [("target", 10), ("spacer", 30), ("protected", 50)]
        let current: [(String, Double)] = [("target", 10), ("protected", 50)]
        #expect(BaselineEquivalence.check(input(helpers: current, baselineHelpers: baseline)) == [.helperMissing("spacer")])
    }

    @Test("no helper baseline supplied (a plain reset/teardown check without helpers) -> not checked at all")
    func helpersNotSupplied() {
        #expect(BaselineEquivalence.check(input(helpers: nil, baselineHelpers: nil)) == [])
    }

    @Test("a helper baseline supplied but the current reading has no helpers at all -> every one missing")
    func helperBaselineSuppliedButNoCurrentHelpers() {
        let baseline: [(String, Double)] = [("target", 10), ("spacer", 30)]
        #expect(BaselineEquivalence.check(input(helpers: nil, baselineHelpers: baseline)) == [.helperMissing("target"), .helperMissing("spacer")])
    }
}
