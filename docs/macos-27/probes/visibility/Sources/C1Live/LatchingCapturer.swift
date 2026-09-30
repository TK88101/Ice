import C1Core
import Foundation
import IceCore
import MenuBarCapture

/// I3: one serial capture path (section 4). Every capture the run takes
/// goes through this decorator before anyone else sees it: `assess` turns
/// the raw capture into the latch's owner-only observation (the actual
/// template matching lives with the stage, which already has the baseline
/// templates `assess` closes over), and a trip rests the spacer and quits
/// every helper -- synchronously, before `capture()` returns -- so nothing
/// downstream can act on a capture the latch has already disowned.
public final class LatchingCapturer: StripCapturing, @unchecked Sendable {
    private let base: any StripCapturing
    private let channel: any C1HelperChannel
    private let onTrip: (@Sendable (LatchTrip) -> Void)?
    private let assess: @Sendable (StripImage) -> Latch.Observation
    private let lock = NSLock()
    private var latch: Latch

    /// `onTrip`, when supplied, fires synchronously the first time this
    /// capturer trips -- ahead of `channel.sendRest()`/`quitAll()` (P0-3:
    /// the stage's own terminal state must be set at least as early as the
    /// helper commands, so nothing downstream can start new cycle work in
    /// the gap between the two).
    public init(
        base: any StripCapturing,
        channel: any C1HelperChannel,
        latch: Latch = Latch(),
        onTrip: (@Sendable (LatchTrip) -> Void)? = nil,
        assess: @escaping @Sendable (StripImage) -> Latch.Observation
    ) {
        self.base = base
        self.channel = channel
        self.latch = latch
        self.onTrip = onTrip
        self.assess = assess
    }

    /// A failed capture is itself an immediate abort (section 4): it never
    /// reaches `assess` -- there is no image to hand it -- but it still
    /// trips the latch exactly like a credible disappearance would.
    public func capture() -> StripImage? {
        guard let image = base.capture() else {
            trip(.init(captureFailed: true))
            return nil
        }
        trip(assess(image))
        return image
    }

    /// Section 4: "its miss state resets only after a passing reset
    /// check" -- the stage calls this once its own baseline-equivalence
    /// check (`BaselineEquivalence.check`) comes back clean.
    public func resetAfterPassingCheck() {
        lock.withLock { latch.resetAfterPassingCheck() }
    }

    /// Feeds the latch an observation the stage gathered outside a single
    /// capture -- the fold appearing (section 4's condition needs agent
    /// frames from a paired AX read, not just this decorator's own
    /// pixels) or a residual-strip ink change over several samples. Same
    /// trip behaviour as `capture()`'s own `assess` path.
    public func feed(_ observation: Latch.Observation) {
        trip(observation)
    }

    private func trip(_ observation: Latch.Observation) {
        let tripped: LatchTrip? = lock.withLock { latch.observe(observation) }
        guard let tripped else { return }
        onTrip?(tripped)
        channel.sendRest()
        channel.quitAll()
    }
}
