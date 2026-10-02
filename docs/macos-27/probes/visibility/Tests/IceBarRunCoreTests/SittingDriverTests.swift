// Q20: the whole sitting as one pure state machine -- S0, then S-adv (the
// desktop picture per appearance, deviation 5 D5.2), then S1; every gate; `«` episodes merged across
// step processes; a safety stop or an ended step ends the sitting.
import C2Core
import IceBarOracle
@testable import IceBarRunCore
import Testing

@Suite("Q20: the sitting driver")
struct SittingDriverTests {
    static func report(_ status: StepStatus = .completed, s0: S0Report? = nil, sweep: RepeatResult? = nil,
                       points: [ReportPoint] = [], cycles: [CycleRecord] = [], b: [BObservation] = []) -> StepReport {
        var r = StepReport(status: status)
        r.s0 = s0
        r.sweep = sweep
        r.points = points
        r.cycles = cycles
        r.chevronObservations = b.map(ReportB.init)
        return r
    }

    static let s0Pass = S0Report(outcome: .pass, c3: .holds, section8: .consistent)
    /// Two `«` episodes of five captures each.
    static let chevronSeen = (0..<10).map { BObservation(episode: $0 < 5 ? 1 : 2, axChevron: true, pixels: .present) }

    /// Answers every request: S-adv passes with two `«` episodes, S1's bands are 600-700 everywhere, midpoints pass.
    static func answer(_ request: SittingRequest) -> StepReport {
        switch request.kind {
        case .s0: return report(s0: s0Pass)
        case .sAdvSweep: return report(sweep: .pass)
        case .sAdvChevron: return report(sweep: .pass, b: chevronSeen)
        case .s1Bracket(let lengths):
            return report(points: lengths.map { ReportPoint(length: $0, reading: (600...700).contains($0) ? "hiddenNoFold" : "stillDrawn") })
        case .s1Confirm:
            let good = ObservationRecord(outcome: .granted, cause: nil, oracleClean: true, attempts: 1)
            return report(cycles: Array(repeating: CycleRecord(observations: Array(repeating: good, count: 4), controlMiss: false), count: 5))
        }
    }

    static func drive(_ driver: inout SittingDriver, answer: (SittingRequest) -> StepReport = answer,
                      pictureSet: (Int) -> Bool = { _ in true }) -> (SittingResult, [SittingRequest], [Appearance?]) {
        var requests = [SittingRequest]()
        var pictures = [Appearance?]()
        while true {
            switch driver.next() {
            case .finished(let result): return (result, requests, pictures)
            case .run(let request):
                requests.append(request)
                driver.record(answer(request))
            case .setDesktopPicture(let appearance):
                pictures.append(appearance)
                driver.desktopPictureSet(pictureSet(pictures.count - 1))
            }
        }
    }

    @Test("deviation 5 D5.2: the desktop picture is set before each S-adv appearance and restored before S1")
    func pictures() {
        var driver = SittingDriver()
        let (result, requests, pictures) = Self.drive(&driver)
        #expect(result == .completed("S1 capacity 16"))
        #expect(requests.first == SittingRequest(kind: .s0, members: 2, menu: .long, name: "S0"))
        #expect(pictures == [.dark, .light, .dark, nil])
    }

    @Test("D5.2: a desktop picture that cannot be set ends the sitting, and the original is asked for once")
    func pictureFails() {
        var driver = SittingDriver()
        let (result, requests, pictures) = Self.drive(&driver, pictureSet: { _ in false })
        #expect(result == .interrupted("the desktop picture could not be set (deviation 5 D5.2)"))
        #expect(requests.count == 1)
        #expect(pictures == [.dark, nil])
    }

    @Test("D5.2: a failed change from one staged picture to the other still asks for the original")
    func secondPictureFails() {
        var driver = SittingDriver()
        let (result, _, pictures) = Self.drive(&driver, pictureSet: { $0 != 1 })
        #expect(result == .interrupted("the desktop picture could not be set (deviation 5 D5.2)"))
        #expect(pictures == [.dark, .light, nil])
    }

    @Test("D5.2: a sitting the runner ends with a staged picture set restores the original before it finishes")
    func endedWithStagedPicture() {
        var driver = SittingDriver()
        #expect(driver.next() == .run(SittingDriver.s0))
        driver.record(Self.answer(SittingDriver.s0))
        #expect(driver.next() == .setDesktopPicture(.dark))
        driver.desktopPictureSet(true)
        guard case .run = driver.next() else {
            Issue.record("no S-adv step")
            return
        }
        driver.end(.interrupted("signal 15"))
        #expect(driver.next() == .setDesktopPicture(nil))
        driver.desktopPictureSet(true)
        #expect(driver.next() == .finished(.interrupted("signal 15")))
    }

