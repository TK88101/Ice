// IceBar build plan T0 (docs/plans/2026-10-03-icebar-build.md, section 7
// note 1): the spike stage's live seams -- the AX press and the helper's
// reply lines. Everything else comes from route C's `IceBarLiveWiring`.
import ApplicationServices
import Darwin
import Foundation
import SpikeStage

extension LiveIceBarHelper: SpikeReplyReading {
    func awaitReply(_ kind: String, timeout: Double) -> [String: Any]? { control.awaitReply(kind, timeout: timeout) }
}

/// `kAXPressAction` on the helper's own extras item, from a thread of its
/// own: AppKit answers the press from the helper's main thread, which may be
/// inside menu tracking until the menu closes, so the call can outlast the
/// 1 s the plan allows the menu to appear in.
final class LiveSpikePress: SpikePressing, @unchecked Sendable {
    /// Returned instead of an `AXError` when the item is not listed under the helper's extras bar.
    static let elementNotFound = -2
    /// Returned when the helper's extras bar cannot be read.
    static let extrasUnreadable = -3
    static let messagingTimeoutSeconds: Float = 3

    private let lock = NSLock()
    private var result: (error: Int, seconds: Double)?
    private var generation = 0

    func beginPress(pid: pid_t, identifier: String) {
        let mine: Int = lock.withLock {
            result = nil
            generation += 1
            return generation
        }
        Thread.detachNewThread { [self] in
            let start = DispatchTime.now()
            let error = Self.press(pid: pid, identifier: identifier)
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            lock.withLock {
                if generation == mine { result = (error, seconds) }
            }
        }
    }

    func pressResult() -> (error: Int, seconds: Double)? { lock.withLock { result } }

    private static func press(pid: pid_t, identifier: String) -> Int {
        let read = RawAX.read(pid: pid)
        guard read.extrasError == .success else { return extrasUnreadable }
        guard let child = read.children.first(where: { $0.identifier == identifier }) else { return elementNotFound }
        AXUIElementSetMessagingTimeout(child.element, messagingTimeoutSeconds)
        return Int(AXUIElementPerformAction(child.element, kAXPressAction as CFString).rawValue)
    }
}
