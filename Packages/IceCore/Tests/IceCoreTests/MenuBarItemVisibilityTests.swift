import Testing
@testable import IceCore

/// The detector must answer "is this item drawn on the bar right now" from
/// pixels, and must refuse to answer whenever the capture cannot carry the
/// answer. Every refusal below is a case that produced a wrong conclusion in the
/// 2026-09-18 measurements (docs/macos-27/FINDINGS.md).
@Suite("MenuBarItemVisibility")
struct MenuBarItemVisibilityTests {
    let tolerance = 0.05

    func detector(tolerance: Double? = nil) -> MenuBarItemVisibility {
        MenuBarItemVisibility(maxMismatch: tolerance ?? self.tolerance)
    }

    // MARK: - The two answers it is allowed to give

    @Test("a unique match inside tolerance, on a stable capture, is drawn")
    func uniqueMatchIsDrawn() {
        let sighting = ItemSighting(id: "a", appearance: .asBaselined, match: .unique(x: 1020, mismatch: 0.01), placement: .consistent)
        #expect(detector().verdict(for: sighting, captureStable: true) == .drawn(x: 1020))
    }

    @Test("no match anywhere, on a stable capture of an unchanged item, is not drawn")
    func absentIsNotDrawn() {
        let sighting = ItemSighting(id: "a", appearance: .asBaselined, match: .absent(bestMismatch: 0.4), placement: .consistent)
        #expect(detector().verdict(for: sighting, captureStable: true) == .notDrawn)
    }

    // MARK: - Refusals

    @Test("an unstable capture answers nothing, however clear the match looks")
    func unstableCaptureRefuses() {
        // A Space switch slid the whole bar mid-capture and 15 items read as
        // lost at once; the guard's job there was to refuse, not to report.
        for match in [Match.unique(x: 1020, mismatch: 0.0), .absent(bestMismatch: 0.9)] {
            let sighting = ItemSighting(id: "a", appearance: .asBaselined, match: match, placement: .consistent)
            #expect(detector().verdict(for: sighting, captureStable: false) == .unverifiable(.captureUnstable))
        }
    }

    @Test("an item that redrew itself in place cannot be called absent by its old template")
    func changedAppearanceRefuses() {
        // The clock's text and a Teams badge both changed mid-run.
        let sighting = ItemSighting(id: "clock", appearance: .changedSinceBaseline, match: .absent(bestMismatch: 0.5), placement: .consistent)
        #expect(detector().verdict(for: sighting, captureStable: true) == .unverifiable(.appearanceChanged))
    }

    @Test("an item that redrew itself is still drawn when its template is found anyway")
    func changedAppearanceStillReportsAMatch() {
        let sighting = ItemSighting(id: "clock", appearance: .changedSinceBaseline, match: .unique(x: 1500, mismatch: 0.02), placement: .consistent)
        #expect(detector().verdict(for: sighting, captureStable: true) == .drawn(x: 1500))
    }

    @Test("several matches mean the template is not specific enough to decide")
    func ambiguousMatchRefuses() {
        let sighting = ItemSighting(id: "a", appearance: .asBaselined, match: .ambiguous(count: 2), placement: .consistent)
        #expect(detector().verdict(for: sighting, captureStable: true) == .unverifiable(.ambiguousMatch))
    }

    @Test("a match worse than the tolerance is not evidence of absence either")
    func weakMatchRefuses() {
        // Something is drawn there that resembles the item. Calling that "not
        // drawn" is how a translucent bar over a changed window reads as harm.
        let sighting = ItemSighting(id: "a", appearance: .asBaselined, match: .unique(x: 1020, mismatch: 0.2), placement: .consistent)
        #expect(detector().verdict(for: sighting, captureStable: true) == .unverifiable(.weakMatch))
    }

    @Test("the mismatch tolerance is inclusive at its boundary")
    func toleranceBoundaryIsInclusive() {
        let sighting = ItemSighting(id: "a", appearance: .asBaselined, match: .unique(x: 1020, mismatch: 0.05), placement: .consistent)
        #expect(detector().verdict(for: sighting, captureStable: true) == .drawn(x: 1020))
    }

    // MARK: - Hiding, which needs more than one item's verdict

