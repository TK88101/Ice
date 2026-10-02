# Route C instrument, part 3 closing: deviation 5 D5.2 and the second pre-S0 manifest addendum

2026-10-03 · branch `wip/icebar-runner` (HEAD `7f469fe`, not re-cut from main) · final (Codex round 2, cap two) ·
closes `2026-10-03-icebar-c-runner.md` (section 9 row 12) under the pre-registration
`2026-09-30-icebar-c-prereg.md`, sha256 `a4e8b31b714b3acf2972fbfb3573f08ea41f9935ccaa25561606b6d6346fa572`
(v3 + deviations 1-5 + the first pre-S0 addendum).

Labels: MEASURED (file:line, test, command) or INFERRED (reasoning).

## 1. Goal, non-goals, constraints

Goal: D5.2's desktop-picture change (already committed in `7f469fe`) tested, reviewed
and frozen in a second pre-S0 manifest, with a second addendum drafted, reviewed by
Codex and **stopped for the owner**.

Not in this part: any `icetest` run (S0, S-adv, S1), any probe that injects events or
creates status items, any helper launch, Ice's own IceBar, push, merge. The live
`NSWorkspace.setDesktopImageURL` call is therefore **not exercised** here (stated, not
skipped silently); it first runs in the owner's sitting.

Constraints (owner, unchanged): pre-registration text unchanged except the scheduled
addendum, and that only after approval; `Packages/MenuBarCapture` and detector files
byte-equal to `af4baf1`, `Packages/` to `32d523a`; `Sources/VZGlyphs`,
`Sources/IceBarCorpus` unchanged (corpus 3, `freeze.json` `f8a64fbc…`); `IceBarOracle`,
`IceBarClaim` only for a real bug, logged; scratch outside `~/Documents`; no image in
the repository. Settled items (runner plan section 3, deviations 1-5, the first
addendum, K1, corpus 3 not re-checked, the deferred P2 and security LOW of section 9
row 9) are not reopened.

## 2. What exists (MEASURED, `git diff 1d671d3..7f469fe`)

- `SittingDriver` (`Sources/IceBarRunCore/SittingDriver.swift`): emits
  `.setDesktopPicture(Appearance?)` before an S-adv step whose variant's appearance
  differs from the picture now set, before S1 (`nil`: the original), and when the
  sitting is done with a staged picture still set; `desktopPictureSet(false)` ends the
  sitting `interrupted`. `Sitting.beforeSAdv` and `AppearanceDecision` removed.
- `LiveDesktopPicture` (`Sources/vizprobe/IceBarLive.swift`): two 64 px solid PNGs
  (grey 30, grey 225) written once into the sitting directory; each change logged with
  path, sha256 and the wall-clock stamp `RunnerLog.record` adds (`C2Run.swift:191`).
- Warm-up and settle after a change: every step is its own process (Q20) whose
  `StepRunner` runs the 24-capture warm-up (`Step.swift:95`) and whose baseline
  cadence enforces the settle (Q2); a picture change only ever happens between step
  processes, so D5.2's "repeats the 24-capture warm-up and the settle" is met by the
  next step itself. INFERRED from the code path; pinned by T2's test below.
- `icebarfreeze verify` fails on this tree (runner sources changed since `1d671d3`):
  the expected fail-closed state.

## 3. Defect found while reading (to fix, test first)

**B1** (`SittingDriver.desktopPictureSet`, MEASURED by reading; to be pinned red):
on a failed set the driver sets `picture = nil` and ends the sitting. If the failure
is the dark -> light change, the staged dark image is still on the desktop, the driver
now believes the original is there, and the `.done` branch never asks for the
restore. That breaks "the original picture is restored however the sitting ends".
Fix: on a failure outside `.done`, keep (or assume) a staged picture
(`picture = pendingPicture ?? picture`) and end the sitting, so `.done` requests one
restore; a failed restore in `.done` gives up (`picture = nil`) and keeps the result
already reached -- no loop.

