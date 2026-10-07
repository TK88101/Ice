import Foundation
import Testing
@testable import IceWatchCore

/// `icewatch references` (plan 2026-10-07-icebar-menu-frame-fix, section 11):
/// one JSON line saying whether Ice's baseline will find a reference on this
/// bar, and where the run's own helpers are. Other apps' items are counted,
/// never named.
@Suite("ReferencesReport")
struct ReferencesReportTests {
    @Test("the keys, sorted; helpers by id with their side")
    func line() throws {
        let line = ReferencesReport.line(
            complete: true, items: 6, dividerMinX: 1200, iceIconMidX: 1310.5, references: 1,
            helpers: [.init(id: "vz-t7-ref1", x: 1250, side: "visible"), .init(id: "vz-t7-hidden2", x: 1100, side: "hidden")],
            others: [.init(namespace: "com.example.a", basis: "declared", position: "onBar", x: 1000, side: "hidden")]
        )
        #expect(line == #"{"complete":true,"dividerMinX":1200,"helpers":[{"id":"vz-t7-ref1","side":"visible","x":1250},{"id":"vz-t7-hidden2","side":"hidden","x":1100}],"iceIconMidX":1310.5,"items":6,"otherHidden":1,"others":[{"basis":"declared","namespace":"com.example.a","position":"onBar","side":"hidden","x":1000}],"otherVisible":0,"references":1}"#)
    }

    @Test("Ice's items not found: nulls, no reference")
    func noIce() throws {
        let line = ReferencesReport.line(complete: false, items: 1, dividerMinX: nil, iceIconMidX: nil, references: 0, helpers: [.init(id: "vz-t7-ref1", x: nil, side: "unknown")], others: [])
        let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(object["dividerMinX"] is NSNull)
        #expect(object["iceIconMidX"] is NSNull)
        #expect(object["references"] as? Int == 0)
        #expect(object["complete"] as? Bool == false)
    }

    @Test("which side of Ice's divider and icon a point is on")
    func side() {
        #expect(ReferencesReport.side(midX: 1100, dividerMinX: 1200, iceIconMidX: 1310) == "hidden")
        #expect(ReferencesReport.side(midX: 1250, dividerMinX: 1200, iceIconMidX: 1310) == "visible")
        #expect(ReferencesReport.side(midX: 1400, dividerMinX: 1200, iceIconMidX: 1310) == "rightOfIce")
        #expect(ReferencesReport.side(midX: nil, dividerMinX: 1200, iceIconMidX: 1310) == "unknown")
        #expect(ReferencesReport.side(midX: 1250, dividerMinX: nil, iceIconMidX: 1310) == "unknown")
        #expect(ReferencesReport.side(midX: 1250, dividerMinX: 1200, iceIconMidX: nil) == "visible")
    }
}
