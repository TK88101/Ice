// Rule 1, the hidden-state baseline (pre-registration sections 2-3; deviation 2
// C2's texture bound; claim plan R1-R4, R7-R10, R14). Every added rule here
// only refuses.
import IceBarOracle
import IceCore

/// An accepted hidden-state baseline: what `RegionClear` compares against.
public struct HiddenBaseline: Equatable, Sendable {
    /// The first kept capture, whole; only its region is compared.
    public let stored: StripImage
    public let region: PtSpan
    public let notch: PtSpan?
    /// The earliest kept read's on-bar `MenuBarAgent` frames.
    public let canonicalAgentFrames: [AgentFrame]
    /// Region columns minus notch columns.
    let columns: [Int]
}

public enum BaselineRefusal: Equatable, Sendable {
    case foldNotAbsent(Fold)
    case keptCount(Int)
    /// `frozen.agentFrames` is not the latest kept read's.
    case frozenMismatch
    case capturesDiffer
    case chevronFrame
    case agentFramesMoved
    case regionUndefined
    /// Rule 1 (a).
    case disagree
    /// Rule 1 (b).
    case rowDeviation
    /// Deviation 2 C2.
    case texture
    case contrastUnmeasurable
    case contrast
}

public enum BaselineOutcome: Equatable, Sendable {
    case accepted(HiddenBaseline)
    case refused(BaselineRefusal)
}

/// The numbers section 8 asks S0 to report, filled whenever the structural
/// checks passed, whatever the refusal (claim plan R14).
public struct BaselineMeasurements: Equatable, Sendable {
    /// Largest distance of any kept-capture region pixel from the stored one.
    public let maxAgreementDistance: Int?
    /// Largest 8-connected cluster deviating from its row median by > `T_bg`.
    public let largestRowCluster: Int?
    /// Largest distance of any quiet region pixel from its row median.
    public let maxRowDeviation: Int?
    /// `TextureBound` over the kept captures: refused if any is, worst deviation.
    public let texture: TextureBound.Outcome?
    public let contrast: ContrastMeasurement?

    public init(maxAgreementDistance: Int? = nil, largestRowCluster: Int? = nil, maxRowDeviation: Int? = nil,
                texture: TextureBound.Outcome? = nil, contrast: ContrastMeasurement? = nil) {
        self.maxAgreementDistance = maxAgreementDistance
        self.largestRowCluster = largestRowCluster
        self.maxRowDeviation = maxRowDeviation
        self.texture = texture
        self.contrast = contrast
    }
}

public struct BaselineVerdict: Equatable, Sendable {
    public let outcome: BaselineOutcome
    public let measurements: BaselineMeasurements
    /// Every failing pixel clause, in order (a), (b), texture, contrast.
    public let failedClauses: [BaselineRefusal]
}

extension HiddenBaseline {
    /// `kept`: samples 2-5 of the baseline (part 3's cadence); `frozen`: the
    /// frozen `StripAssessor.baseline` over all five; `visible`: every visible
    /// helper's template, references included.
    public static func evaluate(kept: [ObservationSample], frozen: BaselineResult, references: [String],
                                visible: [OracleTemplate], parameters: ClaimParameters = .preRegistered) -> BaselineVerdict {
        switch prepare(kept: kept, frozen: frozen, references: references, parameters: parameters) {
        case let .refused(reason):
            return BaselineVerdict(outcome: .refused(reason), measurements: BaselineMeasurements(), failedClauses: [])
        case let .ready(setup):
            return judge(setup, visible: visible, references: references, parameters: parameters)
        }
    }

    struct Setup {
        let stored: StripImage
        let captures: [StripImage]
        let geometry: BarGeometry
        let canonical: [AgentFrame]
        let region: ClaimRegion
    }

    enum Preparation {
        case refused(BaselineRefusal)
        case ready(Setup)
    }

