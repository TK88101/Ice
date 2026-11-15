import Testing
@testable import IceCore

/// The coordinator's hold of the bar at standard length (plan
/// 2026-11-15-blind-at-length, D3, D4): one current hold, one token, one
/// release every ending passes through; a stale token changes nothing.
/// (A mutating call is made before its `#expect`: the macro cannot make one.)
@Suite("IceBarHold")
struct IceBarHoldTests {
    static let tag = fixtureTag("m1")
    static let other = fixtureTag("m2")

    /// A press hold begun at 100 with a 2 s wait.
    static func pressHold() -> (hold: IceBarHold, token: Int) {
        var hold = IceBarHold()
        let token = hold.begin(.press(tag), now: 100, wait: 2) ?? -1
        return (hold, token)
    }

    /// A re-read hold begun at 100 with a 4 s wait.
    static func rereadHold() -> (hold: IceBarHold, token: Int) {
        var hold = IceBarHold()
        let token = hold.begin(.reread, now: 100, wait: 4) ?? -1
        return (hold, token)
    }

    /// A re-read hold that took its pass at 101.1 and waits for the length until 103.1.
    static func reapplyingHold() -> (hold: IceBarHold, token: Int) {
        var (hold, token) = rereadHold()
        _ = hold.passed(token, beganAt: 101, now: 101.1, reapply: 2)
        return (hold, token)
    }

    func due(_ hold: IceBarHold, now: Double, dragging: Bool = false, modeOn: Bool = true, members: [TagKey] = [tag, other]) -> IceBarHold.Ending? {
        hold.due(now: now, isDragging: dragging, isModeOn: modeOn, members: members)
    }

    // MARK: - Begin and release

    @Test("no hold at first: nothing is held, nothing is due")
    func empty() {
        let hold = IceBarHold()
        #expect(!hold.isHeld)
        #expect(hold.current == nil)
        #expect(due(hold, now: 1) == nil)
    }

    @Test("a hold begins waiting, held, with its deadline")
    func begins() {
        let (hold, token) = Self.pressHold()
        #expect(hold.isHeld)
        #expect(hold.isCurrent(token))
        #expect(hold.current?.phase == .waiting(deadline: 102))
        #expect(hold.current?.purpose == .press(Self.tag))
    }

    @Test("the release ends the hold once: the second call, and any stale token, change nothing")
    func releaseOnce() {
        var (hold, token) = Self.pressHold()
        let stale = hold.release(token + 1, .finished)
        #expect(!stale, "another token")
        #expect(hold.isHeld)
        let first = hold.release(token, .finished)
        #expect(first)
        #expect(!hold.isHeld)
        #expect(hold.lastEnded == IceBarHold.Ended(token: token, ending: .finished))
        let second = hold.release(token, .deadline)
        #expect(!second)
        #expect(hold.lastEnded?.ending == .finished)
    }

    @Test("a new hold replaces a waiting one: the old token is stale in every call")
    func replacesWaiting() {
        var (hold, old) = Self.pressHold()
        let new = hold.begin(.press(Self.other), now: 101, wait: 2)
        #expect(new != nil && new != old)
        #expect(hold.lastEnded == IceBarHold.Ended(token: old, ending: .replaced))
        #expect(!hold.isCurrent(old))
        let dispatched = hold.dispatched(old)
        let returned = hold.returned(old, showing: true)
        let released = hold.release(old, .finished)
        #expect(!dispatched && !returned && !released)
        #expect(hold.current?.purpose == .press(Self.other))
        #expect(hold.current?.phase == .waiting(deadline: 103))
    }

    @Test("a new hold is refused while a press is out or what it opened shows: its menu may be open")
    func refusedWhilePressing() {
        var (hold, token) = Self.pressHold()
        _ = hold.dispatched(token)
        let press = hold.begin(.press(Self.other), now: 101, wait: 2)
        let reread = hold.begin(.reread, now: 101, wait: 4)
        #expect(press == nil && reread == nil)
        #expect(hold.isCurrent(token))
        _ = hold.returned(token, showing: true)
        let whileShowing = hold.begin(.reread, now: 102, wait: 4)
        #expect(whileShowing == nil)
        #expect(hold.isCurrent(token))
        #expect(hold.lastEnded == nil, "nothing was replaced")
    }

    @Test("tokens never repeat, across releases and replacements")
    func tokensNeverRepeat() {
        var hold = IceBarHold()
        var seen = Set<Int>()
        for index in 0..<6 {
            let token = hold.begin(index.isMultiple(of: 2) ? .reread : .press(Self.tag), now: Double(index), wait: 1)
            #expect(token != nil)
            let isNew = seen.insert(token ?? -1).inserted
            #expect(isNew)
            if index.isMultiple(of: 3) { _ = hold.release(token ?? -1, .finished) }
        }
    }

    // MARK: - A press hold's phases

    @Test("waiting, then pressing when the press is dispatched, then showing while what it opened shows")
    func pressPhases() {
        var (hold, token) = Self.pressHold()
        let dispatched = hold.dispatched(token)
        #expect(dispatched)
        #expect(hold.current?.phase == .pressing)
        #expect(hold.isHeld)
        let returned = hold.returned(token, showing: true)
        #expect(returned)
        #expect(hold.current?.phase == .showing)
        #expect(hold.isHeld)
    }

    @Test("a press that returned with nothing showing stays in its phase: the caller releases it")
    func returnedNothingShowing() {
        var (hold, token) = Self.pressHold()
        _ = hold.dispatched(token)
        let returned = hold.returned(token, showing: false)
        #expect(returned)
        #expect(hold.current?.phase == .pressing)
        let released = hold.release(token, .finished)
        #expect(released)
    }

