import Testing
@testable import C1Core

/// Section 3 condition 1: "the order from AX and from pixels agree: Target,
/// then the spacer, leftmost of every rendered item (user and system);
/// Target is the only item left of the spacer."
@Suite("PreflightOrderCheck")
struct PreflightOrderCheckTests {
    let target = "vz-target"
    let spacer = "vz-spacer"

    @Test("AX and pixels agree, Target then the spacer leftmost -> passes")
    func agree() {
        let order = [target, spacer, "vz-protected", "owner-1"]
        #expect(PreflightOrderCheck.check(axOrder: order, pixelOrder: order, target: target, spacer: spacer) == nil)
    }

    @Test("AX and pixels disagree about order -> disagree")
    func disagree() {
        let ax = [target, spacer, "owner-1"]
        let pixels = [target, "owner-1", spacer]
        #expect(PreflightOrderCheck.check(axOrder: ax, pixelOrder: pixels, target: target, spacer: spacer) == .disagree)
    }

    @Test("something else is leftmost of Target -> targetNotLeftmost")
    func targetNotLeftmost() {
        let order = ["owner-1", target, spacer]
        #expect(PreflightOrderCheck.check(axOrder: order, pixelOrder: order, target: target, spacer: spacer) == .targetNotLeftmost)
    }

    @Test("an extra item sits between Target and the spacer on both readings -> targetNotAloneLeftOfSpacer")
    func extraItemBetweenTargetAndSpacer() {
        let order = [target, "owner-1", spacer]
        #expect(PreflightOrderCheck.check(axOrder: order, pixelOrder: order, target: target, spacer: spacer) == .targetNotAloneLeftOfSpacer)
    }

    @Test("the spacer is missing from the order entirely -> targetNotAloneLeftOfSpacer")
    func spacerMissing() {
        let order = [target, "owner-1"]
        #expect(PreflightOrderCheck.check(axOrder: order, pixelOrder: order, target: target, spacer: spacer) == .targetNotAloneLeftOfSpacer)
    }

    @Test("Target alone with nothing else on the bar -> targetNotAloneLeftOfSpacer (the spacer must also be there)")
    func targetAloneNoSpacer() {
        let order = [target]
        #expect(PreflightOrderCheck.check(axOrder: order, pixelOrder: order, target: target, spacer: spacer) == .targetNotAloneLeftOfSpacer)
    }

    @Test("an extra item appears only on the pixel side, displacing the spacer later -> disagree, not silently accepted")
    func extraItemOnDisplacedSidePixelsOnly() {
        let ax = [target, spacer, "owner-1"]
        let pixels = [target, spacer, "phantom", "owner-1"]
        #expect(PreflightOrderCheck.check(axOrder: ax, pixelOrder: pixels, target: target, spacer: spacer) == .disagree)
    }
}
