import Testing
@testable import IceCore

/// Pins the one rule that decides whether a child's attribute read lets the
/// walk go on (2026-09-25 plan, axis A2 -- vector K1).
///
/// The rule lives here, in a pure function, rather than inline in the live
/// reader, for one reason the plan states outright: `AttributeRead` carries no
/// duration, so a rule that depends on how long a call took cannot live in
/// `ReadClassifier`, which only ever sees the recorded error. It has to be
/// decided where the clock is -- and if it is decided there, it has to be
/// testable there, which means a seam.
///
/// The tolerated case is exactly one attribute and one error, and only when it
/// was fast: MEASURED 2026-09-25, one third-party process answers `AXIdentifier`
/// with `kAXErrorFailure` immediately and answers `AXFrame` correctly, so the
/// frame the old walk never asked for was readable all along.
@Suite("AttributeWalkPolicy")
struct AttributeWalkPolicyTests {
    private let timeout = ReadClassifier.defaultTimeout
    private var slowThreshold: Double { timeout * ReadClassifier.slowFraction }

    // MARK: - the tolerated case, and how narrow it is

    @Test("a fast identifier failure lets the walk go on, keeping what the call returned")
    func fastIdentifierFailureProceeds() {
        let verdict = AttributeWalkPolicy.classify(attribute: "identifier", rawError: "failure", elapsed: 0.001, timeout: timeout)
        #expect(verdict == AttributeVerdict(recordedError: "failure", value: .keep, decision: .proceed))
    }

    @Test("the same identifier failure taken slowly stops the walk")
    func slowIdentifierFailureStops() {
        let verdict = AttributeWalkPolicy.classify(attribute: "identifier", rawError: "failure", elapsed: 0.24, timeout: timeout)
        #expect(verdict.decision == .stopWalk)
    }

    @Test("only `failure` is tolerated on the identifier -- every other hard error still stops")
    func otherIdentifierErrorsStop() {
        for error in ["invalidUIElement", "apiDisabled", "cannotComplete", "notImplemented"] {
            let verdict = AttributeWalkPolicy.classify(attribute: "identifier", rawError: error, elapsed: 0.001, timeout: timeout)
            #expect(verdict.decision == .stopWalk, "\(error) must stop the walk")
        }
    }

    @Test("the tolerated error is tolerated on the identifier only, never on role or frame")
    func failureElsewhereStops() {
        for attribute in ["role", "frame", "title", "description", "help"] {
            let verdict = AttributeWalkPolicy.classify(attribute: attribute, rawError: "failure", elapsed: 0.001, timeout: timeout)
            #expect(verdict.decision == .stopWalk, "a failure on \(attribute) must stop the walk")
        }
    }

    // MARK: - the harmless errors, unchanged

    @Test("the harmless errors let the walk go on, whatever the attribute")
    func harmlessErrorsProceed() {
        for attribute in ["role", "identifier", "frame"] {
            for error in ["success", "noValue", "attributeUnsupported"] {
                let verdict = AttributeWalkPolicy.classify(attribute: attribute, rawError: error, elapsed: 0.001, timeout: timeout)
                #expect(verdict == AttributeVerdict(recordedError: error, value: .keep, decision: .proceed))
            }
        }
    }

    // MARK: - the slow-success normalization, moved here from the adapter

    @Test("a successful call at the threshold becomes cannotComplete, drops its value, and stops")
    func slowSuccessAtThresholdNormalizes() {
        let verdict = AttributeWalkPolicy.classify(attribute: "role", rawError: "success", elapsed: slowThreshold, timeout: timeout)
        #expect(verdict == AttributeVerdict(recordedError: "cannotComplete", value: .discard, decision: .stopWalk))
    }

    @Test("a successful call just under the threshold stays a success and keeps its value")
    func successJustUnderThresholdIsFast() {
        let verdict = AttributeWalkPolicy.classify(attribute: "role", rawError: "success", elapsed: slowThreshold - 0.000_001, timeout: timeout)
        #expect(verdict == AttributeVerdict(recordedError: "success", value: .keep, decision: .proceed))
    }

    @Test("the normalization applies to every attribute, the frame included")
    func slowSuccessNormalizesForEveryAttribute() {
        // The frame is the one attribute whose value is not a String, and the
        // discard has to reach it too or a slow frame read would keep a
        // `BarRect` beside `cannotComplete`.
        for attribute in ["role", "identifier", "frame", "title"] {
            let verdict = AttributeWalkPolicy.classify(attribute: attribute, rawError: "success", elapsed: 0.25, timeout: timeout)
            #expect(verdict == AttributeVerdict(recordedError: "cannotComplete", value: .discard, decision: .stopWalk))
        }
    }

    @Test("a hard error keeps whatever the call returned -- only the slow-success case discards")
    func hardErrorsKeepTheirValue() {
        let verdict = AttributeWalkPolicy.classify(attribute: "role", rawError: "invalidUIElement", elapsed: 0.001, timeout: timeout)
        #expect(verdict.value == .keep)
    }

    // MARK: - the threshold follows the timeout it is given

    @Test("the threshold is a fraction of the timeout handed in, not a constant")
    func thresholdFollowsTheTimeout() {
        // 0.8 * 0.5 = 0.4: an elapsed of 0.3 is fast against a 0.5 s timeout and
        // slow against the 0.25 s default.
        let againstHalfSecond = AttributeWalkPolicy.classify(attribute: "role", rawError: "success", elapsed: 0.3, timeout: 0.5)
        #expect(againstHalfSecond.decision == .proceed)
        let againstDefault = AttributeWalkPolicy.classify(attribute: "role", rawError: "success", elapsed: 0.3, timeout: 0.25)
        #expect(againstDefault.decision == .stopWalk)
    }
}
