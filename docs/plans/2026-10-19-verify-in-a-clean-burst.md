# Verify only in a burst the capture indicator does not answer

Follows STATUS "The lab matrix, a fifth round" and the sixth round, run `20261019-004100`
(build `0fbae72`, `icetest`, 2026-10-19). Branch `wip/icebar-build`. The design was
argued with Codex over six rounds (thecure, 2026-10-19) and confirmed by the owner the
same day.

## Goal and non-goals

Goal: Ice says `verified` only from an observation that cannot be followed by its own
capture indicator, so that a verified rest is not taken back some ten seconds later by
`stacked`; and the lab sees that it holds past the indicator's window.

Non-goals: the `stacked` rule (`ItemPosition`, 25 %), `MenuBarAgent`'s children as
obstacles, the judge's criteria, the calibration walk's own captures (two observations a
burst stay), `Packages/MenuBarCapture` and the frozen detector files.

## 1. What the sixth round showed

| # | What | Grade |
|---|---|---|
| E1 | Rounds 1-2 clean; round 3 unclean for `press` alone ("ended unverified, expected verified") | MEASURED (run report) |
| E2 | `crowded`, all three rounds: `notEstablished`, "the system folded the members out of the roster", the ruled exclusion. Answers the fifth round's TBD: without the push it ends as the fold | MEASURED (`*-crowded/verdict.json`, `steps.jsonl`) |
| E3 | `3-press`: length 728 set at 293.8 s; the settle's observation at 297.3 s had `waited` 0 and `burstAge` 6.9, the burst's second session (begun about 290.4 s); `verified` at 297.3 s; at 300.7 s, 10.2 s after the burst began, `notVerified(stacked:1)`, member 1 `stacked` at an unchanged frame, until the scenario ended | MEASURED (`3-press/report-1.jsonl` seq 184-200) |
| E4 | Rounds 1-2 of `press` verified on a burst's first session (`waited` 18.5, `burstAge` 1.5) and ended inside 10.75 s of the burst's start with no `stacked` | MEASURED |
| E5 | Over the run (`crowded` aside), a `stacked` beginning 8-16 s after a burst's start: 0 of 137 one-session bursts, 305 of 402 two-session bursts | MEASURED (the run's reports, tallied 2026-10-19) |
| E6 | The capture indicator is a `MenuBarAgent` child that arrives about 10.3 s after a capture session begins, for sessions of 4.2 s or more, not for one of 1.5 s; `ItemCatalog` feeds `MenuBarAgent`'s children to `PositionRule` as obstacles | MEASURED (FINDINGS "The capture indicator, timed"; `ItemCatalog.swift`) |
| E7 | Every verified scenario but `3-press` passed by timing: it verified on a one-session burst, or ended before the indicator came | MEASURED (E3-E5) |
| E8 | The overlapping obstacle of E3 was the indicator | INFERRED (E3, E5, E6): the report holds no obstacle frames |

## 2. Design

D1 **Who may verify.** An observation proves a rest only when its reading carries the
burst it was taken in, as the first session of that burst (`ordinal == 1`), with
`capturedAt - burstStartedAt <= observationNeed` (2.5 s; 2.5 itself counts). Both
times are the clock's, fixed when the session ends; the machine never uses the time it
receives the reading at. A reading without a burst never proves.

D2 **Confirming.** A settle's (or a rest re-check's) observation that sees every ready
member absent but does not prove (D1) does not rest. The machine keeps the length and
asks for one confirmation at it: phase `confirming`, status `notVerified(confirming)`.
The confirmation proves only in a burst other than the candidate's. Its result is then
taken as the settle's own would have been. A confirmation that sees a member drawn or
unchecked is taken the same way; one that sees every member absent and still does not
prove is asked again, up to `maxFailures` times, then the rest stands with no checks
(`notVerified(unchecked:n)`), never `verified`.

D3 **Dropping the candidate.** While confirming: a layout change, a precondition result
other than the one the candidate was found under, interaction or a drag, retire the
length and go quiet (a new baseline, a new walk). A new baseline cannot happen while
confirming.

D4 **Sessions that close their burst.** A settle, a re-check and a confirmation are
asked with `closesBurst`: the observer reserves them as `verdict` sessions, and the
rule closes the burst in the same step that lets the session start -- so it is
closed however the session then ends (returned, cancelled, refused, superseded),
nothing joins the burst a verified rest was read in, and the next session starts a
burst of its own. A call already superseded or cancelled reserves nothing. The
calibration's trials do not close theirs.

D5 **Reservation and ownership.** `CaptureBurstRule` numbers bursts and the sessions
in each, and reserves a session atomically with deciding it may start (`begin`). A
session on a clear bar opens a new burst at that moment. A burst opened by a capture
outside any session (another capturer on the shared clock) counts that as its first
session, so a session joining it is the second. `observe` takes the observer's
`generation` as `takeBaseline` does: a reading of a superseded session is `.nothing`.
`finish` reads the session's burst under the lock; a burst that is no longer the
current one yields no burst (D1: never proves).

D6 **The lab.** The report's observation line carries `burstID`, `ordinal`, `burstAge`
and `sinceCapture` (from the session's last capture to the line). The snapshot names,
for each roster member, the frames it overlaps (`overlaps`), and lists `systemElements`.
`hide` waits, after the first `verified`, until the verifying observation's last
capture plus `CLEAR_AFTER` (22 s) has passed in the report. The judge is unchanged: a
status taken back by the indicator ends the scenario unverified.

## 3. Tasks (TDD; each test written and seen failing first)

| # | Task | Tests |
|---|---|---|
| T1 | `CaptureBurstRule`: burst ids, session ordinals, `begin`, `finish`; a capture outside a session | `CaptureBurstRuleTests` |
| T2 | `IceBarHidingMachine`: D1-D3, `closesBurst` on the command, the `confirming` reason and phase name | `IceBarHidingMachineTests` (2.5 - e / 2.5 + e, ordinal 2, same burst, nil burst, drawn confirmation, repeated non-proof, each D3 trigger) |
| T3 | `HiddenLengthObserver`, `CaptureBurstClock`: D4-D5 | `HiddenLengthObserverTests`, `CaptureBurstObserverTests` (close on each exit path; the next reading produced is a new burst's first session; a superseded session's reading dropped) |
| T4 | Contract: the observer's reading against the machine: only a first session of a new burst within 2.5 s verifies | a test in the Feed package driving both |
| T5 | Coordinator, `LabReport`: the new fields; app build | `LabReportTests`; `xcodebuild` |
| T6 | `lab-tool.py` (`verified-clear` predicate, `SNAPSHOT_KEYS`), `run-lab.sh` `hide` | `test_lab_tool.py`, `test-lab.sh` |
| T7 | /simcodex, then stage, then the seventh round | -- |

Cost: a verified rest that the walk reached on a burst's second session waits about
22 s more, once. The matrix runs about 22 minutes longer (`hide`'s wait).
