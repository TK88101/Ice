# The lab matrix's first run: why every check was `captureUnstable`, and the judge's `incomplete`

Follows plan `2026-10-07-icebar-preference-hiding` (S4, T4) and STATUS "The lab matrix's
first run" (run `20261008-234718`, build `1a33df4`, `icetest`). Branch `wip/icebar-build`.

## Goal and non-goals

Goal: (1) set out what the run's own evidence shows about why every member check of the
first run was `unverifiable:captureUnstable`: an evidence table and one graded hypothesis,
not a proven root cause (review round 1); (2) repair the judge's reading of a step's `seq`,
so that the `incomplete` scenario's report, which shows what the scenario expects, is
judged `pass` -- with the two other places in the tool that misread it the same way.

Non-goals: changing Ice so that the check succeeds (a design step of its own: the detector
files and `Packages/MenuBarCapture` are frozen, and the remedy touches how a baseline and
an observation are sequenced); another sitting; restaging `/Users/Shared/IceReverse-lab`
(done before the next sitting, which is not worth spending before Ice is changed);
`crowded`'s roster flapping and `inverted`'s pre-seed (STATUS rows of their own).

## 1. The cause (evidence read 2026-10-09; nothing was run)

| # | What | Grade |
|---|---|---|
| C1 | `drawn` applies no length (`length` events `applied: null`, `held: true`), yet the Accessibility x of the member and of the hidden divider both move by -48 pt (1269 -> 1221, 1289 -> 1241) between the discovery passes at t = 17 s and t = 22 s, and back between t = 47 s and t = 52 s; Ice's icon stays at 1517. An Accessibility layout shift: the report holds no pixels and no reference's frame | MEASURED (`1-drawn/report-1.jsonl`, snapshots) |
| C2 | In that run the baseline was reported at t = 13.6 s and the two trials at t = 26.8 s and t = 40.9 s: the shift arrives 3-8 s after the baseline, before the first trial ends, and leaves 6-11 s after the last. That capturing began at about t = 7 s (the `baselining` phase) is INFERRED: no capture is logged | MEASURED (`report-1.log`, `report-1.jsonl`) / INFERRED (the capture's start) |
| C3 | Of the runner's 37 bar captures, 4 (the end of `crowded`, `incomplete`, `inverted`, `inverted-moved`) show a coloured block about 40 pt wide between our helpers and Apple's input menu, and in those 4 both reference helpers' glyphs lie 48 pt left of where the other 33 have them (1315.0 -> 1267.0, 1343.0 -> 1295.0). Ink right of the block is where it always is, apart from the clock, 3 pt, with a dot right of it (FINDINGS 2026-09-18; the dot alone in `drawn`'s first capture) | MEASURED (ink spans; capture times are the files' own) |
| C4 | The 4 with the block were taken 1.5 s and 4.2 s after a baseline or trial was logged, or while one was under way that was never logged (`incomplete`, `inverted-moved`: Ice calibrating with a length set when the runner ended it). Of the 33 without, 31 were taken 246 s or more after one, 2 at 11.2 s and 15.5 s; `positional`, where Ice never took a baseline, has none in either capture | MEASURED (file times against `IceBar baseline` / `IceBar trial` lines) |
| C5 | One of the conditions under which `CaptureStability.isStable` refuses is a reference not `.unique` within `referenceTolerancePt` = 1 pt of its template's origin; `HidingVerification.verify` reads against the baseline's templates. Others: no or duplicate references, a missing template, a mismatch above 0.05; and `StripAssessor.settled` refuses when a target reads differently between captures | MEASURED (code) |
| C6 | `noref`, whose references are Apple's own items right of the block, is the one scenario with no `captureUnstable` (52 of 52 `foldUnreadable`). Not a controlled comparison: the scenario differs in more than where its references are | MEASURED; supports, does not discriminate |
| C7 | 3 of 36 trials read their members `hidden` (`placed-off` first start, `placed-on` second start, `incomplete` after its second baseline): each the first trial after a baseline; no later trial on the same baseline did. A timing pattern to be explained, not evidence for one cause over another | MEASURED (`IceBar trial` lines) |
| C8 | The block is the system's screen-capture indicator, summoned by Ice's own captures | INFERRED (C4; FINDINGS 2026-09-19, MEASURED on this Mac: "Capturing the bar summons an indicator", there about 20 pt and left of the third-party items). Not done: a minimal capturer of our own, and nothing else, as the control |
| C9 | The first refusal path of `drawn`'s second trial is a reference moved by the block (C5's first condition): the trial ran from t = 29 s to 40.9 s, inside C1's shift. Every other `captureUnstable` trial is taken to be the same mechanism: the baseline cut before the block arrives, the observation read after | INFERRED (C1, C3, C5). Not measured: which references the baseline accepted, and what the matcher read in any observation. Whether another stability condition refuses as well: TBD |
| C10 | `noref`'s `foldUnreadable` is the same block read as unexplained ink in the fold region | TBD: nothing in the report separates it from any other unreadable fold |
| C11 | Whether the block lands right of third-party items in the owner's account too (2026-09-19 it was left of them), and why it is 40 pt here | TBD |

