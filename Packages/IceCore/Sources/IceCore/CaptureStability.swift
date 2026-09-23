/// Whether a capture can be trusted at all.
///
/// Decided from references: items the action does not touch, whose templates
/// were cut at the same baseline. If they are all still exactly where they were,
/// the bar did not slide, the appearance did not flip, and the capture was not
/// taken mid-animation.
///
/// This is a **necessary** condition, never a sufficient one. The bar is
/// translucent over the window beneath it, and that window can change under one
/// item while the references are untouched — on 2026-09-19 two captures 2 s
/// apart differed in 17-23 % of the status area's pixels for that reason. Ruling
/// on a single item is the matcher's job, not this one's.
public enum CaptureStability {
    public static func isStable(
        references: [String],
        templates: [String: ItemTemplate],
        captures: [[String: Match]],
        parameters: DetectorParameters
    ) -> Bool {
        guard !references.isEmpty, !captures.isEmpty else { return false }
        guard Set(references).count == references.count else { return false }

        for id in references {
            guard let template = templates[id] else { return false }
            for capture in captures {
                guard case .unique(let x, let mismatch)? = capture[id] else { return false }
                guard mismatch <= parameters.maxMismatch else { return false }
                guard abs(x - template.originXPt) <= parameters.referenceTolerancePt else { return false }
            }
        }
        return true
    }
}

/// What an item's own Accessibility frame says about the place its template
/// matched.
///
/// A veto and nothing more. Accessibility cannot show that something is drawn —
/// it keeps laying out items the screen does not draw (FINDINGS, the no-fold
/// band) — so this never turns into evidence of presence, and absence never
/// consults it at all.
public enum Placement: Equatable, Sendable {
    /// The frame is on this bar and over the match.
    case consistent
    /// A frame was read and it is somewhere else, or off the bar entirely.
    case inconsistent
    /// The read carried no frame for this item.
    case unavailable

    public static func assess(
        frame: ItemFrame?,
        matchX: Double,
        matchWidthPt: Double,
        geometry: BarGeometry,
        parameters: DetectorParameters
    ) -> Placement {
        guard let frame, frame.isFinite else { return .unavailable }
        guard frame.minY >= 0, frame.minY < geometry.heightPt else { return .inconsistent }
        guard frame.minX >= 0, frame.minX + frame.width <= geometry.widthPt else { return .inconsistent }
        let slack = parameters.placementSlackPt
        let match = PtSpan(lo: matchX - slack, hi: matchX + max(0, matchWidthPt) + slack)
        return frame.span.overlaps(match) ? .consistent : .inconsistent
    }
}
