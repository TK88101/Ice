import Foundation

/// The T9 case list. Every function here reads swctl's own recorded fields —
/// `target`, `chevron`, `newAgentItems`, `decision`, `staticItemsNotAtBaseline`
/// — and nothing from IceCore. This is the oracle: it must be written and
/// frozen (`vzreplay label`) before `vzreplay check` ever runs IceCore's rules
/// over the same evidence.
enum Cases {
    static func labels(for run: RunEvidence) throws -> [LabelEntry] {
        switch run.runId {
        case "20260918-204150-m-mid": return try mMidLabels(run)
        case "20260918-194520-c-mid": return try pillBaselineLabel(run, otherItems: pillBaselineOtherItems)
        case "20260918-202302-o1": return try pillBaselineLabel(run, otherItems: pillBaselineOtherItems)
        case "20260918-202525-scan-mid": return try spaceSlideLabels(run)
        case "20260918-200903-scan-mid": return try teamsBadgeLabel(run)
        default: throw ReplayError.unknownCase(run.runId)
        }
    }

    /// Plain apps used only to give ink calibration real glyphs to count, for
    /// the two runs whose own case doesn't otherwise need any item template.
    static let pillBaselineOtherItems = ["com.google.Chrome#0", "com.openai.codex#0"]

    /// Every run this tool has a case for, in report order.
    static let knownRuns = [
        "20260918-204150-m-mid",
        "20260918-194520-c-mid",
        "20260918-202302-o1",
        "20260918-202525-scan-mid",
        "20260918-200903-scan-mid",
    ]

    // MARK: - 204150-m-mid: band probes, ordinary visible/overflowed probes, chevron present

    private static func mMidLabels(_ run: RunEvidence) throws -> [LabelEntry] {
        var entries: [LabelEntry] = []

        // Ordinary "visible" probes: the target's own two-colour marker (T) is
        // unique, so swctl calls it `visible(x:)`.
        for capture in ["00041-probe-mid-4.png", "00042-probe-mid-8.png", "00043-probe-mid-12.png"] {
            let (probe, assess, gap) = try probeAndAssess(run, capture: capture)
            let targetField = try probe.string("target", context: "probe.target")
            guard let x = parseVisibleX(targetField) else {
                throw ReplayError.reconstructionFailed("\(capture): target field '\(targetField)' is not visible(x:)")
            }
            _ = assess
            entries.append(LabelEntry(
                id: "\(run.runId).visible.\(capture)",
                run: run.runId,
                kind: "targetDrawn",
                captures: [capture],
                oracleField: "probe.target",
                oracleValue: targetField,
                expected: "drawn~\(x)",
                note: "swctl's own T marker found unique; nearest assess \(String(format: "%.3f", gap))s away."
            ))
        }

        // "Band" (selfov) and ordinary (hide) overflow probes with the chevron's
        // AX frame at the plan's 17.5 pt width — the fold witness's own case.
        let overflowChevron = [
            ("00011-probe-mid-20.png", "hide"),
            ("00015-probe-mid-648.png", "selfov"),
            ("00017-probe-mid-652.png", "selfov"),
        ]
        for (capture, band) in overflowChevron {
            let (probe, assess, gap) = try probeAndAssess(run, capture: capture)
            let targetField = try probe.string("target", context: "probe.target")
            guard targetField == "overflowed" else {
                throw ReplayError.reconstructionFailed("\(capture): expected target 'overflowed', found '\(targetField)'")
            }
            let newAgentItems = try Frames.newAgentItems(assess)
            guard let chevron = newAgentItems.first(where: { abs($0.width - 17.5) < 0.6 }) else {
                throw ReplayError.reconstructionFailed("\(capture): no 17.5 pt-wide newAgentItems entry (chevron) in the nearest assess")
            }
            entries.append(LabelEntry(
                id: "\(run.runId).overflow.\(capture)",
                run: run.runId,
                kind: "targetNotDrawn",
                captures: [capture],
                oracleField: "probe.target (\(band))",
                oracleValue: targetField,
                expected: "notDrawn",
                note: "nearest assess \(String(format: "%.3f", gap))s away; also grounds the fold-present case below."
            ))
            entries.append(LabelEntry(
                id: "\(run.runId).foldPresent.\(capture)",
                run: run.runId,
                kind: "foldPresent",
                captures: [capture],
                oracleField: "assess.newAgentItems",
                oracleValue: "x=\(chevron.minX) w=\(chevron.width)",
                expected: "present",
                note: "A MenuBarAgent item 17.5 pt wide (plan 3.5's chevron width) appears in AX that was not in the baseline set."
            ))
        }

        return entries
    }

    // MARK: - 194520-c-mid / 202302-o1: the microphone pill at baseline

