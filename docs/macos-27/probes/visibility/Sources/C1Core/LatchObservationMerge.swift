/// Round 4 item 2 (Amendment v4 / G-b, applied to the latch itself): "the
/// latching capturer's assess path also runs the keyed untemplated check
/// on every capture, not only at checkpoints; a missing/moved/
/// unenumerated item trips the latch like a templated miss." This is the
/// pure fold: the stage's `assess` closure computes the templated
/// (pixel-matched) observation as before, runs `UntemplatedOwnerWatch.
/// check` against a fresh keyed discovery read, and merges the two here
/// before handing the result to `Latch.observe`.
public enum LatchObservationMerge {
    /// `untemplated`: `UntemplatedOwnerWatch.check`'s result, or `nil`
    /// when the keyed discovery read itself failed or came back late
    /// (through `TimedDiscoverer`) -- indistinguishable from a failed
    /// pixel capture, and treated the same way: an immediate abort
    /// (`captureFailed`), not merely "no untemplated failures found".
    public static func merge(templated: Latch.Observation, untemplated: [UntemplatedOwnerWatch.Failure]?) -> Latch.Observation {
        guard let untemplated else {
            return Latch.Observation(
                missingOwnerItems: templated.missingOwnerItems,
                protectedMissing: templated.protectedMissing,
                residualInkChanged: templated.residualInkChanged,
                foldAppearedWithoutExpansion: templated.foldAppearedWithoutExpansion,
                captureFailed: true
            )
        }
        guard !untemplated.isEmpty else { return templated }

        var missing = Set(templated.missingOwnerItems)
        for failure in untemplated {
            switch failure {
            case .missing(let id), .moved(let id):
                missing.insert(id)
            }
        }
        return Latch.Observation(
            missingOwnerItems: missing.sorted(),
            protectedMissing: templated.protectedMissing,
            residualInkChanged: templated.residualInkChanged,
            foldAppearedWithoutExpansion: templated.foldAppearedWithoutExpansion,
            captureFailed: templated.captureFailed
        )
    }
}
