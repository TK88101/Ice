import Darwin
import Foundation
import IceCore
import MenuBarCapture
import MenuBarDiscovery
@testable import MenuBarDetectorFeed

/// Shared fixture builders for `HidingVerificationTests` (T7): a small
/// synthetic bar with two adjacent targets and a reference, wired to fake
/// discovery/capture/AX seams so `HidingVerification`'s sessions can be
/// driven deterministically with no real sleep, screen, or Accessibility.
enum Scenario {
    /// A discovered item's *raw* (untrimmed) AX frame, as `CheckPlan.make`
    /// would see it in a fresh discovery pass.
    static func discoveredItem(identifier: String, pid: Int32, rawMinX: Double, rawWidth: Double = 9, basis: IdentityBasis = .declared, position: ItemPosition = .onBar) -> DiscoveredItem {
        fixtureItem(identifier: identifier, pid: pid, minX: rawMinX, width: rawWidth, basis: basis, position: position)
    }

    static func set(_ items: [DiscoveredItem]) -> DiscoveredItemSet {
        fixtureSet(items: items)
    }

    static func discovery(_ items: [DiscoveredItem], origin: DiscoveryOrigin = DiscoveryOrigin(x: 0, y: 0)) -> DiscoveryResult {
        fixtureDiscovery(set: set(items), origin: origin)
    }

    static func sectionMap(_ items: [DiscoveredItem], section: ItemSection = .hidden) -> [TagKey: ItemSection] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.tagKey, section) })
    }

    /// A capture-level (detector-facing, already trimmed) AX snapshot: one
    /// frame per `(id, atPt)` pair, plus the agent's own frame.
    static func snapshot(_ frames: [(id: String, atPt: Double)], agentMinX: Double = 200, agentWidth: Double = 26) -> MenuBarAXSnapshot {
        var itemFrames = [String: ItemFrame]()
        for (id, atPt) in frames {
            itemFrames[id] = TestBar.frame(id: id, atPt: atPt)
        }
        return MenuBarAXSnapshot(itemFrames: itemFrames, agentFrames: [AgentFrame(minX: agentMinX, minY: 0, width: agentWidth)])
    }

    /// The same shape as `snapshot(_:agentMinX:)`, but able to place a raw
    /// (untrimmed-width) frame directly -- used for a rejected candidate
    /// whose reported frame is made to overlap another item's, or one that
    /// is deliberately too narrow to template.
    static func snapshot(explicit: [String: ItemFrame], agentMinX: Double = 200, agentWidth: Double = 26) -> MenuBarAXSnapshot {
        MenuBarAXSnapshot(itemFrames: explicit, agentFrames: [AgentFrame(minX: agentMinX, minY: 0, width: agentWidth)])
    }

    static func image(_ glyphs: [(shape: [String], atPt: Double)]) -> StripImage {
        TestBar.image(glyphs)
    }

    static func repeated<T>(_ value: T, count: Int) -> [T?] {
        Array(repeating: value, count: count)
    }

    /// `HidingVerification`'s own retries/warm-up default to production
    /// values (5 retries, 24-capture warm-up); tests override `warmUpCount`
    /// to 0 throughout, since warm-up is not itself under test here and its
    /// captures would otherwise have to be scripted for every case.
    static func makeVerification(
        discoveryResults: [DiscoveryResult?],
        capturerResults: [StripImage?],
        axResults: [MenuBarAXSnapshot?],
        clockStep: Double = 1.0,
        retries: Int = 5,
        warmUpCount: Int = 0
    ) -> (verification: HidingVerification, discoverer: FakeDiscoverer, capturer: FakeStripCapturer, ax: FakeMenuBarAXReader, sleeps: CallCounter) {
        let discoverer = FakeDiscoverer(results: discoveryResults)
        let capturer = FakeStripCapturer(results: capturerResults)
        let ax = FakeMenuBarAXReader(results: axResults)
        let clock = FakeClock(step: clockStep)
        let sleeps = CallCounter()
        let verification = HidingVerification(
            discoverer: discoverer,
            capturer: capturer,
            readerFactory: { _ in ax },
            geometry: { TestBar.geometry },
            preflight: { .ready(geometry: TestBar.geometry) },
            sleep: { _ in sleeps.increment() },
            now: clock.now,
            queue: DispatchQueue(label: "test.hidingverification.\(UUID().uuidString)"),
            parameters: .preRegistered,
            warmUpCount: warmUpCount,
            warmUpSpacing: 0,
            retries: retries,
            retrySpacing: 0
        )
        return (verification, discoverer, capturer, ax, sleeps)
    }

    /// 4 samples (8 captures, 4 reads): enough to span
    /// `DetectorParameters.preRegistered.baselineMinSpan` (3s) at
    /// `clockStep = 1` and satisfy `baselineMinSamples` (4) -- one baseline
    /// attempt's worth of scripted results.
    static func baselineCaptureCount() -> Int { 8 }
    static func baselineReadCount() -> Int { 4 }

    /// 2 samples (4 captures, 2 reads): `DetectorParameters.minSamples`.
    static func observeCaptureCount() -> Int { 4 }
    static func observeReadCount() -> Int { 2 }
}
