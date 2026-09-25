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
    /// The walk policy stopped this process's walk (`RawRead.walkInterrupted`).
    /// Kept separate from `unexpectedError` because the record that triggered
    /// the stop may itself look clean now that one attribute error is
    /// tolerated: the stop is the fact, not the attribute.
    case walkInterrupted
    /// The children read succeeded and the walk was not stopped, yet the
    /// records produced do not match the snapshot the walk was handed -- a
    /// malformed read, which must not be mistaken for a process with fewer
    /// items.
    case partialWalk(childCount: Int, records: Int)
}

/// The pure function behind plan section 4.1.2's table.
public enum ReadClassifier {
    /// Per-call messaging timeout (plan section 4.2; matches
    /// `LiveMenuBarAXReader.messagingTimeout` and `swctl`'s `AXReader`).
    public static let defaultTimeout: Double = 0.25
    /// A `cannotComplete` at or above this fraction of the timeout is treated
    /// as a stall rather than a quick refusal.
    public static let slowFraction: Double = 0.8
    /// The call names `FailureReason` carries for the extras-bar and the
    /// children reads -- one spelling, shared with `ResponsivenessQuarantine`,
    /// whose only trigger is `.timedOut(call: extrasBarCall)` (hardening plan H7).
    public static let extrasBarCall = "extrasBar"
    public static let childrenCall = "children"

    /// The attribute errors that never fail a per-child attribute read
    /// (`role`, `identifier`, `frame`): the attribute simply was not there,
    /// or this process does not support it. Everything else -- including
    /// `cannotComplete`, which for a single attribute carries no elapsed time
    /// to judge fast from slow -- fails the whole read (plan 4.1.2, row 3).
    ///
    /// Not `private`: `AttributeWalkPolicy` answers the same question one layer
    /// earlier, at walk time, and the two must never disagree -- a walk that
    /// read past an error this type then failed, or the reverse, is drift no
    /// pass invariant can catch, because the walk simply never produces the
    /// record that would have failed. One definition, read from both.
    static let harmlessAttributeErrors: Set<String> = ["success", "noValue", "attributeUnsupported"]

    /// The one hard error `identifier` tolerates that the other two do not:
    /// `failure` (`kAXErrorFailure`). MEASURED 2026-09-25 -- a third-party
    /// process answers `AXIdentifier` with it immediately and deterministically
    /// while answering `AXFrame` correctly, and failing the whole process for it
    /// cost that item its place in the list entirely and made every pass
    /// incomplete. Whether the error was fast enough to be read past is not
    /// decided here, because `AttributeRead` carries no duration:
    /// `AttributeWalkPolicy` decides that where the clock is, and a stop it made
    /// arrives here as `RawRead.walkInterrupted` instead. Shared with the policy
    /// for the same reason the set above is.
    static let toleratedIdentifierError = "failure"

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
                ? .failed(.timedOut(call: extrasBarCall))
                : .none(.declinesAccessibility)
        default:
            return .failed(.unexpectedError(call: extrasBarCall, error: raw.extrasError))
        }

        switch raw.childrenError {
        case "success", "noValue":
            break
        case "cannotComplete":
            let elapsed = raw.childrenElapsed ?? 0
            return elapsed >= slowThreshold
                ? .failed(.timedOut(call: childrenCall))
                : .items([])
        case let other?:
            return .failed(.unexpectedError(call: childrenCall, error: other))
        case nil:
            // Contract violation by the caller: extras succeeded, so a
            // children read must have been attempted. Fail rather than guess.
            return .failed(.unexpectedError(call: childrenCall, error: "missing"))
        }

        // What the walk did, before what it produced. A stop is checked first
        // because it is the more specific fact: an interrupted walk usually
        // also leaves the records short, and "the policy stopped" is the
        // cause, while a count mismatch would only be its symptom.
        if raw.walkInterrupted {
            return .failed(.walkInterrupted)
        }
        // Reached only when the children read succeeded (every other path has
        // returned above), so a snapshot existed and the records must account
        // for all of it: a walk that lost children for any reason other than a
        // policy stop would otherwise read as a process with fewer items.
        //
        // Honest about what these two checks are worth *today*: under the
        // current policy they are belt and braces. The only tolerated error is
        // on `identifier`, and `frame` is read after it, so any stop still
        // leaves a non-harmless `frame` on the interrupted child -- which the
        // per-record loop below already fails. They are here because that is a
        // coincidence of the read order, and the order is explicitly no longer
        // load-bearing: the moment a tolerance is added to `role` or `frame`, or
        // the order changes, or a second adapter produces a `RawRead`, this is
        // what keeps R-e true instead of silently regressing it.
        if raw.records.count != raw.childCount {
            return .failed(.partialWalk(childCount: raw.childCount, records: raw.records.count))
        }

        for record in raw.records {
            if let reason = attributeFailure(call: "role", read: record.role) { return .failed(reason) }
            if let reason = attributeFailure(call: "identifier", read: record.identifier, toleratesFailure: true) { return .failed(reason) }
            if let reason = attributeFailure(call: "frame", read: record.frame) { return .failed(reason) }
        }

        return .items(raw.records)
    }

    /// Shared by `role`/`identifier` (`AttributeRead<String>`) and `frame`
    /// (`AttributeRead<BarRect>`): only the error name decides, never the
    /// value's type. `toleratesFailure` is a flag rather than a second set of
    /// harmless errors, because the fact it carries is one string on one call.
    private static func attributeFailure<Value>(
        call: String,
        read: AttributeRead<Value>,
        toleratesFailure: Bool = false
    ) -> FailureReason? {
        if harmlessAttributeErrors.contains(read.error) { return nil }
        if toleratesFailure, read.error == toleratedIdentifierError { return nil }
        return .unexpectedError(call: call, error: read.error)
    }
}
