/// The one channel every live piece sends helper commands through -- I3's
/// trip response, I5's expansion/collapse and teardown. One protocol so a
/// test can record every command a fake channel received, in order,
/// instead of reaching into `HelperControl` (which touches real processes).
public protocol C1HelperChannel: Sendable {
    /// `length <pt>` to the spacer.
    func sendLength(_ pt: Double)
    /// `rest` to the spacer.
    func sendRest()
    /// Quits every launched helper (Target, the spacer, Protected).
    func quitAll()
}
