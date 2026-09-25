/// I5's dry-run seam: section 5 step 2's `length L` and its collapse back
/// to rest both go through here, so `--dry` (section 7: "a path that never
/// sends `length`") is enforced in one place instead of re-checked at every
/// call site in the stage.
public struct C1ExpansionDriver: Sendable {
    public let channel: any C1HelperChannel
    public let dry: Bool

    public init(channel: any C1HelperChannel, dry: Bool) {
        self.channel = channel
        self.dry = dry
    }

    /// Section 5 step 2: "preflight -> jump from rest to L" -- issued
    /// synchronously right after a passing preflight (section 3). Never
    /// sent under `--dry`, which must touch nothing that would move the
    /// bar.
    public func expand(to lengthPt: Double) {
        guard !dry else { return }
        channel.sendLength(lengthPt)
    }

    /// Section 5 step 2's collapse back to rest.
    public func collapse() {
        guard !dry else { return }
        channel.sendRest()
    }
}
