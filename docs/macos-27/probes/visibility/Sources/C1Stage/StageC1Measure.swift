// C2 (docs/plans/2026-09-28-c2-protocol.md 6.1 item 3): the measurement
// mode -- one full C1 cycle per listed length, 6.2's retries per length
// (`C2Retry.settleReading`), every settled point recorded as `c2.point`.
// This process only measures; bands, the length and every verdict across
// configurations are `C2Core`'s, in the sequencer. The staged teardown and
// every safety rule are C1's own, unchanged.
import C1Core
import C2Core

/// What a `StageC1` run does after its baseline.
public enum C1LengthPlan: Sendable, Equatable {
    /// C1: the scan, then five smoke cycles at its midpoint.
    case c1
    /// C2: exactly these lengths, in order.
    case measure([Double])
}

extension StageC1 {
    func runMeasurement(_ lengths: [Double]) -> Verdict {
        var points = [C2Point]()
        for (index, length) in lengths.enumerated() {
            guard !isTerminal, !budgetExceeded else { break }
            measurementRemainingCycles = lengths.count - index - 1
            var attempts = [C2Reading?]()
            var settled: C2Reading?
            while settled == nil, !isTerminal, !budgetExceeded {
                let result = runCycle(length: length, label: "measure.\(Int(length)).\(attempts.count)")
                guard !budgetExceeded else { break }
                attempts.append(result.map(Self.c2Reading))
                settled = C2Retry.settleReading(attempts)
            }
            guard let settled else { break }
            points.append(C2Point(length: length, reading: settled))
            evidence?.record("c2.point", ["length": length, "reading": "\(settled)", "attempts": attempts.count])
        }
        runStagedTeardown()
        return Self.measurementVerdict(
            safetyStop: safetyStop,
            placementGateFailureReason: placementGateFailureReason,
            measured: points.count,
            planned: lengths.count
        )
    }

    /// A settled cycle's reading of the whole hidden section: a hide counts
    /// as a band point only with every other check passing.
    static func c2Reading(_ result: C1CycleResult) -> C2Reading {
        switch result.reading {
        case .hidden(folded: false): result.otherChecksPassed ? .hiddenNoFold : .notShown
        case .hidden(folded: true): .hiddenFolded
        case .stillDrawn: .stillDrawn
        case .refused: .notShown
        }
    }

    /// PASS here means only "every listed length was measured" -- the
    /// process's exit code 0; the sequencer reads the points.
    public static func measurementVerdict(safetyStop: RunAccounting.SafetyStop?, placementGateFailureReason: String?, measured: Int, planned: Int) -> Verdict {
        if let safetyStop { return safetyStop == .needingAttention ? .safetyStopNeedingAttention : .safetyStop }
        if let placementGateFailureReason { return .inconclusive(placementGateFailureReason) }
        guard measured == planned else { return .inconclusive("measured \(measured) of \(planned) lengths") }
        return .pass
    }
}
