# The matrix is no longer the gate; a bar displaced under its baseline is baselined again

Follows the ninth sitting, run `20261111-233109` (build `9a6d7a6`, `icetest`,
2026-11-11). Branch `wip/unstable-rest-rebaseline`. Argued with Codex over three rounds
(thecure, 2026-11-12); the owner's decision and confirmation the same day.

## 0. The owner's decision (2026-11-12)

No more full overnight matrix. Nine sittings since 2026-10-08 never met "three clean
rounds running" (best: two of three, 2026-10-19); each cost the owner the Mac for hours.
This plan **lowers S4's acceptance confidence on purpose**. It is not an equivalent of
three clean rounds and nothing below may be read as one.

Amended in plan `2026-10-07-icebar-preference-hiding`: S4's DoD ("every verifiable
scenario verified three runs in a row") and S5's "Only after S4's DoD" are replaced by
the gate in section 3.

## Goal and non-goals

Goal: Ice recovers when a system item changes its width under a baseline; S4 closes on
stated evidence and stated limits; S5 follows.

Non-goals: `run-lab.sh` and `lab-tool.py` (unchanged; the matrix command stays, it is
just not run as a gate), a deterministic lab scenario for the shift (rejected: more lab
engineering for one path), the cause of transient discovery incompletes,
`Packages/MenuBarCapture` and the ten frozen detector files.

## 1. What the ninth sitting showed