What would turn C9 into a measurement: Ice recording, for each observation, each
reference's identity, match kind, mismatch and distance from its template's origin, and
whether the targets settled. That is the first task of the step that changes Ice, before
any change to how a baseline and an observation are sequenced (review round 1).

Consequence, stated not solved: at a rest Ice never checks again, so one refused observation
stands as `notVerified(unchecked:n)` for the rest's whole life.

## 2. The judge

A step's `seq` is a **cut of the report**: `mark` in `run-lab.sh` gives a step the number
of lines the report holds at that moment, so every line with `seq <= cut` was written
before the step and every line with `seq > cut` after it. The tool's `since` parameters
(`seq > since`) already read the second half correctly. Three places read the first half
wrongly, each in its own way:

| # | Place | Now | Effect | Change |
|---|---|---|---|---|
| J1 | `judge_incomplete`, the rest | `snapshot_before(events, stall.seq)`, strictly before | the runner marks `stall` on the rest's first snapshot, so the judge reads the snapshot before it (`settling`): the first run's `notEstablished` | `snapshot_at_or_before(events, cut)` |
| J2 | `judge_incomplete`, "still blocked 30 s after" | statuses with `seq < settled.seq` | the report's last line at `settled` is not seen: a `blocked(` there is a false pass, a recovery there a false fail (found by T1's fixture) | `<=` |
| J3 | `judge_crowded`, witness against the first length | `witness.seq > length_seq` | a length that is the last line when the witness is marked counts as after it: a false pass of the setup | `>=` |

J1 picks the snapshot the runner had when it marked; J2 is the closed end of "30 s after";
J3 asks whether an event was already there when the witness was marked. J3 is in another
scenario's judge and is kept in this change as the same cut rule (review rounds 1-2):
one character, an equality fixture, and its expected difference on the real run is none
(`crowded` applied no length there). `first_status(..., since)`, `first_retire`,
`statuses(..., since)` and `crowded` clause 6's `<=` are right and are left.

## 3. Tasks

