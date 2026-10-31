# A hide limit for two walks, and a discovery that goes incomplete seen

Follows the seventh round, run `20261031-015900` (build `b2f8744`, `icetest`,
2026-10-31). Branch `wip/k8-hide-limit`. Argued with Codex over four rounds (thecure,
2026-10-31); confirmed by the owner the same day.

## Goal and non-goals

Goal: a hide scenario has time for one walk started again after a transient
`blocked(discoveryIncomplete)`; and no pass, clean round or "S4 DoD: met" hides that a
discovery went incomplete on the way.

Non-goals: the hiding machine (a blocked machine retires its length and baselines
again, as designed and judged by `incomplete`), `CaptureBurstRule`'s numbers,
`Completeness` and the reason a read failed, the cause of the transient incompletes
(a later plan, once the report names the process), `Packages/MenuBarCapture` and the
frozen detector files.

## 1. What the seventh round showed

| # | What | Grade |
|---|---|---|
| E1 | Round 1 not clean for `k8` alone: "never verified (last status: notVerified(lengthNotApplied))"; the run stopped | MEASURED (run report) |
| E2 | Every verifying observation of the round was a burst's first session (`ordinal` 1, `burstAge` about 1.56 s); no `notVerified(confirming)`; no verified rest fell back during the hold (later changes in `addremove`, `front-short` are the scenarios' own) | MEASURED (`1-*/report-1.jsonl`) |
| E3 | `k8`: none of 19 observations joined a burst (`waited` about 17 s each, `sinceCapture` about 2.23 s against `k4`'s 1.40 s); a step costs about 24 s. Round six's `k8`: 0 of 19 joined, verified at 467-471 s | MEASURED |
| E4 | `k4`'s second session starts about 5.4 s into its burst, against the 5.5 s it may (budget 8 - need 2.5) | MEASURED (`1-k4`, `burstAge` - `sinceCapture`) |
| E5 | `k8` at 217 s: `incomplete:1` for about 5 s at length 608, `blocked(discoveryIncomplete)`, the length retired, a baseline again, the walk from 736 again; about 685 s needed against `STATUS_LIMIT` 600 | MEASURED (`1-k8/report-1.jsonl` seq 96-109) |
| E6 | Over runs `20261019-004100` and `20261031-015900`: a transient incomplete outside `incomplete` in 7 of about 76 scenario runs (`drawn`, `fresh-off`, `crowded` twice, `addremove`, `front-long`, `k8`); always one failed process, never Ice itself (no `ownReadNotOk`); every one but `k8` judged pass, none named in the report | MEASURED |
| E7 | Which process failed: unknown, the snapshot keeps only the count | MEASURED (`LabReport.swift`, `LabReportNames.completeness`) |

## 2. Design

D1 **The hide limit.** `run-lab.sh` gains `HIDE_LIMIT` (lab.env optional, default
1100, checked as the other limits). `hide()` alone waits for `verified` that long;
`STATUS_LIMIT` (600: `length-null`, `rest`) and `DRAWN_LIMIT` (900) stay. Why 1100: the
worst case is a reset just before verifying, about 465 + 16 + 443 = 925 s, about 950 s
with the quiet period and the clear-after; 1100 leaves about 15 %. It allows one
recoverable reset, not a discovery that keeps failing.

D2 **The snapshot names the failed reads.** `LabReportSnapshot` gains `incomplete`:
`[{pid, bundleID, isSelf}]`, from the set's `Completeness` and `staleProcesses` (a
failed pid not among them: `bundleID` null, `isSelf` false); empty when complete. The
key list is pinned in four places, changed together: `LabReportSnapshot.keys`,
`lab-tool.py`'s `SNAPSHOT_KEYS`, `test_lab_tool.py`'s and `test-lab.sh`'s fixtures.

D3 **Episodes.** `lab-tool.py` folds the snapshots of a report into episodes: one
begins at a snapshot whose completeness is `incomplete:`, ends at the next `complete`
one (or never). Each keeps its first and closing seq and time, `lengthApplied` and
`calibratedHiddenLength` when it began, and the failed processes over all its
snapshots, each classed `self` (`isSelf`), `member` (`com.icespike4.target`),
`reference` (`com.icespike4.protected`) or `other`. In `incomplete`, an episode that
begins inside the runner's `stall`..`settled` steps is the scenario's own and not
counted.

D4 **What an episode means for a verdict.** A counted episode with a `self` process
fails the scenario ("Ice's own discovery read failed"); one with a `member` process
(and no `self`) makes it `notEstablished` ("a member's discovery read failed"), which is
no exclusion, so the round is not clean; `reference` and `other` leave the verdict as
the judge made it. The verdict carries every counted episode.

D5 **What the report says.** Each round lists every counted episode by scenario,
processes, length and duration. A run line counts them ("discovery incomplete: N
episode(s) in M scenario run(s)", or "none"), and a met DoD reads "S4 DoD: met
(functional; ...)", never a bare "met".

Codex, round 4: the recovery after an episode is not traced (the machine leaves
`blocked` only through `quiet` and a baseline; `verified_rest` judges the verified
snapshot itself), and a geometry is recorded, not judged, until data says more.

## 3. Tasks (tests first)

| # | What | Tests first | DoD |
|---|---|---|---|
| T1 | IceCore: `LabReportFailedRead`, the snapshot's `incomplete`, `keys` | `LabReportTests`: keys, the line, pids resolved and not | `swift test` green |
| T2 | Ice: the snapshot built from `set?.completeness` and `set?.staleProcesses` | build | `xcodebuild` green |
| T3 | `lab-tool.py`: `SNAPSHOT_KEYS`, episodes, classes, the stall window, the verdict, the report | `test_lab_tool.py`: one episode over several snapshots; a never-closed one; processes changing inside one episode, `self` and `member` first; the stall window; fail, notEstablished, pass-with-episode; report lines and the DoD line | `python3 -I -m unittest` green |
| T4 | `run-lab.sh`: `HIDE_LIMIT` | `test-lab.sh`: allowlist and check; `hide` waits `HIDE_LIMIT`, `length-null` and `rest` `STATUS_LIMIT` | `test-lab.sh` green |
| T5 | `/simcodex`; STATUS: the seventh round, the transient incompletes as a MEASURED limit; restage; dry run in `icetest`; the owner's matrix run | | |
