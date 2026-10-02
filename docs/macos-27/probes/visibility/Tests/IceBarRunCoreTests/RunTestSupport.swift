// Shared fixtures for the runner's pure decisions
// (docs/plans/2026-10-03-icebar-c-runner.md). Captures here are 1 x 1 stand-ins:
// cadence and accounting never look at pixels.
@testable import IceBarRunCore
import IceCore

enum Fixture {
    static func image(_ value: UInt8 = 40) -> StripImage {
        StripImage(width: 1, height: 1, scale: 2, bytes: [value, value, value, 255])
    }

    /// A bracketed sample started at `start` that ended 0.1 s later.
    static func timed(_ start: Double, agentFrames: [AgentFrame] = [], duration: Double = 0.1) -> TimedSample {
        TimedSample(start: start, sample: ObservationSample(
            time: start + duration, before: image(), after: image(), agentFrames: agentFrames, itemFrames: [:]
        ))
    }

    /// `count` samples `spacing` apart from `first`.
    static func series(_ count: Int, from first: Double, spacing: Double) -> [TimedSample] {
        (0..<count).map { timed(first + Double($0) * spacing) }
    }
}
