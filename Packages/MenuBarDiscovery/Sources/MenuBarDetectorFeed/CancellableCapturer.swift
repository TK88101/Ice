import IceCore
import MenuBarCapture

/// Wraps another `StripCapturing`, returning `nil` once `flag` is set instead
/// of delegating (D19: "a cancellation-aware capturer ... return `nil` once
/// cancelled, so the observer stops within one sample"). The flag is checked
/// before every delegated call, never cached, so a cancellation that lands
/// mid-loop is seen on the very next capture.
public struct CancellableCapturer: StripCapturing {
    private let wrapped: any StripCapturing
    private let flag: CancellationFlag

    public init(wrapping capturer: any StripCapturing, flag: CancellationFlag) {
        self.wrapped = capturer
        self.flag = flag
    }

    public func capture() -> StripImage? {
        guard !flag.isSet() else { return nil }
        return wrapped.capture()
    }
}
