import Testing
@testable import IceCore

/// Pins every row of plan section 4.1.2: what one process's raw AX read is
/// allowed to become. The distinction that matters most is between `.none`
/// (this process genuinely has nothing to report) and `.failed` (the read
/// could not be trusted) -- a failed read must never be silently folded into
/// "no items", or a hung or refusing process would look identical to one that
/// simply has no extras.
@Suite("ReadClassifier")
struct ReadClassifierTests {
    // MARK: - extras bar: the four errors that mean "nothing here"

    @Test("no value for the extras bar means the process has none")
    func extrasBarNoValue() {
        #expect(ReadClassifier.outcome(rawRead(extrasError: "noValue")) == .none(.noExtrasBar))
    }

    @Test("an unsupported extras-bar attribute also means the process has none")
    func extrasBarAttributeUnsupported() {
        #expect(ReadClassifier.outcome(rawRead(extrasError: "attributeUnsupported")) == .none(.noExtrasBar))
    }

    @Test("an invalid element means the process is gone")
    func extrasBarInvalidElement() {
        #expect(ReadClassifier.outcome(rawRead(extrasError: "invalidUIElement")) == .none(.processGone))
    }

    @Test("apiDisabled on the extras bar is reported as such, distinct from the other three")
    func extrasBarAPIDisabled() {
        #expect(ReadClassifier.outcome(rawRead(extrasError: "apiDisabled")) == .none(.apiDisabled))
    }

    // MARK: - extras bar: cannotComplete, which depends on how long it took

    @Test("a fast cannotComplete on the extras bar is a decline, not a timeout")
    func extrasBarCannotCompleteFastDeclines() {
        // MEASURED 2026-09-23: every cannotComplete in the census landed under
        // 50 ms -- the plan calls this an immediate refusal, not a timeout.
        let raw = rawRead(extrasError: "cannotComplete", extrasElapsed: 0.05)
        #expect(ReadClassifier.outcome(raw) == .none(.declinesAccessibility))
    }

    @Test("a slow cannotComplete on the extras bar is a failure")
    func extrasBarCannotCompleteSlowFails() {
        let raw = rawRead(extrasError: "cannotComplete", extrasElapsed: 0.24)
        #expect(ReadClassifier.outcome(raw) == .failed(.timedOut(call: "extrasBar")))
    }

    @Test("an unclassified extras-bar error falls to failed")
    func extrasBarUnknownErrorFails() {
        let raw = rawRead(extrasError: "failure")
        #expect(ReadClassifier.outcome(raw) == .failed(.unexpectedError(call: "extrasBar", error: "failure")))
    }

    // MARK: - the fast / slow boundary, exactly as measured

    @Test("elapsed just under 80% of the timeout is fast")
    func boundaryJustUnderIsFast() {
        let raw = rawRead(extrasError: "cannotComplete", extrasElapsed: 0.199)
        #expect(ReadClassifier.outcome(raw, timeout: 0.25) == .none(.declinesAccessibility))
    }

    @Test("elapsed at 80% of the timeout is slow")
    func boundaryAtThresholdIsSlow() {
        let raw = rawRead(extrasError: "cannotComplete", extrasElapsed: 0.200)
        #expect(ReadClassifier.outcome(raw, timeout: 0.25) == .failed(.timedOut(call: "extrasBar")))
    }

    @Test("the published defaults match the plan's timeout and slow fraction")
    func publishedDefaultsMatchThePlan() {
        #expect(ReadClassifier.defaultTimeout == 0.25)
        #expect(ReadClassifier.slowFraction == 0.8)
    }

    // MARK: - children

    @Test("a successful children read returns its records, whatever their count")
    func childrenSuccessReturnsRecords() {
        let records = [goodRecord(childIndex: 0), goodRecord(childIndex: 1)]
        let raw = rawRead(childrenError: "success", records: records)
        #expect(ReadClassifier.outcome(raw) == .items(records))
    }

    @Test("a successful children read with zero records is an empty item list, not none")
    func childrenSuccessZeroRecords() {
        let raw = rawRead(childrenError: "success", records: [])
        #expect(ReadClassifier.outcome(raw) == .items([]))
    }

    @Test("noValue for children is an empty item list")
    func childrenNoValue() {
        let raw = rawRead(childrenError: "noValue", records: [])
        #expect(ReadClassifier.outcome(raw) == .items([]))
    }

    @Test("a fast cannotComplete on children reads as an empty item list")
    func childrenCannotCompleteFast() {
        let raw = rawRead(childrenError: "cannotComplete", childrenElapsed: 0.05)
        #expect(ReadClassifier.outcome(raw) == .items([]))
    }

    @Test("a slow cannotComplete on children is a failure")
    func childrenCannotCompleteSlow() {
        let raw = rawRead(childrenError: "cannotComplete", childrenElapsed: 0.24)
        #expect(ReadClassifier.outcome(raw) == .failed(.timedOut(call: "children")))
    }

