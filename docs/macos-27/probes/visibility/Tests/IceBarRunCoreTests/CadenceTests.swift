// U18 (pre-registration section 7) and the cadence of section 2, as fixed by
// the runner plan's Q1-Q3.
@testable import IceBarRunCore
import IceCore
import Testing

@Suite("U18: cadence")
struct CadenceTests {
    let p = CadenceParameters.preRegistered

    @Test("the registered numbers")
    func numbers() {
        #expect(p.warmUpCaptures == 24 && p.warmUpSpacing == 0.25)
        #expect(p.settle == 1.0)
        #expect(p.baselineSamples == 5 && p.baselineSpacing == 1.0)
        #expect(p.observationSamples == 3 && p.observationSpacing == 0.5)
        #expect(p.maxAttempts == 3 && p.attemptGap == 1.0)
        #expect(p.timeout == 10)
        #expect(p.observationsPerCycle == 4 && p.observationStartSpacing == 5)
    }

    @Test("U18: 5 samples 1.0 s apart -> the first dropped, samples 2-5 kept, 8 captures")
    func fiveSamples() throws {
        let samples = Fixture.series(5, from: 11, spacing: 1.0)
        let selection = try Cadence.baseline(samples, lastChange: 10, parameters: p).get()
        #expect(selection.all == samples.map(\.sample))
        #expect(selection.kept == samples.dropFirst().map(\.sample))
        #expect(selection.keptCaptures.count == 8)
    }

    @Test("U18: 4 samples -> no baseline, although the frozen minimum is met; 6 -> none either", arguments: [4, 6])
    func wrongCount(count: Int) {
        let samples = Fixture.series(count, from: 11, spacing: 1.0)
        #expect(throws: CadenceRefusal.sampleCount(count)) { try Cadence.baseline(samples, lastChange: 10, parameters: p).get() }
    }

    @Test("settle: the first sample starts >= 1.0 s after the last change")
    func settle() throws {
        let samples = Fixture.series(5, from: 10.9, spacing: 1.0)
        #expect(throws: CadenceRefusal.settle) { try Cadence.baseline(samples, lastChange: 10, parameters: p).get() }
        #expect(throws: Never.self) { try Cadence.baseline(Fixture.series(5, from: 11, spacing: 1.0), lastChange: 10, parameters: p).get() }
    }

    @Test("a baseline gap under 1.0 s refuses it")
    func spacing() {
        var samples = Fixture.series(5, from: 11, spacing: 1.0)
        samples[3] = Fixture.timed(13.95)
        #expect(throws: CadenceRefusal.spacing(index: 3)) { try Cadence.baseline(samples, lastChange: 10, parameters: p).get() }
    }

    @Test("a baseline spanning more than 10 s is a timeout; exactly 10 s is not")
    func timeout() {
        let late = Fixture.series(4, from: 11, spacing: 1.0) + [Fixture.timed(20.95)]
        #expect(throws: CadenceRefusal.timeout) { try Cadence.baseline(late, lastChange: 10, parameters: p).get() }
        let edge = Fixture.series(4, from: 11, spacing: 1.0) + [Fixture.timed(20.9)]
        #expect(throws: Never.self) { try Cadence.baseline(edge, lastChange: 10, parameters: p).get() }
    }

    @Test("an attempt: 3 samples >= 0.5 s apart, not before its earliest start")
    func attempt() {
        #expect(Cadence.attempt(Fixture.series(3, from: 20, spacing: 0.5), notBefore: 20, parameters: p) == nil)
        #expect(Cadence.attempt(Fixture.series(2, from: 20, spacing: 0.5), notBefore: 20, parameters: p) == .sampleCount(2))
        #expect(Cadence.attempt(Fixture.series(3, from: 20, spacing: 0.4), notBefore: 20, parameters: p) == .spacing(index: 1))
        #expect(Cadence.attempt(Fixture.series(3, from: 19.9, spacing: 0.5), notBefore: 20, parameters: p) == .settle)
    }

    @Test("the next attempt starts >= 1.0 s after the previous one ended; the first after the settle")
    func attemptStarts() {
        let first = Fixture.series(3, from: 20, spacing: 0.5)
        #expect(Cadence.nextAttemptStart(after: first, parameters: p) == 22.1)
        #expect(Cadence.firstAttemptStart(lastChange: 18.5, parameters: p) == 19.5)
    }

    @Test("an observation spanning more than 10 s, over all its attempts, times out")
    func observationTimeout() {
        let a1 = Fixture.series(3, from: 20, spacing: 0.5)
        let a3 = Fixture.series(3, from: 28.9, spacing: 0.5)
        #expect(!Cadence.observationTimedOut([a1, a3], parameters: p))
        let late = Fixture.series(3, from: 29.0, spacing: 0.5)
        #expect(Cadence.observationTimedOut([a1, late], parameters: p))
        #expect(!Cadence.observationTimedOut([], parameters: p))
    }

    @Test("the 4 observations of a cycle start nominally 5 s apart")
    func observationStarts() {
        #expect((0..<4).map { Cadence.observationStart($0, first: 30, parameters: p) } == [30, 35, 40, 45])
    }
}
