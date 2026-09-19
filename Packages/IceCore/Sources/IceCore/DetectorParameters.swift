/// Every threshold the detector uses, in one place.
///
/// `preRegistered` holds the values fixed in
/// docs/plans/2026-09-19-visibility-adapter.md section 3.0, before any replay or
/// live run. Changing one after seeing a result is a deviation, and belongs in
/// that plan's ledger with its reason.
public struct DetectorParameters: Equatable, Sendable {
    /// Glyph colour on a dark bar (`swctl` Calibration.swift:38).
    public let whiteInk: ColorMatch
    /// Glyph colour on a light bar (`swctl` Calibration.swift:37).
    public let blackInk: ColorMatch
    /// Median luma inside which the glyphs, not the median, decide the ink.
    public let inkDecisionBand: ClosedRange<Int>

    /// A match at or below this is `drawn` (the decision layer's tolerance).
    public let maxMismatch: Double
    /// A match at or below this is found at all; above `maxMismatch` it is weak.
    public let foundThreshold: Double
    /// Pass 2's looser mismatch: enough to keep a partly redrawn glyph from
    /// reading as gone, tight enough that a vacated slot still does.
    public let weakThreshold: Double
    /// Core ink ≥ this × `foundThreshold` × cared pixels.
    public let coreInkFactor: Double
    /// Core background ≥ max(core ink, this × cared pixels).
    public let coreBackgroundFraction: Double

    public let templateMarginPx: Int
    public let suppressionRadiusPx: Int
    public let minTemplateWidthPt: Double

    public let referenceTolerancePt: Double
    public let sightingTolerancePt: Double
    public let placementSlackPt: Double
    public let readAgreementTolerancePt: Double

    public let minSamples: Int
    public let minSampleSpacing: Double
    public let baselineMinSamples: Int
    public let baselineMinSpan: Double
    public let baselineDroppedSamples: Int

    public let chevronWidthPt: Double
    public let chevronWidthTolerancePt: Double
    /// The microphone pill's Accessibility width, 16 pt in the two recorded
    /// baselines that carry one. Named here so a recalibration is a deviation
    /// from a parameter rather than an edit to a literal in a harness.
    public let pillWidthPt: Double
    public let pillWidthTolerancePt: Double
    public let agentXTolerancePt: Double
    public let agentWidthTolerancePt: Double
    public let foldClusterMinPx: Int
    public let regionAgreementMax: Double

    public init(
        whiteInk: ColorMatch = ColorMatch(center: RGBA(255, 255, 255), tolerance: 70),
        blackInk: ColorMatch = ColorMatch(center: RGBA(0, 0, 0), tolerance: 100),
        inkDecisionBand: ClosedRange<Int> = 118...138,
        maxMismatch: Double = 0.05,
        foundThreshold: Double = 0.08,
        weakThreshold: Double = 0.12,
        coreInkFactor: Double = 2,
        coreBackgroundFraction: Double = 0.3,
        templateMarginPx: Int = 2,
        suppressionRadiusPx: Int = 2,
        minTemplateWidthPt: Double = 4,
        referenceTolerancePt: Double = 1,
        sightingTolerancePt: Double = 0.5,
        placementSlackPt: Double = 4,
        readAgreementTolerancePt: Double = 0.5,
        minSamples: Int = 2,
        minSampleSpacing: Double = 0.3,
        baselineMinSamples: Int = 4,
        baselineMinSpan: Double = 3,
        baselineDroppedSamples: Int = 1,
        chevronWidthPt: Double = 17.5,
        chevronWidthTolerancePt: Double = 0.5,
        pillWidthPt: Double = 16,
        pillWidthTolerancePt: Double = 0.5,
        agentXTolerancePt: Double = 1,
        agentWidthTolerancePt: Double = 0.5,
        foldClusterMinPx: Int = 16,
        regionAgreementMax: Double = 0.01
    ) {
        self.whiteInk = whiteInk
        self.blackInk = blackInk
        self.inkDecisionBand = inkDecisionBand
        self.maxMismatch = maxMismatch
        self.foundThreshold = foundThreshold
        self.weakThreshold = weakThreshold
        self.coreInkFactor = coreInkFactor
        self.coreBackgroundFraction = coreBackgroundFraction
        self.templateMarginPx = templateMarginPx
        self.suppressionRadiusPx = suppressionRadiusPx
        self.minTemplateWidthPt = minTemplateWidthPt
        self.referenceTolerancePt = referenceTolerancePt
        self.sightingTolerancePt = sightingTolerancePt
        self.placementSlackPt = placementSlackPt
        self.readAgreementTolerancePt = readAgreementTolerancePt
        self.minSamples = minSamples
        self.minSampleSpacing = minSampleSpacing
        self.baselineMinSamples = baselineMinSamples
        self.baselineMinSpan = baselineMinSpan
        self.baselineDroppedSamples = baselineDroppedSamples
        self.chevronWidthPt = chevronWidthPt
        self.chevronWidthTolerancePt = chevronWidthTolerancePt
        self.pillWidthPt = pillWidthPt
        self.pillWidthTolerancePt = pillWidthTolerancePt
        self.agentXTolerancePt = agentXTolerancePt
        self.agentWidthTolerancePt = agentWidthTolerancePt
        self.foldClusterMinPx = foldClusterMinPx
        self.regionAgreementMax = regionAgreementMax
    }

    public static let preRegistered = DetectorParameters()

    /// The invariants the rules rely on. A pass-2 hit must read as weak, which
    /// needs `foundThreshold ≥ maxMismatch`; suppression must never merge two
    /// items, which needs its radius under half the narrowest template.
    public var isValid: Bool {
        let fractions = [maxMismatch, foundThreshold, weakThreshold, coreBackgroundFraction, regionAgreementMax]
        return fractions.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
            && foundThreshold >= maxMismatch
            // A vacated slot mismatches by at least the glyph's own ink share,
            // which the core-ink invariant keeps at or above
            // `coreInkFactor * foundThreshold`; pass 2 must stay under that or
            // an item that is gone would read as merely weak, for ever.
            && weakThreshold >= foundThreshold
            && weakThreshold < coreInkFactor * foundThreshold
            && coreInkFactor >= 1
            && templateMarginPx >= 0
            && suppressionRadiusPx >= 0
            && Double(2 * suppressionRadiusPx) <= minTemplateWidthPt
            && minSamples >= 2
            && minSampleSpacing >= 0
            && baselineMinSamples > baselineDroppedSamples + 1
            && foldClusterMinPx > 0
    }
}
