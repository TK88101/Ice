import Testing
@testable import C1Core

/// Section 5 step 2 (19 lengths, `L = 600, 616, ..., 896`) and section 1's
/// smoke midpoint ("the midpoint of its widest contiguous run"). `lengths`
/// is `stride(from: 600, through: 896, by: 16)`, which stops at 888 -- the
/// last multiple of 16 past 600 that does not overshoot 896 -- and that is
/// exactly 19 values, matching the plan's own count.
@Suite("ScanPlanner")
struct ScanPlannerTests {
    @Test("19 lengths, 600 to 888 by 16")
    func lengths() {
        #expect(ScanPlanner.lengths.count == 19)
        #expect(ScanPlanner.lengths.first == 600)
        #expect(ScanPlanner.lengths.last == 888)
        #expect(ScanPlanner.lengths[1] == 616)
    }

    func readings(_ hidden: [Bool]) -> [ScanPlanner.Reading] {
        zip(ScanPlanner.lengths, hidden).map { .init(length: $0, hidden: $1) }
    }

    @Test("no hidden length -> no midpoint")
    func noneHidden() {
        #expect(ScanPlanner.midpointOfWidestHiddenRun(readings(Array(repeating: false, count: 19))) == nil)
    }

    @Test("every length hidden -> the run's own middle")
    func allHidden() {
        let mid = ScanPlanner.midpointOfWidestHiddenRun(readings(Array(repeating: true, count: 19)))
        #expect(mid == ScanPlanner.lengths[9]) // 19 values, index (19-1)/2 = 9
    }

    @Test("one odd-length run -> its exact middle")
    func oddRun() {
        // indices 2...6 (5 lengths) hidden.
        var hidden = Array(repeating: false, count: 19)
        for i in 2...6 { hidden[i] = true }
        let mid = ScanPlanner.midpointOfWidestHiddenRun(readings(hidden))
        #expect(mid == ScanPlanner.lengths[4]) // 2 + (5-1)/2 = 4
    }

    @Test("one even-length run -> the lower of the two middle lengths")
    func evenRunPicksLower() {
        // indices 3...6 (4 lengths) hidden.
        var hidden = Array(repeating: false, count: 19)
        for i in 3...6 { hidden[i] = true }
        let mid = ScanPlanner.midpointOfWidestHiddenRun(readings(hidden))
        #expect(mid == ScanPlanner.lengths[4]) // 3 + (4-1)/2 = 4 (floor), the lower of 4 and 5
    }

    @Test("two equal-width runs -> the lower (earlier) run")
    func tieGoesToLowerRun() {
        var hidden = Array(repeating: false, count: 19)
        hidden[0] = true; hidden[1] = true // run A: 600, 616
        hidden[10] = true; hidden[11] = true // run B: same width, higher lengths
        let mid = ScanPlanner.midpointOfWidestHiddenRun(readings(hidden))
        #expect(mid == ScanPlanner.lengths[0])
    }

    @Test("a wider run beats an earlier, narrower one")
    func widerRunWins() {
        var hidden = Array(repeating: false, count: 19)
        hidden[0] = true // run A: width 1
        for i in 10...13 { hidden[i] = true } // run B: width 4
        let mid = ScanPlanner.midpointOfWidestHiddenRun(readings(hidden))
        #expect(mid == ScanPlanner.lengths[11]) // 10 + (4-1)/2 = 11
    }

    @Test("a run at the very start and a run at the very end are both found")
    func edgesOfTheArray() {
        var startHidden = Array(repeating: false, count: 19)
        startHidden[0] = true
        #expect(ScanPlanner.midpointOfWidestHiddenRun(readings(startHidden)) == ScanPlanner.lengths[0])

        var endHidden = Array(repeating: false, count: 19)
        endHidden[18] = true
        #expect(ScanPlanner.midpointOfWidestHiddenRun(readings(endHidden)) == ScanPlanner.lengths[18])
    }
}