**B2** (Codex r1; MEASURED `Sources/vizprobe/IceBarRun.swift:102-133`: the parent
`icebar-run` installs no signal handler, only the step children do): SIGINT, SIGTERM
or SIGHUP kills the parent with a staged picture left on the desktop. Fix: the parent
ignores the three signals' default action and a `SignalStop` object -- owned by
`IceBarSitting` for the whole of `run()`, holding its `DispatchSource`s, its state
behind an `NSLock` -- records the first signal (Codex r2); `runChild` gets a `stop` closure polled in its existing loop (the child is
terminated, as for a console loss), and the sitting loop turns the flag into
`driver.end(.interrupted("signal"))`, so the driver's `.done` branch restores the
picture on the normal path (never inside a handler). **Limit, stated in every record
of the guarantee**: SIGKILL, a crash or a power loss cannot restore; the first log
record (`desktopPicture.original`, written before S0) carries the original's path and
sha256 for a manual restore.

**B3** (Codex r1; MEASURED `IceBarLive.swift` `LiveDesktopPicture.init`): an original
picture that is `nil` or unreadable is accepted at the start and only fails at the
restore. Fix: a preflight before S0 -- the original's URL must exist and be readable
(its sha256 is recorded); otherwise the sitting ends `interrupted` before any step
and before any change.

## 4. Tasks

| # | task | DoD |
|---|---|---|
| T1 | runner plan section 9 row 13: D5.2's implementation record (warm-up and settle by the next step process; the original restored however the sitting ends, limits stated; a failed change interrupts) | row present |
| T2 | B1, test first in `SittingDriverTests`: (a) a failure at the first change (original -> dark) -> `interrupted`, one restore requested, then finished; (b) a failure at dark -> light -> `interrupted`, restore requested; (c) a sitting ended by the runner (`end(...)`) or by a step's safety stop during S-adv with a staged picture set -> restore requested before `.finished`; (d) a failed restore in `.done` keeps the result and terminates; (e) every `.setDesktopPicture` is followed by a `.run` (a new step process) or `.finished`, never by a sample of the same process. Then the fix | red (a/b at least) then green |
| T2b | B2 and B3 in `vizprobe` (executable, no unit test: section 6 R2); `IceBarStageTests`: a step's first 24 captures are warm-up and precede every baseline capture (Codex r1 P2; the step-side half of D5.2's re-warm) | builds; the stage assertion green |
| T3 | tests: `IceBarRunCoreTests`; `IceBarStageTests` in release with `-Xswiftc -enable-testing`; full probe `swift test` in debug (I7 group about 7 min; release I7 fails on main too, runner plan section 9 row 10) | all green; counts recorded |
| T4 | `/simcodex` once on the source changes `1d671d3..HEAD` (Sources, Tests of the probe package) | converged or rulings recorded; tests green after |
| T5 | `icebarfreeze`: split the one constant into `preregistrationAtCorpus3Freeze` (`e693654c…`, compared with `freeze.json`'s recorded hash and written to `corpus3.preregistrationAtFreeze`) and `preregistrationCurrent` (`a4e8b31b…`, compared with the file and written to `preregistrationSHA256Before`: the hash before the addendum that will cite this manifest). No schema change | builds; `write` no longer refuses on the pre-registration hash |
| T6 | manifest v2: a **new** file `docs/plans/2026-10-03-icebar-c-pre-s0-manifest-v2.json`; the first manifest stays byte-equal (`41b91f4d…`, cited by the pre-registration's first addendum); `stage-icebar.sh` verifies against v2. Order: commit T2-T5 and the `stage-icebar.sh` change as a `wip/` checkpoint (the tool refuses a dirty tree and records the revision), `write`, then `verify` passes, then commit the manifest | manifest sha256 and revision recorded; `verify` exit 0; a diff of v1 and v2 `sources` lists exactly the files changed since `1d671d3`; `renderings`, `chevronAlphaSHA256`, `corpus3` equal to v1's |
| T7 | second addendum draft `docs/plans/2026-10-03-icebar-c-pre-s0-addendum-2.md`: replaces only the manifest (v2 sha256, revision), lists each source whose hash differs from v1 with both hashes, states that D5.2's implementation (and B1's fix, T5's constant split, the `stage-icebar.sh` path) is the whole change, that no rule, threshold or expectation changes, and that corpus 3 is still not re-checked (its bound hashes equal v1's). Codex review (thecure), round cap two; **stop for the owner** | draft + review record in section 7 here |
| T8 | **after the owner approves only**: addendum under the pre-registration's section 9 ledger; re-hash; the new sha256 in the claim plan section 8 row 5, route C rule 6, runner plan section 9 | `shasum -a 256` recorded in all three |

Parallel candidates: none (a chain: tests -> review -> freeze -> addendum).

## 5. Acceptance

| # | check | how |
|---|---|---|
| C1 | suites green | T3's three commands; scratch under `/private/tmp/claude-501/` |
| C2 | frozen code untouched | `docs/plans/checks/check-a3a4.sh`; `git diff --exit-code 32d523a -- Packages`; `git diff --exit-code 6ab69ce -- Sources/VZGlyphs Sources/IceBarCorpus`; `git diff --exit-code 2948a45 -- Sources/IceBarOracle Sources/IceBarClaim` |
| C3 | pre-registration unchanged until T8 | `shasum -a 256` = `a4e8b31b…a572` |
| C4 | v1 manifest unchanged | `shasum -a 256` = `41b91f4d…5db5` |
| C5 | staging's check passes again | `icebarfreeze verify --manifest …-v2.json` exit 0 (run directly; `stage-icebar.sh` itself is not run: it stages into `icetest`'s shared directory) |
| C6 | v2 differs from v1 only where expected | T6's diff |
| C7 | nothing launched, no image in the repository | no `vzhelper` process; `git status --porcelain` shows no image |
| C8 | line coverage of `SittingDriver.swift` >= 80 % | `--enable-code-coverage` on `IceBarRunCoreTests` |