| # | What | Grade |
|---|---|---|
| E1 | Round 1 not clean for `k8` alone: "never verified (last status: notVerified(unchecked:8))". Every other runnable scenario matched its kind | MEASURED (run report) |
| E2 | `k8`: walk 736 to 672 clean (17-135 s, about 24 s a step, every reading stable, references at offset 0). Between 137 and 157 s (23:59:40 to 0:00:00) the clock went from 124 to 116 pt wide and every item left of it moved 8 pt (Ice's icon x 1500 to 1508) | MEASURED (`1-k8/report-1.jsonl` seq 68-72) |
| E3 | `k8`: the trial at 656 (159 s) and the settle at 704 (183 s) read `captureStable: false`, both references `unique`, mismatch 0, offset 8; 8 checks `unverifiable:captureUnstable`; then 185 identical snapshots and no observation to 1107 s | MEASURED (seq 73-270) |
| E4 | Why it stayed: a rest observes again only when a baseline is owed (`.unbaselined`) or a layout change is pending; `LayoutSignature` leaves frames and `MenuBarAgent`'s items out on purpose | INFERRED (`IceBarHidingMachine.advance`, `LayoutSignature.swift`); reproduced by unit test |
| E5 | The same at a verified rest needs no walk: the clock changes, nothing is observed, and the next frontmost-app change re-checks against the old baseline and rests unchecked | INFERRED (same code); unit test |
| E6 | `front-long` (passed): its re-check with 24 menus in front also read `captureStable: false`, both references `absent`, offset null; the length stayed 728, the member was never shown, and it verified again when the app changed back | MEASURED (`1-front-long/report-1.jsonl` seq 207-223) |
| E7 | Over runs `20261019-004100`, `20261031-015900`, `20261111-233109`: 1893 observations, 6 unstable; "at least two references, each unique within `maxMismatch`, each more than `referenceTolerancePt` off, all the same distance" is true of `k8`'s two and of none of `front-long`'s four | MEASURED (the rule replayed over the reports) |
| E8 | Discovery incomplete: 3 episodes, all `other`, all at standard length (`com.apple.Safari` 1.5 s in `noref`; `com.microsoft.autoupdate.fba` 10.0 s in `crowded`, 12.5 s in `relaunch`); none Ice's own, none a member's | MEASURED (run report) |

## 2. Design

D1 **The signal.** `ObservationDiagnostics.baselineDisplaced(tolerance:maxMismatch:)`,
pure: at least two references, every one `unique` with mismatch within `maxMismatch`
and an offset beyond `tolerance`, all offsets within `tolerance` of each other. One
reference alone, a covered or ambiguous one, or offsets that disagree are not evidence
of a bar moved as one piece (Codex round 3: the trigger means "a credible common-mode
translation", not "a baseline might help").

D2 **The plumbing.** `IceBarHidingEvent.observed` gains `displaced: Bool` (default
false). The coordinator computes it from the reading's diagnostics with the detector's
own `referenceTolerancePt` and `maxMismatch`. The machine keeps it on the `Rest`, false
whenever the reading saw every ready member absent.

D3 **The recovery.** A rest with `displaced` and no pending re-check starts a new cycle
(`enterQuiet`: the length retired, then the baseline at standard length, then the walk
or the last verified length): not while interacting, not before `minInterval` since the
last start, at most `maxFailures` (3) times. The counter is its own: a baseline that
covers the members gives nothing back (every such cycle takes one; Codex round 1: reusing
`baselineRetries` would loop). A verified length, by settle or by re-check, and a
structural layout change reset it. Spent: the rest stays `notVerified`, never
`verified`, and nothing more is captured.

D4 **Not during a walk.** A displaced trial ends the walk as any unreadable one does
(the calibrator's rule); only the rest owes the baseline. One transient reading does not
spend a cycle.

D5 **Not for any unstable reading.** The first cut triggered on `captureUnstable`
alone; it would have shown the hidden member in `front-long` (E6), where no baseline
cures covered references. Found while implementing, argued again (round 3), replaced by
D1.

## 3. The gate that replaces S4's DoD

| # | What | State |
|---|---|---|
| G1 | The evidence ledger in STATUS: per scenario, its latest live pass (run, build), whether the hiding machine changed since, and the tests that cover the change | this plan |
| G2 | IceCore, MenuBarDiscovery and lab-tool suites green; the app builds; the frozen files untouched (`check-a3a4.sh`); `/simcodex` | this plan |
| G3 | One live `run-lab.sh k8`, about 20 minutes, started by the owner at about hh:57:30 before 10:00 or 0:00 so the clock's digit change falls in the walk. A **recovery witness** only if the scenario's report shows an observation with `captureStable: false` and both references `unique` at one nonzero offset, then `length` null, and `report-1.log` a second "IceBar baseline: ok true", and the run ends `verified`. If the change misses the walk: a regression pass only, and STATUS says the recovery is unit-tested, not witnessed live. Not run again either way | the owner's sitting |
| G4 | STATUS states the limits: `noref`, `crowded` excluded; `inverted*` to S5; `front-long` best effort; one reference alone is never recovered; transients can leave `notVerified`, never falsely `verified`; three clean rounds never achieved | this plan |

Then S5.

## 4. Tasks (tests first)

| # | What | Tests first | DoD |
|---|---|---|---|
| T1 | `ObservationDiagnostics.baselineDisplaced` | `ObservationDiagnosticsTests`: the two measured readings; zero, one, three references; absent, ambiguous, unobserved; no offset, no mismatch, high mismatch; disagreeing and opposite offsets; within tolerance | `swift test` green |
| T2 | The machine: `displaced` on the event and the rest, `displacedRetries`, `retryDisplaced`, `rechecked` | `IceBarHidingMachineTests`, "A rest read on a bar that moved under its baseline": the measured sequence to verified; the interval; the bound and no capture after it; the counter reset by settle and by re-check; the re-check path (E5); covered references keep the length (E6); not while interacting; not during a walk | `swift test` green, changed files at least 80 % |
| T3 | The coordinator passes `displaced` | build | `xcodebuild` green |
| T4 | `/simcodex`; STATUS; the older plan's two sentences; restage for G3 | | |

## Appendix: the argument with Codex

| Round | Point | Outcome |
|---|---|---|
| 1 | Dropping three clean rounds is a reduction, not a replacement; a ledger is needed | Codex's; taken (section 0, G1) |
| 1 | Reusing `baselineRetries` loops: a covering baseline resets it | Codex's; taken (D3) |
| 1 | Re-taking a baseline mid-walk on a rigid shift | refused: a baseline needs the section shown |
| 1 | A machine test cannot show the coordinator's order, the bar's reflow, a crossing cancel | Codex's; taken (G3) |
| 2 | A plain `k8` does not enter the recovery; the run must be timed, and judged from the report and Ice's log | mine; Codex added that "baseline: ok" is in the log, not the report (G3) |
| 2 | The trigger at the rest, not at the first unstable trial | agreed (D4) |
| 3 | `captureUnstable` alone would show the member in `front-long` | mine, from E6; agreed (D5) |
| 3 | At least two references, each within `maxMismatch` | Codex's; taken (D1) |
| 3 | Reset on a clean re-check, with `displaced` cleared in the same step | agreed (D3) |
