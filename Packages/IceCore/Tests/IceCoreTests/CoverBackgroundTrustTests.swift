import Testing
@testable import IceCore

/// Plan 2026-11-18-cover-stale-and-lost, D1: a background is confirmed, not
/// trusted. The owner's Sidecar bar showed the wallpaper at half brightness
/// for as long as nothing asked for another capture.
@Suite("CoverBackgroundTrust")
struct CoverBackgroundTrustTests {
    typealias Trust = CoverBackgroundTrust

    /// The reason with an image held, the key unchanged and nothing stale.
    func idle(_ trust: Trust, _ now: Double) -> Trust.Reason? {
        trust.reason(now: now, hasUsableImage: true, keyEqual: true, stale: false)
    }

    @Test("with no image the reason is size; then the key, then stale, in that order")
    func signalOrder() {
        #expect(Trust().reason(now: 0, hasUsableImage: true, keyEqual: true, stale: false) == .size, "nothing was ever captured")
        let trust = Trust().captured(reason: .size, equal: false, at: 0)
        #expect(trust.reason(now: 0, hasUsableImage: false, keyEqual: false, stale: true) == .size)
        #expect(trust.reason(now: 0, hasUsableImage: true, keyEqual: false, stale: true) == .key)
        #expect(trust.reason(now: 0, hasUsableImage: true, keyEqual: true, stale: true) == .stale)
        #expect(trust.reason(now: 0, hasUsableImage: true, keyEqual: true, stale: false) == nil)
    }

    @Test("a new background is confirmed 12 s and 60 s after it, and then left to the refresh")
    func ladder() {
        var trust = Trust().captured(reason: .size, equal: false, at: 100)
        #expect(trust.step == 0)
        #expect(idle(trust, 111.9) == nil)
        #expect(idle(trust, 112) == .confirm)
        trust = trust.captured(reason: .confirm, equal: true, at: 112)
        #expect(trust.step == 1)
        #expect(idle(trust, 159.9) == nil)
        #expect(idle(trust, 160) == .confirm)
        trust = trust.captured(reason: .confirm, equal: true, at: 160)
        #expect(trust.step == 2)
        #expect(trust.confirmDue == nil)
        #expect(idle(trust, 160 + 1799) == nil)
        #expect(idle(trust, 160 + 1800) == .refresh)
    }

    @Test("an unequal comparison starts again 12 s later; from the fourth in a row the steps are 300 s apart")
    func unequalRuns() {
        var trust = Trust().captured(reason: .key, equal: false, at: 0)
        var now = 0.0
        for run in 1...3 {
            now += 12
            #expect(idle(trust, now) == .confirm)
            trust = trust.captured(reason: .confirm, equal: false, at: now)
            #expect(trust.unequalRun == run)
            #expect(trust.step == 0)
            #expect(idle(trust, now + 11.9) == nil)
        }
        now += 12
        trust = trust.captured(reason: .confirm, equal: false, at: now)
        #expect(trust.unequalRun == 4)
        #expect(idle(trust, now + 299) == nil)
        #expect(idle(trust, now + 300) == .confirm)
        now += 300
        trust = trust.captured(reason: .confirm, equal: false, at: now)
        #expect(idle(trust, now + 299) == nil)
        #expect(idle(trust, now + 300) == .confirm)
        // It holds still at last: the run is over, and the next step is the second confirmation.
        now += 300
        trust = trust.captured(reason: .confirm, equal: true, at: now)
        #expect(trust.unequalRun == 0)
        #expect(trust.step == 1)
        #expect(idle(trust, now + 48) == .confirm)
    }

    @Test("the waits: 12 s for the first four comparisons, 300 s after; a failed capture 12, 12, 60, then 300")
    func waits() {
        #expect((0...5).map(Trust.wait) == [12, 12, 12, 12, 300, 300])
        #expect((1...5).map(Trust.retry) == [12, 12, 60, 300, 300])
    }

    @Test("a signal's capture starts the steps again, leaves the unequal run, and never puts a confirmation off")
    func signalsDoNotRefill() {
        var trust = Trust().captured(reason: .size, equal: false, at: 0)
        for now in [12.0, 24, 36, 48] { trust = trust.captured(reason: .confirm, equal: false, at: now) }
        #expect(trust.unequalRun == 4)
        #expect(trust.confirmDue == 348)
        // Stale signals every 12 s, as a window moving under the bar gives them.
        for now in stride(from: 60.0, through: 336, by: 12) {
            trust = trust.captured(reason: .stale, equal: false, at: now)
            #expect(trust.unequalRun == 4)
            #expect(trust.step == 0)
        }
        #expect(trust.confirmDue == 348)
        #expect(idle(trust, 347.9) == nil)
        #expect(idle(trust, 348) == .confirm)
        // A signal's capture just before the deadline keeps the two strips 12 s apart.
        trust = trust.captured(reason: .key, equal: false, at: 345)
        #expect(trust.confirmDue == 357)
    }

