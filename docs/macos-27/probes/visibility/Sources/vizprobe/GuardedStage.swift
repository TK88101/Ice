// The watchdog and signal handling every live stage run gets -- moved out of
// `main.swift`'s `c1` branch unchanged (C2 T4) so `c2-config` runs under
// exactly the same safety teardown. See the comments below for the history.
import C1Stage
import Darwin
import Foundation

enum GuardedStage {
    static func run(_ stage: StageC1, name: String, watchdogMinutes: Double) -> Never {
        signal(SIGPIPE, SIG_IGN)
        for number in [SIGINT, SIGTERM, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                FileHandle.standardError.write(Data("vizprobe \(name): signal \(number) -- entering the terminal safety teardown\n".utf8))
                // Item 8: its own terminal reason (`signalReceived()`, needing
                // attention -- never `emergencyStop()`'s `.watchdog`), the
                // same pre-armed recorded backstop the watchdog uses below
                // (armed before the signal's own cleanup runs, for the same
                // reason: that cleanup's own `confirmReap()` could hang), and
                // no bare `exit(3)` here any more -- that used to leave the
                // run with no recorded verdict at all, since `stage.run()`'s
                // own thread never got a chance to reach `finish(...)`.
                // `exit(stage.run())` below still reports the real exit code
                // once that thread notices `isTerminal` and completes.
                DispatchQueue.global().asyncAfter(deadline: .now() + StageC1.watchdogBackstopSeconds) {
                    FileHandle.standardError.write(Data("vizprobe \(name): signal teardown did not finish within 2 min -- forcing exit\n".utf8))
                    stage.recordWatchdogBackstopVerdict()
                    exit(3)
                }
                stage.signalReceived()
            }
            source.resume()
        }
        // Item 5 (Codex round 2): the watchdog must run the same terminal
        // safety teardown a trip does -- rest first (already synchronous
        // inside `emergencyStop`), then reap, then the 30 s
        // baseline-equivalence check, then a recorded verdict (including
        // needs-attention) -- not exit before any of that happens.
        // `emergencyStop()` only marks the run terminal and performs the
        // immediate rest/quit/reap/stop-caffeinate cleanup; `stage.run()`'s
        // own main-thread loop notices `isTerminal` at its next checkpoint
        // and falls through to `runTeardownAndDecide(...)`, whose exit code
        // `exit(stage.run())` below reports. Item 8's AX/discovery bounds are
        // what make that checkpoint reachable within a few seconds even if a
        // read was hung when the watchdog fired.
        DispatchQueue.global().asyncAfter(deadline: .now() + watchdogMinutes * 60) {
            FileHandle.standardError.write(Data("vizprobe \(name): WATCHDOG after \(watchdogMinutes) min -- entering the terminal safety teardown\n".utf8))
            // Round 4 item 3: the 120 s backstop is armed *before*
            // `emergencyStop()` is even called, not after it returns --
            // `emergencyStop()` itself calls `confirmReap()` synchronously
            // (as part of its cleanup actions), whose discovery could hang;
            // arming the backstop first means that hang is still covered,
            // instead of the backstop never being scheduled at all.
            DispatchQueue.global().asyncAfter(deadline: .now() + StageC1.watchdogBackstopSeconds) {
                FileHandle.standardError.write(Data("vizprobe \(name): WATCHDOG teardown did not finish within 2 min of firing -- forcing exit\n".utf8))
                // Round 3 item 4: synchronously write the recorded terminal
                // verdict to evidence before any raw exit -- the run must
                // never disappear from the record silently just because
                // `run()` itself never reached its own `finish(...)`.
                stage.recordWatchdogBackstopVerdict()
                exit(2)
            }
            stage.emergencyStop()
        }
        exit(stage.run())
    }
}
