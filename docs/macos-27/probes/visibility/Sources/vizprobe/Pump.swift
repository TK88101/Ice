// Two small bridges the 2026-09-23 stages need because vizprobe runs its
// protocol on the main thread without ever calling `NSApplication.run()`.
//
// `NSWorkspace.runningApplications` "will only change when the main run
// loop is run in a common mode" (its documentation). Discovery reads it
// (`LiveRunningApps`), so a helper launched after vizprobe started would
// never be discovered unless the main run loop is given turns. `pump` does
// that; every stage wait goes through it instead of `Thread.sleep`.
import Foundation

enum Pump {
    /// Runs the main run loop for `seconds` (in short turns).
    static func run(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.05)))
        }
    }

    /// Runs `body` on the cooperative pool and waits for it on the main
    /// thread, pumping the main run loop meanwhile.
    static func blocking<T>(_ body: @escaping @Sendable () async -> T) -> T {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await body()
            done.signal()
        }
        while done.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return box.value!
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}