    @Test("a signal's capture of a background that was confirmed is due for confirmation 12 s later")
    func signalAfterConfirmed() {
        var trust = Trust().captured(reason: .size, equal: false, at: 0)
        trust = trust.captured(reason: .confirm, equal: true, at: 12).captured(reason: .confirm, equal: true, at: 60)
        #expect(trust.step == 2)
        trust = trust.captured(reason: .key, equal: false, at: 500)
        #expect(trust.step == 0)
        #expect(trust.confirmDue == 512)
    }

    @Test("a refresh is a comparison too: equal keeps a confirmed background confirmed, unequal starts the steps")
    func refresh() {
        var trust = Trust().captured(reason: .size, equal: false, at: 0)
        trust = trust.captured(reason: .confirm, equal: true, at: 12).captured(reason: .confirm, equal: true, at: 60)
        let same = trust.captured(reason: .refresh, equal: true, at: 1860)
        #expect(same.step == 2)
        #expect(same.confirmDue == nil)
        #expect(idle(same, 1860 + 1800) == .refresh)
        let moved = trust.captured(reason: .refresh, equal: false, at: 1860)
        #expect(moved.step == 0)
        #expect(moved.unequalRun == 1)
        #expect(moved.confirmDue == 1872)
    }

    @Test("a capture that returns nothing is tried again at 12, 12, 60, then every 300 s, whatever is pending; one that works ends it")
    func failures() {
        var trust = Trust().captureFailed(at: 0)
        #expect(trust.reason(now: 11.9, hasUsableImage: false, keyEqual: true, stale: false) == nil)
        #expect(trust.reason(now: 12, hasUsableImage: false, keyEqual: true, stale: false) == .size)
        trust = trust.captureFailed(at: 12)
        #expect(trust.reason(now: 24, hasUsableImage: false, keyEqual: true, stale: false) == .size)
        trust = trust.captureFailed(at: 24)
        #expect(trust.failedRun == 3)
        #expect(trust.reason(now: 83, hasUsableImage: false, keyEqual: false, stale: true) == nil)
        #expect(trust.reason(now: 84, hasUsableImage: false, keyEqual: true, stale: false) == .size)
        trust = trust.captureFailed(at: 84)
        #expect(trust.reason(now: 383, hasUsableImage: false, keyEqual: true, stale: false) == nil)
        #expect(trust.reason(now: 384, hasUsableImage: false, keyEqual: true, stale: false) == .size)
        trust = trust.captured(reason: .size, equal: false, at: 384)
        #expect(trust.failedRun == 0)
        #expect(idle(trust, 396) == .confirm)
    }

    @Test("one capture that does not show the bar transparent is not believed while a transparent image is held; the next is, whatever it shows")
    func doubt() {
        var trust = Trust().captured(reason: .size, equal: false, at: 0)
        #expect(trust.believes(transparent: true, heldTransparent: true))
        #expect(trust.believes(transparent: false, heldTransparent: false), "nothing better is held")
        #expect(!trust.believes(transparent: false, heldTransparent: true))
        trust = trust.doubted(at: 12)
        #expect(trust.believes(transparent: false, heldTransparent: true), "the second in a row")
        // Nothing of the image changed: its steps, the run and the failures are as they were.
        #expect(trust.step == 0)
        #expect(trust.unequalRun == 0)
        #expect(trust.failedRun == 0)
        #expect(trust.confirmDue == 12)
    }

    @Test("a doubted capture is asked again 12 s later for the reason it was taken, and a capture that is believed ends the doubt")
    func doubtWaits() {
        var trust = Trust().captured(reason: .size, equal: false, at: 0).doubted(at: 12)
        // The budget alone would allow a second session within the same second: it would be of the same moment.
        #expect(trust.reason(now: 12.5, hasUsableImage: true, keyEqual: true, stale: true) == nil)
        #expect(idle(trust, 23.9) == nil)
        #expect(idle(trust, 24) == .confirm)
        #expect(trust.reason(now: 24, hasUsableImage: true, keyEqual: false, stale: false) == .key)
        trust = trust.captured(reason: .confirm, equal: true, at: 24)
        #expect(trust.doubtedAt == nil)
        #expect(!trust.believes(transparent: false, heldTransparent: true))
    }

    @Test("a doubt does not count as a failed capture: the first real failure after it is retried at 12 s")
    func doubtIsNoFailure() {
        var trust = Trust().captured(reason: .size, equal: false, at: 0).doubted(at: 12)
        trust = trust.captureFailed(at: 24)
        #expect(trust.failedRun == 1)
        #expect(idle(trust, 35.9) == nil)
        #expect(idle(trust, 36) == .confirm)
        #expect(trust.doubtedAt == 12, "still doubted: the next capture that works is believed")
    }

    @Test("a failed confirmation keeps the image's steps and the deadline")
    func failedConfirmation() {
        var trust = Trust().captured(reason: .size, equal: false, at: 0)
        trust = trust.captureFailed(at: 12)
        #expect(trust.step == 0)
        #expect(trust.confirmDue == 12)
        #expect(idle(trust, 20) == nil)
        #expect(idle(trust, 24) == .confirm)
    }
}