    /// The structural checks, in claim plan R14's order; each stops evaluation.
    static func prepare(kept: [ObservationSample], frozen: BaselineResult, references: [String], parameters: ClaimParameters) -> Preparation {
        guard frozen.foldAtBaseline == .absent else { return .refused(.foldNotAbsent(frozen.foldAtBaseline)) }
        guard kept.count == parameters.keptSamples else { return .refused(.keptCount(kept.count)) }
        let ordered = kept.sorted { $0.time < $1.time }
        guard let first = ordered.first, let last = ordered.last, frozen.agentFrames == last.agentFrames else {
            return .refused(.frozenMismatch)
        }
        let geometry = frozen.geometry
        let captures = ordered.flatMap { [$0.before, $0.after] }
        guard captures.allSatisfy({ $0.width == geometry.widthPx && $0.height == geometry.heightPx && $0.scale == geometry.scale }) else {
            return .refused(.capturesDiffer)
        }
        let reads = ordered.map { $0.agentFrames.filter { $0.minY >= 0 && $0.minY < geometry.heightPt } }
        let detector = DetectorParameters.preRegistered
        guard !reads.joined().contains(where: { FoldWitness.isChevron($0, parameters: detector) }) else { return .refused(.chevronFrame) }
        let canonical = reads[0]
        guard reads.dropFirst().allSatisfy({ FoldWitness.agentSetMatches(current: $0, baseline: canonical, parameters: detector) }) else {
            return .refused(.agentFramesMoved)
        }
        let origins = references.map { frozen.templates[$0]?.originXPt }
        guard !origins.isEmpty, !origins.contains(nil), let rightEdge = origins.compactMap({ $0 }).min(),
              let region = ClaimRegion(geometry: geometry, widthPx: first.before.width, rightEdgePt: rightEdge,
                                       agentSpans: canonical.map(\.span))
        else { return .refused(.regionUndefined) }
        return .ready(Setup(stored: first.before, captures: captures, geometry: geometry, canonical: canonical, region: region))
    }

    /// The four pixel clauses, all measured; the refusal is the first failing.
    static func judge(_ setup: Setup, visible: [OracleTemplate], references: [String], parameters: ClaimParameters) -> BaselineVerdict {
        let agreement = setup.captures.map { maxDistance($0, from: setup.stored, columns: setup.region.columns) }.max() ?? 0
        let rows = setup.captures.map { rowDeviation($0, region: setup.region, parameters: parameters) }
        let largestRowCluster = rows.map(\.largestCluster).max() ?? 0
        let texture = textureOutcome(setup)
        let contrast = ContrastGate.measure(stored: setup.stored, visible: visible, references: references,
                                            region: setup.region, notch: setup.geometry.notch, agentSpans: setup.canonical.map(\.span))

        var failed = [BaselineRefusal]()
        if agreement > parameters.tAgree { failed.append(.disagree) }
        if largestRowCluster >= parameters.clusterMinPx { failed.append(.rowDeviation) }
        if case .refused = texture { failed.append(.texture) }
        if let contrast {
            if !contrast.passes(parameters) { failed.append(.contrast) }
        } else {
            failed.append(.contrastUnmeasurable)
        }
        let measurements = BaselineMeasurements(maxAgreementDistance: agreement, largestRowCluster: largestRowCluster,
                                                maxRowDeviation: rows.map(\.maxDeviation).max() ?? 0,
                                                texture: texture, contrast: contrast)
        let baseline = HiddenBaseline(stored: setup.stored, region: setup.region.span, notch: setup.geometry.notch,
                                      canonicalAgentFrames: setup.canonical, columns: setup.region.columns)
        let outcome: BaselineOutcome = failed.first.map { .refused($0) } ?? .accepted(baseline)
        return BaselineVerdict(outcome: outcome, measurements: measurements, failedClauses: failed)
    }

    /// Rule 1 (a): the largest distance from the stored image over `columns`.
    static func maxDistance(_ capture: StripImage, from stored: StripImage, columns: [Int]) -> Int {
        var worst = 0
        for y in 0..<capture.height {
            for x in columns { worst = max(worst, PixelKit.distance(capture, stored, x, y)) }
        }
        return worst
    }

    /// Rule 1 (b) for one capture: pixels farther than `T_bg` from their
    /// row's median, clustered over the quiet columns.
    static func rowDeviation(_ capture: StripImage, region: ClaimRegion,
                             parameters: ClaimParameters) -> (largestCluster: Int, maxDeviation: Int) {
        var mask = [Bool](repeating: false, count: capture.width * capture.height)
        var worst = 0
        for y in 0..<capture.height {
            guard let median = region.rowMedian(capture, y) else { continue }
            for x in region.quietColumns {
                let d = PixelKit.distance(PixelKit.colour(capture, x, y), median)
                worst = max(worst, d)
                if d > parameters.tBg { mask[y * capture.width + x] = true }
            }
        }
        let largest = PixelKit.clusterSizes(mask, width: capture.width, height: capture.height).max() ?? 0
        return (largest, worst)
    }

    /// Deviation 2 C2 through part 1's own symbol, with the corpus's argument
    /// construction: rule 1's region, the notch, the canonical agent frames.
    static func textureOutcome(_ setup: Setup) -> TextureBound.Outcome {
        let outcomes = setup.captures.map {
            TextureBound.evaluate($0, region: setup.region.span, notch: setup.geometry.notch, agentFrames: setup.canonical.map(\.span))
        }
        var worst = 0
        var refused = false
        for outcome in outcomes {
            switch outcome {
            case let .accepted(d): worst = max(worst, d)
            case let .refused(d):
                worst = max(worst, d)
                refused = true
            }
        }
        return refused ? .refused(maxDeviation: worst) : .accepted(maxDeviation: worst)
    }
}