Test kinds: unit (`SittingDriver`), integration (the stage suite, unchanged, must stay
green), E2E (`icebarfreeze write` / `verify` on the real tree; the live picture change
is the owner's sitting).

## 6. Risks and rollback

- R1 (INFERRED): `setDesktopImageURL` on macOS 27 may succeed without the bar's luma
  moving into E5's range in time; then Q18 names the step inconclusive -- fail-closed,
  no rule changes.
- R2: `LiveDesktopPicture` has no unit test (AppKit, live desktop); its decisions
  (when, which, failure handling) live in `SittingDriver`, which is tested. Its first
  real exercise is the sitting.
- R3: SIGKILL, a crash or a power loss leaves the staged picture (section 3, B2's limit).
- Rollback: `git reset --hard 7f469fe` on the `wip/` branch (local only, nothing pushed
  from this part).

## 7. Review record

Round cap set before round 1: two.

### Plan review, round 1 (Codex gpt-5.6-terra): 3 P1, 1 P2

| finding | ruling | change |
|---|---|---|
| P1 a `nil` or unreadable original picture is accepted, then fails at the restore | accepted | B3: preflight before S0, sha256 recorded, else `interrupted` before any step |
| P1 "restored however the sitting ends" contradicts the signal limit | accepted, modified | B2: the parent turns SIGINT/SIGTERM/SIGHUP into a normal end, restore on the normal path; the guarantee is worded with its limit (SIGKILL, crash) wherever it is recorded |
| P1 `icebarfreeze verify` compares only `sources`; should re-verify every bound field and the manifest's own sha256 | rejected (owner's ruling stands) | `verify`'s meaning -- "`stage-icebar.sh` refuses to stage unless every one [source] still matches" -- is the text of the first pre-S0 addendum, reviewed twice and approved by the owner (runner plan section 9 rows 11-12); widening it is a change beyond D5.2 and outside this part. The other fields are records of what `write` checked at freeze time; the manifest's own sha256 is bound by the pre-registration's addendum and by git |
| P2 T2(e) does not show the next step really warms up | accepted | T2b's stage assertion (24 warm-up captures before any baseline capture) |

### Plan review, round 2: 1 P1 -- accepted; cap reached, plan final

| finding | ruling | change |
|---|---|---|
| P1 B2's flag unsynchronised, sources not retained; no test of the signal path | accepted | `SignalStop` (lock-guarded state, sources held by the sitting until `run()` returns); the child is terminated at the next poll and the loop ends the driver `interrupted` after the child is reaped. The restore after such an end is pinned at the driver (T2 c); the executable's wiring itself has no unit test (R2) |

Trend: 3 P1 + 1 P2 -> 1 P1 (a detail of an accepted fix) -> closed by specification. The
rejection of the `verify` widening was not contested in round 2.

### /simcodex (Phase 3), one round, on `git diff 1d671d3` of the probe's Sources and Tests

Tests before the round: `IceBarRunCoreTests` 97 green; `IceBarStageTests` release 25 green;
full probe `swift test` debug 648 tests in 11 bundles green (I7 group 55 tests, 410 s; the
stage suite takes 2354 s in debug).

| source | finding | ruling |
|---|---|---|
| /simplify, 4 angles (reuse, simplification, efficiency, altitude) | 0 P1 | applied from the P2s: `if let pendingPicture` for the `??` on an optional; `LiveDesktopPicture.set` as one `switch` with one label; the appearance levels as an exhaustive `switch`; one `terminated` flag in `runChild`; two stale K2 wordings in `SittingDriverTests` |
| security review (once) HIGH | after SIGHUP the terminal is gone; `FileHandle.standardError.write` raises on EIO and SIGPIPE was not ignored on the `icebar-run` path, so the parent could die before the restore | fixed: SIGPIPE ignored by `SignalStop`, progress lines written with `try?` |
| security MEDIUM | the restore depended on re-reading the original's bytes | fixed: the original is always set; an unreadable file only leaves the hash out |
| security MEDIUM | the restore dropped the original's scaling, clipping and fill colour | fixed: `desktopImageOptions` read at the start and handed back |
| security MEDIUM | a failed restore was visible only in `runner.jsonl` | fixed: a progress line names the original's path |
| security LOW | a staged PNG already at its path in the shared directory was trusted | fixed: removed and rewritten at each change; the logged sha256 is of what was read back |
| security MEDIUM | a step that ignores SIGTERM makes the tool stoppable only by SIGKILL | deferred: each step has its own watchdog (20 or 28 min) and exactly-once finisher |
| Codex P1 | the parent's ignored SIGTERM is inherited by the step child; a single SIGTERM sent before the child installs its handlers is lost | accepted, fixed: for the stop cause SIGTERM is re-sent at every poll until the child is reaped (C2's console-loss path unchanged). Codex re-read: closed, 0 P0 / 0 P1 |

