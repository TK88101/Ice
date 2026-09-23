import Testing
@testable import IceCore

/// Whether a capture can be trusted at all, decided from items the action does
/// not touch. A necessary condition, never a sufficient one: it catches the bar
/// sliding through a Space switch and a global appearance flip, not a change
/// under one item, which the matcher's second pass handles.
@Suite("CaptureStability")
struct CaptureStabilityTests {
    let params = DetectorParameters.preRegistered
    let ink = Ink(colours: [ColorMatch(center: Paint.white, tolerance: 70)])

    func template(_ id: String, atPt x: Double) throws -> ItemTemplate {
        var canvas = Canvas()
        canvas.draw(.flag, atPt: x)
        let frame = ItemFrame(id: id, minX: x - 1, minY: 0, width: 7, height: 12)
        return try #require(ItemTemplate.cut(frame, from: canvas.image, ink: ink, geometry: canvas.geometry(), parameters: params).template)
    }

    func stable(_ references: [String], _ templates: [String: ItemTemplate], _ captures: [[String: Match]]) -> Bool {
        CaptureStability.isStable(references: references, templates: templates, captures: captures, parameters: params)
    }

    @Test("every reference found where it was baselined, in every capture, is stable")
    func allReferencesInPlace() throws {
        let reference = try template("reference", atPt: 150)
        let sighting: [String: Match] = ["reference": .unique(x: reference.originXPt, mismatch: 0.01)]
        #expect(stable(["reference"], ["reference": reference], [sighting, sighting]))
    }

    @Test("no reference at all is not stable: nothing vouches for the capture")
    func noReferences() throws {
        let reference = try template("reference", atPt: 150)
        #expect(!stable([], ["reference": reference], [["reference": .unique(x: 149, mismatch: 0)]]))
    }

    @Test("a reference named twice is not stable")
    func duplicateReference() throws {
        let reference = try template("reference", atPt: 150)
        let sighting: [String: Match] = ["reference": .unique(x: reference.originXPt, mismatch: 0)]
        #expect(!stable(["reference", "reference"], ["reference": reference], [sighting, sighting]))
    }

    @Test("a reference missing from one capture is not stable")
    func referenceMissingFromOneCapture() throws {
        let reference = try template("reference", atPt: 150)
        let present: [String: Match] = ["reference": .unique(x: reference.originXPt, mismatch: 0)]
        #expect(!stable(["reference"], ["reference": reference], [present, [:]]))
    }

    @Test("a reference with no template is not stable")
    func referenceWithoutTemplate() throws {
        let reference = try template("reference", atPt: 150)
        #expect(!stable(["other"], ["reference": reference], [["other": .unique(x: 149, mismatch: 0)]]))
    }

    @Test("a reference that moved past the tolerance is not stable")
    func referenceMoved() throws {
        let reference = try template("reference", atPt: 150)
        let moved: [String: Match] = ["reference": .unique(x: reference.originXPt + 1.5, mismatch: 0)]
        #expect(!stable(["reference"], ["reference": reference], [moved]))
        let nudged: [String: Match] = ["reference": .unique(x: reference.originXPt + 1, mismatch: 0)]
        #expect(stable(["reference"], ["reference": reference], [nudged]))
    }

    @Test("a reference found only weakly, ambiguously or not at all is not stable")
    func referenceNotStronglyFound() throws {
        let reference = try template("reference", atPt: 150)
        let weak: [String: Match] = ["reference": .unique(x: reference.originXPt, mismatch: 0.07)]
        let ambiguous: [String: Match] = ["reference": .ambiguous(count: 2)]
        let absent: [String: Match] = ["reference": .absent(bestMismatch: 0.4)]
        for capture in [weak, ambiguous, absent] {
            #expect(!stable(["reference"], ["reference": reference], [capture]))
        }
    }

    @Test("no captures at all is not stable")
    func noCaptures() throws {
        let reference = try template("reference", atPt: 150)
        #expect(!stable(["reference"], ["reference": reference], []))
    }
}

/// What the item's own Accessibility frame says about a match. It can only
/// veto: nothing here ever makes an item drawn, and absence never consults it,
/// because Accessibility keeps laying out items the screen does not draw.
@Suite("Placement")
struct PlacementTests {
    let params = DetectorParameters.preRegistered
    let geometry = BarGeometry(widthPt: 1728, heightPt: 32, scale: 2, notch: PtSpan(lo: 640, hi: 1088))

    func placement(frame: ItemFrame?, matchX: Double, matchWidth: Double = 7) -> Placement {
        Placement.assess(frame: frame, matchX: matchX, matchWidthPt: matchWidth, geometry: geometry, parameters: params)
    }

    @Test("a frame on this bar, over the match, agrees with it")
    func frameOverTheMatch() {
        let frame = ItemFrame(id: "a", minX: 1200, minY: 0, width: 12, height: 32)
        #expect(placement(frame: frame, matchX: 1201) == .consistent)
    }

    @Test("a parked item's frame contradicts any match")
    func parkedFrame() {
        let frame = ItemFrame(id: "a", minX: 7, minY: 1104, width: 12, height: 32)
        #expect(placement(frame: frame, matchX: 7) == .inconsistent)
    }

    @Test("a frame elsewhere on the bar contradicts the match")
    func frameElsewhere() {
        let frame = ItemFrame(id: "a", minX: 1200, minY: 0, width: 12, height: 32)
        #expect(placement(frame: frame, matchX: 1400) == .inconsistent)
    }

    @Test("the slack is four points on either side")
    func slackBoundary() {
        let frame = ItemFrame(id: "a", minX: 1200, minY: 0, width: 12, height: 32)
        #expect(placement(frame: frame, matchX: 1215) == .consistent)   // 3 pt past the frame
        #expect(placement(frame: frame, matchX: 1217) == .inconsistent) // 5 pt past it
    }

    @Test("no frame at all is unavailable, which is not consent")
    func noFrame() {
        #expect(placement(frame: nil, matchX: 1200) == .unavailable)
    }

    @Test("a frame outside the display contradicts the match")
    func frameOutsideDisplay() {
        let frame = ItemFrame(id: "a", minX: 1800, minY: 0, width: 12, height: 32)
        #expect(placement(frame: frame, matchX: 1800) == .inconsistent)
    }
}
