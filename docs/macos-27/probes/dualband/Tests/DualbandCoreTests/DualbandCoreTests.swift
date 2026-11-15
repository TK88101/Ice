import Testing
@testable import DualbandCore

@Suite("Judge")
struct JudgeTests {
    func strip(_ width: Int, _ height: Int, fill: UInt8 = 20, marks: [(Int, Int, UInt8)] = []) -> GrayStrip {
        var pixels = [UInt8](repeating: fill, count: width * height)
        for (x, y, v) in marks { pixels[y * width + x] = v }
        return GrayStrip(width: width, height: height, pixels: pixels)
    }

    @Test("an empty bar beside the standard strip hides")
    func emptyHides() throws {
        let standard = strip(100, 4, marks: (60..<80).map { ($0, 1, 240) })
        let reading = try Judge.read(sample: strip(100, 4), standard: standard, spot: 60..<80)
        #expect(reading == BarReading(newForeground: 0, spotForeground: 0))
        #expect(reading.hides)
    }

    @Test("members still in the spot do not hide")
    func spotDrawn() throws {
        let standard = strip(100, 4, marks: (60..<80).map { ($0, 1, 240) })
        let sample = strip(100, 4, marks: (60..<80).flatMap { [($0, 1, 240), ($0, 2, 240)] }.filter { $0.0 % 2 == 0 })
        let reading = try Judge.read(sample: sample, standard: standard, spot: 60..<80)
        #expect(reading.spotForeground == 20)
        #expect(!reading.hides)
    }

    @Test("a member or chevron drawn left of the spot does not hide; menus unchanged do not count")
    func drawnLeft() throws {
        let menus = (0..<20).map { ($0, 1, UInt8(200)) }
        let standard = strip(100, 4, marks: menus)
        let sample = strip(100, 4, marks: menus + (30..<45).flatMap { [($0, 1, 230), ($0, 2, 230)] })
        let reading = try Judge.read(sample: sample, standard: standard, spot: 60..<80)
        #expect(reading.newForeground == 30)
        #expect(!reading.hides)
        #expect(try Judge.read(sample: standard, standard: standard, spot: 60..<80).newForeground == 0)
    }

    @Test("changes inside the pad next to the spot are ignored; at the threshold they do not count")
    func padAndThreshold() throws {
        let standard = strip(100, 1)
        let padded = strip(100, 1, marks: [(57, 0, 250), (10, 0, UInt8(20 + Judge.changeThreshold))])
        #expect(try Judge.read(sample: padded, standard: standard, spot: 60..<80).newForeground == 0)
    }

    @Test("noise up to the allowance still hides, one more does not")
    func allowance() {
        #expect(BarReading(newForeground: Judge.maxNewForeground, spotForeground: Judge.maxSpotForeground).hides)
        #expect(!BarReading(newForeground: Judge.maxNewForeground + 1, spotForeground: 0).hides)
        #expect(!BarReading(newForeground: 0, spotForeground: Judge.maxSpotForeground + 1).hides)
    }

    @Test("mismatched strips and bad spots are refused")
    func refusals() {
        #expect(throws: JudgeRefusal.sizeMismatch) { try Judge.read(sample: strip(10, 2), standard: strip(11, 2), spot: 2..<4) }
        #expect(throws: JudgeRefusal.emptySpot) { try Judge.read(sample: strip(10, 2), standard: strip(10, 2), spot: 3..<3) }
        #expect(throws: JudgeRefusal.spotOutOfStrip) { try Judge.read(sample: strip(10, 2), standard: strip(10, 2), spot: 5..<11) }
        #expect(throws: JudgeRefusal.spotOutOfStrip) { try Judge.read(sample: strip(10, 2), standard: strip(10, 2), spot: -1..<3) }
    }

    @Test("excluded columns are never compared, left of the spot or inside it")
    func exclusion() throws {
        let standard = strip(100, 1)
        let sample = strip(100, 1, marks: (20..<40).map { ($0, 0, 250) } + (62..<70).map { ($0, 0, 250) } + [(61, 0, 20)])
        let plain = try Judge.read(sample: sample, standard: standard, spot: 60..<80)
        #expect(plain.newForeground == 20 && plain.spotForeground == 8)
        let masked = try Judge.read(sample: sample, standard: standard, spot: 60..<80, excluded: [20..<40, 60..<72])
        #expect(masked == BarReading(newForeground: 0, spotForeground: 0))
        #expect(try Judge.read(sample: sample, standard: standard, spot: 60..<80, excluded: [0..<100]).spotForeground == 0)
    }

