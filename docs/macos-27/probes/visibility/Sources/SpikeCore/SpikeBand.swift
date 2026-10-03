// T0: the band of one profile -- the widest contiguous run of clean lengths.

public struct Band: Equatable, Sendable, Codable {
    public let lo: Double
    public let hi: Double
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
    /// Contiguous (in record order) runs of `hiddenClean`.
    public static func runs(_ records: [StepRecord]) -> [Band] {
        var bands = [Band]()
        var open: (lo: Double, hi: Double, count: Int)?
        for record in records {
            if record.outcome.isClean {
                open = open.map { ($0.lo, record.length, $0.count + 1) } ?? (record.length, record.length, 1)
            } else if let run = open {
                bands.append(Band(lo: run.lo, hi: run.hi, count: run.count))
                open = nil
            }
        }
        if let run = open { bands.append(Band(lo: run.lo, hi: run.hi, count: run.count)) }
        return bands
    }

    /// The widest run; a tie goes to the lower one.
    public static func widest(_ records: [StepRecord]) -> Band? {
        runs(records).max { a, b in a.count < b.count || (a.count == b.count && a.lo > b.lo) }
    }
}