| # | Task | DoD |
|---|---|---|
| T1 | Tests first (RED): `test_incomplete` models the runner (the `stall` step carries the rest snapshot's own `seq`); the rest clause with no snapshot at the cut (`seq` 0: `notEstablished`); `blocked(` as the last line at `settled` (must fail); a `crowded` run whose first length is the last line at the witness mark (must be `notEstablished`) | the equal-`seq` cases fail against the present tool, each for the reason named |
| T2 | `lab-tool.py`: J1-J3; one helper `snapshot_at_or_before(events, cut)` whose docstring states the cut rule | `python3 -I test_lab_tool.py` green |
| T3 | Replay, a regression check and not a proof of the rule: every scenario directory of run `20261008-234718` judged by the changed tool, on copies outside the repo | `incomplete`'s `result` becomes `pass` and its `reasons` empty; every other verdict equal as JSON to the run's own `verdict.json` |
| T4 | STATUS (first-run table: the cause row, the `incomplete` row) and FINDINGS (one entry, C1-C11) | each claim tagged as in section 1, with run and date |

## 4. Tests

Unit: `test_lab_tool.py` (T1). Integration: `test-lab.sh` (the tool's tests, the snapshot
keys against IceCore, the runner against stubs). End to end: T3's replay of the real
run's evidence. No Swift changes, so no package or Xcode build. Coverage: the changed
lines are each hit by a test that fails without them.

## 5. Reach and rollback

Touched: `docs/macos-27/probes/visibility/lab-tool.py`, `test_lab_tool.py`,
`docs/macos-27/STATUS.md`, `docs/macos-27/FINDINGS.md`, this plan. Not touched: Ice,
the packages, `run-lab.sh`, the staged copy (its `TOOL_SHA` differs from the repo's tool
until the next `stage-lab.sh`). Rollback: revert the commit.

## 6. Risks

- C9 is an inference: if another condition also refuses, moving the baseline will not be
  enough. Section 1 says what would settle it.
- The replay judges one round of one run; `incomplete` passing there says the judge reads
  that report as the scenario's design does, not that three rounds will pass.

## Appendix: plan review

Codex `gpt-5.6-terra`, reasoning medium, 2026-10-09; two rounds, converged.

| Round | Raised | Outcome |
|---|---|---|
| 1 | 18 items. Section 1: the table wrote a strong timing correlation as a settled cause (the conclusion row "fatal": no observation's matcher result is on record; `settled` can refuse too); C1 proves an Accessibility shift, not pixels; the capture's start is not logged; the captures need their times; the indicator's identity and `noref`'s reading graded too high; the goal says "why". Section 2: J1-J3 correct, but "read as after" is imprecise -- define the `seq` as a prefix cut; name the helper for what it does and test `seq` 0, no snapshot, equal; J3 better split out; validate `steps.jsonl`'s `seq`; T3's "byte for byte" proves nothing about the equal branches | **taken**: the goal reworded; C1 as an Accessibility shift; the capture's start INFERRED; the pixel row states pixels only, with a row of capture times added (C4); the refusal row lists the other conditions; `noref` as support only; the 3-of-36 row as a pattern; `noref`'s fold to TBD; the cut rule, the helper's name and its tests; T3 as a regression check on `result` and `reasons`. **Disputed**, to round 2: the indicator's and the conclusion's grades, a second helper family, J3's place, the `steps` validation |
| 2 | Answers to the five | **Mine upheld**: the indicator row stays INFERRED on the new capture times (4 of 4 with the block beside a capture session, 33 of 33 without it away from one or with none); one helper only (`since` already says "after"); J3 stays, named as the same rule with a zero expected difference on the real run; the `steps` validation withdrawn (only the runner writes the file; the damage rules are T4's). **Codex's upheld**: `drawn`'s second trial is not "deduced" -- no matcher result of that observation exists, and the references are whichever candidates the baseline accepted, not "the two leftmost" -- so the conclusion row says "first refusal path, INFERRED" and names what is not measured |

## What follows (thecure with Codex, 2026-10-09; the owner's go-ahead for S1 the same day)

One proposal, converged in two calls. Mine withdrawn: "warm up until the references'
frames stop moving" (they are still before the block comes, so it would pass at once);
and re-baselining at a rest (ruled out in T3b). Codex's taken: avoid the block rather
than wait for it -- a check read with the block up certifies a bar 48 pt narrower than
the one the owner sees, and at a rest Ice does not look again.

| # | Step | State |
|---|---|---|
| S1 | In the owner's account, no sitting: the block's timing against Ice's own session shapes (`vizprobe indicator`) | **done**, run `20261009-111216-indicator`; FINDINGS "The capture indicator, timed" |
| S2 | Gate: the shortest arrival (10.2 s) against a baseline's 4.2 s | **passed** |
| S3 | Ice, frozen files untouched, no baseline at a rest: (a) the lab report records, per observation, each reference's identity, match, mismatch and distance from its template's origin, and `captureStable`; (b) every capture session lies in a window without the block -- its design to be written from S1's numbers and reviewed before any code | open |
| S4 | Restage; one `icetest` sitting: the diagnostics and the change judged together | open |

What S1 adds to S3(b)'s design: a baseline fits before the block and always summons it,
so the first observation after a baseline either ends within about 10 s of the
baseline's first capture or waits until about 21 s after it; a later observation alone
(1.5 s) summons nothing. Not measured: where between 1.5 s and 4.2 s the system starts
to react, and whether Ice's other captures (the item image cache) count towards it.

## S3 design: capture in bursts the block cannot reach, and say what a refusal was

Goal: (a) Ice's lab report says, for every observation, what the matcher read of each
reference, so "the block refused the trials" stops being an inference; (b) no baseline
or observation is read on a bar the block has moved. Non-goals: the detector and
`MenuBarCapture` (frozen); a baseline at a rest (T3b); fewer observations in a walk
(D1's calibrator is not touched); Ice's other captures (the IceBar's cell images, the
search panel, the settings pane: each happens while the owner interacts, when the
machine has already left the cycle -- a stated limit, not handled).

What it rests on (FINDINGS "The capture indicator, timed", both runs; the 13 sessions
that summoned the block: shapes A, B, D three times each, E and G twice each):

| # | Fact | Grade |
|---|---|---|
| M1 | The block never arrived sooner than 10.2 s after the first capture of a session begun 30 s after the last (13 of 13) | MEASURED |
| M2 | 20.5 s after the last capture the block and the clock's shift were both gone (13 of 13) | MEASURED |
| M3 | A baseline's captures take 4.2 s, an observation's 1.5 s (shapes B, C: the probe's sessions, without `prepare`'s discovery and preflight) | MEASURED |
| M4 | A session that starts while the clock's shift is still there may meet the block sooner | INFERRED; so no burst starts then |

**D1 The rule (`CaptureBurstRule`, IceCore, pure, tested).** Policy, conservative on
M1-M2, its constants named parameters and not measurements: a *burst* begins with the
first capture after `clearAfter` (22 s) without any. An observation may start within
it while its need (2.5 s) still fits before `budget` (8 s) after that first capture. A
baseline starts only on a clear bar and closes its burst when it is done, so nothing
else is read in it: what a baseline does before its first capture (a discovery, a
preflight) has no bound to fit a burst by (code review, round 1). Asked with a session
and the time the rule answers `go` or `wait(until:)` the moment the bar is clear
again. Its state: the burst's first capture, the last capture, whether the burst is
closed; fed by every capture actually taken.

**D2 Where it sits (`MenuBarDetectorFeed`, not frozen).** A capturer wrapper
(`BurstRecordingCapturer`) tells a shared `CaptureBurstClock` the time of each capture
it takes -- the preflight's included; nothing guesses when a session's captures began.
`HiddenLengthObserver.takeBaseline` and `observe` (after its settle) ask the clock,
sleep through a `wait` with the injected, cancellable sleep, and leave as today when
cancelled. The observer's `HidingVerification` is built with `retries: 1`: one attempt
a session, since the retries were there to get past the block's flicker and a session
that retried could outlast its burst (shape G: 7.1 s). `HidingVerifier` (the hiding
check) is unchanged. The coordinator cancels the work under way when it executes
`.setLength(nil)`: a session whose answer the machine no longer waits for must not
capture 22 s later, in the owner's interaction (`IceBarHidingCoordinator.swift:77-87`).

What the owner sees, said: after a baseline the first observation waits about 22 s
with the trial length already set; a walk gets two observations to a burst, so a
first calibration's fifteen take about three and a half minutes instead of one, and
its bound of 24 about five and a half (waiting before every one would pass the
baseline's ten minutes, `BaselineReuse.maxAge`); a rest reached from a remembered
length takes about half a minute. The violet block still appears for about ten
seconds after each burst: capturing summons it, this only keeps it out of the readings.

**D3 What a refusal was (`ObservationDiagnostics`).** `verify` keeps its signature;
beside it `verifyReporting` returns the checks and, when an observation was read, per
reference its key, the match's kind, its mismatch and its distance from the template's
origin (from `reading.sightings` and `baseline.templates`), `captureStable` and the
fold. `HiddenLengthReading` carries it with the seconds waited and the burst's age at the
session's last capture (first to last capture: whether the session stayed inside the
budget); the coordinator records it as a lab event `observation`
(identifiers and numbers, no titles; the judge ignores events it does not know,
`lab-tool.py:107-124`) and logs counts only.

Tests first: `CaptureBurstRuleTests` (a first burst, a second observation that fits,
one that does not, the wait, clearing, the baseline's envelope; 100 % of the rule);
`HiddenLengthObserverTests` (a baseline then an observation sleeps the wait; two
observations share a burst; a cancelled wait captures nothing);
`HidingVerificationTests` (the diagnostics of a moved reference say `unique` with its
distance); `LabReportTests` (the event's JSON). Then `xcodebuild`, `check-a3a4.sh`,
the three packages' suites, `test-lab.sh`; `/simcodex`. The probes' full run (over an
hour) only if a probe's Swift changes.

Touched: `Packages/IceCore` (the rule, the diagnostics value, the lab event);
`Packages/MenuBarDiscovery/Sources/MenuBarDetectorFeed` (`HidingVerification`,
`HiddenLengthObserver`, the live wiring, the clock and wrapper);
`Ice/MenuBar/IceBar27/IceBarHidingCoordinator.swift`, `Ice/Main/LabReport.swift`;
STATUS. Rollback: revert the commit.

Risks: the numbers are one Mac's, one OS build's, two runs' -- the diagnostics will
show a burst the block reached all the same; M4 is why bursts do not overlap, and it
is not measured; a walk three times slower is three times likelier to be interrupted
by the owner's mouse; without retries one unreadable fold costs an observation.

### S3 design review (Codex `gpt-5.6-terra`, reasoning medium, 2026-10-09; two rounds, converged)

| Round | Raised | Outcome |
|---|---|---|
| 1 | 15 items: "15 of 15" miscounted (13); 22 s and 8 s are policy, not measurements; the needs leave out `prepare`'s discovery and preflight, and the preflight's capture would go unrecorded; a retry deadline cannot stop a bracket that is already capturing; **a session waiting 22 s is not cancelled when the machine leaves its phase, and would capture later**; the text had a baseline and an observation both fit one burst and wait 22 s; the diagnostics hide earlier attempts; simpler: wait 22 s before every session, one attempt each | **taken**: the count; policy wording; the capturer wrapper; one attempt a session in place of a deadline; the coordinator's cancel; the envelope and its test; burst times in the diagnostics. **Disputed**, to round 2: waiting before every observation, an Accessibility check that the bar is clear, re-baselining a stale rest, the throttle's meaning |
| 2 | Answers to the four | **Mine upheld, all four withdrawn by Codex**: two observations to a burst stay (24 waits of 23.5 s pass the baseline's 600 s; shape E has the second observation 5 s clear of the block); no Accessibility check (which agent frame is the clock, and where it rests, is a new way to be wrong); a stale rest is the owner's ruling (T3b); the throttle is untouched (tokens, and now the cancel). Codex adds: pin the baseline's envelope by a test |

### S3 code review (/simcodex, 2026-10-09)

| Round | Simplify (own review: the diff is small, no agents dispatched) | Codex review | Outcome |
|---|---|---|---|
| 1 | the burst's age computed in the observer by nested maps: moved into the rule | 1 P1: a baseline admitted into a running burst reserves 5 s, but `prepare`'s discovery and preflight come before its first capture and are not bounded | both taken: a baseline needs a clear bar and closes its burst (`baselineNeed` removed; the envelope test replaced by the two that pin this) |
| 2 | none | 1 P1: the hiding check (`AppState+HidingCheck`) captures through a capturer of its own that the clock never hears of | taken: one clock for the process (`CaptureBurstClock.shared`), every live capturer reports to it; this also keeps the history when the coordinator builds an observer for another display. Ice's window captures (`ScreenCapture`: cell images, search, settings) still do not report: the stated limit |
| 3 | none | 1 P1: with a shared clock a capture elsewhere during the wait moves the moment the bar is clear, and the observer slept to the old one | taken: the wait asks again after every sleep and adds up (test first, red, then green) |
| after | -- | confirmation: the P1 resolved; 1 P2: the event carries the burst's age, not its two endpoints | P2 left: the age and the wait say whether a session stayed inside its budget; the plan's wording corrected to what is emitted |

P0/P1 per round: 1, 1, 1, 0. The stated cap of three rounds, then one confirmation.

## S4, before the sitting (thecure with Codex, 2026-10-09, one call, converged)

- The runner waited 300 s for a first rest; a first calibration under the bursts takes
  about 270 s for T0's band and about 350 s at the calibrator's bound of 24. Now
  `STATUS_LIMIT` 600, `RUN_LIMIT` 28800 (`run-lab.sh`); the fixed naps follow scenario
  actions and are not affected (Codex).
- A reference helper lives 10800 s at most and one round may come near it (a round is
  estimated at 2-2.5 hours, not measured): each scenario now begins by checking the
  references are alive and is `aborted` otherwise, so a dead reference cannot read as
  Ice failing its checks (Codex's worry; `test-lab.sh` has the case).
- The sitting is in two parts: `run-lab.sh sparse` first (minutes), its `observation`
  events read here; then `k2`; the whole matrix only if those verify.
