import Testing
@testable import IceCore

/// A rest is verified only from a burst Ice's own capture indicator does not
/// answer: a burst's first session, read within 2.5 s of its start (plan
/// 2026-10-19-verify-in-a-clean-burst, D1-D4; run 20261019-004100, `3-press`).
@Suite("IceBarHidingMachine, confirming")
struct IceBarHidingConfirmationTests {
    typealias Fixtures = IceBarHidingMachineTests
    typealias Driver = IceBarHidingMachineTests.Driver

    /// The lengths asked for with or without closing their burst.
    static func observations(_ log: [IceBarHidingCommand], closing: Bool) -> [Double] {
        log.compactMap { command in
            if case .observe(_, let length, let closes) = command, closes == closing { length } else { nil }
        }
    }

    // MARK: - Who may verify (D1)

    @Test("a calibration's trials keep their burst; the settle closes its own")
    func settleClosesItsBurst() {
        var driver = Driver()
        driver.settle()
        #expect(Self.observations(driver.log, closing: true) == [736])
        #expect(!Self.observations(driver.log, closing: false).isEmpty)
        #expect(driver.state == .verifiedHidden)
    }

    @Test("a settle that sees every member absent in a burst's second session confirms in a burst of its own")
    func secondSessionConfirms() {
        var driver = Driver()
        driver.burstScript = [Fixtures.burst(50, ordinal: 2, age: 5.4)]
        driver.settle()
        #expect(Self.observations(driver.log, closing: true) == [736, 736])
        #expect(driver.reports.contains(.state(.requestedNotVerified(reasons: [.confirming]))))
        #expect(driver.state == .verifiedHidden)
        #expect(driver.restLength == 736)
    }

    @Test("a burst's first session proves up to 2.5 s from the burst's start, not past it", arguments: [
        (2.5 - 1e-9, 1), (2.5, 1), (2.5 + 1e-9, 2),
    ])
    func ageBoundary(age: Double, closing: Int) {
        var driver = Driver()
        driver.burstScript = [Fixtures.burst(50, age: age)]
        driver.settle()
        #expect(Self.observations(driver.log, closing: true).count == closing)
        #expect(driver.state == .verifiedHidden)
    }

    @Test("a confirmation read in the candidate's own burst does not prove")
    func confirmationInCandidatesBurst() {
        var driver = Driver()
        driver.burstScript = [Fixtures.burst(50, age: 3), Fixtures.burst(50, age: 1)]
        driver.settle()
        #expect(Self.observations(driver.log, closing: true).count == 3)
        #expect(driver.state == .verifiedHidden)
    }

    @Test("readings without a burst never verify: after maxFailures confirmations the rest stands unchecked")
    func noBurstNeverVerifies() {
        var driver = Driver()
        driver.burstScript = Array(repeating: nil, count: 10)
        driver.settle()
        #expect(Self.observations(driver.log, closing: true).count == 1 + driver.machine.parameters.maxFailures)
        #expect(driver.restLength == 736)
        #expect(driver.machine.status.logSummary == "notVerified(unchecked:2)")
    }

    // MARK: - Confirming (D2)

    @Test("while confirming: the length stays, no IceBar is offered, and the status says so")
    func confirmingFacts() {
        var driver = Driver()
        guard let settle = driver.answerUntilClosing() else { Issue.record("no settle asked"); return }
        let commands = driver.send(.observed(
            token: settle.token, checks: driver.checks(at: settle.length), chevronListed: false,
            burst: Fixtures.burst(50, ordinal: 2)
        ))
        guard case .observe(_, let length, true)? = commands.first else { Issue.record("no confirmation asked"); return }
        #expect(length == settle.length)
        #expect(!commands.contains(.setLength(nil)))
        #expect(driver.machine.lengthSet)
        #expect(!driver.machine.lengthApplied)
        #expect(driver.machine.awaitsAnswer)
        #expect(driver.machine.status.logSummary == "notVerified(confirming)")
        #expect(driver.machine.labFacts.phase == "confirming")
    }

