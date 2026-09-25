/// Whether one attribute read lets a child walk go on, and what to record for
/// it -- the rule the live reader used to carry inline (2026-09-25 plan, axis A).
///
/// It is a pure function here for a reason the classifier cannot work around:
/// `AttributeRead` carries no duration, so `ReadClassifier` sees only the error
/// name a read ended with and can never tell a fast refusal from a stall. The
/// decision has to be made where the clock is. Making it a function rather than
/// three lines inside the adapter is what lets a test state the rule and a
/// second test state that the walk obeys it.

/// Whether the value a read returned may be recorded, or must be dropped.
public enum AttributeValueHandling: Equatable, Sendable {
    case keep
    case discard
}

/// Whether the walk may go on after this read.
public enum AttributeWalkDecision: Equatable, Sendable {
    /// Read this child's remaining attributes, and the next child.
    case proceed
    /// Stop: no more attributes of this child, no more children. The caller
    /// records `RawRead.walkInterrupted`.
    case stopWalk
}

/// One read's verdict: what to record for it, what to do with its value, and
/// whether the walk continues.
public struct AttributeVerdict: Equatable, Sendable {
    public let recordedError: String
    public let value: AttributeValueHandling
    public let decision: AttributeWalkDecision

    public init(recordedError: String, value: AttributeValueHandling, decision: AttributeWalkDecision) {
        self.recordedError = recordedError
        self.value = value
        self.decision = decision
    }
}

public enum AttributeWalkPolicy {
    /// The one attribute whose hard error may be tolerated, named so the
    /// exception cannot silently widen to another one. This is the policy's own
    /// constant rather than `ReadClassifier`'s `call:` label: there the string
    /// names a failure, here it gates behaviour.
    private static let identifierAttribute = "identifier"

    /// Which errors are harmless, and which single error `identifier` tolerates
    /// beyond them, both come from `ReadClassifier` -- the type that has to
    /// accept whatever this one reads past. Restating either here would let the
    /// walk and the verdict drift apart, and that drift is invisible to the pass
    /// invariants: the walk would simply never produce the record that would
    /// have failed.
    ///
    /// MEASURED 2026-09-25 for the tolerated error: a third-party process
    /// answers `AXIdentifier` with `kAXErrorFailure` immediately and
    /// deterministically while answering `AXFrame` correctly, so stopping the
    /// walk threw away a readable frame and every later child of that process.
    /// Everything else, and this same error taken slowly, still stops: a slow
    /// answer is a stall, and a stall is not something to read past.
    private static var harmlessErrors: Set<String> { ReadClassifier.harmlessAttributeErrors }
    private static var toleratedIdentifierError: String { ReadClassifier.toleratedIdentifierError }

    /// Judges one read from the attribute it was, the `AXError` name it ended
    /// with, how long it took, and the per-call timeout in force.
    ///
    /// A successful call that took at least `ReadClassifier.slowFraction` of
    /// the timeout is not treated as a success: it is recorded as
    /// `cannotComplete` **and its value is dropped**, because a call that slow
    /// is a stall whose result cannot be trusted. The comparison is `>=`: at
    /// exactly the threshold the call is slow.
    public static func classify(
        attribute: String,
        rawError: String,
        elapsed: Double,
        timeout: Double = ReadClassifier.defaultTimeout
    ) -> AttributeVerdict {
        let slowThreshold = timeout * ReadClassifier.slowFraction

        if rawError == "success" {
            guard elapsed < slowThreshold else {
                return AttributeVerdict(recordedError: "cannotComplete", value: .discard, decision: .stopWalk)
            }
            return AttributeVerdict(recordedError: "success", value: .keep, decision: .proceed)
        }

        if harmlessErrors.contains(rawError) {
            return AttributeVerdict(recordedError: rawError, value: .keep, decision: .proceed)
        }

        if attribute == Self.identifierAttribute, rawError == Self.toleratedIdentifierError, elapsed < slowThreshold {
            // `.discard`, not `.keep`: reading past this error is only defensible
            // because the item is then keyed as if it had no identifier at all.
            // If Accessibility ever populated the out-parameter while returning
            // the error, keeping it would key the item on a string a failed call
            // produced. Discarding makes "tolerated failure implies no
            // identifier" true by construction rather than by trust.
            return AttributeVerdict(recordedError: rawError, value: .discard, decision: .proceed)
        }

        return AttributeVerdict(recordedError: rawError, value: .keep, decision: .stopWalk)
    }
}
