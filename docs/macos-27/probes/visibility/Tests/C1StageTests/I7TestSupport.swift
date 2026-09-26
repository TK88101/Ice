// I7 (rework #6a): shared plumbing for `I7OrchestrationTests.swift` and
// `I7FaultTriggerTests.swift` -- the three helper bundle stand-ins, one
// `run(world:)` convenience that builds a fresh environment/evidence and
// drives the real `StageC1` orchestration exactly like every I7 scenario
// always has, and the one assertion (section 4 / P0-3: "rest reaches the
// spacer before any helper is quit") every latch-trigger scenario needs.
import C1Live
import C1Stage
import Foundation

enum I7 {
    static func apps() -> C1Apps {
        C1Apps(
            target: URL(fileURLWithPath: "/tmp/fakebar/Target.app"),
            protected: URL(fileURLWithPath: "/tmp/fakebar/Protected.app"),
            spacer: URL(fileURLWithPath: "/tmp/fakebar/Spacer.app")
        )
    }

    struct Run {
        let code: Int32
        let evidence: FakeEvidence
        let caffeinate: FakeCaffeinate
    }

    /// `signalDuringLaunchOfRole`: scenario 6's own hook -- when supplied,
    /// `stage.signalReceived()` fires synchronously right as that role's
    /// helper begins launching (`FakeHelperLauncher.onLaunch`), simulating
    /// a signal arriving mid-setup with no change to any file outside this
    /// test target.
    static func run(
        world: FakeBarWorld,
        dry: Bool = false,
        signalDuringLaunchOfRole: String? = nil,
        discoveryExecutorBoundSeconds: Double = C1DiscoveryExecutor.boundSeconds
    ) -> Run {
        let evidence = FakeEvidence()
        let caffeinate = FakeCaffeinate()
        let handback = StageHandback()
        var onLaunch: (@Sendable (String) -> Void)?
        if let signalDuringLaunchOfRole {
            onLaunch = { role in
                guard role == signalDuringLaunchOfRole else { return }
                handback.stage?.signalReceived()
            }
        }
        let environment = FakeC1EnvironmentFactory.make(world: world, evidence: evidence, caffeinate: caffeinate, onHelperLaunch: onLaunch, discoveryExecutorBoundSeconds: discoveryExecutorBoundSeconds)
        let stage = StageC1(environment: environment, apps: apps(), dry: dry)
        handback.stage = stage
        let code = stage.run()
        return Run(code: code, evidence: evidence, caffeinate: caffeinate)
    }

    /// Section 4 / P0-3: whatever tripped the latch, `rest` reaches the
    /// spacer before any helper is quit -- scoped to *after the last
    /// `length` command* (crosscheck #14): an ordinary cycle's own
    /// mid-run collapse already logs `spacer.rest` long before any
    /// teardown quit, which would satisfy a plain "rest appears somewhere
    /// before quit" check by accident regardless of whether the trip's own
    /// cleanup ordering is correct.
    static func restPrecedesFirstQuitAfterLastLength(_ world: FakeBarWorld) -> Bool {
        let log = world.commandLog
        guard let firstQuitIndex = log.firstIndex(where: { $0.hasSuffix(".quit") }) else { return false }
        let searchFrom = log.lastIndex(where: { $0.hasPrefix("spacer.length ") }) ?? log.startIndex
        guard let restIndex = log[searchFrom...].firstIndex(of: "spacer.rest") else { return false }
        return restIndex < firstQuitIndex
    }
}
