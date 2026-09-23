// Turns settled samples of one leg into brackets, brackets into verdicts, and
// plans which lengths to test next. Pure logic: no I/O, no AppKit, no time.

/// A tolerance shared by every bracket-and-verdict computation below, used so
/// two nearly-equal doubles (a plateau of `spacerLeft`/`spacerAppKitWidth`
/// readings, or a grid boundary against an extra) are treated as the same
/// value instead of drifting apart on floating-point noise.
private enum Numeric {
    static let epsilon = 1e-9
}

/// Turns one leg's settled samples into brackets for every transition,
/// decides verdicts across repeats of a leg, and combines per-bound verdicts
/// into one headline.
public enum Analysis {

    /// Brackets every transition of interest (`hide`, `edge`, `sat`, `selfov`,
    /// `top`, `harm`) for one leg, using only samples that settled.
    ///
    /// Samples are sorted by length before anything else, so the rule applies
    /// identically whether the leg was walked up, walked down, or the samples
    /// arrived out of order.
    public static func brackets(for leg: [LegSample], tolerance: Double) -> LegBrackets {
        precondition(tolerance.isFinite && tolerance >= 0, "tolerance must be finite and non-negative")

        let settled = leg.filter { !$0.unsettled }.sorted { $0.length < $1.length }
        precondition(settled.allSatisfy { $0.length.isFinite }, "sample lengths must be finite")

        guard let maxTested = settled.map(\.length).max() else {
            let notObserved = Bracket.notObserved(maxTested: 0)
            return LegBrackets(
                hide: notObserved, edge: notObserved, sat: notObserved,
                selfov: notObserved, top: notObserved, harm: notObserved
            )
        }

        let hide = transitionBracket(
            in: settled, maxTested: maxTested,
            isNew: { $0.target == .overflowed },
            isOld: { isVisible($0.target) }
        )
        let top = topBracket(in: settled, maxTested: maxTested, hide: hide)
        let harm = transitionBracket(
            in: settled, maxTested: maxTested,
            isNew: { $0.harm },
            isOld: { !$0.harm }
        )
        let selfov = transitionBracket(
            in: settled, maxTested: maxTested,
            isNew: { $0.spacerDrawn == false },
            isOld: { $0.spacerDrawn == true }
        )
        let edge = plateauBracket(
            in: settled, maxTested: maxTested, tolerance: tolerance,
            direction: .min, value: { $0.spacerLeft }
        )
        let sat = plateauBracket(
            in: settled, maxTested: maxTested, tolerance: tolerance,
            direction: .max, value: { $0.spacerAppKitWidth }
        )

        return LegBrackets(hide: hide, edge: edge, sat: sat, selfov: selfov, top: top, harm: harm)
    }

    /// Decides, across the repeats of one leg type, whether `W_hide` (the
    /// smallest length at which the target overflowed) is smaller than a
    /// bound's own transition by at least `tolerance`.
    public static func verdict(hide: [Bracket], bound: [Bracket], tolerance: Double) -> Verdict {
        precondition(tolerance.isFinite && tolerance >= 0, "tolerance must be finite and non-negative")
        precondition(
            hide.allSatisfy(isFiniteBracket) && bound.allSatisfy(isFiniteBracket),
            "bracket lo/hi/maxTested values must be finite"
        )

        guard !hide.isEmpty else {
            return .insufficient(reason: "no repeats")
        }

        let notObservedHideCount = hide.count { isNotObserved($0) }
        if notObservedHideCount == hide.count {
            return .fails(reason: "target never overflowed on the tested grid")
        }
        if notObservedHideCount > 0 {
            return .insufficient(reason: "repeats disagree on whether the target overflowed")
        }

        // Every repeat observed the target overflow; every hide bracket is `.at`.
        let hideHis = hide.compactMap(atHi)
        let hideLos = hide.map { atLo($0) ?? -Double.infinity }
        let hideMax = hideHis.max() ?? -Double.infinity
        let hideLoMin = hideLos.min() ?? -Double.infinity

        let observed = bound.filter { !isNotObserved($0) }

        guard !observed.isEmpty else {
            guard !bound.isEmpty else {
                return .insufficient(reason: "no bound data")
            }
            let maxTestedMin = bound.compactMap(notObservedMaxTested).min() ?? -Double.infinity
            let margin = maxTestedMin - hideMax
            if margin >= tolerance {
                return .holds(margin: margin, gridScoped: true)
            }
            return .insufficient(reason: "tested grid ends too close to W_hide")
        }

        let boundLoMin = observed.map { atLo($0) ?? -Double.infinity }.min() ?? -Double.infinity
        let boundHiMin = observed.compactMap(atHi).min() ?? Double.infinity
        // A repeat that ended before reaching the bound only shows the bound lies
        // above where it stopped, so its limit caps the margin as well.
        let censoredMin = bound.compactMap(notObservedMaxTested).min() ?? Double.infinity

        if boundHiMin <= hideLoMin {
            return .fails(
                reason: "the bound was reached at \(boundHiMin) but the target was not yet overflowed there"
            )
        }
        guard hideMax + tolerance <= boundLoMin else {
            return .insufficient(reason: "the hide and bound brackets overlap")
        }
        guard hideMax + tolerance <= censoredMin else {
            return .insufficient(reason: "a repeat's tested range ends too close to W_hide")
        }
        return .holds(margin: min(boundLoMin, censoredMin) - hideMax, gridScoped: observed.count < bound.count)
    }

