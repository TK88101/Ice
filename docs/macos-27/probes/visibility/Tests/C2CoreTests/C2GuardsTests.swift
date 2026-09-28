import C2Core
import Testing

@Suite("C2Guards")
struct C2GuardsTests {
    @Test("only the expected isolated account, never the owner's, never empty")
    func user() {
        #expect(C2Guards.userAllowed(current: "icetest", expected: "icetest", owner: "owner"))
        #expect(!C2Guards.userAllowed(current: "owner", expected: "owner", owner: "owner"))
        #expect(!C2Guards.userAllowed(current: "other", expected: "icetest", owner: "owner"))
        #expect(!C2Guards.userAllowed(current: "", expected: "", owner: "owner"))
    }

    @Test("only system items, and at least one")
    func roster() {
        #expect(C2Guards.rosterAllowed(bundleIDs: ["com.apple.MenuBarAgent", "com.apple.controlcenter"]))
        #expect(!C2Guards.rosterAllowed(bundleIDs: ["com.apple.MenuBarAgent", "com.example.app"]))
        #expect(!C2Guards.rosterAllowed(bundleIDs: []))
    }

    @Test("geometry spec parses with or without a notch, and matches within 0.5 pt")
    func geometry() {
        let notched = C2Guards.Geometry(spec: "1728x32:771.5-956.5")
        #expect(notched == C2Guards.Geometry(widthPt: 1728, heightPt: 32, notchLo: 771.5, notchHi: 956.5))
        #expect(C2Guards.Geometry(spec: "1440x24") == C2Guards.Geometry(widthPt: 1440, heightPt: 24, notchLo: nil, notchHi: nil))
        for bad in ["1728", "x32", "1728x32:956.5-771.5", "1728x32:abc", "1728x32:1-2-3"] {
            #expect(C2Guards.Geometry(spec: bad) == nil)
        }
        let live = C2Guards.Geometry(widthPt: 1728.3, heightPt: 32, notchLo: 771.5, notchHi: 956.9)
        #expect(notched?.matches(live) == true)
        #expect(notched?.matches(C2Guards.Geometry(widthPt: 1728, heightPt: 32, notchLo: 771.5, notchHi: 958)) == false)
        #expect(notched?.matches(C2Guards.Geometry(widthPt: 1728, heightPt: 32, notchLo: nil, notchHi: nil)) == false)
        let flat = C2Guards.Geometry(spec: "1440x24")
        #expect(flat?.matches(C2Guards.Geometry(widthPt: 1440, heightPt: 24, notchLo: nil, notchHi: nil)) == true)
    }
}
