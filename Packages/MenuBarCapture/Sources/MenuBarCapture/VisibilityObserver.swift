import Foundation
import IceCore

/// A capture's `StripReading`, together with the decision layer's verdict for
/// each sighted item.
public struct ObservationResult: Equatable, Sendable {
    public let reading: StripReading
    public let visibility: [String: Visibility]

    public init(reading: StripReading, visibility: [String: Visibility]) {
        self.reading = reading
        self.visibility = visibility
    }
}

/// Turns a `Sampler` into a baseline and, from it, observations: the sampling
/// loop the plan asks for (section 4), on top of the rules IceCore already
/// enforces (`StripAssessor`, `MenuBarItemVisibility`).
public struct VisibilityObserver: Sendable {
    private let sampler: Sampler
    private let parameters: DetectorParameters
    private let sleep: @Sendable (Double) -> Void

    public init(
        sampler: Sampler,
        parameters: DetectorParameters = .preRegistered,
        sleep: @escaping @Sendable (Double) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.sampler = sampler
        self.parameters = parameters
        self.sleep = sleep
    }

    /// Samples `items` until at least `parameters.baselineMinSamples` samples
    /// span at least `parameters.baselineMinSpan` seconds, then hands every
    /// sample to `StripAssessor.baseline`, which drops the first and enforces
    /// agreement across the rest (plan deviation 3). This function only
    /// gathers; IceCore decides what the samples are allowed to mean.
    ///
    /// `nil` when a capture or an AX read failed on any attempt: a baseline
    /// built around a hole in the record is not a baseline.
    public func baseline(items: [String: pid_t], geometry: BarGeometry, maxAttempts: Int = 32) -> BaselineResult? {
        var samples = [ObservationSample]()
        while samples.count < maxAttempts {
            guard let sample = sampler.sample(items: items) else { return nil }
            samples.append(sample)
            let span = samples[samples.count - 1].time - samples[0].time
            if samples.count >= parameters.baselineMinSamples, span >= parameters.baselineMinSpan {
                break
            }
            sleep(parameters.minSampleSpacing)
        }
        guard samples.count >= parameters.baselineMinSamples,
              samples[samples.count - 1].time - samples[0].time >= parameters.baselineMinSpan
        else {
            return nil
        }
        return StripAssessor.baseline(samples: samples, geometry: geometry, parameters: parameters)
    }

    /// Samples `parameters.minSamples` observations, spaced by at least
    /// `parameters.minSampleSpacing`, and returns IceCore's `StripReading`
    /// together with each sighted item's verdict from the decision layer.
    ///
    /// `nil` when a capture or an AX read failed on any attempt.
    public func observe(
        baseline: BaselineResult,
        targets: [String],
        references: [String],
        items: [String: pid_t]
    ) -> ObservationResult? {
        var samples = [ObservationSample]()
        while samples.count < parameters.minSamples {
            guard let sample = sampler.sample(items: items) else { return nil }
            samples.append(sample)
            if samples.count < parameters.minSamples {
                sleep(parameters.minSampleSpacing)
            }
        }

        let reading = StripAssessor.observe(
            baseline: baseline,
            targets: targets,
            references: references,
            samples: samples,
            parameters: parameters
        )
        let decision = MenuBarItemVisibility(maxMismatch: parameters.maxMismatch)
        var visibility = [String: Visibility]()
        for sighting in reading.sightings {
            visibility[sighting.id] = decision.verdict(for: sighting, captureStable: reading.captureStable)
        }
        return ObservationResult(reading: reading, visibility: visibility)
    }
}