    @Test("an item is hidden only when it is not drawn and the capture could see it")
    func hiddenNeedsANotDrawnVerdict() {
        let reading = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .absent(bestMismatch: 0.4), placement: .consistent)],
            fold: .absent,
            foldAtBaseline: .absent,
            captureStable: true
        )
        #expect(detector().hiding(of: "target", in: reading) == .hidden(folded: false))
    }

    @Test("an item that is still drawn is not hidden, whatever the fold says")
    func stillDrawnIsNotHidden() {
        let reading = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .unique(x: 1020, mismatch: 0.01), placement: .consistent)],
            fold: .present,
            foldAtBaseline: .absent,
            captureStable: true
        )
        #expect(detector().hiding(of: "target", in: reading) == .stillDrawn)
    }

    @Test("a fold raised beside a hidden item is reported with it")
    func foldIsReportedAlongsideHiding() {
        // Squeeze-out hiding *is* the system fold, so which of the two happened
        // is the difference between the paths, not a detail.
        let reading = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .absent(bestMismatch: 0.4), placement: .consistent)],
            fold: .present,
            foldAtBaseline: .absent,
            captureStable: true
        )
        #expect(detector().hiding(of: "target", in: reading) == .hidden(folded: true))
    }

    @Test("an unreadable fold makes the hiding unverifiable even when the item is gone")
    func unknownFoldRefuses() {
        let reading = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .absent(bestMismatch: 0.4), placement: .consistent)],
            fold: .unreadable,
            foldAtBaseline: .absent,
            captureStable: true
        )
        #expect(detector().hiding(of: "target", in: reading) == .unverifiable(.foldUnreadable))
    }

    @Test("an item the reading never mentions is unverifiable, not hidden")
    func unknownItemRefuses() {
        // The most dangerous failure the detector can have: an item nobody
        // looked for reading as successfully hidden.
        let reading = StripReading(sightings: [], fold: .absent, foldAtBaseline: .absent, captureStable: true)
        #expect(detector().hiding(of: "target", in: reading) == .unverifiable(.notObserved))
    }

    // MARK: - Putting it back

    @Test("an item drawn again after release is restored")
    func drawnAgainIsRestored() {
        let after = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .unique(x: 1020, mismatch: 0.01), placement: .consistent)],
            fold: .absent,
            foldAtBaseline: .absent,
            captureStable: true
        )
        #expect(detector().restoration(of: "target", in: after) == .restored(x: 1020))
    }

    @Test("an item still missing after release is not restored")
    func stillMissingIsNotRestored() {
        let after = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .absent(bestMismatch: 0.4), placement: .consistent)],
            fold: .absent,
            foldAtBaseline: .absent,
            captureStable: true
        )
        #expect(detector().restoration(of: "target", in: after) == .notRestored)
    }

    @Test("release is never reported as restored on evidence that cannot decide")
    func restorationFailsClosed() {
        // The dangerous direction: an unverifiable capture read as "put back".
        let unstable = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .unique(x: 1020, mismatch: 0.01), placement: .consistent)],
            fold: .absent,
            foldAtBaseline: .absent,
            captureStable: false
        )
        #expect(detector().restoration(of: "target", in: unstable) == .unverifiable(.captureUnstable))

        let unseen = StripReading(sightings: [], fold: .absent, foldAtBaseline: .absent, captureStable: true)
        #expect(detector().restoration(of: "target", in: unseen) == .unverifiable(.notObserved))

        let changed = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .changedSinceBaseline, match: .absent(bestMismatch: 0.5), placement: .consistent)],
            fold: .absent,
            foldAtBaseline: .absent,
            captureStable: true
        )
        #expect(detector().restoration(of: "target", in: changed) == .unverifiable(.appearanceChanged))
    }

    // MARK: - What the item's own Accessibility frame is allowed to do

    @Test("a strong match whose item is parked elsewhere is not drawn, it is unverifiable")
    func placementVetoesAStrongMatch() {
        // Residual A: a window under the translucent bar can reproduce a glyph.
        // The item's own frame is the independent evidence against that.
        let sighting = ItemSighting(id: "a", appearance: .asBaselined, match: .unique(x: 1020, mismatch: 0.0), placement: .inconsistent)
        #expect(detector().verdict(for: sighting, captureStable: true) == .unverifiable(.contradictsAccessibility))
    }

    @Test("a strong match with no frame read for the item is unverifiable, never drawn")
    func unavailablePlacementVetoes() {
        let sighting = ItemSighting(id: "a", appearance: .asBaselined, match: .unique(x: 1020, mismatch: 0.0), placement: .unavailable)
        #expect(detector().verdict(for: sighting, captureStable: true) == .unverifiable(.contradictsAccessibility))
    }

    @Test("absence never consults Accessibility: it lays out items the screen does not draw")
    func absenceIgnoresPlacement() {
        for placement in [Placement.consistent, .inconsistent, .unavailable] {
            let sighting = ItemSighting(id: "a", appearance: .asBaselined, match: .absent(bestMismatch: 0.4), placement: placement)
            #expect(detector().verdict(for: sighting, captureStable: true) == .notDrawn)
        }
    }

    @Test("a weak match stays weak whatever the frame says")
    func placementDoesNotRescueAWeakMatch() {
        let sighting = ItemSighting(id: "a", appearance: .asBaselined, match: .unique(x: 1020, mismatch: 0.2), placement: .consistent)
        #expect(detector().verdict(for: sighting, captureStable: true) == .unverifiable(.weakMatch))
    }

    // MARK: - The fold before the action

    @Test("an item that vanished while the fold was already up is unverifiable")
    func foldAlreadyUpRefuses() {
        let reading = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .absent(bestMismatch: 0.4), placement: .consistent)],
            fold: .present,
            foldAtBaseline: .present,
            captureStable: true
        )
        #expect(detector().hiding(of: "target", in: reading) == .unverifiable(.foldAlreadyUp))
    }

    @Test("an unreadable fold at the baseline refuses too")
    func foldUnreadableAtBaselineRefuses() {
        let reading = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .absent(bestMismatch: 0.4), placement: .consistent)],
            fold: .absent,
            foldAtBaseline: .unreadable,
            captureStable: true
        )
        #expect(detector().hiding(of: "target", in: reading) == .unverifiable(.foldUnreadable))
    }

    @Test("the baseline fold does not change a verdict of still drawn")
    func baselineFoldIrrelevantWhenStillDrawn() {
        let reading = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .unique(x: 1020, mismatch: 0.01), placement: .consistent)],
            fold: .present,
            foldAtBaseline: .present,
            captureStable: true
        )
        #expect(detector().hiding(of: "target", in: reading) == .stillDrawn)
    }

    @Test("an unstable capture cannot report hiding")
    func unstableCaptureCannotReportHiding() {
        let reading = StripReading(
            sightings: [ItemSighting(id: "target", appearance: .asBaselined, match: .absent(bestMismatch: 0.4), placement: .consistent)],
            fold: .absent,
            foldAtBaseline: .absent,
            captureStable: false
        )
        #expect(detector().hiding(of: "target", in: reading) == .unverifiable(.captureUnstable))
    }
}