    /// Combines one verdict per bound into a single headline: the first
    /// failure wins, then the first insufficiency, both in `Bound.allCases`
    /// order; only when every bound holds does the headline hold.
    public static func headline(_ verdicts: [Bound: Verdict]) -> Verdict {
        guard !verdicts.isEmpty else {
            return .insufficient(reason: "no bounds")
        }

        for bound in Bound.allCases {
            guard case .fails(let reason) = verdicts[bound] else { continue }
            return .fails(reason: "\(bound.rawValue): \(reason)")
        }
        for bound in Bound.allCases {
            guard case .insufficient(let reason) = verdicts[bound] else { continue }
            return .insufficient(reason: "\(bound.rawValue): \(reason)")
        }

        let holdings: [(margin: Double, gridScoped: Bool)] = Bound.allCases.compactMap { bound in
            guard case .holds(let margin, let gridScoped) = verdicts[bound] else { return nil }
            return (margin, gridScoped)
        }
        let minMargin = holdings.map(\.margin).min() ?? 0
        let anyGridScoped = holdings.contains { $0.gridScoped }
        return .holds(margin: minMargin, gridScoped: anyGridScoped)
    }

    /// The overlap of every span, or nil when the input is empty or any pair
    /// fails to overlap.
    public static func intersection(_ spans: [Span]) -> Span? {
        guard !spans.isEmpty else { return nil }
        let lo = spans.map(\.lo).max()!
        let hi = spans.map(\.hi).min()!
        guard lo <= hi else { return nil }
        return Span(lo: lo, hi: hi)
    }
}

// MARK: - Bracket helpers

extension Analysis {

    /// True when the target was seen visible (as opposed to overflowed,
    /// unconfirmed, or ambiguous).
    fileprivate static func isVisible(_ target: TargetState) -> Bool {
        if case .visible = target { return true }
        return false
    }

    fileprivate static func isNotObserved(_ bracket: Bracket) -> Bool {
        if case .notObserved = bracket { return true }
        return false
    }

    fileprivate static func atHi(_ bracket: Bracket) -> Double? {
        guard case .at(_, let hi) = bracket else { return nil }
        return hi
    }

    fileprivate static func atLo(_ bracket: Bracket) -> Double? {
        guard case .at(let lo, _) = bracket else { return nil }
        return lo
    }

    fileprivate static func notObservedMaxTested(_ bracket: Bracket) -> Double? {
        guard case .notObserved(let maxTested) = bracket else { return nil }
        return maxTested
    }

    /// False for a bracket carrying a NaN or infinite length, so callers that
    /// build `Bracket` values directly (bypassing `brackets(for:tolerance:)`)
    /// can't smuggle a non-finite value into a verdict and violate the spec's
    /// "never produce NaN" rule.
    fileprivate static func isFiniteBracket(_ bracket: Bracket) -> Bool {
        switch bracket {
        case .at(let lo, let hi):
            return hi.isFinite && (lo?.isFinite ?? true)
        case .notObserved(let maxTested):
            return maxTested.isFinite
        }
    }

    /// The general bracket rule: `hi` is the smallest length where `isNew`
    /// holds, `lo` is the largest length below `hi` where `isOld` positively
    /// holds (nil when there is none). `samples` must already be sorted by
    /// length ascending.
    fileprivate static func transitionBracket(
        in samples: [LegSample],
        maxTested: Double,
        isNew: (LegSample) -> Bool,
        isOld: (LegSample) -> Bool
    ) -> Bracket {
        guard let hi = samples.first(where: isNew)?.length else {
            return .notObserved(maxTested: maxTested)
        }
        let lo = samples
            .filter { $0.length < hi && isOld($0) }
            .map(\.length)
            .max()
        return .at(lo: lo, hi: hi)
    }

    /// `top` only exists relative to `hide`'s own bracket: it looks for the
    /// target becoming visible again above `hide`'s hi, with the old state
    /// being "still overflowed, somewhere between hide's hi and top's hi".
    fileprivate static func topBracket(
        in samples: [LegSample],
        maxTested: Double,
        hide: Bracket
    ) -> Bracket {
        guard case .at(_, let hideHi) = hide else {
            return .notObserved(maxTested: maxTested)
        }
        guard let hi = samples.first(where: { $0.length > hideHi && isVisible($0.target) })?.length else {
            return .notObserved(maxTested: maxTested)
        }
        let lo = samples
            .filter { $0.length >= hideHi && $0.length < hi && $0.target == .overflowed }
            .map(\.length)
            .max()
        return .at(lo: lo, hi: hi)
    }

    fileprivate enum PlateauDirection {
        case min
        case max
    }

