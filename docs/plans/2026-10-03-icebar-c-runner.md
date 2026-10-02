# Route C instrument, part 3 of 3: cadence, accounting, the runner, the pre-S0 freeze

2026-10-03 · branch `wip/icebar-runner` (from main `2948a45`) · final (Codex converged, round 2) ·
implements `2026-09-30-icebar-c-prereg.md` v3 + deviations 1-4 (sha256
`e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3`), sections 2, 4, 5,
6, 7 and 9: U18-U20, U24, the runner (S0, S-adv, S1), the live wiring of
`OverlapGuard` and `BControl` (deviation 2 C3, C5), the pre-S0 freeze manifest and
its section 9 addendum.

The pre-registration is not changed by this plan except by the addendum that
section 6 of it schedules (section 7 below). Where it leaves a detail open,
section 3 fixes a reading **before** the code is written; each reading only
chooses among what the text allows, and where two are possible it takes the
fail-closed one. A result that needs a registered rule changed stops the work and
goes to the owner as a section 9 deviation, never an edit here.

Labels: MEASURED (file:line or run id) or INFERRED (reasoning). Nothing in this
part runs in `icetest`, launches a helper, creates a status item or posts an event.

## 1. Scope and interfaces with parts 1 and 2

| part | status | this plan's contact with it |
|---|---|---|
| 1 | merged `6ab69ce` | **uses, does not change**: `Oracle.label`, `CaptureLabels`, `Controls` (`positiveMisses`, `memberMisses`, `cycleInconclusive`), `AttemptVerdict.evaluate`, `ChevronRule.fromAX`, `OverlapGuard.evaluate`, `WindowBounds`, `BControl.evaluate`, `BObservation`, `OracleContext`, `OracleTemplate`; `CorpusTemplates` (`IceBarCorpus`: the very templates and the K1 chevron cut that corpus 3 validated); `GlyphRenderer` and `Glyphs.image(_:side:coloured:)` (`VZGlyphs`). `VZGlyphs` and `IceBarCorpus` are frozen by corpus 3 and not touched; `IceBarOracle` only for a real bug, logged in the instrument plan's section 8 |
| 2 | merged `2948a45` | **uses, does not change**: `StartupCheck.evaluate(claim:detector:scale:)`, `HiddenBaseline.evaluate(kept:frozen:references:visible:parameters:)` -> `BaselineVerdict`, `Claim.decide(fold:baseline:captures:parameters:)` -> `ClaimOutcome` (evaluates `RegionClear` once; this part never calls `RegionClear.evaluate`), `ClaimParameters.preRegistered`. `IceBarClaim` only for a real bug, logged in the claim plan's section 8 |
| 3 | this plan | U18 (cadence and kept-sample selection), U19 (attempts and observations), U20 (fallback accounting), the runner (S0, S-adv, S1 sequencing and one-step processes), vzhelper's coloured flag, the roster-to-glyph manifest, member rest controls, `OverlapGuard` per capture on window-server bounds, `BControl` over S0 and S-adv, U24 in `build.sh`, the pre-S0 freeze manifest and addendum |

Frozen code reused as is (never edited): `MenuBarCapture.Sampler` (the frozen
bracket: capture, AX read, capture), the existing vizprobe capture and AX
adapters, `StripAssessor.baseline` / `observe`, `FoldWitness.isPill`,
`DetectorParameters`.