    @Test("D5.2: a safety stop during S-adv restores the original; a failed restore keeps the result and ends")
    func safetyStopWithStagedPicture() {
        let stop: (SittingRequest) -> StepReport = { request in
            if case .sAdvSweep = request.kind { var r = Self.report(.safetyStop); r.reason = "foreign item"; return r }
            return Self.answer(request)
        }
        var restored = SittingDriver()
        let (result, _, pictures) = Self.drive(&restored, answer: stop)
        #expect(result == .safetyStop("S-adv dark-ordinary: foreign item"))
        #expect(pictures == [.dark, nil])
        var failing = SittingDriver()
        let (kept, _, asked) = Self.drive(&failing, answer: stop, pictureSet: { $0 == 0 })
        #expect(kept == .safetyStop("S-adv dark-ordinary: foreign item"))
        #expect(asked == [.dark, nil])
    }

    @Test("D5.2: a picture change is always followed by a new step process (its own warm-up and settle) or the end")
    func pictureThenStep() {
        var driver = SittingDriver()
        var afterPicture = false
        var changes = 0
        loop: while true {
            switch driver.next() {
            case .finished:
                break loop
            case .run(let request):
                afterPicture = false
                driver.record(Self.answer(request))
            case .setDesktopPicture:
                #expect(!afterPicture)
                afterPicture = true
                changes += 1
                driver.desktopPictureSet(true)
            }
        }
        #expect(changes == 4)
    }

    @Test("S0, four variants x two sweeps, the `«` rest state, then S1 to its capacity")
    func whole() {
        var driver = SittingDriver()
        let (result, requests, _) = Self.drive(&driver)
        #expect(result == .completed("S1 capacity 16"))
        #expect(requests.filter { if case .sAdvSweep = $0.kind { true } else { false } }.count == 8)
        #expect(requests.filter { if case .sAdvChevron = $0.kind { true } else { false } }.count == 1)
        #expect(requests.filter { $0.name.hasPrefix("S-adv") }.allSatisfy { $0.members == 4 && $0.menu == .short })
        #expect(requests.last?.name == "S1 k3-mid")
    }

    @Test("`«` episodes of the separate S0 and S-adv processes are merged before BControl")
    func merged() {
        var driver = SittingDriver()
        let (result, _, _) = Self.drive(&driver) { request in
            switch request.kind {
            case .s0: return Self.report(s0: Self.s0Pass, b: Array(Self.chevronSeen.prefix(5)))
            case .sAdvChevron: return Self.report(sweep: .pass, b: Array(Self.chevronSeen.prefix(5)))
            default: return Self.answer(request)
            }
        }
        #expect(result == .completed("S1 capacity 16"))
        var mismatch = SittingDriver()
        let (stopped, _, _) = Self.drive(&mismatch) { request in
            if case .sAdvChevron = request.kind { return Self.report(sweep: .pass, b: [BObservation(episode: 1, axChevron: true, pixels: .absent)]) }
            return Self.answer(request)
        }
        #expect(stopped == .interrupted("« (b) control: mismatch at capture 0; the owner decides"))
    }

    @Test("S0's gates; a step without its S0 report is S0 not shown")
    func s0Gates() {
        var noGo = SittingDriver()
        #expect(Self.drive(&noGo) { _ in Self.report(.noGo, s0: S0Report(outcome: .noGo, c3: .holds, section8: .consistent)) }.0
            == .failed("S0: the claim was granted with a long menu"))
        var missing = SittingDriver()
        #expect(Self.drive(&missing) { _ in var r = Self.report(.inconclusive); r.reason = "placement gate: missing(\"ell\")"; return r }.0
            == .failed("S0 not shown: placement gate: missing(\"ell\")"))
    }

    @Test("a safety stop in any step, or a step the runner ended, ends the sitting")
    func ends() {
        var safety = SittingDriver()
        #expect(Self.drive(&safety) { _ in var r = Self.report(.safetyStop); r.reason = "foreign item"; return r }.0 == .safetyStop("S0: foreign item"))
        var ended = SittingDriver()
        _ = ended.next()
        ended.end(.interrupted("this session left the screen during step 1"))
        #expect(ended.next() == .finished(.interrupted("this session left the screen during step 1")))
    }

    @Test("S-adv NO-GO fails the sitting")
    func sAdvNoGo() {
        var driver = SittingDriver()
        let (result, _, _) = Self.drive(&driver) { request in
            if case .sAdvSweep = request.kind { return Self.report(.noGo, sweep: .noGo) }
            return Self.answer(request)
        }
        #expect(result == .failed("S-adv: the claim was granted while the oracle saw a member or «"))
    }
}