    @Test("a press is dispatched only from waiting, once, and returns only from pressing; a re-read presses nothing")
    func phaseOrder() {
        var (hold, token) = Self.pressHold()
        let early = hold.returned(token, showing: true)
        #expect(!early, "not dispatched yet")
        let first = hold.dispatched(token)
        let again = hold.dispatched(token)
        #expect(first && !again)
        var (reread, rereadToken) = Self.rereadHold()
        let rereadPress = reread.dispatched(rereadToken)
        #expect(!rereadPress)
    }

    @Test("the deadline ends a waiting hold, and never one whose press is out or whose interface shows")
    func deadlineOnlyWhileWaiting() {
        var (hold, token) = Self.pressHold()
        #expect(due(hold, now: 101.9) == nil)
        #expect(due(hold, now: 102) == .deadline)
        _ = hold.dispatched(token)
        #expect(due(hold, now: 500) == nil)
        _ = hold.returned(token, showing: true)
        #expect(due(hold, now: 5000) == nil)
    }

    @Test("a drag, the mode going off, or the pressed member leaving the roster ends a hold in any phase", arguments: [0, 1, 2])
    func otherEndings(phase: Int) {
        var (hold, token) = Self.pressHold()
        if phase >= 1 { _ = hold.dispatched(token) }
        if phase >= 2 { _ = hold.returned(token, showing: true) }
        #expect(due(hold, now: 101, dragging: true) == .dragBegan)
        #expect(due(hold, now: 101, modeOn: false) == .modeOff)
        #expect(due(hold, now: 101, members: [Self.other]) == .memberGone)
        #expect(due(hold, now: 101) == nil)
    }

    @Test("the mode going off is named before a drag, a drag before a member gone, that before the deadline")
    func endingOrder() {
        let (hold, _) = Self.pressHold()
        #expect(due(hold, now: 200, dragging: true, modeOn: false, members: []) == .modeOff)
        #expect(due(hold, now: 200, dragging: true, members: []) == .dragBegan)
        #expect(due(hold, now: 200, members: []) == .memberGone)
        #expect(due(hold, now: 200) == .deadline)
    }

    @Test("a member arriving during the hold ends nothing: only the pressed member's leaving does")
    func arrivalDoesNotEnd() {
        let (hold, _) = Self.pressHold()
        #expect(due(hold, now: 101, members: [fixtureTag("new"), Self.tag]) == nil)
    }

    // MARK: - A re-read hold (D4)

    @Test("a re-read waits for a pass that began after it did; then it lets the bar go and waits for the length")
    func rereadPhases() {
        var (hold, token) = Self.rereadHold()
        let before = hold.passed(token, beganAt: 99.9, now: 100.2, reapply: 2)
        #expect(!before, "a pass from before the hold")
        #expect(hold.isHeld)
        let taken = hold.passed(token, beganAt: 101.1, now: 101.2, reapply: 2)
        #expect(taken)
        #expect(hold.current?.phase == .reapplying(deadline: 103.2))
        #expect(!hold.isHeld, "the machine may hide again")
        #expect(hold.isCurrent(token))
    }

    @Test("a re-read's token opens the IceBar once")
    func rereadOpensOnce() {
        var (hold, token) = Self.reapplyingHold()
        let first = hold.release(token, .finished)
        let second = hold.release(token, .finished)
        #expect(first && !second)
        #expect(hold.current == nil)
    }

    @Test("either deadline ends a re-read: no trusted pass in time, or no length in time")
    func rereadDeadlines() {
        let (waiting, _) = Self.rereadHold()
        #expect(due(waiting, now: 103.9) == nil)
        #expect(due(waiting, now: 104) == .deadline)
        let (reapplying, _) = Self.reapplyingHold()
        #expect(due(reapplying, now: 103) == nil)
        #expect(due(reapplying, now: 103.1) == .deadline)
    }

    @Test("a pass does nothing for a press hold, a stale token, or a re-read already let go")
    func passedOnlyForWaitingReread() {
        var (press, pressToken) = Self.pressHold()
        let forPress = press.passed(pressToken, beganAt: 101, now: 101.1, reapply: 2)
        #expect(!forPress)
        var (hold, token) = Self.rereadHold()
        let stale = hold.passed(token + 1, beganAt: 101, now: 101.1, reapply: 2)
        let first = hold.passed(token, beganAt: 101, now: 101.1, reapply: 2)
        let again = hold.passed(token, beganAt: 102, now: 102.1, reapply: 2)
        #expect(!stale && first && !again)
        #expect(hold.current?.phase == .reapplying(deadline: 103.1))
    }

    @Test("a re-read has no member to lose; a drag or the mode going off ends it")
    func rereadEndings() {
        let (hold, _) = Self.rereadHold()
        #expect(due(hold, now: 101, members: []) == nil)
        #expect(due(hold, now: 101, dragging: true) == .dragBegan)
        #expect(due(hold, now: 101, modeOn: false) == .modeOff)
    }

    @Test("a new hold replaces a re-read that has let the bar go: the replaced token opens nothing")
    func rereadReplaced() {
        var (hold, token) = Self.reapplyingHold()
        let press = hold.begin(.press(Self.tag), now: 101.5, wait: 2)
        #expect(press != nil)
        let opened = hold.release(token, .finished)
        #expect(!opened)
        #expect(hold.isHeld)
    }
}
