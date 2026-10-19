import Testing
import IceCore
@testable import MenuBarDetectorFeed

/// What the observer says of the burst a reading was taken in is what the
/// hiding machine verifies by: only a new burst's first session, read within
/// 2.5 s of its start, rests verified (plan 2026-10-19-verify-in-a-clean-burst, T4).
@Suite("Observation burst contract")
struct ObservationContractTests {
    typealias Rigs = CaptureBurstObserverTests
    typealias Base = HiddenLengthObserverTests

    static let membership = PreferenceHidingMembership(
        members: [Base.items.t1.key, Base.items.t2.key].map { PreferenceHidingMember(tag: $0.tagKey(isSelf: false), key: $0, condition: .ready) },
        blockers: []
    )

    static func sample() -> IceBarHidingSample {
        let tags = membership.members.map(\.tag)
        return IceBarHidingSample(
            signature: LayoutSignature(items: tags, members: tags, frontmostPID: 10, menuMaxX: 400, displayID: 1, spaceID: 7),
            preconditions: .ok, membership: membership, isInteracting: false, isDragging: false, boundaryUsable: true
        )
    }

    /// A machine walked to its settle, every trial seeing the members absent:
    /// the settle's request, unanswered.
    static func settling() -> (machine: IceBarHidingMachine, token: Int, length: Double, now: Double)? {
        var machine = IceBarHidingMachine()
        var now = 0.0
        var pending: [IceBarHidingCommand] = []
        func step(_ event: IceBarHidingEvent) {
            let (next, commands) = machine.step(event, now: now)
            machine = next
            pending += commands
        }
        step(.mode(isIceBar: true))
        for trial in 0..<300 {
            if pending.isEmpty {
                now += 1
                step(.sample(sample()))
                continue
            }
            let command = pending.removeFirst()
            switch command {
            case .takeBaseline(let token, _, _):
                step(.baseline(token: token, ok: true))
            case .observe(let token, _, false):
                let checks = Dictionary(uniqueKeysWithValues: membership.members.compactMap(\.key).map { ($0, Base.clean) })
                let burst = ObservationBurst(burstID: trial, ordinal: 1, burstStartedAt: now, capturedAt: now + 1)
                step(.observed(token: token, checks: checks, chevronListed: false, burst: burst))
            case .observe(let token, let length, true):
                return (machine, token, length, now)
            default:
                break
            }
        }
        return nil
    }

    static func answer(_ machine: IceBarHidingMachine, token: Int, with reading: HiddenLengthReading, now: Double)
        -> (machine: IceBarHidingMachine, commands: [IceBarHidingCommand]) {
        machine.step(.observed(token: token, checks: reading.checks, chevronListed: reading.chevronListed, burst: reading.burst), now: now)
    }

    @Test("a settle read on a clear bar, a new burst's first session, rests verified")
    func clearBarVerifies() async throws {
        let rig = Rigs.rig()
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        let settle = try #require(Self.settling())
        rig.now.set(200)
        let reading = await rig.observer.observe(closesBurst: true)
        let (machine, _) = Self.answer(settle.machine, token: settle.token, with: reading, now: settle.now)
        #expect(machine.status == .state(.verifiedHidden))
    }

    @Test("a settle read in a burst it joined confirms; the confirmation, its own burst's first session, verifies")
    func joinedBurstConfirms() async throws {
        let rig = Rigs.rig(observations: 2)
        _ = await rig.observer.takeBaseline(sectionMap: Base.sectionMap)
        let settle = try #require(Self.settling())
        // A trial's captures a moment ago: the settle joins their burst.
        rig.burst.noteCapture(at: 200)
        rig.burst.noteCapture(at: 201.5)
        rig.now.set(202)
        let joined = await rig.observer.observe(closesBurst: true)
        #expect(joined.burst?.ordinal == 2)
        let (confirming, commands) = Self.answer(settle.machine, token: settle.token, with: joined, now: settle.now)
        #expect(confirming.status == .state(.requestedNotVerified(reasons: [.confirming])))
        guard case .observe(let token, _, true)? = commands.first else { Issue.record("no confirmation asked"); return }
        // The settle closed its burst: the confirmation waits for a clear bar and opens one of its own.
        let own = await rig.observer.observe(closesBurst: true)
        #expect(own.waited > 0)
        #expect(own.burst?.ordinal == 1)
        let (rested, _) = Self.answer(confirming, token: token, with: own, now: settle.now + 30)
        #expect(rested.status == .state(.verifiedHidden))
    }
}
