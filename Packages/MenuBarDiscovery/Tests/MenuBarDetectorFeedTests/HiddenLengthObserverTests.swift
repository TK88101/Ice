import Testing
import IceCore
import MenuBarCapture
import MenuBarDiscovery
@testable import MenuBarDetectorFeed

/// D1's observation source on macOS 27 (plan 2026-10-03-icebar-build, section
/// 9.3): a shown baseline of every hidden-section member, then one outcome per
/// length. Driven through `HidingVerification`'s fake seams over `TestBar`.
@Suite("HiddenLengthObserver")
struct HiddenLengthObserverTests {
    static let items = HidingVerificationTests.basicItems()

    static var sectionMap: [TagKey: ItemSection] {
        Scenario.sectionMap([items.t1, items.t2]).merging(Scenario.sectionMap([items.ref], section: .visible)) { first, _ in first }
    }

    static var drawnSnapshot: MenuBarAXSnapshot {
        HidingVerificationTests.drawnSnapshot(t1: items.t1.key, t2: items.t2.key, ref: items.ref.key)
    }

    static var hiddenImage: StripImage { Scenario.image([(TestBar.shapeB, 150)]) }
    static var hiddenSnapshot: MenuBarAXSnapshot { Scenario.snapshot([(items.ref.key.encoded, 150)]) }

    static func agents(chevron: Bool) -> MenuBarAXSnapshot {
        var frames = [AgentFrame(minX: 200, minY: 0, width: 26)]
        if chevron { frames.append(AgentFrame(minX: 180, minY: 0, width: 17.5)) }
        return MenuBarAXSnapshot(itemFrames: [:], agentFrames: frames)
    }

    /// An observer whose baseline sees both members drawn, and whose
    /// observation captures and reads are the given ones.
    static func observer(
        discovery: DiscoveryResult? = Scenario.discovery([items.t1, items.t2, items.ref]),
        observeImage: StripImage = hiddenImage,
        observeSnapshot: MenuBarAXSnapshot = hiddenSnapshot,
        chevron: [MenuBarAXSnapshot?] = [agents(chevron: false)]
    ) -> (observer: HiddenLengthObserver, settles: Box<[Double]>) {
        let captures = Scenario.repeated(HidingVerificationTests.drawnImage(), count: Scenario.baselineCaptureCount())
            + Scenario.repeated(observeImage, count: Scenario.observeCaptureCount())
        let reads = Scenario.repeated(drawnSnapshot, count: Scenario.baselineReadCount())
            + Scenario.repeated(observeSnapshot, count: Scenario.observeReadCount())
        let (verification, _, _, _, _) = Scenario.makeVerification(
            discoveryResults: [discovery],
            capturerResults: captures,
            axResults: reads
        )
        let settles = Box([Double]())
        let observer = HiddenLengthObserver(
            verification: verification,
            chevron: ChevronReader(reader: FakeMenuBarAXReader(results: chevron), barHeight: Double(TestBar.heightPt)),
            settle: 1.5,
            sleep: { settles.set(settles.get() + [$0]) }
        )
        return (observer, settles)
    }

    @Test("both members gone with no fold is a clean length, after the settle")
    func cleanLength() async {
        let (observer, settles) = Self.observer()
        #expect(await observer.takeBaseline(sectionMap: Self.sectionMap))
        #expect(await observer.observe() == .hiddenClean)
        #expect(settles.get() == [1.5])
    }

    @Test("members still drawn is a drawn length")
    func drawnLength() async {
        let (observer, _) = Self.observer(observeImage: HidingVerificationTests.drawnImage(), observeSnapshot: Self.drawnSnapshot)
        #expect(await observer.takeBaseline(sectionMap: Self.sectionMap))
        #expect(await observer.observe() == .drawn)
    }

    @Test("a listed chevron is a folded length")
    func foldedLength() async {
        let (observer, _) = Self.observer(chevron: [Self.agents(chevron: true)])
        #expect(await observer.takeBaseline(sectionMap: Self.sectionMap))
        #expect(await observer.observe() == .folded)
    }

    @Test("an unreadable agent is an unknown length")
    func unreadableAgent() async {
        let (observer, _) = Self.observer(chevron: [nil])
        #expect(await observer.takeBaseline(sectionMap: Self.sectionMap))
        #expect(await observer.observe() == .unknown)
    }

    @Test("no discovery means no baseline, and any observation is unknown")
    func noBaseline() async {
        let (observer, settles) = Self.observer(discovery: nil)
        #expect(await observer.takeBaseline(sectionMap: Self.sectionMap) == false)
        #expect(await observer.observe() == .unknown)
        #expect(settles.get().isEmpty)
    }

    @Test("observing before any baseline is unknown")
    func observeWithoutBaseline() async {
        let (observer, _) = Self.observer()
        #expect(await observer.observe() == .unknown)
    }

    @Test("a member the detector cannot check fails the baseline", arguments: [IdentityBasis.positional])
    func uncheckableMember(basis: IdentityBasis) async {
        let positional = Scenario.discoveredItem(identifier: "t3", pid: 604, rawMinX: 100, basis: basis)
        let map = Self.sectionMap.merging(Scenario.sectionMap([positional])) { first, _ in first }
        let (observer, _) = Self.observer(discovery: Scenario.discovery([Self.items.t1, Self.items.t2, positional, Self.items.ref]))
        #expect(await observer.takeBaseline(sectionMap: map) == false)
    }

    // MARK: - Coverage rule

    static func ready(targets: [ItemKey], skipped: [ItemKey: CheckSkipReason] = [:], rejections: [ItemKey: Rejection] = [:]) -> PreparedVerification.Ready {
        PreparedVerification.Ready(
            baseline: BaselineResult(templates: [:], rejections: [:], ink: nil, agentFrames: [], foldAtBaseline: .absent, geometry: TestBar.geometry),
            geometry: TestBar.geometry,
            origin: DiscoveryOrigin(x: 0, y: 0),
            checkableTargets: targets,
            alsoObserved: [],
            references: [],
            planSkipped: skipped,
            baselineRejections: rejections,
            baselineFrames: [:]
        )
    }

    @Test("a baseline covers the section only when every member is checkable")
    func coverageRule() {
        let keys = [Self.items.t1.key, Self.items.t2.key]
        let full = PreparedVerification(state: .ready(Self.ready(targets: keys)), targets: keys, createdAt: 0)
        #expect(HiddenLengthObserver.covers(full))

        let skip = PreparedVerification(state: .skip(.noRoom), targets: keys, createdAt: 0)
        #expect(!HiddenLengthObserver.covers(skip))

        let empty = PreparedVerification(state: .ready(Self.ready(targets: [])), targets: [], createdAt: 0)
        #expect(!HiddenLengthObserver.covers(empty))

        let planSkip = PreparedVerification(state: .ready(Self.ready(targets: [keys[0]], skipped: [keys[1]: .positional])), targets: keys, createdAt: 0)
        #expect(!HiddenLengthObserver.covers(planSkip))

        let rejected = PreparedVerification(state: .ready(Self.ready(targets: keys, rejections: [keys[1]: .noInk])), targets: keys, createdAt: 0)
        #expect(!HiddenLengthObserver.covers(rejected))

        let partial = PreparedVerification(state: .ready(Self.ready(targets: [keys[0]])), targets: keys, createdAt: 0)
        #expect(!HiddenLengthObserver.covers(partial))
    }
}
