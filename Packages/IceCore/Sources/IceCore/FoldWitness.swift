/// One of `MenuBarAgent`'s own items, as Accessibility reported it.
public struct AgentFrame: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double

    public init(minX: Double, minY: Double, width: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
    }

    public var span: PtSpan { PtSpan(lo: minX, hi: minX + max(0, width)) }

    var isFinite: Bool { minX.isFinite && minY.isFinite && width.isFinite }
}

/// One bracketed observation: a capture, an Accessibility read, a capture.
///
/// A read that failed as a whole produces no sample at all, so an empty
/// `agentFrames` here means the read succeeded and found nothing — which cannot
/// happen on a real bar (`MenuBarAgent` owns the clock and the control centre)
/// and is therefore unreadable rather than "no fold".
public struct FoldSample: Equatable, Sendable {
    public let time: Double
    public let before: InkMap
    public let after: InkMap
    public let agentFrames: [AgentFrame]
    /// Whether the references held still in both captures of this sample.
    public let referencesStable: Bool
    /// Spans whose ink is accounted for: the templates that matched here, or at
    /// the baseline, the items' own frames.
    public let explained: [PtSpan]

    public init(time: Double, before: InkMap, after: InkMap, agentFrames: [AgentFrame], referencesStable: Bool, explained: [PtSpan]) {
        self.time = time
        self.before = before
        self.after = after
        self.agentFrames = agentFrames
        self.referencesStable = referencesStable
        self.explained = explained
    }
}

