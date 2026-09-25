import Darwin
import IceCore
import MenuBarCapture

/// Wraps another `MenuBarAXReading`, returning `nil` once `flag` is set
/// instead of delegating -- the read-side twin of `CancellableCapturer`
/// (D19).
struct CancellableReader: MenuBarAXReading {
    private let wrapped: any MenuBarAXReading
    private let flag: CancellationFlag

    init(wrapping reader: any MenuBarAXReading, flag: CancellationFlag) {
        self.wrapped = reader
        self.flag = flag
    }

    func read(items: [String: pid_t]) -> MenuBarAXSnapshot? {
        guard !flag.isSet() else { return nil }
        return wrapped.read(items: items)
    }
}
