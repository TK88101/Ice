// The read-only half of plan section 6.1 step 1: preflight, then a baseline
// of the bar with nothing of ours running. Shared between `--dry-run`
// (which stops here on purpose -- this is naturally the one part of the
// protocol that launches nothing) and the live run, which continues past it
// only when every check here passes.
import AppKit
import Foundation
import IceCore
import MenuBarCapture

/// What the leftmost third-party item and the notch say about the room our
/// helpers would land in.
struct RoomCheck {
    let leftmostThirdPartyX: Double?
    let freeRoomPt: Double?
    /// A `MenuBarAgent` frame left of the leftmost third-party item is the
    /// chevron or a privacy pill (plan 6.1 step 1) -- this is never empty on
    /// its own; `foldAtBaseline` from `baseline` below is the stronger
    /// pixel-backed version of the same check (3.5's fold rule), kept
    /// alongside it because it costs nothing and it is what the plan's own
    /// wording names first.
    let agentFramesLeftOfLeftmost: [BarItem]
}

struct PreflightOutcome {
    let geometry: BarGeometry?
    let preflight: PreflightResult
    let room: RoomCheck?
    /// The pre-flight baseline: IceCore's own `TemplateBaseline` rules
    /// (3.2) applied to every third-party item on the bar right now. `nil`
    /// only when a capture or an AX read failed outright.
    let baseline: BaselineResult?
    let minFreeRoomPt: Double
    /// The same thresholds IceCore decides with, so a recalibration reaches
    /// this side too (the widths used to be literals here).
    let parameters: DetectorParameters

    /// True when `«` or a privacy pill is up before anything of ours runs.
    ///
    /// Not "any MenuBarAgent frame left of the leftmost third-party item" any
    /// more: **MEASURED 2026-09-19** — capturing the bar repeatedly summons a
    /// ≈ 20 pt `MenuBarAgent` indicator there, which goes again when the
    /// capturing stops. That rule aborted every live run before it began, and
    /// the run cannot avoid capturing. So only the two widths that matter abort:
    /// the chevron (17.5 pt in every reading on record) and the microphone pill
    /// (16 pt in two recorded baselines). Anything else left of the items is an
    /// environment indicator: it is recorded, the warm-up makes sure it is
    /// already up when the baseline is taken, and the fold witness's
    /// one-to-one rule stops the run if it changes afterwards.
    var chevronOrPillSignal: Bool { chevronSignal || pillSignal }

    /// The chevron, from two directions. `foldAtBaseline` is IceCore's own
    /// pixel-and-Accessibility answer; the width check beside it is defence in
    /// depth and can go without losing a guard.
    var chevronSignal: Bool {
        let fold = baseline.map { $0.foldAtBaseline == .present } ?? true
        let byWidth = leftOfItems.contains { FoldWitness.isChevron(asAgentFrame($0), parameters: parameters) }
        return fold || byWidth
    }

    /// The privacy pill. **The only guard there is**: nothing in IceCore models
    /// a pill — the fold witness asks about the chevron alone — so removing
    /// this check removes pill detection entirely.
    var pillSignal: Bool {
        leftOfItems.contains { FoldWitness.isPill(asAgentFrame($0), parameters: parameters) }
    }

    /// Indicators left of the items that are neither chevron nor pill. They are
    /// allowed, and they have to stay put for the rest of the run.
    var environmentIndicators: [BarItem] {
        leftOfItems.filter {
            !FoldWitness.isChevron(asAgentFrame($0), parameters: parameters)
                && !FoldWitness.isPill(asAgentFrame($0), parameters: parameters)
        }
    }

    private var leftOfItems: [BarItem] { room?.agentFramesLeftOfLeftmost ?? [] }

    private func asAgentFrame(_ item: BarItem) -> AgentFrame {
        AgentFrame(minX: item.minX, minY: item.minY, width: item.width)
    }

    var freeRoomOK: Bool {
        guard let freeRoomPt = room?.freeRoomPt else { return false }
        return freeRoomPt >= minFreeRoomPt
    }

    /// Whether the live protocol may continue past step 1.
    var ready: Bool {
        guard case .ready = preflight else { return false }
        return baseline != nil && !chevronOrPillSignal && freeRoomOK
    }
}

enum PreflightCheck {
    /// Plan 6.1 step 1: "the free room ... is under 30 pt" aborts.
    static let minFreeRoomPt = 30.0

    /// How many times the pre-flight baseline may be attempted, and how long
    /// to wait between attempts.
    static let baselineAttempts = 5
    static let baselineRetryInterval = 1.0

    /// Enough capturing to summon the indicator before anything is decided.
    static let warmUpCaptures = 24
    static let warmUpInterval = 0.25

    static func run(
        capturer: some StripCapturing,
        axReader: some MenuBarAXReading,
        parameters: DetectorParameters = .preRegistered
    ) -> PreflightOutcome {
        guard let screen = NSScreen.main, let geometry = BarGeometry(screen: screen) else {
            return PreflightOutcome(geometry: nil, preflight: .unavailable(.captureUnavailable), room: nil, baseline: nil, minFreeRoomPt: minFreeRoomPt, parameters: parameters)
        }

        // Warm-up: capturing the bar summons a ≈ 20 pt `MenuBarAgent`
        // indicator (2026-09-19). Take the captures that summon it *before*
        // the baseline, so it is already in the baseline's agent set instead of
        // arriving mid-run and making every later fold reading unreadable.
        for _ in 0..<warmUpCaptures {
            _ = capturer.capture()
            Thread.sleep(forTimeInterval: warmUpInterval)
        }

        let preflight = Preflight.run(capturer: capturer, axReader: axReader, geometry: geometry)
        guard case .ready = preflight else {
            return PreflightOutcome(geometry: geometry, preflight: preflight, room: nil, baseline: nil, minFreeRoomPt: minFreeRoomPt, parameters: parameters)
        }

        let onBar = BarScan.items().filter { $0.minY >= 0 && $0.minY < geometry.heightPt }
        let thirdParty = onBar.filter { $0.bundleID != BarScan.menuBarAgentBundleID }
        let room: RoomCheck
        if let leftmost = thirdParty.min(by: { $0.minX < $1.minX }) {
            let agentLeft = onBar.filter { $0.bundleID == BarScan.menuBarAgentBundleID && $0.minX < leftmost.minX }
            room = RoomCheck(leftmostThirdPartyX: leftmost.minX, freeRoomPt: leftmost.minX - (geometry.notch?.hi ?? 0), agentFramesLeftOfLeftmost: agentLeft)
        } else {
            room = RoomCheck(leftmostThirdPartyX: nil, freeRoomPt: nil, agentFramesLeftOfLeftmost: [])
        }

        // The indicator that capturing summons comes and goes, and a capture
        // that catches it drawn before Accessibility lists it leaves ink in the
        // fold region that nothing accounts for — the rule that exists for a
        // chevron drawn early. Retry the observation rather than weaken it;
        // MEASURED 2026-09-19, roughly half of consecutive attempts read
        // `unreadable` this way.
        var baseline = ThirdPartyBaseline.take(capturer: capturer, geometry: geometry, parameters: parameters)
        for _ in 1..<baselineAttempts where baseline?.foldAtBaseline != .absent || (baseline?.templates.isEmpty ?? true) {
            Thread.sleep(forTimeInterval: baselineRetryInterval)
            baseline = ThirdPartyBaseline.take(capturer: capturer, geometry: geometry, parameters: parameters)
        }
        return PreflightOutcome(geometry: geometry, preflight: preflight, room: room, baseline: baseline, minFreeRoomPt: minFreeRoomPt, parameters: parameters)
    }
}