Not in part 3: any `icetest` run (S0, S-adv, S1 wait for the owner's time), any
probe that injects events or creates status items, Ice's own IceBar, any push or
merge, S2-S5 wiring.

## 2. Goals, non-goals, constraints

Goal: everything S0, S-adv and S1 need to run unattended in `icetest` once the
owner names a time, with every decision a pure, tested function and every live
seam behind a protocol driven by fakes in tests; then the pre-S0 manifest.

Constraints (owner): pre-registration unchanged except the scheduled addendum
(A5); `Packages/MenuBarCapture` byte-equal to `af4baf1`, `Packages/` byte-equal to
`32d523a` (A3, A4); `Sources/VZGlyphs`, `Sources/IceBarCorpus` unchanged (A6);
build scratch outside `~/Documents`; images only under
`~/IceReverse-evidence/<run id>/` (tests build strips in memory; the runner's
staging directory `/Users/Shared/IceReverse-icebar/evidence` in `icetest` follows
C2's pattern and is copied to `~/IceReverse-evidence/<run id>/` by the owner).

## 3. Readings fixed before code

| # | detail | fixed as | why |
|---|---|---|---|
| Q1 | sample timing | the runner records each sample's **start** (before the bracket's first capture) next to the frozen `ObservationSample` (whose `time` is the bracket's end): `TimedSample(start, sample)`. Spacing is checked on starts; the scheduler sleeps until each nominal start and never starts early | "1.0 s apart" / "0.5 s apart" are minima the scheduler can guarantee only on starts |
| Q2 | baseline cadence (U18) | exactly 5 samples; the first start >= 1.0 s after the last spacer write or helper change (settle); start gaps >= 1.0 s; first start to last end <= 10 s, else **timeout** (no baseline, cause `timeout`); kept = samples 2-5, all 8 captures, passed to `HiddenBaseline.evaluate`; the frozen `StripAssessor.baseline` gets all 5 (claim plan R1). 4 or 6 samples: no baseline; a settle or spacing violation: no baseline (`cadence`) | section 2; U18 "4 samples -> no baseline" |
| Q3 | attempt cadence | exactly 3 samples, start gaps >= 0.5 s, the first attempt's first start >= 1.0 s after the last change; attempt n+1 starts >= 1.0 s after attempt n's last end; at most 3; stop after the first attempt whose claim is **granted** (`Claim.decide(...).granted`). The observation's span (first attempt's first start to last attempt's last end) > 10 s: not granted, cause `timeout` (a NO-GO of any attempt still stands) | section 2 "stopping at the first granted one"; the stop rule reads the claim, not the oracle, so the oracle may run after the observation |
| Q4 | one attempt's inputs | fold = frozen `observe(baseline: frozen, targets: [], references: visible ids, samples: the 3, parameters: .preRegistered)`; captures = before, after of each sample in time order (6); `Claim.decide(fold:baseline:captures:)` once. Oracle per capture with `chevron:` the K1 template; context: notch = geometry's; agent frames = the canonical set (always the first kept read's on-bar frames, accepted or refused baseline; no kept read -> every attempt of that cycle inconclusive) union that sample's on-bar frames; leftmost reference origin = the frozen template origin (rest captures: the leftmost visible helper's AX `minX`). `AttemptVerdict.evaluate` per sample (its 2 captures, its read, its visible helpers' `minX`, the first non-clear of its 2 captures' `OverlapGuard` outcomes); the attempt = OR of `seesMember`, `seesChevron`, `chevronNotEvaluable`, `inconclusive` over its samples | section 5 per capture / per attempt; `AttemptVerdict` takes one `visible` list, and AX `minX` is per read |
| Q5 | attempt classification | precedence: **NO-GO** if granted and the oracle sees a member or `«`; else **inconclusive** if `inconclusive` or `chevronNotEvaluable` (a granted attempt included: it is not "granted and clean"); else **granted** (clean) if granted; else **not granted**. In S1, any capture of any phase with a member `drawn(full)` in zone `leftOfNotch`, or an unexplained sighting whose box ends at or left of the notch's left edge, is NO-GO (route C S1 row; deviation 2 C1's fail-closed "sees a member") | section 4 "Safety, per attempt"; fail-closed |
| Q6 | observation outcome and cause | outcome: **NO-GO** if any attempt is; else **inconclusive** if any attempt is inconclusive and none granted (clean), an observation timeout included (fail-closed: it then counts toward the > 2 rule); else **granted** if some attempt is granted (clean) within the 10 s span; else **not granted**. One cause per observation, first match: `noGo`; `inconclusive`; observation `timeout`; baseline `timeout` (Q2) -> `timeout`; baseline `cadence` -> `baseline refused`; the baseline's refusal (`.contrast`, `.contrastUnmeasurable` -> `contrast gate`; `.texture` -> `texture`; every other -> `baseline refused`); the last attempt's claim reasons (`.fold(.unreadable)` -> `fold unreadable`; `.fold(.present)` -> `fold present`; `.notClear` -> `not clear`). Oracle-clean = no attempt sees a member or `«` | section 4 "rate split by cause"; `fold present` is listed apart because the registered list does not name it (counted, never dropped) |
| Q7 | refused-baseline cycles | all 4 observations are taken (3 attempts each, since none can be granted), oracle on every capture; each enters the numerator only when oracle-clean | section 4 numerator; prereg r2 P1 |
| Q8 | cycle (S0, S1) | rest control (1 sample: every member and visible helper `drawn(full)`, visible positive controls) -> `length L` -> settle -> baseline (Q2) -> 4 observations whose first starts are nominally 5 s apart (start i >= start 0 + 5 i s, never earlier; lateness recorded) -> `rest` -> settle -> restore control (1 sample, as the first). A member miss in either control, or a control whose appearance variant (E5 luma), colour variant or indicator state (any on-bar `FoldWitness.isPill` frame) differs from the hold's, makes the cycle **inconclusive**: each of its observations then counts as inconclusive (cause `member control`); a NO-GO stays NO-GO | section 2 "per S1 cycle"; section 5 "Member controls" |
| Q9 | fallback accounting (U20) | per length: 20 observations (4 x 5 cycles); numerator = not granted and oracle-clean, plus every inconclusive; **repeat inconclusive** iff inconclusive > 2; else pass iff numerator <= 5, fail iff >= 6; counts by cause recorded. A NO-GO anywhere ends the study (route C 4.0 rule 5) | section 4 |
| Q10 | roster and glyphs | helper id = glyph name; visible V = `reference`, `alt`, `target` (instrument D1, the corpus's references); members = the other 16 in `Glyph.allCases` order; a profile with k members uses the first k. vzhelper form: `--items 1 --identifiers vz-icebar-<glyph> --glyphs <glyph> [--coloured] --autosave vz-icebar-<glyph>`; members under `com.icespike4.target` (`Target.app`), visible helpers, spacer and Menus under `com.icespike4.protected` (C2's ids; no new bundle id). `--coloured` on members only (S-adv's coloured variant); visible helpers stay ordinary (they are the frozen references and the contrast gate's measure). Each step's manifest records role, glyph, coloured, pid, bundle id, identifier | section 5 "The manifest records the roster-to-glyph mapping"; build.sh's bundle-id rule |
| Q11 | placement | launch order: Menus, the 3 visible helpers, the spacer, then members, each after the previous one's AX frame is discovered; then a gate on AX frames: every member's `maxX` <= the spacer's `minX`, the spacer's `maxX` <= every visible helper's `minX`, all on-bar; else the step is inconclusive (no cycle runs). Helper domains forgotten and verified empty before the first launch and after teardown | INFERRED: a new status item appears left of the existing ones; C1's preferred-position plan existed for the owner's crowded bar, `icetest` has system items only; the gate makes the inference fail-closed |
| Q12 | window-server bounds (C3) | after **every** capture (a `StripCapturing` decorator inside the capture path) the runner lists all windows (`CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)`, off-screen included) and selects per helper pid the windows at `kCGStatusWindowLevel`: exactly one -> its bounds; none or more -> not listed. `OverlapGuard.evaluate(roster: every launched glyph helper, bounds:)` per capture | deviation 2 C3 "at each capture ... every helper ... no helper exempt" |
| Q13 | S0's C3 measurement | S0 records per capture which helpers are listed, and for visible helpers the deltas of x, y, width and height between window bounds and the same sample's AX frame; C3 holds iff every helper is listed in every capture and every visible delta <= 1 pt; else the sitting stops before S-adv (`中斷`, owner decides) | deviation 2 C3 |
| Q14 | `BControl` (C5) | every capture of S0 and S-adv (baseline, observation, control) yields `BObservation(episode, axChevron: (a) on that sample's read, pixels: that capture's chevron)`; an **episode** is a maximal run of consecutive reads with (a); numbering continues across S0 and S-adv. After S-adv, `BControl.evaluate`: `.valid` -> S1 may run; `.mismatch` / `.insufficient*` -> the sitting stops before S1 (`中斷`) | deviation 2 C5 |
| Q15 | S0 | Menus `long`, k = 2 members, 3 visible helpers, ordinary glyphs, 5 cycles (Q8) at L = 728 pt (MEASURED: C1 smoke 5/5 at 728, `20260928-202509-vzc1`; the question -- does the claim stay ungranted -- is the same at any L). Pass: in 5/5 cycles no observation granted, both members `drawn(full)` at every restore control, and after Menus quits a final control sample with every helper `drawn(full)`. A granted observation: NO-GO | route C S0 row leaves L open |
| Q16 | section 8 report and check | from S0's `BaselineVerdict.measurements`: max kept distance vs `T_agree`, largest row cluster vs 16 and max row deviation vs `T_bg`, C_r vs 129, texture max vs 12. A **contradiction** = every S0 baseline that has the number fails its inequality (the registered examples: "C_r < 128 in every S0 baseline, or kept captures never within 8"); a single failing baseline is a refused baseline, i.e. "a number that merely makes the fallback rate high", which section 8 says "is not a contradiction and changes nothing". Contradiction -> the sitting stops before S-adv. **No S0 baseline reached the pixel clauses** (all refused by fold, shape, frames or region): the report says so and the sitting stops before S-adv too (section 8 cannot be checked; fail-closed) | section 8; risk K1 |
| Q17 | S-adv | k = 4, 3 visible, Menus `short`; four variants (dark, light) x (ordinary, coloured members); per variant two sweeps, each **up** from 16 pt in 16 pt steps until a step whose every capture is conclusive (no control miss, no ambiguity, overlap clear) and shows no member (`seesMember` false; `«` is not part of the endpoint) -- 1000 pt reached first: the sweep is inconclusive -- then **down** in 16 pt steps to 16 pt, then `rest`. A member rest control (Q8's control sample, same states) before each sweep's first push and after its return to rest; a miss makes the sweep inconclusive, re-run at most twice, a third is not shown (failure). Each step: settle, baseline (Q2), one observation (Q3), oracle on every capture; a granted step where the oracle sees a member or `«`: NO-GO. Then the `«` rest state: members 5..16 launched one at a time at rest until a read shows (a); then episodes (quit the last member, confirm (a) gone, relaunch it, confirm (a)), each with a baseline and an observation, until `BControl` has >= 10 (a)-captures from >= 2 episodes or a 20 min time box ends. No (a) with 16 members: `BControl` insufficient -> stop before S1 | route C S-adv row; deviation 2 C5 |
| Q18 | S-adv appearance variants | the variant is **named** by the baseline's median luma outside the notch (E5: dark < 118, light > 138); a step whose baseline names the other variant, or neither, is inconclusive. **How** the variant is produced is open (section 8, K2): the variant loop is code behind an `AppearanceSetting` seam whose live implementation is **not wired**; `icebar-run` refuses to start S-adv until the owner's decision is implemented (no per-invocation workaround is offered as compliant) | E3 vs E5, section 8 |
| Q19 | S1 | profiles k = 1, 2, 4, 8, then 12 and 16 while each passes, each at `short` then `mid`; per profile: coarse 520-960 pt by 16 pt, expansion and 4 pt refinement by `C2Band` (`band`, `nextExpansion`, `refinementPoints`), one cycle (Q8) per length; a length is **in band** (`C2Reading.hiddenNoFold`) iff the cycle is conclusive, no NO-GO, both controls pass and at least one observation is granted and clean; an inconclusive cycle is retried up to 3 times (`C2Retry.settleReading`), then `notShown`. Midpoint L = ((lo + hi) / 2).rounded() (C2's 32 pt minimum is an intersection rule, not route C's). At L: 5 cycles, accounted by Q9; repeat inconclusive -> re-run, at most twice, a third is not shown (failure); a fail is replicated once in a new step process before it counts. k passes iff both menus pass. Capacity search, k = 3 confirmation, "no band at k = 1: NO-GO", "capacity below 4: the sitting ends" exactly as the route C S1 row | route C S1 row and section 3 |
| Q20 | processes | as C2: `vizprobe icebar-run` (the sitting's sequencer: guards, one child per step, verified final manifests, Chinese progress lines and the final `結果：…｜…｜…` line of route C 7a) and `vizprobe icebar-step` (one profile, one batch of at most 14 lengths -- as C2: the parent keeps the profile's points across batches, hands out the pending lengths in order, re-runs a short batch without its measured lengths, and a step's manifest lists the lengths given and measured, so no candidate is skipped silently -- a 20 min watchdog, its own launch, warm-up of 24 captures 0.25 s apart, cycles, teardown). Mapping: PASS (a measured capacity included, F1 accepted) -> `結果：完成`; NO-GO or not shown -> `結果：失敗`; console left, signal, watchdog, and every stop-for-the-owner of Q13, Q14, Q16, Q19 (capacity < 4) -> `結果：中斷`; safety stop -> `結果：安全停止` | route C 7a; C2's run pattern (MEASURED `20260929-234942-c2A`) |
| Q21 | guards (every step) | isolated account (`C2Guards.userAllowed`), console session, geometry (`--expect-geometry`), `StartupCheck.evaluate` (scale 2, invariants) before the first capture (`.abort` -> no capture); roster before launch only `com.apple.*`, after launch only `com.apple.*` plus the step's own helper pids; anything else: safety stop | route C 4.1; prereg U23 |
| Q22 | evidence | every capture kept as PNG in the step directory with its sample index; `cycles.jsonl`, one record per attempt (claim, fold, `RegionClear`, verdict, overlap per capture, oracle labels), per observation, per cycle; `manifest.json` (roster-to-glyph, binary hashes, git revision, pre-registration sha256); `manifest.final.json` last, with every file's sha256 | section 4 "also recorded" |

## 4. Design

New, all under `docs/macos-27/probes/visibility` (not linked into Ice):

- Reused, not duplicated (Codex r1 P2): C2's step-process pattern in `vizprobe`
  (`runChild`, `hashes(of:)`, `readBack`, console check), `C2Manifest.verify`,
  `C2Guards`, `C2Band`, `C2Retry`, `GuardedStage`'s signal/watchdog shape.
- `Sources/IceBarRunCore/` (new target; standard library + IceCore, IceBarOracle,
  IceBarClaim, C2Core; Swift 6): `Cadence` (Q1-Q3, U18), `AttemptJudge` (Q4-Q6,
  U19), `FallbackTally` (Q7-Q9, U20), `Roster` (Q10, vzhelper arguments),
  `PlacementCheck` (Q11), `StatusWindows` (Q12's pure selection over window-list
  entries), `S0Judge` and `Section8Check` (Q13, Q15, Q16), `ChevronEpisodes` (Q14),
  `SAdvPlan` (Q17-Q18), `S1Sequencer` (Q19), `SittingSequencer` and `ProgressLine`
  (Q20, the 7a strings).
- `Sources/IceBarStage/` (new target; + MenuBarCapture, VZGlyphs, IceBarCorpus;
  no AppKit): `IceBarEnvironment` (seams: capturer, AX reader, window lister,
  helper launcher and defaults, Menus control, pump/clock, evidence, roster
  scanner), `BoundsRecordingCapturer` (Q12), `CycleRunner` (Q8, with the frozen
  `Sampler`), `StepRunner` (launch, placement, warm-up, S0/S-adv/S1 step bodies,
  teardown).
- `Sources/vizprobe/IceBarLive.swift`, `IceBarRun.swift`: the live environment
  (existing `HelperControl`, `HelperDefaults`, `CGWindowListStripCapturer`, the
  live AX reader, `LiveFrontmost`, `CGWindowListCopyWindowInfo`) and the
  subcommands `icebar-run`, `icebar-step`, `icebar-dry` (no launch, no capture:
  loads the templates, checks K1's sha256, `StartupCheck` at the screen's scale,
  prints the roster manifests).
- `Sources/vzhelper/main.swift`: `--coloured` (the item's image is
  `Glyphs.image(glyph, side:, coloured: true)`); nothing else changes.
- `Sources/icebarfreeze/main.swift` (new executable): writes the pre-S0 manifest.
- `build.sh`: first calls `docs/plans/checks/check-a3a4.sh` (U24);
  `stage-icebar.sh` and `run-icebar.sh` modelled on the C2 pair (K1 copied to the
  shared directory and checked against its pre-registered sha256).
- `docs/plans/checks/check-a3a4.sh [repo]`: `git diff --exit-code af4baf1 --
  Packages/MenuBarCapture` and the ten detector files
  (`Packages/IceCore/Sources/IceCore/{DetectorParameters,Ink,StripImage,Template,TemplateMatcher,CaptureStability,FoldWitness,StripAssessor,MenuBarItemVisibility,MenuBarItemCacheState}.swift`,
  the list of `2026-09-25-residuals.md` section 2); `test-check-a3a4.sh` runs it on
  a throwaway worktree outside `~/Documents`, untouched (must pass) and with one
  frozen file touched (must fail).

## 5. Tasks (TDD: each test written and seen failing before its code)

| # | task | DoD |
|---|---|---|
| T1 | targets skeleton; U18 (5 samples -> kept 2-5, 8 captures; 4 and 6 -> no baseline; settle < 1.0 s, a gap < 1.0 s -> refused; span > 10 s -> timeout; attempt gaps 0.5 s; attempt-to-attempt 1.0 s; observation span > 10 s) red; `Cadence` green | `swift test --filter IceBarRunCoreTests` red then green |
| T2 | U19, every registered case plus Q5's precedence (granted + inconclusive is not clean; NO-GO on attempt 1 even if attempt 2 is clean; stop after the first granted; timeout keeps a NO-GO) red; `AttemptJudge` green | red then green |
| T3 | U20, every registered case plus Q6's cause mapping and Q8's cycle-inconclusive propagation red; `FallbackTally` green | red then green |
| T4 | `Roster`, `PlacementCheck`, `StatusWindows`, `ChevronEpisodes`, `Section8Check`, `S0Judge` red, green | red then green |
| T5 | `SAdvPlan`, `S1Sequencer` (band, expansion, refinement, retries, midpoint, repeat-inconclusive re-runs, replication, capacity search incl. 12/16, integers after a failure, k = 3, capacity < 4, no band at k = 1), `SittingSequencer`, the 7a lines red, green | red then green |
| T6 | vzhelper `--coloured`; the `Roster` argument test asserts the flag on members of a coloured variant only | build + test |
| T7 | `IceBarStage` on an instrumented fake environment (a synthesized bar drawing the glyph renderings; every capture numbered and tagged with its phase: warm-up, rest control, baseline, attempt, restore control, S-adv step, `«` episode). **Integration**: (a) `OverlapGuard` call site -- exactly one bounds read per capture for every roster helper, every phase; a missing window or a 0.6 pt overlap injected into each phase in turn -> that attempt (or control, or step) inconclusive; 0.5 pt -> clear; (b) `BControl` call site -- exactly one `BObservation` per S0 and S-adv capture (warm-up excluded, recorded); (a) true / (b) false injected into each phase in turn -> `.mismatch` -> the sitting stops before S1; (a) with the chevron drawn -> `.valid` after >= 10 captures in 2 episodes; (c) a member missing at a rest control -> cycle inconclusive; (d) `Claim.decide` once per attempt, and no call of `RegionClear.evaluate` in `Sources/IceBarRunCore` or `Sources/IceBarStage` (source scan in the test) | red then green |
| T8 | vizprobe live wiring, `icebar-dry`; `stage-icebar.sh`, `run-icebar.sh` | `build.sh` builds; `icebar-dry` runs in the owner account and launches nothing (E2E) |
| T9 | U24: `check-a3a4.sh` + `test-check-a3a4.sh` red (script absent), green; `build.sh` calls it first | test script exit 0 |
| T10 | coverage >= 80 % lines per file of `IceBarRunCore`, `IceBarStage`; acceptance A1-A10 | section 6 |
| T11 | `icebarfreeze` writes the manifest (section 7); addendum drafted; Codex review; **stop for the owner** | manifest JSON + draft + review record |
| T12 | after the owner approves: the addendum into section 9, re-hash; the new sha256 recorded in the claim plan section 8 row 5, route C rule 6, and section 9 here | `shasum -a 256` recorded in all three |

Parallel candidates: none (each task consumes the previous one's types; T6 and
T9 are small). Checkpoint commits on `wip/icebar-runner` after T5, T7, T10 (local).

## 6. Acceptance

| # | check | how |
|---|---|---|
| A1 | new suites green | `swift test --scratch-path /private/tmp/claude-501/icebar-runner --filter 'IceBarRunCoreTests\|IceBarStageTests'` |
| A2 | line coverage >= 80 % per file of `Sources/IceBarRunCore`, `Sources/IceBarStage` | `--enable-code-coverage`, `llvm-cov report` |
| A3 | MenuBarCapture frozen | `git diff --exit-code af4baf1 -- Packages/MenuBarCapture` |
| A4 | Packages frozen | `git diff --exit-code 32d523a -- Packages` |
| A5 | pre-registration unchanged until T12 | `shasum -a 256` = `e693654c…7eb3` |
| A6 | corpus-3 sources frozen | `git diff --exit-code 6ab69ce -- Sources/VZGlyphs Sources/IceBarCorpus`; `freeze.json` `f8a64fbc…` |
| A7 | oracle and claim unchanged or logged | `git diff --exit-code 2948a45 -- Sources/IceBarOracle Sources/IceBarClaim`, or a row per change in their plans' section 8 |
| A8 | nothing else broken | full probe `swift test` (I7 group about 7 min); `build.sh` builds (U24 included) |
| A9 | U24 bites | `test-check-a3a4.sh` exit 0 |
| A10 | no image in the repository; no helper launched | `git status --porcelain` shows no image; no `vzhelper` process during the session |

Test kinds: unit (T1-T5), integration (T7: the stage + frozen `Sampler` + oracle +
claim + guard + `BControl` on a fake bar), E2E (T8: `icebar-dry` and `build.sh`;
the live run is the owner's sitting -- stated, not skipped silently).

## 7. Pre-S0 freeze manifest and addendum (T11, T12)

**Manifest** (`icebarfreeze --out docs/plans/2026-10-03-icebar-c-pre-s0-manifest.json`;
text only; refuses a dirty tree): sha256 of every `.swift` file of `Sources/VZGlyphs`
(the 13 new glyphs' source with the 6 old), `Sources/IceBarCorpus` (the generator),
`Sources/IceBarOracle`, `Sources/IceBarClaim`, and -- beyond section 6's list,
fail-closed (Codex r1) -- everything that runs in a sitting: `Sources/IceBarRunCore`,
`Sources/IceBarStage`, `Sources/vizprobe`, `Sources/vzhelper`, `Sources/C1Core`,
`Sources/C2Core`, `Package.swift`, `build.sh`, `stage-icebar.sh`, `run-icebar.sh`;
`stage-icebar.sh` refuses to build unless every one of these hashes equals the
manifest's, and each step records its binaries' sha256 next to the manifest's
sha256; every glyph's 1x/2x ordinary alpha and
coloured RGB rendering (`GlyphRenderer`, the coloured rendering path); the K1
chevron template's alpha; corpus 3's `freeze.json` (`f8a64fbc…`) and `check.json`
(`1844ac22…`), with every PNG re-hashed against `freeze.json` at manifest time; every `kInputs` entry of `freeze.json` (K1-K4, K3 included) re-hashed against its
recorded and pre-registered sha256; the pre-registration's sha256 before the
addendum (`e693654c…`) and the git revision. It asserts and records that every `VZGlyphs`, `IceBarCorpus` and
`IceBarOracle` source hash equals the one in corpus 3's `freeze.json`, and that every
rendering and the chevron hash equal its records (the oracle and generator that
were checked are the ones frozen).

**Addendum** (appended to section 9 under its ledger, after review and the owner's
approval): the manifest's sha256, a per-file table of the source hashes, the
aggregate rendering and corpus hashes, and:
1. *R15, one line (claim plan section 8 row 5)*: "Part 2 R15, approved by the
   owner: U5's and U8's 'accepted' cases mean the named clause accepts; the
   texture bound (deviation 2 C2) stays an added, independent refusal, so for
   those inputs the whole baseline verdict is `.texture`; no threshold,
   expectation or refusal is loosened."
2. *Corpus 3 is not re-checked (claim plan section 8 row 6)*: its single check ran
   under `e693654c…` (instrument plan section 8 row 12) and is the result
   (deviation 2 C6, deviation 4 D4.2); a re-run would be a second experiment.
   After the re-hash `vzcorpus check` refuses corpus 3 by design
   (`Sources/vzcorpus/main.swift:109-111`) and is not run, and `vzcorpus` is not
   changed; corpus 3's standing rests on the manifest's equality of every frozen
   source, rendering, template and image hash with its `freeze.json`.

T12 records the new sha256 in the claim plan section 8 row 5 (the canonical
record), in route C rule 6 (as each deviation's), and in section 9 here.

## 8. Risks and open items

- **K1 (INFERRED, likely): S0 yields no section 8 numbers.** With a long menu, C2
  read the frozen baseline fold `unreadable` in every attempt (MEASURED
  `20260929-234942-c2A`); `HiddenBaseline.evaluate` stops at the fold (claim plan
  R14), so S0 may produce no measurement and Q16 stops the sitting before S-adv.
  Not fixable within the registered text (R14 is part 2's, S0's profile is route
  C's); raised for the owner with the addendum, not changed here.
- **K2 (open, owner): E3 vs S-adv's dark and light bar.** E3 registers a desktop
  picture static for the whole sitting; S-adv needs both appearance variants and
  O3 puts S-adv in the same sitting as S0 and S1; E5 says the variant is produced
  by the desktop picture. A change between variants contradicts E3's text. Until
  the owner decides (a deviation, after thecure), S-adv cannot run (Q18); S0 and
  everything before S-adv can.
- K3 (INFERRED): Q11's launch-order placement fails on 27 -> the step is
  inconclusive at the gate, before any cycle; recorded, never a verdict.
- K4 (INFERRED): status-item windows not listed per helper on 27 (FINDINGS: no
  per-item windows) -> Q13 stops the sitting before S-adv, as deviation 2 C3
  registers.
- K5: S1 with k up to 16 may exceed route C's 3-4 h estimate (INFERRED about 5 h);
  per-step watchdogs only.
- Rollback: new targets and files, a vzhelper flag and a `build.sh` line;
  `git checkout main -- docs/macos-27/probes/visibility docs/plans/checks`.

## 9. Implementation notes

| # | date | note |
|---|---|---|
| 1 | 2026-10-03 | T1-T4: tests written and seen failing (missing types) before code. T5: tests written first but compiled together with the code, no separate red run; T7: `IceBarStage` written before its integration tests (fake bar). Both are TDD-order lapses, stated here; T10's mutation checks are the evidence that those tests bite |
| 2 | 2026-10-03 | Design fix found by the fake bar (T7): the oracle is slow (debug about 2-3 s per 800 px capture), and judging inline would stretch attempts past their cadence (Q3's 10 s, Q8's spacing). Captures are now taken on the cadence and judged after the cycle (S-adv: after each step), in capture order; the stop rule reads the claim only, as Q3 fixes. Stage tests run in release with `-enable-testing` (part 1's precedent for U21) |
| 3 | 2026-10-03 | **Risk K6 (open, owner)**: with `«` listed by AX, its 17.5 pt frame is one of the attempt's on-bar agent frames, whose columns the oracle never sees (section 5 edge rule + instrument D6), so (b) is blind to a listed chevron by construction and deviation 2 C5's "(a) implies (b)" could never hold (pinned: `ChevronFrameTests`). For the C5 control only, the runner reads (b) as it is used -- a chevron AX does not list: the same oracle and templates, chevron-width frames left out of the context. The safety verdict keeps the registered context. A reading of a registered rule: goes to the owner with the addendum (thecure first) |
| 4 | 2026-10-03 | Risk K4b (INFERRED): if 27 places pushed-off items' windows at one off-screen point, `OverlapGuard` reports them overlapping and every attempt is inconclusive (the fake bar first did exactly that). S0's records show it; no rule changes |
| 5 | 2026-10-03 | `SAdvSequencer` (one process per sweep; the `«` rest state as its own step, re-run like a sweep) and `ChevronEpisodes.merged` (episodes renumbered across processes) added to `IceBarRunCore`, test first |

## Appendix. Review record

Round cap set before round 1: three.

### Round 1 (Codex gpt-5.6-terra): 1 P0, 10 P1, 1 P2

| finding | ruling | change |
|---|---|---|
| P0 Q18 one variant per invocation breaks O3's single sitting | accepted, modified | the variant loop is code; its live setter is not wired and `icebar-run` refuses S-adv until the owner decides K2 (no workaround presented as compliant) |
| P1 Q4 canonical set from the latest read on a refused baseline | accepted | always the first kept read's on-bar frames; none -> inconclusive |
| P1 Q6 contradictory timeout/cadence causes | accepted | one precedence list; inconclusive over timeout (fail-closed) |
| P1 Q13 x and width only | accepted | x, y, width, height within 1 pt |
| P1 Q16 any single violation must stop | rejected with evidence | section 8: "A number that merely makes the fallback rate high is not a contradiction and changes nothing"; a single failing baseline is a refused baseline (a fallback); the registered examples are aggregates ("in every S0 baseline", "never within 8") |
| P1 Q17 endpoint adds `«`, allows inconclusive | accepted | conclusive and no member seen; `«` stays a per-step safety rule |
| P1 S-adv member rest controls missing | accepted | control before each sweep's push and after its return; miss -> sweep inconclusive, re-run rule |
| P1 Q19 left-of-notch only `full` | accepted | unexplained sightings left of the notch too |
| P1 Q20 14-length cap vs 28 coarse lengths | accepted | C2's batching across processes, lengths given/measured in each manifest |
| P1 T7 favourable examples only | accepted | instrumented fake, every phase, exactly one bounds read and one `BObservation` per capture, faults injected per phase |
| P1 manifest omits the runner | accepted | runner sources, scripts, package manifest hashed; staging verifies; steps record binaries |
| P1 K inputs omitted | accepted | every `kInputs` entry re-hashed, K3 included; old pre-registration hash recorded |
| P2 two orchestration targets, duplicates C2 | modified | C2's process, manifest, guard, band and retry code reused; `IceBarStage` kept (the only testable home for orchestration: `vizprobe` is an executable) |

### Round 2: 0 P0, 0 P1 -- CONVERGED

Trend: 1 P0 + 10 P1 + 1 P2 -> none. Codex confirmed each change closes its finding
and withdrew the Q16 finding on the section 8 evidence ("a lone failed baseline is
correctly treated as a refused baseline/fallback").