    @Test("an unclassified children error falls to failed")
    func childrenUnknownErrorFails() {
        let raw = rawRead(childrenError: "attributeUnsupported")
        #expect(ReadClassifier.outcome(raw) == .failed(.unexpectedError(call: "children", error: "attributeUnsupported")))
    }

    @Test("a missing children read after a successful extras-bar read is a contract violation, not a guess")
    func missingChildrenReadFails() {
        let raw = rawRead(extrasError: "success", childrenError: nil, childrenElapsed: nil)
        #expect(ReadClassifier.outcome(raw) == .failed(.unexpectedError(call: "children", error: "missing")))
    }

    // MARK: - per-child role, identifier, frame

    @Test("a failed child role, other than noValue or attributeUnsupported, fails the whole read")
    func childRoleFailureFails() {
        let bad = ExtrasRecord(childIndex: 0, role: attr(error: "cannotComplete"), identifier: ok("x"), title: ok(), description: ok(), help: ok(), frame: okFrame())
        #expect(ReadClassifier.outcome(rawRead(records: [bad])) == .failed(.unexpectedError(call: "role", error: "cannotComplete")))
    }

    @Test("a failed child identifier, other than noValue or attributeUnsupported, fails the whole read")
    func childIdentifierFailureFails() {
        let bad = ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: attr(error: "invalidUIElement"), title: ok(), description: ok(), help: ok(), frame: okFrame())
        #expect(ReadClassifier.outcome(rawRead(records: [bad])) == .failed(.unexpectedError(call: "identifier", error: "invalidUIElement")))
    }

    @Test("a failed child frame, other than noValue or attributeUnsupported, fails the whole read")
    func childFrameFailureFails() {
        let bad = ExtrasRecord(childIndex: 0, role: ok("AXMenuBarItem"), identifier: ok("x"), title: ok(), description: ok(), help: ok(), frame: frameErr("apiDisabled"))
        #expect(ReadClassifier.outcome(rawRead(records: [bad])) == .failed(.unexpectedError(call: "frame", error: "apiDisabled")))
    }

    @Test("noValue or attributeUnsupported on role, identifier, or frame do not fail the read")
    func childAttributeNoValueOrUnsupportedDoesNotFail() {
        let record = ExtrasRecord(
            childIndex: 0,
            role: attr(error: "noValue"),
            identifier: attr(error: "attributeUnsupported"),
            title: ok(),
            description: ok(),
            help: ok(),
            frame: frameErr("noValue")
        )
        #expect(ReadClassifier.outcome(rawRead(records: [record])) == .items([record]))
    }

    @Test("title, description, and help errors never fail the read -- only role, identifier, and frame do")
    func titleDescriptionHelpErrorsDoNotFail() {
        let record = ExtrasRecord(
            childIndex: 0,
            role: ok("AXMenuBarItem"),
            identifier: ok("x"),
            title: attr(error: "cannotComplete"),
            description: attr(error: "apiDisabled"),
            help: attr(error: "invalidUIElement"),
            frame: okFrame()
        )
        #expect(ReadClassifier.outcome(rawRead(records: [record])) == .items([record]))
    }

    @Test("the first failing child stops the read; a good child earlier does not save it")
    func oneBadChildFailsTheWholeRead() {
        let good = goodRecord(childIndex: 0)
        let bad = ExtrasRecord(childIndex: 1, role: ok("AXMenuBarItem"), identifier: attr(error: "cannotComplete"), title: ok(), description: ok(), help: ok(), frame: okFrame())
        #expect(ReadClassifier.outcome(rawRead(records: [good, bad])) == .failed(.unexpectedError(call: "identifier", error: "cannotComplete")))
    }
}

// MARK: - Fixtures

private func ok(_ value: String = "") -> AttributeRead<String> {
    AttributeRead(value: value, error: "success")
}

private func attr(error: String, value: String? = nil) -> AttributeRead<String> {
    AttributeRead(value: value, error: error)
}

private func okFrame(_ value: BarRect = BarRect(minX: 0, minY: 0, width: 10, height: 10)) -> AttributeRead<BarRect> {
    AttributeRead(value: value, error: "success")
}

private func frameErr(_ error: String) -> AttributeRead<BarRect> {
    AttributeRead(value: nil, error: error)
}

private func goodRecord(childIndex: Int) -> ExtrasRecord {
    ExtrasRecord(childIndex: childIndex, role: ok("AXMenuBarItem"), identifier: ok("x"), title: ok(), description: ok(), help: ok(), frame: okFrame())
}

private func testProcess() -> ProcessInfoRecord {
    ProcessInfoRecord(pid: 100, bundleID: "com.example.a", localizedName: nil, executableName: nil, launchTime: nil, isSelf: false)
}

private func rawRead(
    extrasError: String = "success",
    extrasElapsed: Double = 0.01,
    childrenError: String? = "success",
    childrenElapsed: Double? = 0.01,
    records: [ExtrasRecord] = []
) -> RawRead {
    RawRead(process: testProcess(), extrasError: extrasError, extrasElapsed: extrasElapsed, childrenError: childrenError, childrenElapsed: childrenElapsed, records: records)
}
