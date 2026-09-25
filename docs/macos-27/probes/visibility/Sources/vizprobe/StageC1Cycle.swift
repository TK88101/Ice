// I5: section 3's own preflight and section 5 step 2's one cycle (jump,
// settle, verdicts, collapse, settle, restored?, reset check) -- shared by
// the scan (one cycle per length) and the smoke (five cycles at the
// midpoint).
import C1Core
import C1Live
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDetectorFeed

struct C1CycleResult {
    let reading: TargetReading
    /// Fold absent at the expansion, Protected and every templated owner
    /// item drawn, no unexplained residual-strip change (never set true --
    /// see the worker report), and Target `restored` after the collapse:
    /// section 1's PASS list besides the reading itself.
    let otherChecksPassed: Bool
}

extension StageC1 {
    /// One full cycle: preflight -> jump -> settle -> read -> collapse ->
    /// settle -> restored? -> reset check. `nil` when the preflight never
    /// passes (the caller records INCONCLUSIVE) or a capture goes
    /// unreadable.
    func runCycle(length: Double, label: String) -> C1CycleResult? {
        guard performPreflight(label: label) else {
            capturesStayedUnreadable = capturesStayedUnreadable || !preflightEverPassed
            return nil
        }
        preflightEverPassed = true

        expansionDriver.expand(to: length)
        Pump.run(1.0)
        guard let hiddenReading = readTarget(label: "\(label).hidden") else { return nil }
        // The fold is allowed to go up here -- an expansion is in progress
        // by definition (section 4's "while no expansion is in progress"
        // exclusion) -- so this read only feeds the PASS-list bookkeeping,
        // never the latch.
        let foldAbsentAtExpansion = readFold(label: "\(label).fold") == .absent

        expansionDriver.collapse()
        Pump.run(1.0)
        guard let restoredCheck = verifyOnce() else { return nil }
        let restored = classify(restoredCheck[targetKey!], expected: .stillDrawn) == .expected

        let resetOK = performResetCheck(label: "\(label).reset")
        if !resetOK { safetyStop = safetyStop ?? .stop }

        let protectedAndOwnersDrawn = readOwnerAndProtectedDrawn(label: "\(label).drawn")
        let otherChecksPassed = foldAbsentAtExpansion && protectedAndOwnersDrawn && restored && resetOK
        evidence.record("cycle", ["label": label, "reading": "\(hiddenReading)", "otherChecksPassed": otherChecksPassed])
        return C1CycleResult(reading: hiddenReading, otherChecksPassed: otherChecksPassed)
    }

    /// Reads Target's own `Hiding` through the C1-discoverer-backed
    /// verification (I4), mapped to C1Core's `TargetReading`.
    private func readTarget(label: String) -> TargetReading? {
        guard let results = verifyOnce(), let targetKey else { return nil }
        guard case .checked(let hiding)? = results[targetKey] else { return .refused }
        switch hiding {
        case .hidden(let folded): return .hidden(folded: folded)
        case .stillDrawn: return .stillDrawn
        case .unverifiable: return .refused
        }
    }

    private func verifyOnce() -> [ItemKey: SectionItemCheck]? {
        guard let prepared else { return nil }
        return Pump.blocking { await self.verification.verify(prepared) }
    }

    private func classify(_ check: SectionItemCheck?, expected: Hiding) -> CheckOutcome {
        if case .checked(let hiding)? = check, hiding == expected { return .expected }
        return .unexpected
    }

    private enum CheckOutcome { case expected, unexpected }

    /// The fold, read through the owner observer (section 3 condition 2,
    /// section 4's "the fold appearing").
    private func readFold(label: String) -> Fold? {
        guard let ids = ownerObserverIDs(), let result = ownerObserver.observe(baseline: ownerBaseline, targets: [], references: Array(ids.keys), items: ids) else {
            latchingCapturer.feed(.init(captureFailed: true))
            return nil
        }
        return result.reading.fold
    }

    private func ownerObserverIDs() -> [String: pid_t]? {
        ownerItemIDs.isEmpty ? nil : ownerItemIDs
    }