Deferred P2 (not fixed): the three restore checks in `SittingDriver.next()` as one
reconcile rule; one shared helper for the `SIGINT/SIGTERM/SIGHUP` source loop (five
copies in `vizprobe` / `icewatch`); `SAdvStep.variant` as a driver-private helper; the
signal check at the top of the sitting loop; `pictureThenStep` on `drive`'s event log;
a dynamic or per-Space wallpaper comes back as a static file on the current Space
(INFERRED; the sitting's account uses a system picture).

### Second addendum review (Codex gpt-5.6-terra, thecure), round cap two

Manifest v2 `docs/plans/2026-10-03-icebar-c-pre-s0-manifest-v2.json`, sha256
`18187e2c9f217497ad4e12ccf10a9c04747fa84a7ff5d3ba555149580b8955c5`, revision `d8e05a5`;
`icebarfreeze verify` exit 0; seven source hashes differ from v1 (the files git lists as
changed since `1d671d3`), `renderings`, `chevronAlphaSHA256` and `corpus3` equal.

| round | finding | ruling |
|---|---|---|
| 1 | P1 "seven source hashes, nothing else" ignores the revision and pre-registration hash fields | accepted, reworded |
| 1 | P1 "the whole change" ignores three changed test files | accepted: scoped to what the manifest freezes, the test files listed |
| 2 | none -- CONVERGED; every hash, the equalities and each row's description confirmed in round 1 | -- |

**Stopped for the owner**: draft `2026-10-03-icebar-c-pre-s0-addendum-2.md` needs approval
before T8.