/// Whether the system's overflow chevron is up.
///
/// On macOS 27 squeezing an item off the bar *is* that fold, so an item that
/// vanished without one vanished some other way — which makes this the
/// difference between two mechanisms, not a detail. Every rule here is
/// fail-closed, and each answers something the 2026-09-18 runs got wrong:
/// Accessibility lags the pixels by ≈ 0.1 s, a privacy pill is another
/// `MenuBarAgent` item, and a chevron can be drawn before Accessibility lists it.
public enum FoldWitness {
    /// The fold across a run of samples: at least `minSamples`, spaced at least
    /// `minSampleSpacing` apart, all saying the same thing.
    public static func derive(
        samples: [FoldSample],
        baselineFrames: [AgentFrame]?,
        region: PtSpan,
        geometry: BarGeometry,
        parameters: DetectorParameters
    ) -> Fold {
        guard samples.count >= parameters.minSamples else { return .unreadable }
        let ordered = samples.sorted { $0.time < $1.time }
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            guard next.time - previous.time >= parameters.minSampleSpacing else { return .unreadable }
        }
        let verdicts = ordered.map {
            verdict(for: $0, baselineFrames: baselineFrames, region: region, geometry: geometry, parameters: parameters)
        }
        guard let first = verdicts.first, verdicts.allSatisfy({ $0 == first }) else { return .unreadable }
        return first
    }

    /// Whether a frame is the overflow chevron by width: 17.5 pt in every
    /// reading on record. Public because the harnesses ask the same question
    /// before a run starts, and a second copy of the number would drift.
    public static func isChevron(_ frame: AgentFrame, parameters: DetectorParameters) -> Bool {
        abs(frame.width - parameters.chevronWidthPt) <= parameters.chevronWidthTolerancePt
    }

    /// Whether a frame is a privacy pill by width (16 pt, measured twice).
    /// Nothing else in this module models the pill: the fold witness only ever
    /// asks about the chevron, so this is the only guard there is.
    public static func isPill(_ frame: AgentFrame, parameters: DetectorParameters) -> Bool {
        abs(frame.width - parameters.pillWidthPt) <= parameters.pillWidthTolerancePt
    }

    /// Whether the system's own items are exactly where they were: each
    /// non-chevron frame paired with a baseline frame at the same x and width.
    /// Public for the same reason as `isChevron`.
    public static func agentSetMatches(current: [AgentFrame], baseline: [AgentFrame], parameters: DetectorParameters) -> Bool {
        let currentOthers = current.filter { !isChevron($0, parameters: parameters) }
        let baselineOthers = baseline.filter { !isChevron($0, parameters: parameters) }
        return matchOneToOne(currentOthers, baselineOthers, parameters: parameters)
    }

    static func verdict(
        for sample: FoldSample,
        baselineFrames: [AgentFrame]?,
        region: PtSpan,
        geometry: BarGeometry,
        parameters: DetectorParameters
    ) -> Fold {
        guard !sample.agentFrames.isEmpty, sample.agentFrames.allSatisfy(\.isFinite) else { return .unreadable }
        guard sample.referencesStable else { return .unreadable }
        guard regionsAgree(sample.before, sample.after, region: region, geometry: geometry, parameters: parameters) else {
            return .unreadable
        }

        let onBar = sample.agentFrames.filter { $0.minY >= 0 && $0.minY < geometry.heightPt }
        let candidates = onBar.filter { isChevron($0, parameters: parameters) }
        let others = onBar.filter { !isChevron($0, parameters: parameters) }

        if let baselineFrames {
            guard agentSetMatches(current: onBar, baseline: baselineFrames, parameters: parameters) else { return .unreadable }
        }

        switch candidates.count {
        case 0:
            // A chevron can be drawn before Accessibility lists it, so absence
            // needs the pixels to agree: no ink in the fold region that the
            // sighted templates do not account for. A system item that IS
            // listed accounts for its own ink — capturing the bar summons a
            // ≈ 20 pt `MenuBarAgent` indicator there (2026-09-19), and its
            // glyph is explained by its own frame, not unexplained ink.
            let explained = sample.explained + others.map(\.span)
            let clusters = unexplainedClusters(in: sample.after, region: region, explained: explained, geometry: geometry, parameters: parameters)
            return clusters.isEmpty ? .absent : .unreadable
        case 1:
            let inkPixels = inkCount(in: sample.after, span: candidates[0].span, geometry: geometry)
            return inkPixels >= parameters.foldClusterMinPx ? .present : .unreadable
        default:
            return .unreadable
        }
    }

    /// The fold region's ink must be the same in both captures of a sample: the
    /// references are all to the right of where `«` is drawn, so they say
    /// nothing about it (they were the whole bracket before 2026-09-19).
    private static func regionsAgree(_ before: InkMap, _ after: InkMap, region: PtSpan, geometry: BarGeometry, parameters: DetectorParameters) -> Bool {
        guard before.width == after.width, before.height == after.height else { return false }
        let columns = columnRange(region, width: before.width, scale: geometry.scale)
        guard !columns.isEmpty else { return true }
        var differing = 0
        var total = 0
        for y in 0..<before.height {
            for x in columns where !geometry.isNotchColumn(x) {
                total += 1
                if before[x, y] != after[x, y] { differing += 1 }
            }
        }
        guard total > 0 else { return true }
        return Double(differing) / Double(total) <= parameters.regionAgreementMax
    }

    /// Every current non-chevron frame paired with a baseline frame at the same
    /// x and width. Anything that arrived, left, moved or was replaced by an
    /// item of the same width breaks the pairing, and the sample is unreadable.
    private static func matchOneToOne(_ current: [AgentFrame], _ baseline: [AgentFrame], parameters: DetectorParameters) -> Bool {
        guard current.count == baseline.count else { return false }
        let left = current.sorted { $0.minX < $1.minX }
        let right = baseline.sorted { $0.minX < $1.minX }
        for (a, b) in zip(left, right) {
            guard abs(a.minX - b.minX) <= parameters.agentXTolerancePt else { return false }
            guard abs(a.width - b.width) <= parameters.agentWidthTolerancePt else { return false }
        }
        return true
    }

    /// Connected areas of ink in the fold region that no template explains.
    static func unexplainedClusters(in map: InkMap, region: PtSpan, explained: [PtSpan], geometry: BarGeometry, parameters: DetectorParameters) -> [Int] {
        let columns = columnRange(region, width: map.width, scale: geometry.scale)
        guard !columns.isEmpty else { return [] }

        var eligible = [Bool](repeating: false, count: map.width * map.height)
        for y in 0..<map.height {
            for x in columns where map[x, y] && !geometry.isNotchColumn(x) {
                let pt = Double(x) / geometry.scale
                guard !explained.contains(where: { $0.contains(pt) }) else { continue }
                eligible[y * map.width + x] = true
            }
        }

        var clusters = [Int]()
        var visited = [Bool](repeating: false, count: eligible.count)
        for y in 0..<map.height {
            for x in columns where eligible[y * map.width + x] && !visited[y * map.width + x] {
                var stack = [(x, y)]
                visited[y * map.width + x] = true
                var size = 0
                while let (cx, cy) = stack.popLast() {
                    size += 1
                    for dy in -1...1 {
                        for dx in -1...1 where !(dx == 0 && dy == 0) {
                            let nx = cx + dx, ny = cy + dy
                            guard nx >= 0, nx < map.width, ny >= 0, ny < map.height else { continue }
                            let index = ny * map.width + nx
                            guard eligible[index], !visited[index] else { continue }
                            visited[index] = true
                            stack.append((nx, ny))
                        }
                    }
                }
                if size >= parameters.foldClusterMinPx { clusters.append(size) }
            }
        }
        return clusters
    }

    private static func inkCount(in map: InkMap, span: PtSpan, geometry: BarGeometry) -> Int {
        let columns = columnRange(span, width: map.width, scale: geometry.scale)
        var total = 0
        for y in 0..<map.height {
            for x in columns where map[x, y] && !geometry.isNotchColumn(x) {
                total += 1
            }
        }
        return total
    }

    private static func columnRange(_ span: PtSpan, width: Int, scale: Double) -> Range<Int> {
        let lo = max(0, Int((span.lo * scale).rounded(.down)))
        let hi = min(width, Int((span.hi * scale).rounded(.up)))
        return lo < hi ? lo..<hi : 0..<0
    }
}
