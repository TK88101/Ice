import Foundation

/// A small lock-protected flag shared between one `HidingVerification`
/// session (`prepare` or `verify`) and the `Task` that owns it (D19): the
/// task's cancellation handler sets it, and the capturer/reader wrappers
/// below poll it so a running session stops within one sample rather than
/// racing a blocking Accessibility or capture call it has no way to
/// interrupt.
final class CancellationFlag: @unchecked Sendable {
    private var flag = false
    private let lock = NSLock()

    init() {}

    func set() {
        lock.withLock { flag = true }
    }

    func isSet() -> Bool {
        lock.withLock { flag }
    }
}
