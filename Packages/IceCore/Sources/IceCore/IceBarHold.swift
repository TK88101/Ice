/// The coordinator's hold of the bar at standard length on a system that
/// lists no pushed-off item (plan 2026-11-15-blind-at-length, D3, D4): a
/// hidden member is pressed on the bar, or the bar is read once before the
/// IceBar opens. Pure: the coordinator feeds it and acts on its answers.
///
/// At most one hold is current. Every call names its token, and a call with
/// a token that is not the current one changes nothing: a press that returns
/// late, a pass that ends late, cannot end or move a newer hold.
public struct IceBarHold: Equatable, Sendable {
    public enum Purpose: Equatable, Sendable {
        /// The member with this tag is pressed on the bar.
        case press(TagKey)
        /// One trusted pass at standard length, then the IceBar opens.
        case reread
    }

    public enum Phase: Equatable, Sendable {
        /// A press: until its element is listed. A re-read: until a trusted
        /// pass that began after the hold has ended. Bounded by the deadline.
        case waiting(deadline: Double)
        /// The press is dispatched and has not returned. No deadline ends it:
        /// a menu it opened may be up.
        case pressing
        /// The press returned and what it opened still shows.
        case showing
        /// A re-read only: the bar is let go, and the IceBar opens when the
        /// length is applied again. Bounded by the deadline.
        case reapplying(deadline: Double)
    }

    public enum Ending: Equatable, Sendable {
        /// A press: returned, and nothing it opened shows. A re-read: the
        /// IceBar was opened.
        case finished
        case deadline
        case dragBegan
        case modeOff
        /// A newer hold began.
        case replaced
        /// The pressed member is no longer in the roster.
        case memberGone
    }

    public struct Current: Equatable, Sendable {
        public let token: Int
        public let purpose: Purpose
        public let beganAt: Double
        public fileprivate(set) var phase: Phase
    }

    /// The last hold that ended, and how.
    public struct Ended: Equatable, Sendable {
        public let token: Int
        public let ending: Ending
    }

    public private(set) var current: Current?
    public private(set) var lastEnded: Ended?
    /// Tokens never repeat: a late answer must not match a newer hold.
    private var lastToken = 0

    public init() {}

    /// The machine must stay at standard length: a hold is current and has
    /// not let the bar go.
    public var isHeld: Bool {
        switch current?.phase {
        case .waiting, .pressing, .showing: true
        case .reapplying, nil: false
        }
    }

    public func isCurrent(_ token: Int) -> Bool {
        current?.token == token
    }

    /// A new hold, waiting until `now + wait`; its token. Refused (`nil`)
    /// while a press is out or what it opened shows: letting the bar go
    /// under that menu is worse than a click that does nothing. Any other
    /// current hold is replaced.
    public mutating func begin(_ purpose: Purpose, now: Double, wait: Double) -> Int? {
        if let current {
            switch current.phase {
            case .pressing, .showing: return nil
            case .waiting, .reapplying: lastEnded = Ended(token: current.token, ending: .replaced)
            }
        }
        lastToken += 1
        current = Current(token: lastToken, purpose: purpose, beganAt: now, phase: .waiting(deadline: now + wait))
        return lastToken
    }

    /// The press of a waiting press hold is dispatched. `false`, and nothing
    /// may be pressed, when the token is stale or the hold is not waiting
    /// for a press.
    public mutating func dispatched(_ token: Int) -> Bool {
        guard var hold = current, hold.token == token, case .press = hold.purpose, case .waiting = hold.phase else {
            return false
        }
        hold.phase = .pressing
        current = hold
        return true
    }

    /// The dispatched press returned. With `showing` the hold lasts while
    /// what the press opened shows; without, the caller releases it.
    /// `false` when the token is stale or no press is out.
    public mutating func returned(_ token: Int, showing: Bool) -> Bool {
        guard var hold = current, hold.token == token, hold.phase == .pressing else {
            return false
        }
        if showing {
            hold.phase = .showing
            current = hold
        }
        return true
    }

    /// A trusted pass at standard length ended. A waiting re-read takes one
    /// that began after the hold did: the bar is let go (`reapplying` until
    /// `now + reapply`) and `true` is returned. Anything else changes nothing.
    public mutating func passed(_ token: Int, beganAt passBeganAt: Double, now: Double, reapply: Double) -> Bool {
        guard var hold = current, hold.token == token, hold.purpose == .reread, case .waiting = hold.phase,
              passBeganAt > hold.beganAt
        else {
            return false
        }
        hold.phase = .reapplying(deadline: now + reapply)
        current = hold
        return true
    }

    /// The one way a hold ends. `true` exactly once, for the current token:
    /// only then may the caller act on the ending (hide again, open the
    /// IceBar, disable a cell).
    public mutating func release(_ token: Int, _ ending: Ending) -> Bool {
        guard current?.token == token else { return false }
        current = nil
        lastEnded = Ended(token: token, ending: ending)
        return true
    }

    /// What ends the current hold by itself now, the first of: IceBar mode
    /// off; a drag (the owner needs the real divider, and the drag holds
    /// the bar); the pressed member gone from `members`; a deadline, which
    /// only `waiting` and `reapplying` have.
    public func due(now: Double, isDragging: Bool, isModeOn: Bool, members: [TagKey]) -> Ending? {
        guard let current else { return nil }
        if !isModeOn { return .modeOff }
        if isDragging { return .dragBegan }
        if case .press(let tag) = current.purpose, !members.contains(tag) { return .memberGone }
        switch current.phase {
        case .waiting(let deadline), .reapplying(let deadline): return now >= deadline ? .deadline : nil
        case .pressing, .showing: return nil
        }
    }
}
