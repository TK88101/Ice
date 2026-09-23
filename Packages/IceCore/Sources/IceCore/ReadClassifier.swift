/// Turns one process's raw AX read into a verdict the rest of IceCore can act
/// on, following plan section 4.1.2's table exactly.
///
/// The table exists because `cannotComplete` is not one fact: the 2026-09-23
/// census found 49 of them, every one under 50 ms -- an immediate refusal,
/// not a stalled call -- so classifying every `cannotComplete` as a failure
/// would misreport 49 ordinary processes as broken. Duration is what tells
/// the two apart, which is why `RawRead` carries elapsed time alongside every
/// error.
///
/// The three outcomes matter because they are not interchangeable:
/// `.none` says a process genuinely has nothing to report (no extras bar, no
/// children, or it declined to answer); `.failed` says the read could not be
/// trusted and must not be read as "no items", because a hung or refusing
/// process would then look identical to one with nothing on the bar at all.
public enum ReadOutcome: Equatable, Sendable {
    /// The children read succeeded (or answered `noValue`) and every child's
    /// role, identifier, and frame came back clean. May be empty.
    case items([ExtrasRecord])
    /// Nothing to report, and why.
    case none(NoneReason)
    /// The read could not be trusted.
    case failed(FailureReason)
}

/// Why a process reported nothing, distinguished because each implies a
/// different next step for a caller (retry, skip, or ask the user to grant
/// Accessibility).
public enum NoneReason: Equatable, Sendable {
    /// `AXExtrasMenuBar` is `noValue` or `attributeUnsupported`: this process
    /// simply does not have one.
    case noExtrasBar
    /// A fast `cannotComplete` on the extras bar: the process answered
    /// quickly by refusing, rather than by timing out.
    case declinesAccessibility
    /// `invalidUIElement`: the element reference no longer resolves, most
    /// likely because the process quit between being enumerated and being
    /// read.
    case processGone
    /// `apiDisabled` on this call. Whole-system trust is `permissionDenied`,
    /// decided separately from `AXIsProcessTrusted()` and handed to the
    /// catalog (plan section 4.1.2) -- this case is what one call itself
    /// reported.
    case apiDisabled
}

/// Why a read could not be trusted.
public enum FailureReason: Equatable, Sendable {
    /// The named call took at least `ReadClassifier.slowFraction` of the
    /// timeout before reporting `cannotComplete` -- long enough that it read
    /// as an actual stall, not a quick refusal.
    case timedOut(call: String)
    /// The named call reported an `AXError` this table does not otherwise
    /// account for.
    case unexpectedError(call: String, error: String)
}

/// The pure function behind plan section 4.1.2's table.
public enum ReadClassifier {
    /// Per-call messaging timeout (plan section 4.2; matches
    /// `LiveMenuBarAXReader.messagingTimeout` and `swctl`'s `AXReader`).
    public static let defaultTimeout: Double = 0.25
    /// A `cannotComplete` at or above this fraction of the timeout is treated
    /// as a stall rather than a quick refusal.
    public static let slowFraction: Double = 0.8

    /// The attribute errors that never fail a per-child attribute read
    /// (`role`, `identifier`, `frame`): the attribute simply was not there,
    /// or this process does not support it. Everything else -- including
    /// `cannotComplete`, which for a single attribute carries no elapsed time
    /// to judge fast from slow -- fails the whole read (plan 4.1.2, row 3).
    private static let harmlessAttributeErrors: Set<String> = ["success", "noValue", "attributeUnsupported"]

    public static func outcome(_ raw: RawRead, timeout: Double = defaultTimeout) -> ReadOutcome {
        let slowThreshold = timeout * slowFraction

        switch raw.extrasError {
        case "success":
            break
        case "noValue", "attributeUnsupported":
            return .none(.noExtrasBar)
        case "invalidUIElement":
            return .none(.processGone)
        case "apiDisabled":
            return .none(.apiDisabled)
        case "cannotComplete":
            return raw.extrasElapsed >= slowThreshold
                ? .failed(.timedOut(call: "extrasBar"))
                : .none(.declinesAccessibility)
        default:
            return .failed(.unexpectedError(call: "extrasBar", error: raw.extrasError))
        }

        switch raw.childrenError {
        case "success", "noValue":
            break
        case "cannotComplete":
            let elapsed = raw.childrenElapsed ?? 0
            return elapsed >= slowThreshold
                ? .failed(.timedOut(call: "children"))
                : .items([])
        case let other?:
            return .failed(.unexpectedError(call: "children", error: other))
        case nil:
            // Contract violation by the caller: extras succeeded, so a
            // children read must have been attempted. Fail rather than guess.
            return .failed(.unexpectedError(call: "children", error: "missing"))
        }

        for record in raw.records {
            if let reason = attributeFailure(call: "role", read: record.role) { return .failed(reason) }
            if let reason = attributeFailure(call: "identifier", read: record.identifier) { return .failed(reason) }
            if let reason = attributeFailure(call: "frame", read: record.frame) { return .failed(reason) }
        }

        return .items(raw.records)
    }

    /// Shared by `role`/`identifier` (`AttributeRead<String>`) and `frame`
    /// (`AttributeRead<BarRect>`): only the error name decides, never the
    /// value's type.
    private static func attributeFailure<Value>(call: String, read: AttributeRead<Value>) -> FailureReason? {
        guard harmlessAttributeErrors.contains(read.error) else {
            return .unexpectedError(call: call, error: read.error)
        }
        return nil
    }
}
