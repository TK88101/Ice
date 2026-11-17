# The grace outlasts Mission Control: re-read until readable

2026-11-17 · branch `wip/grace-mission-control` (from `main` 408eee0) · follows
plan 2026-11-17-transient-pass-grace (v1.1.6). Labels: MEASURED, INFERRED, TBD.

## What is wrong

Evidence: `~/IceReverse-evidence/20261117-builtin-shown/` (`icebar-stream.log`,
`ownextras-watch.log`; Dock's `Changing from mode` lines from `log show`).

| # | Fact | Grade |
|---|---|---|
| M1 | While Mission Control shows, Ice's `AXExtrasMenuBar` answers -25212 and no third-party extras are listed; only `MenuBarAgent`'s four slots remain. About 1.1 s after it closes, everything is listed again (Ice's icon at the same x) | MEASURED, 26B131, 13:48:59-13:49:02, `open -a "Mission Control"` twice |
| M2 | That pass is the "unreadable pass": `grace: began ... iconUnreadable, ownReadNotOk(identifiersMissing) items 4`, then `expired after 5.2 s`, then `blocked(iconUnreadable)` and a retire; reproduced on the first try | MEASURED, same run |
| M3 | All 10 unreadable passes of 2026-11-17 (9 on 1.1.5, 1 on 1.1.6) fell within about 1 s of Dock `.none to missionControl`; Mission Control opened 22 times in that span | MEASURED (`log show`) |
| M4 | Mission Control stayed open 0.6-3.0 s in those 22 openings (median 1.0 s) | MEASURED |
| M5 | On an unreadable pass the machine asks for one `.reread` (run 1.15 s later, `rereadDelay`); later unreadable passes in the grace ask for none (`setAside`, `rest.suspect != nil` returns `[]`). The regular pass comes from a 5 s timer plus 1 s debounce (`MenuBarItemManager`) | MEASURED (code) |
| M6 | Within the grace the only read Ice asks for is the one at about +1.15 s, which can fall while Mission Control is up or before AX returns; whether the next regular pass lands inside the 5 s depends on the 5 s timer's phase, not measured | MEASURED: in the run AX was back by +2.0 s and the grace still expired at +5.2 s; the phase part INFERRED |

The earlier INFERRED cause (Ice's icon off the bar at the hiding length) is wrong: at
rest at the length the icon is listed (watch, 13:45:49 and 13:49:02).

## Goal and non-goals

Goal: a Mission Control opening of the length measured in M4 no longer retires the
length; the grace ends with `recovered`.

Limit (G4, accepted in round 4): a readable pass published within the last moment
before the expiry but not yet sampled (the tick's menu-frame read still running)
loses to the expiry and retires, as in 1.1.6; H4's ~2.2 s margin makes it rare.

Non-goals: detecting Mission Control itself (no public API; Dock's log is not an
interface); a stay in Mission Control longer than the grace allows still retires, as
in 1.1.6; `discoveryIncomplete`, structural changes, the verifying mode: unchanged.

## Design (after Codex round 1)

H1 A grace owns one re-read loop. The first unreadable pass at a rest emits
`.graceReread(token:)` in place of `.reread` (with `.armGrace` as today); later
unreadable passes emit nothing, as today. The machine is otherwise unchanged.

H2 The coordinator runs the loop as its own task (`graceLoop`), not through the
cancel-and-reschedule `reread` slot: repeat { sleep `graceRereadInterval` (0.5 s);
one pass (`cacheItemsRegardless`); `tick()` } while the machine still holds a
suspect with that token. It ends on a readable pass (recovered), the expiry, a
retire, a mode change; a new token cancels the old loop. Nothing else can
postpone it, and the standard-length `reread` keeps its own slot.

H3 Bound: at most `ceil(7 / 0.5)` = 14 loop passes started per grace, one in flight
at a time (the loop awaits each); d ~0.17 s is the expected cost, not a bound. Samples: the coordinator's own 1 s timer (`tick`, line 224) samples
the published roster (`iceBarRoster`, lines 446-450) whoever published it, so a
regular pass that completes inside the grace is judged within 1 s; the loop also
ticks right after its own pass. A loop pass that the shared `CacheActor` cut short
leaves the roster as it was: the tick then sees the same unreadable state again,
which only replaces the suspect (`setAside`), nothing retires.

H4 Grace 7 s (was 5). Budget after a pass taken as Mission Control opens:
opening (M4 max 3.0 s) + AX lag (M1 ~1.1 s) + loop gap (0.5 s + d) = ~4.8 s, with
d ~0.17 s (MEASURED: the hold's re-read 13:42:15.800 -> 17.123 = 1.32 s, minus the
1.15 s delay). 7 s leaves ~2.2 s. A pass still running at the expiry is lost (G4
kept); a stalled pass (seconds, as with WebKit services) expires as in 1.1.6, a
stated limit. Cost: an unreadable pass that is not transient shows the items 2 s
later than 1.1.6.

H5 Log: `IceBar grace: began, token <t>, would block ...`; at the end
`recovered|expired after X s, token <t>, loop passes R, longest pass D s`, where R and
D are what the loop itself ran and timed (diagnostic only: acceptance rests on
`recovered`, not R). The coordinator keeps the token with `graceBegan`.

H6 The machine exposes `graceToken: Int?` (the held suspect's token). The loop runs
while it equals its own token; its lifecycle (set, kept by more unreadable passes,
cleared by recovery, expiry, retire, mode off, replaced by a new grace) is
unit-tested in IceCore. The loop checks `graceToken == token` after each sleep and
again after each pass; only then does it tick and count. The grace's end cancels the
loop's task. An extra `tick()` is the same call the 1 s timer makes at any moment
(it samples whatever roster is published), so a late one can judge nothing the
timer would not. The loop's timing is checked live (T4).

## Tasks (TDD, IceCore first)

| # | Task | DoD |
|---|---|---|
| T1 | Grace tests: first unreadable pass yields `[.graceReread(token:), .armGrace(token:, after: 7)]`; later ones `[]`; `transientGrace` 7 in `.unverified` | RED, then GREEN |
| T2 | `IceBarHidingCommand.graceReread(token:)`; `setAside` and parameters per H1/H4; `graceToken` (H6) with lifecycle tests | IceCore tests all green |
| T3 | Coordinator `graceLoop` (H2, H6), log lines (H5) | Debug build of `Ice` succeeds |
| T4 | Live: a Release build under the daily identity; `open -a "Mission Control"` closed after 1 s, 3 s, and 4 s, three times each, log stream running | per opening: one `grace <t>: began`, `recovered` with R >= 1, no `blocked`, no `retire:` within 10 s |
| T5 | STATUS section updated (MEASURED lines with build and date) | -- |

No parallel candidates: T1-T3 touch the same machine and its one caller.

## Acceptance

- `swift test` in `Packages/IceCore` green, coverage of the changed files >= 80 %.
- `xcodebuild` Debug build of `Ice` green.
- T4: 9 of 9 openings as stated in T4.

## Tests

Unit: T1 plus the existing 16 grace tests (expiry, token, drag, hold, verifying
mode, standard length) unchanged in meaning; the token lifecycle is unit-tested (H6); the loop's timing is checked live (T4). Integration: the coordinator path is
covered by the Debug build and T4 (no harness for the coordinator exists). E2E: T4.

## Impact

`IceBarHidingMachine.swift` (`setAside`, one command case),
`IceBarHidingCoordinator.swift` (`execute`, new `graceLoop`, `logGrace`), the grace
tests. Frozen files (`MenuBarCapture`, detectors) untouched.

## Risks and rollback

- More passes during a grace: bounded by H3. A stalled pass does not stretch the
  grace (G4's own clock).
- T4 starts a Release build under the daily identity: export
  `io.github.tk88101.Ice` first, restore after (CLAUDE.md); Mission Control
  shows on the owner's screen for 1-3 s per opening.
- Rollback: the daily Ice stays 1.1.6 until the owner takes the new build.

## Appendix: debate with Codex

Round 1 (12 items):

| # | Item | Verdict |
|---|---|---|
| R1-1 | M6 overstates: the regular pass's phase is not measured | adopted, M6 weakened |
| R1-2 | `rereadSoon` cancel-and-reschedule can be postponed forever | adopted: own token-bound loop (H2) |
| R1-3 | grace reads and regular passes cancel each other in `CacheActor` | modified: whichever completes is sampled (H3); no coalescing machinery |
| R1-4 | the expiry beats a readable pass in flight | modified: no in-flight window (keeps G4); margin by a 7 s grace (H4) |
| R1-5 | "N passes" undefined | adopted: completed loop passes, per token (H5) |
| R1-6 | 5 s has no margin over 4.1 s | adopted: 7 s (H4) |
| R1-7 | the bound needs a formula | adopted (H3) |
| R1-8 | model retry state in IceCore for unit tests | rejected: the loop is sleep, pass, tick; the decision stays in the tested machine; timing covered by T4 at 1/3/4 s |
| R1-9 | deterministic scheduler tests | rejected with R1-8 (no scheduler to test once the loop replaces the reschedule) |
| R1-10 | acceptance bound to a token, R >= 1 | adopted (T4) |
| R1-11 | two meanings in one `reread` slot | adopted (H2) |
| R1-12 | simpler: one token-bound loop | adopted (H1, H2) |

Round 2 (4 items):

| # | Item | Verdict |
|---|---|---|
| R2-1 | 7 s margin unsupported; d unbounded | modified: d measured ~0.17 s, budget written out (H4); a stalled pass expires, stated limit; the loop logs its longest pass |
| R2-2 | a regular pass is never sampled; a cut-short loop pass samples a stale cache | rebutted with code: the 1 s tick samples the published roster whoever published it; a stale unreadable sample only replaces the suspect (H3) |
| R2-3 | R cannot tell a published pass from a skipped one; no token in the log | adopted: R and D diagnostic only, acceptance on `recovered`; token in the log (H5) |
| R2-4 | timing loop untested | modified: `graceToken` lifecycle in IceCore tests (H6); no scheduler abstraction, timing live (T4) |

Round 3 (2 items):

| # | Item | Verdict |
|---|---|---|
| R3-1 | a loop pass returning after recovery ticks with a stale roster | adopted the guards (token after sleep and after the pass; the end cancels the task); rejected a coordinator-level test: the extra tick is the timer's own call and samples the published roster |
| R3-2 | the bound used d as a lower bound | adopted: 14 starts, one in flight (H3) |

Round 4 (1 item):

| # | Item | Verdict |
|---|---|---|
| R4-1 | a readable roster published but not yet sampled can still lose to the expiry; asks a coordinator test or naming it a G4 limit | adopted Codex's second option: written as a limit (Goal section); no coordinator harness. Converged |

Plan final 2026-11-17 after 4 rounds.
