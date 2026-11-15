import Testing
@testable import IceCore

/// On macOS 27.2 an item that appears left of the lengthened divider is in no
/// read (plan 2026-11-15-blind-at-length, D4): a re-read at standard length is
/// owed after an app was started, until a trusted pass has begun late enough
/// after it to have read that app's item.
@Suite("ArrivalRule")
struct ArrivalRuleTests {
    @Test("no app was started: nothing is owed")
    func noLaunch() {
        #expect(!ArrivalRule.isRereadOwed(lastLaunchAt: nil, trustedPassBeganAt: nil))
        #expect(!ArrivalRule.isRereadOwed(lastLaunchAt: nil, trustedPassBeganAt: 50))
    }

    @Test("an app was started and no trusted pass was ever taken: owed")
    func launchAndNoPass() {
        #expect(ArrivalRule.isRereadOwed(lastLaunchAt: 100, trustedPassBeganAt: nil))
    }

    @Test("a trusted pass from before the launch does not pay")
    func passBeforeLaunch() {
        #expect(ArrivalRule.isRereadOwed(lastLaunchAt: 100, trustedPassBeganAt: 99))
    }

    @Test("a trusted pass begun within the grace after the launch does not pay: the app may not have its item yet")
    func passWithinGrace() {
        #expect(ArrivalRule.isRereadOwed(lastLaunchAt: 100, trustedPassBeganAt: 100.5))
        #expect(ArrivalRule.isRereadOwed(lastLaunchAt: 100, trustedPassBeganAt: 102.9))
    }

    @Test("a trusted pass begun the grace or more after the launch pays")
    func passAfterGrace() {
        #expect(!ArrivalRule.isRereadOwed(lastLaunchAt: 100, trustedPassBeganAt: 103))
        #expect(!ArrivalRule.isRereadOwed(lastLaunchAt: 100, trustedPassBeganAt: 250))
    }

    @Test("a later launch owes again")
    func laterLaunch() {
        #expect(ArrivalRule.isRereadOwed(lastLaunchAt: 260, trustedPassBeganAt: 250))
    }

    @Test("the grace is three seconds unless given")
    func graceValue() {
        #expect(ArrivalRule.grace == 3)
        #expect(!ArrivalRule.isRereadOwed(lastLaunchAt: 100, trustedPassBeganAt: 101, grace: 1))
    }
}
