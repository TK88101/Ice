import Foundation

/// Round 3 item 2: "replace the per-instance TimedAXReader queues with
/// ONE stage-wide serial AX executor: every AX read the stage and its
/// verifiers make goes through it; a read not done within the bound
/// marks the executor stuck, and the stuck event synchronously drives
/// the state machine terminal -- every later read fails immediately."
///
/// One serial queue for every AX read this run ever makes (not one per
/// reader instance, which let a timed-out read on one instance overlap a
/// fresh read on another): a hung read leaves the queue's single worker
/// thread occupied forever, so every later submission's own wait times
/// out too, without ever starting its body -- structurally "no two reads
/// ever overlap," not merely "not through the same reader."
public final class C1AXExecutor: @unchecked Sendable {
    /// Generously above every measured per-element Accessibility timeout
    /// already in this probe (0.25 s, `StageRun`/`RawAX`/
    /// `LiveMenuBarAXReader`, several elements per read) while still far
    /// short of anything a live cycle can tolerate waiting on.
    public static let boundSeconds = 1.0

    private let queue = DispatchQueue(label: "com.icereverse.C1Live.C1AXExecutor", qos: .userInitiated)
    private let bound: Double
    private let onStuck: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var stuck = false

    public init(bound: Double = C1AXExecutor.boundSeconds, onStuck: (@Sendable () -> Void)? = nil) {
        self.bound = bound
        self.onStuck = onStuck
    }

    /// Runs `body` (one AX read) serialized on this executor's queue.
    /// Fails at once, without submitting `body` at all, once the
    /// executor is already stuck. Otherwise waits up to `bound`; a body
    /// that does not finish in time marks the executor permanently
    /// stuck and fires `onStuck` -- once, the first time this happens --
    /// before returning `nil`.
    public func run<T>(_ body: @escaping @Sendable () -> T?) -> T? {
        guard !(lock.withLock { stuck }) else { return nil }

        let box = ResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        queue.async {
            box.value = body()
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + bound) == .success else {
            let firstStuck = lock.withLock {
                let wasAlreadyStuck = stuck
                stuck = true
                return !wasAlreadyStuck
            }
            if firstStuck { onStuck?() }
            return nil
        }
        return box.value
    }

    private final class ResultBox<Value>: @unchecked Sendable {
        var value: Value?
    }
}
