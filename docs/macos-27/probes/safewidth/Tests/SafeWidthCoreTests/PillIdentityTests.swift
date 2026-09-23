// PillIdentity: which leading MenuBarAgent item is the microphone pill, and
// whether it is drawn. The overflow chevron stands in the same place, so the
// pill has to be told apart from it without relying on the pill being drawn:
// a pill pushed out of the bar draws nothing, which is the case the rule exists for.
import Testing
@testable import SafeWidthCore

@Suite("PillIdentity.reading")
struct PillIdentityTests {
    let minimum = 40
    let chevron = PillIdentity.chevronWidth

    @Test("no candidate is no pill")
    func noCandidate() {
        #expect(PillIdentity.reading([], orangeMinimum: minimum) == nil)
    }

    @Test("a chevron-wide item drawing no orange is the chevron, not the pill")
    func chevronAloneIsNotThePill() {
        let reading = PillIdentity.reading([PillCandidate(width: chevron, orange: 0)], orangeMinimum: minimum)
        #expect(reading == nil)
    }

    @Test("an item of any other width drawing no orange is a hidden pill")
    func otherWidthWithoutOrangeIsHidden() {
        let reading = PillIdentity.reading([PillCandidate(width: 37, orange: 0)], orangeMinimum: minimum)
        #expect(reading == PillReading(axPresent: true, pixelPresent: false))
    }

    @Test("an item drawing the pill's orange is a drawn pill, whatever its width")
    func orangeMeansDrawn() {
        for width in [chevron, 37.0] {
            let reading = PillIdentity.reading([PillCandidate(width: width, orange: minimum)], orangeMinimum: minimum)
            #expect(reading == PillReading(axPresent: true, pixelPresent: true))
        }
    }

    @Test("one orange pixel short of the minimum is not drawn")
    func orangeBoundary() {
        let reading = PillIdentity.reading([PillCandidate(width: 37, orange: minimum - 1)], orangeMinimum: minimum)
        #expect(reading == PillReading(axPresent: true, pixelPresent: false))
    }

    @Test("the chevron beside a hidden pill does not mask it")
    func chevronBesideHiddenPill() {
        let reading = PillIdentity.reading(
            [PillCandidate(width: chevron, orange: 0), PillCandidate(width: 37, orange: 0)],
            orangeMinimum: minimum
        )
        #expect(reading == PillReading(axPresent: true, pixelPresent: false))
    }

    @Test("the chevron beside a drawn pill reads as a drawn pill")
    func chevronBesideDrawnPill() {
        let reading = PillIdentity.reading(
            [PillCandidate(width: chevron, orange: 0), PillCandidate(width: 37, orange: 120)],
            orangeMinimum: minimum
        )
        #expect(reading == PillReading(axPresent: true, pixelPresent: true))
    }

    @Test("the chevron's width tolerance is inclusive")
    func widthToleranceBoundary() {
        let edge = chevron + PillIdentity.chevronWidthTolerance
        #expect(PillIdentity.reading([PillCandidate(width: edge, orange: 0)], orangeMinimum: minimum) == nil)
        #expect(PillIdentity.reading([PillCandidate(width: edge + 0.5, orange: 0)], orangeMinimum: minimum)
            == PillReading(axPresent: true, pixelPresent: false))
    }
}
