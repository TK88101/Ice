import CoreGraphics
import IceCore

/// `BarRect` is IceCore's (standard library only); these cross to and from
/// CoreGraphics for the callers that hold a `CGRect`.
extension BarRect {
    public init(_ rect: CGRect) {
        self.init(minX: Double(rect.minX), minY: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }

    public var cgRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}