    /// Section 3: order (AX vs pixels, Target then the spacer leftmost),
    /// `.protected`/templated items drawn and the fold absent, the
    /// indicator unmoved, and the roster equalling the snapshot. Up to 3
    /// attempts within 10 s; a first-ever failure relaunches the helpers
    /// once (section 3), after which a second failure is final.
    func performPreflight(label: String) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        var attempt = 0
        while attempt < 3, Date() < deadline {
            attempt += 1
            if passesPreflightOnce(label: "\(label).\(attempt)") { return true }
        }
        guard !preflightEverPassed else { return false }
        // The very first preflight: relaunch once (section 3).
        evidence.record("preflight.relaunchOnce", ["label": label])
        _ = reapAll()
        guard case .ok = step2Launch(), case .ok = step3Baseline() else { return false }
        for retryAttempt in 1...3 {
            if passesPreflightOnce(label: "\(label).relaunch.\(retryAttempt)") { return true }
        }
        return false
    }

    private func passesPreflightOnce(label: String) -> Bool {
        guard let targetKey, let spacerKey else { return false }
        guard let discovery = Pump.blocking({ await self.discoverer.discover(previous: nil) }) else { return false }
        let axOrder = discovery.set.listedItems
            .filter { $0.frame != nil }
            .sorted { $0.frame!.minX < $1.frame!.minX }
            .map(\.key.encoded)

        guard let capture = capturer.capture(), let ink = ownerBaseline.ink else { return false }
        let map = ink.map(capture)
        let pixelOrder = ownerBaseline.templates.compactMap { id, template -> (String, Double)? in
            guard case .unique(let x, let mismatch) = TemplateMatcher.match(template, in: map, geometry: geometry, parameters: parameters),
                  mismatch <= parameters.maxMismatch else { return nil }
            return (id, x)
        }.sorted { $0.1 < $1.1 }.map(\.0)

        guard PreflightOrderCheck.check(axOrder: axOrder, pixelOrder: pixelOrder, target: targetKey.encoded, spacer: spacerKey.encoded) == nil else {
            evidence.record("preflight.orderFailed", ["label": label, "ax": axOrder, "pixel": pixelOrder])
            return false
        }
        guard readOwnerAndProtectedDrawn(label: "\(label).drawn"), readFold(label: "\(label).fold") == .absent else { return false }

        let indicator = detectIndicatorFrame()
        guard indicator == baselineIndicatorFrame else {
            evidence.record("preflight.indicatorMoved", ["label": label])
            return false
        }

        let snapshot = RosterSnapshot(items: axOrder, indicatorFrame: indicator)
        guard RosterSnapshotCheck.compare(current: snapshot, previous: rosterSnapshot) == .equal else {
            evidence.record("preflight.rosterChanged", ["label": label])
            return false
        }
        return true
    }

    /// Section 5's reset check: baseline-equivalent, including the three
    /// helpers. A mismatch is a safety stop; a pass resets the latch and
    /// takes a fresh roster snapshot (section 3: "recorded at the end of
    /// the previous passing reset check").
    func performResetCheck(label: String) -> Bool {
        guard targetKey != nil, spacerKey != nil, protectedKey != nil else { return false }
        guard let capture = capturer.capture(), let ink = ownerBaseline.ink else { return false }
        let map = ink.map(capture)

        func x(_ id: String) -> Double? {
            guard let template = ownerBaseline.templates[id],
                  case .unique(let value, let mismatch) = TemplateMatcher.match(template, in: map, geometry: geometry, parameters: parameters),
                  mismatch <= parameters.maxMismatch
            else { return nil }
            return value
        }

        let currentOwners = ownerBaselineReadings.compactMap { reading in x(reading.id).map { BaselineEquivalence.Reading(id: reading.id, x: $0) } }
        let currentHelpers = helperBaselineReadings.compactMap { reading in x(reading.id).map { BaselineEquivalence.Reading(id: reading.id, x: $0) } }
        let fold = readFold(label: "\(label).fold") ?? .unreadable

        let input = BaselineEquivalence.Input(
            templatedOwnerItems: currentOwners,
            baselineTemplatedOwnerItems: ownerBaselineReadings,
            residualStripChanged: false,
            indicatorFrame: detectIndicatorFrame(),
            baselineIndicatorFrame: baselineIndicatorFrame,
            fold: fold == .present ? .present : (fold == .absent ? .absent : .unreadable),
            helpers: currentHelpers,
            baselineHelpers: helperBaselineReadings
        )
        let failures = BaselineEquivalence.check(input)
        evidence.record("resetCheck", ["label": label, "failures": failures.map { "\($0)" }])
        guard failures.isEmpty else { return false }

        latchingCapturer.resetAfterPassingCheck()
        rosterSnapshot = RosterSnapshot(items: ownerBaseline.acceptedIDs, indicatorFrame: detectIndicatorFrame())
        return true
    }

    /// `.protected` and every templated owner item drawn (section 3
    /// condition 2 / section 1's PASS list).
    func readOwnerAndProtectedDrawn(label: String) -> Bool {
        guard let ids = ownerObserverIDs(), let protectedKey else { return false }
        let targets = ownerBaselineReadings.map(\.id) + [protectedKey.encoded]
        guard let result = ownerObserver.observe(baseline: ownerBaseline, targets: targets, references: [], items: ids) else { return false }
        return targets.allSatisfy {
            if case .drawn? = result.visibility[$0] { return true }
            return false
        }
    }
}
