/// The one channel every live piece sends helper commands through -- I3's
/// trip response, I5's expansion/collapse and teardown. One protocol so a
/// test can record every command a fake channel received, in order,
/// instead of reaching into `HelperControl` (which touches real processes).
public protocol C1HelperChannel: Sendable {
    /// `length <pt>` to the spacer.
    func sendLength(_ pt: Double)
    /// `rest` to the spacer.
    func sendRest()
    /// Quits every launched helper the real `HelperControlChannel` is
    /// willing to reach through this call. F2 (Amendment v6, staged
    /// teardown): the real implementation quits Target and the spacer
    /// only -- Protected is held back until `quitProtected()`, so no
    /// cleanup path (a trip, the watchdog, a signal, an off-main event, a
    /// setup abort) can quit Protected before the staged teardown's own
    /// settled fold read (Protected as the sole reference) has run.
    func quitAll()
    /// F2: Protected's own quit, called only once that staged fold read
    /// has passed (or by a full relaunch's own reap, which really does
    /// want every helper gone).
    func quitProtected()
    /// G5 (Amendment v7): the same reach as `quitAll()` (Target and the
    /// spacer, never Protected), but each helper's non-blocking
    /// `requestQuit()` instead of its blocking `quit()` -- the only quit
    /// this stage's off-main terminal handling (a trip on
    /// `HidingVerification`'s own queue, the watchdog/signal global queue)
    /// may issue.
    func quitAllNonBlocking()
}