    @Test("a confirmation that sees a member drawn is taken as the settle's own would have been")
    func drawnConfirmation() {
        var driver = Driver()
        guard let settle = driver.answerUntilClosing() else { Issue.record("no settle asked"); return }
        let commands = driver.send(.observed(
            token: settle.token, checks: driver.checks(at: settle.length), chevronListed: false,
            burst: Fixtures.burst(50, ordinal: 2)
        ))
        guard case .observe(let token, _, true)? = commands.first else { Issue.record("no confirmation asked"); return }
        let drawn = Dictionary(uniqueKeysWithValues: driver.members.members.compactMap(\.key).map { ($0, Fixtures.drawn) })
        driver.send(.observed(token: token, checks: drawn, chevronListed: false, burst: Fixtures.burst(51)))
        #expect(driver.state == .visibleFailed(drawn: [Fixtures.member(1).tag, Fixtures.member(2).tag]))
    }

    // MARK: - Dropping the candidate (D3)

    static let dropping: [IceBarHidingSample] = [
        Fixtures.sample(Fixtures.signature(frontmostPID: 11)),
        Fixtures.sample(interacting: true),
        Fixtures.sample(dragging: true),
        Fixtures.sample(preconditions: Fixtures.blocks[0]),
    ]

    @Test("a layout change, interaction, a drag or a failed precondition while confirming retires the length", arguments: dropping)
    func candidateDropped(sample: IceBarHidingSample) {
        var driver = Driver()
        guard let settle = driver.answerUntilClosing() else { Issue.record("no settle asked"); return }
        let commands = driver.send(.observed(
            token: settle.token, checks: driver.checks(at: settle.length), chevronListed: false,
            burst: Fixtures.burst(50, ordinal: 2)
        ))
        guard case .observe(let token, _, true)? = commands.first else { Issue.record("no confirmation asked"); return }
        #expect(driver.tick(sample).first == .setLength(nil))
        #expect(!driver.machine.lengthSet)
        // The confirmation that comes late answers nobody.
        let late = driver.send(.observed(token: token, checks: driver.checks(at: settle.length), chevronListed: false, burst: Fixtures.burst(51)))
        #expect(late.isEmpty)
        #expect(driver.state != .verifiedHidden)
    }

    // MARK: - A rest's re-check

    @Test("a re-check read in a burst's second session is asked again in a burst of its own")
    func recheckConfirms() {
        var driver = Driver()
        driver.settle()
        driver.answers = false
        let changed = Fixtures.sample(Fixtures.signature(frontmostPID: 11))
        driver.run(changed, ticks: 4)
        guard case .observe(let token, let length, true)? = driver.log.last else { Issue.record("no re-check asked"); return }
        let commands = driver.send(.observed(token: token, checks: driver.checks(at: length), chevronListed: false, burst: Fixtures.burst(50, ordinal: 2)))
        guard case .observe(let again, _, true)? = commands.first else { Issue.record("no confirmation asked"); return }
        #expect(driver.state == .requestedNotVerified(reasons: [.layoutChangePending(.frontmostAppChanged)]))
        driver.send(.observed(token: again, checks: driver.checks(at: length), chevronListed: false, burst: Fixtures.burst(51)))
        #expect(driver.state == .verifiedHidden)
    }
}

extension IceBarHidingMachineTests.Driver {
    /// Answers baselines and trials by hand until the machine asks for an
    /// observation that closes its burst: that request, unanswered.
    mutating func answerUntilClosing() -> (token: Int, length: Double)? {
        answers = false
        send(.mode(isIceBar: true))
        var mark = log.count
        for _ in 0..<300 {
            let fresh = since(mark)
            mark = log.count
            for command in fresh {
                switch command {
                case .takeBaseline(let token, _, _):
                    send(.baseline(token: token, ok: true))
                case .observe(let token, let length, false):
                    send(.observed(token: token, checks: checks(at: length), chevronListed: false, burst: burst(closes: false)))
                case .observe(let token, let length, true):
                    return (token, length)
                default:
                    break
                }
            }
            if log.count == mark { tick() }
        }
        return nil
    }
}
