import Foundation

/// A small lock-protected flag shared between one `HidingVerification`
/// session (`prepare` or `verify`) and the `Task` that owns it (D19): the
/// task's cancellation handler sets it, and the capturer/reader wrappers
/// below poll it so a running session stops within one sample rather than
/// racing a blocking Accessibility or capture call it has no way to
/// interrupt.
public final class CancellationFlag: @unchecked Sendable {
    private var flag = false
    private let lock = NSLock()

    public init() {}

    public func set() {
        lock.withLock { flag = true }
    }

    public func isSet() -> Bool {
        lock.withLock { flag }
    }
}