    /// Both runs aborted at `establishRest` (the pill blocked the target/
    /// protected/spacer markers) and never reached the trial loop — zero
    /// `assess` records exist in either. So this label is about the run's own
    /// pre-helper baseline only: does the pill (`com.apple.MenuBarAgent#0`,
    /// x=1035, w=16 in both runs' `baseline` record) get folded into the
    /// chevron reading, or correctly kept apart from it (it is 1.5 pt short of
    /// the 17.5 pt candidate width, outside the ± 0.5 pt tolerance)?
    private static func pillBaselineLabel(_ run: RunEvidence, otherItems: [String]) throws -> [LabelEntry] {
        let baseline = try run.swctlBaseline()
        let items = try baseline.recordArray("items", context: "baseline")
        guard let pill = try items.first(where: { try $0.string("id", context: "baseline item") == "com.apple.MenuBarAgent#0" }) else {
            throw ReplayError.reconstructionFailed("\(run.runId): expected the pill at com.apple.MenuBarAgent#0")
        }
        let x = try pill.double("x", context: "pill")
        let w = try pill.double("w", context: "pill")
        return [LabelEntry(
            id: "\(run.runId).foldAtBaseline",
            run: run.runId,
            kind: "foldAtBaselineAbsent",
            captures: (1...8).map { String(format: "%05d-baseline.png", $0) },
            oracleField: "baseline.items[com.apple.MenuBarAgent#0]",
            oracleValue: "x=\(x) w=\(w)",
            expected: "absent",
            note: "The pill is 16 pt wide, not the 17.5 pt chevron width; it must not be read as the fold. "
                + "Every rest.check in this run failed with 'microphone pill present' among its reasons, and the "
                + "run aborted before the trial loop (0 assess records), so this checks the baseline alone, "
                + "with \(otherItems.joined(separator: ", ")) supplying real glyphs for ink calibration."
        )]
    }

    // MARK: - 202525-scan-mid: a Space slide

    /// swctl's own guard independently calls this instability: `protectedLost`
    /// plus `itemLost` for every one of the 15 tracked static items, in the
    /// same capture where the T marker's own x teleports.
    private static func spaceSlideLabels(_ run: RunEvidence) throws -> [LabelEntry] {
        let pairs = [
            ("00022-guard.png", "00023-guard.png"),
            ("00131-guard.png", "00132-guard.png"),
        ]
        var entries: [LabelEntry] = []
        for (first, second) in pairs {
            guard let a = run.records(kind: "assess").first(where: { $0.capture == first }),
                  let b = run.records(kind: "assess").first(where: { $0.capture == second })
            else {
                throw ReplayError.reconstructionFailed("\(run.runId): expected assess records for \(first) and \(second)")
            }
            let targetA = try a.string("target", context: "assess.target")
            let targetB = try b.string("target", context: "assess.target")
            let decisionB = try b.string("decision", context: "assess.decision")
            entries.append(LabelEntry(
                id: "\(run.runId).spaceSlide.\(first)",
                run: run.runId,
                kind: "unstable",
                captures: [first, second],
                oracleField: "assess.target, assess.decision",
                oracleValue: "\(targetA) -> \(targetB); \(decisionB.prefix(120))",
                expected: "unstable",
                note: "swctl's own guard flags protectedLost + itemLost for every tracked static item in the same "
                    + "pair, independent of anything this tool does."
            ))
        }
        return entries
    }

    // MARK: - 200903-scan-mid: the Teams badge changed

    private static func teamsBadgeLabel(_ run: RunEvidence) throws -> [LabelEntry] {
        guard let teardown = run.records(kind: "teardown").first else {
            throw ReplayError.reconstructionFailed("\(run.runId): no teardown record")
        }
        let displaced = try teardown.array("staticItemsNotAtBaseline", context: "teardown")
            .compactMap { $0 as? String }
        guard displaced.contains("com.microsoft.teams2#0") else {
            throw ReplayError.reconstructionFailed("\(run.runId): expected com.microsoft.teams2#0 in staticItemsNotAtBaseline")
        }
        guard let teardownCapture = teardown.capture else {
            throw ReplayError.reconstructionFailed("\(run.runId): teardown record has no capture")
        }
        return [LabelEntry(
            id: "\(run.runId).teamsBadge",
            run: run.runId,
            kind: "notAbsent",
            captures: ["00003-baseline.png", teardownCapture],
            oracleField: "teardown.staticItemsNotAtBaseline",
            oracleValue: displaced.joined(separator: ", "),
            expected: "notAbsent",
            note: "swctl's own strict (2% mismatch, offset-0-only) static check flags Teams as changed at "
                + "teardown, out of all 15 static items — a badge/icon redraw, not a slide (nothing else in the "
                + "list). IceCore must not read this as .notDrawn."
        )]
    }

    // MARK: - Helpers

    static func parseVisibleX(_ field: String) -> Double? {
        guard field.hasPrefix("visible(x: "), field.hasSuffix(")") else { return nil }
        let inner = field.dropFirst("visible(x: ".count).dropLast(1)
        return Double(inner)
    }

    /// Reads the x back out of an `expected` string of the form `drawn~<x>`.
    static func parseDrawnExpectation(_ expected: String) -> Double? {
        guard expected.hasPrefix("drawn~") else { return nil }
        return Double(expected.dropFirst("drawn~".count))
    }

    private static func probeAndAssess(_ run: RunEvidence, capture: String) throws -> (probe: Record, assess: Record, gap: Double) {
        guard let probe = run.records(kind: "probe").first(where: { $0.capture == capture }) else {
            throw ReplayError.reconstructionFailed("\(run.runId): no probe record for \(capture)")
        }
        guard let wall = probe.wall else {
            throw ReplayError.reconstructionFailed("\(run.runId): probe \(capture) has no wall time")
        }
        let (assess, gap) = try run.nearestAssess(to: try WallClock.seconds(wall))
        return (probe, assess, gap)
    }
}
