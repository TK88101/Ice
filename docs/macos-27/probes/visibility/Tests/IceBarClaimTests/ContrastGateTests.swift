// U8 (pre-registration section 7): the contrast gate, measured on the visible
// helpers at the oracle's placement (claim plan R11-R13).
@testable import IceBarClaim
@testable import IceBarOracle
import IceCore
import Testing

@Suite("U8: contrast gate")
struct ContrastGateTests {
    func grey(_ v: Int) -> RGB3 { (UInt8(v), UInt8(v), UInt8(v)) }

    @Test("U8: C_r = 129 is accepted, 128 refused", arguments: [(169, 129, true), (168, 128, false)])
    func contrast(ink: Int, cR: Int, accepted: Bool) {
        let verdict = Bar.verdict(Bar.samples(Bar.strip(targetInk: grey(ink)).image))
        #expect(verdict.measurements.contrast?.cR == cR)
        #expect(verdict.failedClauses == (accepted ? [] : [.contrast]))
    }

    @Test("U8: M_x within T_bg of M_r is accepted, T_bg + 1 refused", arguments: [(32, true), (33, false)])
    func regionMedian(delta: Int, accepted: Bool) {
        var strip = Bar.strip()
        strip.fill(Bar.regionColumns, grey(40 + delta))
        let verdict = Bar.verdict(Bar.samples(strip.image))
        #expect(verdict.measurements.contrast?.mxToMr == delta)
        #expect(verdict.failedClauses == (accepted ? [] : [.contrast]))
    }

    @Test("U8: one region row median T_bg + 1 off M_x fails the gate; the texture bound refuses first (R15)",
          arguments: [(32, [BaselineRefusal.texture]), (33, [.texture, .contrast])])
    func rowMedian(delta: Int, failed: [BaselineRefusal]) {
        var strip = Bar.strip()
        strip.fill(Bar.regionColumns, rows: 5..<6, grey(40 + delta))
        let verdict = Bar.verdict(Bar.samples(strip.image))
        #expect(verdict.measurements.contrast?.maxRowMedianToMx == delta)
        #expect(verdict.failedClauses == failed)
        #expect(verdict.outcome == .refused(.texture))
    }

    @Test("R11: the gate cannot be measured without a well-formed visible roster, all drawn in full")
    func unmeasurable() {
        let samples = Bar.samples(Bar.strip().image)
        let visible = Bar.visible
        let rescaled = visible.map { OracleTemplate(id: $0.id, width: $0.width, height: $0.height, alpha: $0.alpha, scale: 1) }
        for roster in [[], Array(visible.dropFirst()), visible + [visible[0]], rescaled] {
            #expect(Bar.verdict(samples, visible: roster).outcome == .refused(.contrastUnmeasurable))
        }
        var erased = Bar.strip()
        erased.fill(700..<720, Bar.dark)
        #expect(Bar.verdict(Bar.samples(erased.image)).outcome == .refused(.contrastUnmeasurable))
    }

    @Test("R11: the gate's placement is the oracle's own best placement (D12)")
    func placement() throws {
        let image = Bar.strip().image
        let context = OracleContext(notch: Bar.notch, agentFrames: Bar.agentFrames.map(\.span), leftmostReferenceOriginPt: 300)
        let geometry = OracleGeometry(widthPx: image.width, heightPx: image.height, scale: 2, context: context)
        let labels = try Oracle.label(image: image, helpers: Bar.visible, chevron: nil, context: context)
        for template in Bar.visible {
            let found = try #require(labels.matches[template.id])
            let chosen = try #require(ContrastGate.best(found, template: template, geometry: geometry))
            #expect(chosen == Oracle.best(found, template: template, geometry: geometry))
            guard case let .drawn(.full, x, _)? = labels.labels[template.id] else {
                Issue.record("\(template.id) not drawn")
                continue
            }
            #expect(Double(chosen.xPx) / 2 + 1.5 == x)
        }
    }

    @Test("R11: the D12 re-implementation orders exactly as the oracle's")
    func ordering() {
        let template = Bar.visible[0]
        let geometry = OracleGeometry(widthPx: 800, heightPx: 48, scale: 2, context: OracleContext(notch: nil, agentFrames: [], leftmostReferenceOriginPt: nil))
        let cases: [[IceBarOracle.Placement]] = [
            [IceBarOracle.Placement(xPx: 5, yPx: 14, matchClass: .full, hits: 90, visibleOn: 100, falses: 0, visibleOff: 50),
             IceBarOracle.Placement(xPx: 4, yPx: 14, matchClass: .full, hits: 95, visibleOn: 100, falses: 0, visibleOff: 50)],
            [IceBarOracle.Placement(xPx: 5, yPx: 14, matchClass: .full, hits: 95, visibleOn: 100, falses: 2, visibleOff: 50),
             IceBarOracle.Placement(xPx: 6, yPx: 14, matchClass: .full, hits: 95, visibleOn: 100, falses: 1, visibleOff: 50)],
            [IceBarOracle.Placement(xPx: 5, yPx: 11, matchClass: .full, hits: 95, visibleOn: 100, falses: 1, visibleOff: 50),
             IceBarOracle.Placement(xPx: 6, yPx: 15, matchClass: .full, hits: 95, visibleOn: 100, falses: 1, visibleOff: 50)],
            [IceBarOracle.Placement(xPx: 7, yPx: 14, matchClass: .full, hits: 95, visibleOn: 100, falses: 1, visibleOff: 50),
             IceBarOracle.Placement(xPx: 6, yPx: 14, matchClass: .full, hits: 95, visibleOn: 100, falses: 1, visibleOff: 50)],
            [IceBarOracle.Placement(xPx: 7, yPx: 14, matchClass: .partial, hits: 99, visibleOn: 100, falses: 0, visibleOff: 50),
             IceBarOracle.Placement(xPx: 6, yPx: 14, matchClass: .full, hits: 91, visibleOn: 100, falses: 1, visibleOff: 50)],
        ]
        for found in cases {
            let expected = Oracle.best(found, template: template, geometry: geometry)
            #expect(ContrastGate.best(found, template: template, geometry: geometry) == expected)
            #expect(ContrastGate.best(found.reversed(), template: template, geometry: geometry) == expected)
        }
    }
}
