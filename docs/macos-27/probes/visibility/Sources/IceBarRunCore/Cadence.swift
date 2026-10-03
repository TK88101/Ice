// Route C part 3 (docs/plans/2026-10-03-icebar-c-runner.md, Q1-Q3): the capture
// cadence of the pre-registration's section 2 and the kept-sample selection
// (U18). Spacing is checked on each sample's start, which the runner records
// before the frozen bracket's first capture; the frozen sample's `time` is
// the bracket's end.
import IceCore

/// One frozen bracket (capture, AX read, capture) with the time it started.
public struct TimedSample: Equatable, Sendable {
    public let start: Double
    public let sample: ObservationSample

    public init(start: Double, sample: ObservationSample) {
        self.start = start
        self.sample = sample
    }

    public var end: Double { sample.time }
}

/// Section 2's numbers. Fixed by the pre-registration; never tuned.
public struct CadenceParameters: Equatable, Sendable {
    public let warmUpCaptures: Int
    public let warmUpSpacing: Double
    /// The first sample after a spacer write or helper change starts at least this late.
    public let settle: Double
    public let baselineSamples: Int
    public let baselineSpacing: Double
    public let observationSamples: Int
    public let observationSpacing: Double
    public let maxAttempts: Int
    /// From one attempt's last sample end to the next attempt's first start.
    public let attemptGap: Double
    /// A baseline, or an observation over all its attempts, taking longer is not granted.
    public let timeout: Double
    public let observationsPerCycle: Int
    public let observationStartSpacing: Double

    public static let preRegistered = CadenceParameters(
        warmUpCaptures: 24, warmUpSpacing: 0.25, settle: 1.0,
        baselineSamples: 5, baselineSpacing: 1.0,
        observationSamples: 3, observationSpacing: 0.5,
        maxAttempts: 3, attemptGap: 1.0, timeout: 10,
        observationsPerCycle: 4, observationStartSpacing: 5
    )
}

public enum CadenceRefusal: Error, Equatable, Sendable {
    case sampleCount(Int)
    /// The first sample started less than `settle` after the last change.
    case settle
    /// Sample `index` started less than the spacing after the previous one.
    case spacing(index: Int)
    case timeout
}

/// A baseline's samples as the claim consumes them: all five for the frozen
/// `StripAssessor.baseline`, samples 2-5 for `HiddenBaseline.evaluate`.
public struct BaselineSelection: Equatable, Sendable {
    public let all: [ObservationSample]
    public let kept: [ObservationSample]

    public var keptCaptures: [StripImage] { kept.flatMap { [$0.before, $0.after] } }
}

public enum Cadence {
    /// Q2: exactly five samples, settled, >= 1.0 s apart, within 10 s; the first dropped.
    public static func baseline(_ samples: [TimedSample], lastChange: Double,
                                parameters p: CadenceParameters = .preRegistered) -> Result<BaselineSelection, CadenceRefusal> {
        if let refusal = series(samples, count: p.baselineSamples, spacing: p.baselineSpacing, notBefore: lastChange + p.settle) {
            return .failure(refusal)
        }
        if span(samples) > p.timeout { return .failure(.timeout) }
        let all = samples.map(\.sample)
        return .success(BaselineSelection(all: all, kept: Array(all.dropFirst())))
    }

    /// Q3: one attempt's three samples, >= 0.5 s apart, none before `notBefore`.
    public static func attempt(_ samples: [TimedSample], notBefore: Double,
                               parameters p: CadenceParameters = .preRegistered) -> CadenceRefusal? {
        series(samples, count: p.observationSamples, spacing: p.observationSpacing, notBefore: notBefore)
    }

    public static func firstAttemptStart(lastChange: Double, parameters p: CadenceParameters = .preRegistered) -> Double {
        lastChange + p.settle
    }

    public static func nextAttemptStart(after previous: [TimedSample], parameters p: CadenceParameters = .preRegistered) -> Double {
        (previous.last?.end ?? 0) + p.attemptGap
    }

    /// Q3: from the first attempt's first start to the last attempt's last end.
    public static func observationTimedOut(_ attempts: [[TimedSample]], parameters p: CadenceParameters = .preRegistered) -> Bool {
        span(attempts.flatMap { $0 }) > p.timeout
    }

    /// Q8: observation `index` of a cycle starts no earlier than this.
    public static func observationStart(_ index: Int, first: Double, parameters p: CadenceParameters = .preRegistered) -> Double {
        first + Double(index) * p.observationStartSpacing
    }

    static func series(_ samples: [TimedSample], count: Int, spacing: Double, notBefore: Double) -> CadenceRefusal? {
        guard samples.count == count else { return .sampleCount(samples.count) }
        guard let first = samples.first, first.start >= notBefore else { return .settle }
        for index in samples.indices.dropFirst() where samples[index].start - samples[index - 1].start < spacing {
            return .spacing(index: index)
        }
        return nil
    }

    static func span(_ samples: [TimedSample]) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.end - first.start
    }
}
