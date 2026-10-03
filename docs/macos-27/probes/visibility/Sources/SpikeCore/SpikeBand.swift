// T0: the band of one profile -- the widest contiguous run of clean lengths,
// by C2's own rule (`C2Band.band`: widest, a tie to the lower run).
import C2Core

public struct Band: Equatable, Sendable, Codable {
    public let lo: Double
    public let hi: Double
    /// Clean lengths inside the run.
    public let count: Int

    public init(lo: Double, hi: Double, count: Int) {
        self.lo = lo
        self.hi = hi
        self.count = count
    }

    /// The length to rest at (as C1/C2 did): the rounded middle.
    public var midpoint: Double { ((lo + hi) / 2).rounded() }

    public var text: String { "\(Band.format(lo))-\(Band.format(hi)) pt" }

    public static func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : "\(value)"
    }
}

public enum SpikeBand {
    /// `C2Band.band` over the records (`hiddenClean` is C2's `hiddenNoFold`;
    /// anything else splits a run, an `unknown` included -- fail closed).
    public static func widest(_ records: [StepRecord]) -> Band? {
        let points = records.map { C2Point(length: $0.length, reading: $0.outcome.isClean ? .hiddenNoFold : .notShown) }
        guard let span = C2Band.band(points) else { return nil }
        let count = records.filter { $0.outcome.isClean && $0.length >= span.lo && $0.length <= span.hi }.count
        return Band(lo: span.lo, hi: span.hi, count: count)
    }
}