    @Test("a near-black full-height blob is found and widened; a dark glyph of part height is not")
    func blobs() {
        var marks: [(Int, Int, UInt8)] = []
        for x in 30..<40 { for y in 0..<10 { marks.append((x, y, 5)) } }
        for y in 0..<4 { marks.append((70, y, 5)) }
        let bar = strip(100, 10, fill: 120, marks: marks)
        #expect(Judge.darkBlobs(in: bar) == [22..<48])
        #expect(Judge.darkBlobs(in: strip(100, 10, fill: 120)) == [])
        #expect(Judge.darkBlobs(in: strip(10, 2, fill: 0)) == [0..<10])
    }

    @Test("a spot at the left edge compares nothing left of it")
    func spotAtEdge() throws {
        #expect(try Judge.read(sample: strip(10, 1, marks: [(0, 0, 250)]), standard: strip(10, 1), spot: 0..<3).newForeground == 0)
    }
}

@Suite("Sweep")
struct SweepTests {
    @Test("the coarse grid runs 64 to 3000 by 64, and further when asked")
    func coarse() {
        let grid = Sweep.coarseGrid()
        #expect(grid.first == 64 && grid.last == 2944 && grid.count == 46)
        #expect(Sweep.coarseGrid(upTo: 4000).last == 3968)
    }

    @Test("transitions are where hides changes, at the upper length")
    func transitions() {
        let readings: [(length: Double, hides: Bool)] = [(128, false), (64, false), (192, true), (256, true), (320, false)]
        #expect(Sweep.transitions(readings) == [192, 320])
        #expect(Sweep.transitions([]) == [])
        #expect(!Sweep.changingAtTop(readings.filter { $0.length < 300 }))
        #expect(Sweep.changingAtTop(readings))
        #expect(!Sweep.changingAtTop([(64, true)]))
    }

    @Test("the fine grid covers +-128 by 16 around each transition, positive only, merged")
    func fine() {
        #expect(Sweep.fineGrid(around: [64]) == stride(from: 16.0, through: 192, by: 16).map { $0 })
        #expect(Sweep.fineGrid(around: [640, 700]).count == Set(Sweep.fineGrid(around: [640]) + Sweep.fineGrid(around: [700])).count)
        #expect(Sweep.fineGrid(around: []) == [])
    }

    @Test("a point hides for a bar only if every reading in every condition hides and every condition read it")
    func hidingPoints() {
        let c1: [Double: [Bool]] = [700: [true, true, true], 716: [true, false, true], 732: [true]]
        let c2: [Double: [Bool]] = [700: [true], 716: [true], 732: []]
        #expect(Sweep.hidingPoints([c1, c2]) == [700])
        #expect(Sweep.hidingPoints([c1, [700: [true]]]) == [700])
        #expect(Sweep.hidingPoints([]) == [])
    }

    @Test("rule A picks the shared measured point of largest margin, at least 32 pt each side")
    func decideA() {
        let builtin = Set(stride(from: 640.0, through: 832, by: 16))
        let sidecar = Set(stride(from: 704.0, through: 960, by: 16))
        // shared 704...832: 9 points, centre 768 has margin 64.
        #expect(Sweep.decide(builtin: builtin, sidecar: sidecar, inconclusive: false) == .a(length: 768))
    }

    @Test("rule D: no shared point, margin too small, or anything inconclusive")
    func decideD() {
        let builtin = Set(stride(from: 640.0, through: 832, by: 16))
        #expect(Sweep.decide(builtin: builtin, sidecar: [900, 916], inconclusive: false) == .d(reason: "no shared point"))
        #expect(Sweep.decide(builtin: builtin, sidecar: [800, 816, 832], inconclusive: false) == .d(reason: "margin under 32 pt"))
        #expect(Sweep.decide(builtin: builtin, sidecar: builtin, inconclusive: true) == .d(reason: "inconclusive"))
        // A gap breaks the margin.
        #expect(Sweep.decide(builtin: [700, 716, 748, 764], sidecar: [700, 716, 748, 764], inconclusive: false) == .d(reason: "margin under 32 pt"))
    }

    @Test("ties keep the shorter length")
    func tie() {
        let both = Set(stride(from: 700.0, through: 780, by: 16)) // 700...780: 6 points; 732 and 748 both margin 32
        #expect(Sweep.decide(builtin: both, sidecar: both, inconclusive: false) == .a(length: 732))
    }
}