    /// The shared rule behind `edge` and `sat`: among samples where `value`
    /// is known, find the extreme (min for `edge`, max for `sat`), take the
    /// plateau of samples within `tolerance` of it, and require at least two
    /// samples both in the known set and in the plateau before bracketing —
    /// fewer than that means the true extreme may not have been reached yet.
    fileprivate static func plateauBracket(
        in samples: [LegSample],
        maxTested: Double,
        tolerance: Double,
        direction: PlateauDirection,
        value: (LegSample) -> Double?
    ) -> Bracket {
        let known: [(length: Double, value: Double)] = samples.compactMap { sample in
            guard let v = value(sample) else { return nil }
            return (sample.length, v)
        }
        guard known.count >= 2 else { return .notObserved(maxTested: maxTested) }

        let values = known.map(\.value)
        let extreme = direction == .min ? values.min()! : values.max()!
        let inPlateau: (Double) -> Bool = direction == .min
            ? { $0 <= extreme + tolerance }
            : { $0 >= extreme - tolerance }

        let plateau = known.filter { inPlateau($0.value) }
        guard plateau.count >= 2 else { return .notObserved(maxTested: maxTested) }

        let hi = plateau.map(\.length).min()!
        let lo = known
            .filter { $0.length < hi && !inPlateau($0.value) }
            .map(\.length)
            .max()
        return .at(lo: lo, hi: hi)
    }
}

// MARK: - Planner

/// One arithmetic run of candidate lengths: `from`, `from + step`, `from +
/// 2*step`, ... up to and including `to` (within floating-point slop).
public struct GridSegment: Equatable, Sendable {
    public var from: Double
    public var to: Double
    public var step: Double

    public init(from: Double, to: Double, step: Double) {
        self.from = from
        self.to = to
        self.step = step
    }
}

/// Plans which lengths to test: a fixed grid, the next bisection point
/// between two lengths, or a staircase that slows down near known centers of
/// interest.
public enum Planner {

    /// Every segment's stepped values plus `extras`, sorted ascending with
    /// near-duplicates (within `1e-9`) collapsed to one entry. A segment with
    /// `step <= 0` contributes only its `from`, since it cannot step.
    public static func grid(_ segments: [GridSegment], extras: [Double]) -> [Double] {
        var values: [Double] = []
        for segment in segments {
            guard segment.step > 0 else {
                values.append(segment.from)
                continue
            }
            precondition(
                segment.from.isFinite && segment.to.isFinite,
                "GridSegment.from and .to must be finite"
            )
            // Each value is computed directly as from + k*step, never by repeatedly
            // adding step to a running total: accumulation drifts by more than the
            // 1e-9 slop below over long fine-stepped grids and silently drops `to`.
            var k = 0
            while true {
                let value = segment.from + Double(k) * segment.step
                guard value <= segment.to + Numeric.epsilon else { break }
                values.append(value)
                k += 1
            }
        }
        values.append(contentsOf: extras)
        values.sort()
        return deduplicateSorted(values)
    }

    /// The midpoint of `[lo, hi]`, rounded to the nearest whole length, or nil
    /// when the span is already narrow enough (`hi - lo <= resolution`) or the
    /// rounded midpoint would collapse onto an endpoint.
    public static func nextBisection(lo: Double, hi: Double, resolution: Double) -> Double? {
        guard lo < hi else { return nil }
        guard hi - lo > resolution else { return nil }
        let mid = ((lo + hi) / 2).rounded()
        guard mid > lo && mid < hi else { return nil }
        return mid
    }

    /// The lengths to visit after leaving `from`, ending exactly at `to`:
    /// `coarse` steps ordinarily, `fine` steps whenever the current length or
    /// the next coarse step would land within `radius` of a center in
    /// `fineAround`, so a run walking through a region of interest slows down
    /// before it and speeds back up after it.
    public static func staircase(
        from: Double,
        to: Double,
        coarse: Double,
        fine: Double,
        fineAround: [Double],
        radius: Double
    ) -> [Double] {
        precondition(coarse > 0 && fine > 0, "coarse and fine steps must be positive")
        precondition(from.isFinite && to.isFinite, "from and to must be finite")
        guard from != to else { return [to] }

        let direction: Double = to > from ? 1 : -1
        var current = from
        var visited: [Double] = []

        while current != to {
            let looksAheadIntoFineRegion = fineAround.contains { center in
                abs(current - center) <= radius || abs(current + direction * coarse - center) <= radius
            }
            let step = looksAheadIntoFineRegion ? fine : coarse
            var next = current + direction * step
            precondition(next != current, "step is too small to advance past \(current)")
            if (direction > 0 && next > to) || (direction < 0 && next < to) {
                next = to
            }
            visited.append(next)
            current = next
        }

        return visited
    }

    /// Adjacent-duplicate removal on an already-sorted array: values within
    /// `1e-9` of the last kept value are treated as the same value.
    private static func deduplicateSorted(_ values: [Double]) -> [Double] {
        var result: [Double] = []
        for value in values {
            if let last = result.last, abs(value - last) <= Numeric.epsilon {
                continue
            }
            result.append(value)
        }
        return result
    }
}
