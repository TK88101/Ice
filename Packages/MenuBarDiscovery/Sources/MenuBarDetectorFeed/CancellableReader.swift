import Darwin
import IceCore
import MenuBarCapture

/// Wraps another `MenuBarAXReading`, returning `nil` once `flag` is set
/// instead of delegating -- the read-side twin of `CancellableCapturer`
/// (D19).
public struct CancellableReader: MenuBarAXReading {
    private let wrapped: any MenuBarAXReading
    private let flag: CancellationFlag

    public init(wrapping reader: any MenuBarAXReading, flag: CancellationFlag) {
        self.wrapped = reader
        self.flag = flag
    }

    public func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
        guard !flag.isSet() else { return nil }
        return wrapped.read(items: items)
    }
}
