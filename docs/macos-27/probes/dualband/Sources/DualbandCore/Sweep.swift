//  Sweep.swift
//  dualband

/// The grids and the decision of plan T0/T1.
public enum Sweep {
    public static let coarseStep = 64.0
    public static let coarseMax = 3000.0
    public static let extension_ = 1000.0
    public static let fineStep = 16.0
    public static let fineReach = 128.0
    /// Rule A's margin on both sides.
    public static let requiredMargin = 32.0

    public static func coarseGrid(upTo top: Double = coarseMax) -> [Double] {
        stride(from: coarseStep, through: top, by: coarseStep).map { $0 }
    }

    /// Lengths between consecutive grid readings where `hides` changed;
    /// each transition is reported as the pair's upper length.
    public static func transitions(_ readings: [(length: Double, hides: Bool)]) -> [Double] {
        let sorted = readings.sorted { $0.length < $1.length }
        return zip(sorted, sorted.dropFirst()).compactMap { $0.hides != $1.hides ? $1.length : nil }
    }

    /// Whether the top of a coarse sweep is still changing: its last two readings differ.
    public static func changingAtTop(_ readings: [(length: Double, hides: Bool)]) -> Bool {
        let sorted = readings.sorted { $0.length < $1.length }
        guard sorted.count >= 2 else { return false }
        return sorted[sorted.count - 1].hides != sorted[sorted.count - 2].hides
    }

    /// The fine grid around transitions: +- `fineReach` by `fineStep`, positive lengths only.
    public static func fineGrid(around transitions: [Double]) -> [Double] {
        var points = Set<Double>()
        for t in transitions {
            for point in stride(from: t - fineReach, through: t + fineReach, by: fineStep) where point > 0 {
                points.insert(point)
            }
        }
        return points.sorted()
    }

    /// The points that hide in every reading of every condition of one bar.
    /// A point some condition did not read is not in the set.
    public static func hidingPoints(_ byCondition: [[Double: [Bool]]]) -> Set<Double> {
        guard let first = byCondition.first else { return [] }
        return Set(first.keys.filter { point in
            byCondition.allSatisfy { condition in
                guard let readings = condition[point], !readings.isEmpty else { return false }
                return readings.allSatisfy { $0 }
            }
        })
    }

    public enum Branch: Equatable, Sendable {
        case a(length: Double)
        case d(reason: String)
    }

    /// Rule T1: a point of P = builtin ∩ sidecar whose neighbours within
    /// `requiredMargin` on both sides are in P too; the one of largest margin.
    public static func decide(builtin: Set<Double>, sidecar: Set<Double>, inconclusive: Bool) -> Branch {
        if inconclusive { return .d(reason: "inconclusive") }
        let shared = builtin.intersection(sidecar)
        guard !shared.isEmpty else { return .d(reason: "no shared point") }
        func margin(_ point: Double) -> Double {
            var steps = 0.0
            while shared.contains(point - (steps + 1) * fineStep), shared.contains(point + (steps + 1) * fineStep) {
                steps += 1
            }
            return steps * fineStep
        }
        let best = shared.map { ($0, margin($0)) }.max { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0 > $1.0) }
        guard let best, best.1 >= requiredMargin else { return .d(reason: "margin under \(Int(requiredMargin)) pt") }
        return .a(length: best.0)
    }
}
