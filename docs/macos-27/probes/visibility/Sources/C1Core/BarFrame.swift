/// A rectangle on the bar, in the same points every other reading in this
/// module uses. Its own type rather than a tuple -- a tuple cannot conform
/// to `Equatable`/`Sendable` the way a stored property or a test assertion
/// needs (mirrors `IceCore.BarRect`'s reasoning, restated here because
/// C1Core imports nothing, including IceCore).
public struct BarFrame: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }
}
