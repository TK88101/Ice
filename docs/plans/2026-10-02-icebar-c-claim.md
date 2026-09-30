# Route C instrument, part 2 of 3: hidden-state baseline, `RegionClear`, the claim

2026-10-02 · branch `wip/icebar-claim` (from main `6ab69ce`) · final (Codex converged, round 3) ·
implements `2026-09-30-icebar-c-prereg.md` v3 + deviations 1-4 (sha256
`e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3`), sections 1-4 and 7:
rules 1-4 and U1-U17, U23, U9b.

The pre-registration is not changed by this plan. Where it leaves a detail open,
section 3 fixes a reading **before** the code is written; each reading only
chooses among what the text allows, and where two are possible it takes the
fail-closed one. A result that needs a registered rule changed stops the work
and goes to the owner as a section 9 deviation, never an edit here.

Labels: MEASURED (file:line or run id) or INFERRED (reasoning).

## 1. Scope and interfaces with parts 1 and 3

| part | status | this plan's contact with it |
|---|---|---|
| 1 | done, merged `6ab69ce` | **uses, does not change**: `TextureBound.evaluate` (`Sources/IceBarOracle/Kernels.swift:15`), `Oracle.label`, `OracleTemplate`, `OracleContext`, `OracleGeometry.notchColumns` / `centreY` / `isVisible`, `Placement`. `IceBarOracle` changes only for a real bug against section 5, logged in the instrument plan's section 8. `Sources/VZGlyphs` and `Sources/IceBarCorpus` are frozen by corpus 3 (`freeze.json` `f8a64fbc…`) and not touched |
| 2 | this plan | rule 1 (hidden-state baseline: agreement, row median, agent-frame pairing, chevron-width refusal, texture bound, contrast gate), rules 2-3 (`RegionClear`), rule 4 (the claim), threshold invariants and the scale abort |
| 3 | later | **consumes** this plan's API: selects kept samples by cadence (U18), runs the frozen `StripAssessor.baseline` / `observe`, calls `HiddenBaseline.evaluate`, `Claim.decide`, `StartupCheck.evaluate`; attempts, fallback accounting (U19, U20); runner, `OverlapGuard` / `BControl` wiring, pre-S0 manifest (which will hash `Sources/IceBarClaim`), U24 |

Not in part 2: U18-U20, U24, the runner, any live wiring, the manifest, any run
in `icetest`, any push or merge.

API handed to part 3 (all in the new target `IceBarClaim`, standard library +
IceCore + IceBarOracle, Swift 6 language mode):

```swift
ClaimParameters.preRegistered            // T_agree 8, T_bg 32, T_diff 32, C_min 129; cluster = DetectorParameters.foldClusterMinPx
StartupCheck.evaluate(claim:detector:scale:) -> StartupOutcome        // .ready | .abort([AbortReason])
HiddenBaseline.evaluate(kept: [ObservationSample], frozen: BaselineResult,
                        references: [String], visible: [OracleTemplate],
                        parameters: ClaimParameters) -> BaselineVerdict  // outcome + measurements
Claim.decide(fold: Fold, baseline: BaselineOutcome, captures: [StripImage],
             parameters: ClaimParameters) -> ClaimOutcome   // evaluates RegionClear once, returns it
```

Part 3 calls `Claim.decide` only; `RegionClear.evaluate` is public for its own
tests and is never called a second time on the same attempt (Codex r1 P2).

`BaselineVerdict.measurements` carries the numbers section 8 of the
pre-registration asks S0 to report (maximum kept-capture distance, row spread,
C_r, and the texture bound's maximum deviation), filled whenever the structural
checks passed, whatever the refusal reason, so a refused S0 baseline still
reports them. Refusal reasons map one to one onto section 4's causes
("baseline refused" / "contrast gate"); "texture" is its own cause (deviation 2 C2).

## 2. Goals, non-goals, constraints

Goal: rules 1-4 as pure functions over captures and reads, each clause tested
at its boundary (U1-U17, U23, U9b), with the texture bound called through the
one `TextureBound` symbol and the call site pinned by an integration test.

Constraints (owner): pre-registration unchanged (A5); `Packages/MenuBarCapture`
byte-equal to `af4baf1`, `Packages/` byte-equal to `32d523a` (A3, A4);
`Sources/VZGlyphs`, `Sources/IceBarCorpus` unchanged (A6); build scratch outside
`~/Documents`; no image written anywhere (tests build strips in memory).

## 3. Readings fixed before code

| # | detail | fixed as | why |
|---|---|---|---|
| R1 | inputs of rule 1 | `kept`: the kept samples already selected by part 3's cadence (samples 2-5), IceCore `ObservationSample`s, ordered here by `time`; `frozen`: the frozen `StripAssessor.baseline` result over all the cycle's baseline samples (its `foldAtBaseline`, `templates`, `geometry`, `agentFrames`). Checked here, fail-closed: exactly 4 kept samples, else refused `.keptCount`; `frozen.agentFrames` equals the latest kept sample's `agentFrames` (the frozen baseline sets it so, `StripAssessor.swift:133`), else refused `.frozenMismatch`. Selecting and dropping by time and spacing stays U18 (part 3) | section 2 "kept = samples 2-5"; the cadence itself belongs to part 3 (owner's split); Codex r1 P1 |
| R2 | stored image | the earliest kept sample's `before` capture, whole image; comparisons read its region only | section 3 "the stored image (the first kept capture)" |
| R3 | captures of one baseline | all `before` and `after` of every kept sample (8 for 4 samples) must share width, height and scale, and equal `frozen.geometry`'s `widthPx`, `heightPx` and `scale`; else refused `.capturesDiffer` | U3; fail-closed on a geometry change (Codex r1 P1) |
| R4 | region | lo = `geometry.notch?.hi ?? 0` (as the frozen `foldRegion`, `StripAssessor.swift:318-322`); hi = min over `references` of `frozen.templates[id].originXPt` ("the leftmost reference **template**'s origin"). An empty `references`, a reference with no frozen template, or hi <= lo: refused `.regionUndefined`. After notch and canonical agent columns are removed, no eligible pixel left: refused `.regionUndefined` (every median population is then empty; the exclusions are by column, so either every row has eligible pixels or none does) | section 3 text; the frozen observe uses the same origin for its fold region, so the two tests look at the same span |
| R5 | columns | a span's columns are `floor(lo s) ..< ceil(hi s)` clamped to the strip, the convention of `FoldWitness.columnRange` and `OracleGeometry.columns`; notch columns from `OracleGeometry.notchColumns` (IceCore's widening, pinned in part 1) | one convention everywhere |
| R6 | distance | max-channel, alpha ignored (the frozen `RGBA.distance`, internal there; re-implemented as part 1 did, D9) | section 3 |
| R7 | agent frames (section 2, added) | each kept sample's `agentFrames` is its read; on-bar = `minY` in [0, `geometry.heightPt`); any on-bar frame with `FoldWitness.isChevron` in any kept read: refused `.chevronFrame`; canonical set = the earliest kept read's on-bar frames; every other kept read's on-bar frames must pass `FoldWitness.agentSetMatches(current:baseline:)` against it, else refused `.agentFramesMoved`. Excluded columns (rule 1 (b), texture, contrast medians) = the canonical frames' spans, columns per R5, not widened | section 2 text verbatim; frozen symbols called, not copied |
| R8 | rule 1 (a) | for every kept capture, every region pixel outside notch columns (agent frames included) within `T_agree` of the stored image's pixel; one pixel over refuses `.disagree` | section 3 |
| R9 | rule 1 (b) | for **every** kept capture (the text says "the baseline"; every capture is the fail-closed reading, and after (a) passes it differs from stored-only by at most `T_agree`): row median = per-channel lower median (D8's convention) over that row's region pixels outside notch and canonical agent columns; a pixel deviates if its distance from its row median > `T_bg`; 8-connected clusters of deviating pixels among those eligible pixels; any cluster >= 16 px refuses `.rowDeviation` | section 3; cluster rule as `FoldWitness.swift:185-207` |
| R10 | texture bound (deviation 2 C2, U9b) | `TextureBound.evaluate(capture, region: R4 region, notch: geometry.notch, agentFrames: canonical spans)` for every kept capture; any refused: `.texture`. The same symbol and the same argument construction as the corpus (`CorpusRecipe.swift:128-136`: region notch.hi ... leftmost reference, notch, agent frames) | deviation 2 C6 order step 3; deviation 4 item 5 |
| R11 | contrast gate inputs | `visible`: the visible helpers' `OracleTemplate`s (part 3 passes the whole visible roster). Checked, else `.contrastUnmeasurable`: non-empty, ids unique, every template at the stored image's scale, every id in `references` present among them; any `Oracle.label` error maps to `.contrastUnmeasurable` (Codex r1 P1). The gate runs `Oracle.label(image: stored, helpers: visible, chevron: nil, context: (notch, canonical spans, hi))`; each visible helper must be `drawn(full)` and the capture conclusive, else refused `.contrastUnmeasurable`. "The oracle's placement" = that helper's best `full` placement by D12, re-implemented over `Placement`'s public fields (`Oracle.best` is internal and part 1 is not changed for a non-bug); a test pins that the re-implementation picks the placement whose x the oracle's label reports | section 3 "at the oracle's placement" |
| R12 | C_r and M_r | core pixel: template alpha >= 230 (a / 255 >= 0.9) at the placement, visible per `OracleGeometry.isVisible`; M_r: per-channel lower median over the union of every visible helper's visible Q pixels (alpha 0 inside the box); C_r = min over all core pixels of all visible helpers of distance(pixel, M_r). No visible helper, no core or no Q pixel: `.contrastUnmeasurable` | section 3 |
| R13 | M_x and row medians of the gate | on the stored image, over the region pixels outside notch and canonical agent columns (the pixel set of R9 and R10): M_x per-channel lower median; row medians as R9. Gate: C_r >= 129, distance(M_x, M_r) <= `T_bg`, every row median within `T_bg` of M_x; else `.contrast` | section 3; U8 |
| R14 | order and reporting | refusal order: fold (U4) -> capture shape -> agent frames -> region -> (a) -> (b) -> texture -> contrast gate. Fold, shape, frames and region stop evaluation (nothing to measure); the four pixel clauses are all evaluated and reported in `measurements`, and the refusal reason is the first failing one | section 8 needs the numbers even from refused S0 baselines |
| R15 | clause-level U cases vs the texture bound | U1-U9 assert the verdict of the clause they name ("each test names its rule", pre-registration section 7 line 232). U5's two "accepted" cases cannot be whole-baseline accepted under the texture bound: a pixel and its row median both within 12 of M_x are at most 24 apart, below 32 and 33; so deviation 2's "U1-U20 unchanged" is true only clause-level. Deviation 2 added the texture bound to rule 1 and left U1-U20 unchanged; where a U case's "accepted" input also exceeds the texture bound (U5: a 15-px cluster at 33, a 16-px cluster at 32; U8: a row median 33 off M_x), the test asserts the named clause accepts (or refuses) **and** the whole baseline's verdict, which is then `.texture`. No expectation is loosened: the texture bound only adds refusals | deviation 2 section 3 ("rule 1 gains the texture bound as an added refusal") |
| R16 | rules 2-3, `RegionClear` | given an accepted `HiddenBaseline` and the attempt's captures: exactly 6 (3 samples x 2, section 2 observation) or not clear `.captureCount(n)` (Codex r2 P1); a capture whose width, height or scale differs from the stored image -> not clear `.shapeMismatch(index)` (U10); a pixel is changed if its distance from the stored pixel > `T_diff`; eligible pixels = region columns minus notch columns, agent frames **included**; any 8-connected cluster of changed pixels >= 16 px -> not clear `.changed(index, size)`. Every capture is checked (U14); the largest cluster is reported | section 3 |
| R17 | rule 4, the claim | no accepted baseline -> not granted `.noBaseline`, `RegionClear` not evaluated (`regionClear == nil`, U4). With a baseline, `RegionClear` is evaluated exactly once, inside `Claim.decide`, and returned in the outcome (so part 3 can split causes, section 4 "fold unreadable / not clear"), and granted iff `fold == .absent` and clear | section 4 "granted (frozen fold `.absent` and `RegionClear` clear in that attempt)" |
| R18 | invariants and scale (U23) | `StartupCheck.evaluate` returns `.abort` with every violated item: `T_agree < T_diff`, `T_bg <= T_diff`, `C_min == T_diff + 3 T_bg + 1`, the cluster minimum equals `DetectorParameters.foldClusterMinPx`, `detector.isValid`, scale == 2 exactly. The functions of rules 1-4 do not re-check; the runner aborts before any capture (part 3) | section 3 "asserts at start"; section 2 "scale" |
| R19 | U11's frozen side | built with IceCore only: a synthetic bar with two reference items and agent frames, `StripAssessor.baseline` then `StripAssessor.observe` on samples with a red (255, 0, 0) glyph in the region; the test asserts the frozen fold `.absent` and `RegionClear` not clear on the same captures | U11 "proves the gap it closes" |

## 4. Design

New, all under `docs/macos-27/probes/visibility` (not linked into Ice):

- `Package.swift`: target `IceBarClaim` (deps IceCore, IceBarOracle; Swift 6), test
  target `IceBarClaimTests` (deps IceBarClaim, IceBarOracle, IceBarCorpus for
  `CorpusGeometry` in the call-site test, IceCore).
- `Sources/IceBarClaim/ClaimParameters.swift`: thresholds, `StartupCheck`.
- `Sources/IceBarClaim/PixelKit.swift`: distance, columns, lower median, 8-connected
  clusters over a mask (one implementation used by (b) and `RegionClear`).
- `Sources/IceBarClaim/ClaimRegion.swift`: R4, R5, R7 (region, excluded columns,
  canonical agent set).
- `Sources/IceBarClaim/HiddenBaseline.swift`: R1-R3, R8-R10, R14; types
  `HiddenBaseline`, `BaselineOutcome`, `BaselineRefusal`, `BaselineMeasurements`,
  `BaselineVerdict`.
- `Sources/IceBarClaim/ContrastGate.swift`: R11-R13.
- `Sources/IceBarClaim/RegionClear.swift`: R16.
- `Sources/IceBarClaim/Claim.swift`: R17.
- Tests: `U1_U9BaselineTests`, `ContrastGateTests` (U8), `TextureCallSiteTests`
  (U9b + integration), `RegionClearTests` (U10, U12-U16), `U11FrozenGapTests`
  (IceCore integration), `ClaimTests` (U17, U4's claim half), `StartupCheckTests`
  (U23), `ClaimTestSupport` (canvas, shapes).

## 5. Tasks (TDD: each test written and seen failing before its code)

| # | task | DoD |
|---|---|---|
| T1 | target skeleton + `ClaimTestSupport`; U23 tests red, `StartupCheck` green | `swift test --filter IceBarClaimTests` red then green |
| T2 | U1-U7, U9 (clause and whole-baseline assertions, R15), plus R1's `.keptCount` (3 and 5 kept) and `.frozenMismatch`, R3's size mismatch against `frozen.geometry`, R4's empty references and no eligible pixel, red; `ClaimRegion`, `PixelKit`, `HiddenBaseline` without contrast/texture green | red then green |
| T3 | U9b + call-site integration test red (texture 12 accepted, 13 refused, notch-only and agent-only deviations accepted; `HiddenBaseline`'s texture outcome equals `TextureBound.evaluate` with `CorpusGeometry`'s region, notch and a capsule frame, on strips where a wrong region, notch or frame argument would flip the answer); wire `TextureBound` green | red then green |
| T4 | U8 + R11's D12 pin red; `ContrastGate` green | red then green |
| T5 | U10, U12-U16, R16's capture count (0, 5, 6, 7) red; `RegionClear` green; U11 (R19) red then green | red then green |
| T6 | U17 and U4's claim half red; `Claim` green | red then green |
| T7 | coverage >= 80 % lines of `Sources/IceBarClaim`; acceptance A1-A8 | section 6 |

Parallel candidates: none (each task builds on the previous one's types).
Checkpoint commits on `wip/icebar-claim` after T3, T6 and T7 (local only).

## 6. Acceptance

| # | check | how |
|---|---|---|
| A1 | new suite green | `swift test --scratch-path /private/tmp/claude-501/icebar-claim --filter IceBarClaimTests` |
| A2 | line coverage >= 80 % per file of `Sources/IceBarClaim` | `--enable-code-coverage`, `llvm-cov report` |
| A3 | MenuBarCapture frozen | `git diff --exit-code af4baf1 -- Packages/MenuBarCapture` |
| A4 | Packages frozen | `git diff --exit-code 32d523a -- Packages` |
| A5 | pre-registration unchanged | `shasum -a 256` = `e693654c…7eb3` |
| A6 | corpus-3 sources frozen | `git diff --exit-code 6ab69ce -- docs/macos-27/probes/visibility/Sources/VZGlyphs docs/macos-27/probes/visibility/Sources/IceBarCorpus`; `freeze.json` sha256 `f8a64fbc…` unchanged |
| A7 | oracle unchanged or logged | `git diff --exit-code 6ab69ce -- docs/macos-27/probes/visibility/Sources/IceBarOracle`, or every change has a row in the instrument plan's section 8 |
| A8 | nothing else broken | full probe `swift test` (I7 group about 7 min); `build.sh <scratch>` builds |

Coverage kinds: unit (clauses), integration (U11 with the frozen assessor; the
`TextureBound` call site; `Oracle.label` inside the contrast gate), E2E: none in
this part (no executable; part 3's runner is the first end-to-end path, stated
not skipped silently).

## 7. Risks

- R-a (INFERRED): R15's reading is wrong in the owner's eyes (U5/U8 "accepted"
  meant the whole baseline). Then U5/U8 and deviation 2 contradict each other and
  that is a section 9 matter for the owner; the code would not change, only the
  test's framing.
- R-b (INFERRED): the contrast gate's triangle argument (section 3) bounds
  `dist(row median, p)` only outside agent frames (rule 1 (b) excludes them), so
  inside an agent frame `RegionClear`'s sensitivity is not proved by the gate.
  Stated, not fixed: a pre-registered argument, and route C's safety rests on
  the oracle, not on this bound.
- R-c: `Oracle.label` over a full 2x strip for the contrast gate is slow in debug.
  Mitigation: only the visible templates are searched (3), the prune is sound
  (part 1). Not a rule change.
- Rollback: new files plus `Package.swift`; `git checkout main -- docs/macos-27/probes/visibility`.

## 8. Implementation notes

| # | date | note |
|---|---|---|
| 1 | 2026-10-02 | R10 region's right edge: the frozen template origin is the ink box's left edge minus `templateMarginPx` (2 px), clipped to the item frame (`Template.swift`, `ItemTemplate.cut`). For VZGlyphs (1.5 pt inset) that is the AX `minX` + 0.5 pt, so the live region runs up to 0.5 pt further right than the corpus's (`CorpusRecipe.textureRegion` ends at the slot x): a superset, over the glyph's empty inset, so the live bound checks more pixels, never fewer. INFERRED from the code; the call-site test pins the construction with test shapes whose origin equals the slot (`TextureCallSiteTests.arguments`) |
| 2 | 2026-10-02 | T1-T6: all tests written first and seen failing (34 compile errors: the target's types absent), then 54 tests green; mutation check (`> T_diff` -> `>=`; texture without agent frames; region from the notch's left edge) each caught (1, 5, 2 failures), sources restored. Line coverage `Sources/IceBarClaim` 91.7-100 % per file |
| 3 | 2026-10-02 | /simcodex, 3 rounds on `main..wip/icebar-claim` + working tree. Codex review: 0 findings in each round. /simplify r1: `quietColumns` now read from the oracle's own `OracleGeometry.isVisible` (the exclusions `TextureBound` applies), so rule 1 (b), the texture bound and the gate medians cannot drift apart; one `ClaimRegion` carried in `HiddenBaseline`; `largestCluster`; test helpers centralised; D12 pin gained a same-x, different-y pair. r2: found that r1 had reduced three accepted-case tests (U6 inside, U7, U9 off-bar) to `failedClauses.isEmpty`, which a structural refusal also satisfies; acceptance asserted again; forwarding wrappers removed. r3: 0 P0/P1. Skipped as P2: `Result` in place of `Preparation`, sharing one distance map between rule 1 (a) and rule 3, re-using row medians between (b) and the gate |
| 4 | 2026-10-02 | Acceptance: A1 54/54; A2 91.7-100 %; A3, A4, A6, A7 no diff; A5 `e693654c…`; corpus-3 `freeze.json` `f8a64fbc…`; A8 full probe `swift test` 526 tests in 9 targets green (I7 group 420 s), `build.sh` builds. No image written; the gitignored `.build/index-build` in the probe directory is SourceKit-LSP's index (created 2026-09-19), not a build scratch |
| 5 | 2026-09-30 | **R15 approved by the owner** (after thecure, Codex 2 rounds, converged). Interpretation: U5's "accepted" (15 px at `T_bg` + 1; 16 px at `T_bg`) means the row-median deviation clause (rule 1 (b)) passes, not that the whole baseline is accepted; the texture bound (deviation 2 C2, 61-65) stays an added, independent fail-closed refusal, and for those inputs the whole verdict is `.texture`. Nothing is loosened: no threshold, corpus expectation or baseline refusal changes, and no live run changes outcome. At approval no S0, S1 or live hidden-state baseline has run. Pre-registration sha256 at approval `e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3`. Tests: `BaselineTests.u5Accepted`, `u5Refused`; the same framing for U8's row case in `ContrastGateTests.rowMedian`. No deviation now (Codex: no registered line requires one); **part 3 must state this interpretation in one line of the pre-S0 addendum** (pre-registration section 6, 223-228, section 9, re-hashed before S0) and record that addendum's new sha256 here, which becomes the canonical record. Codex's biggest worry: a third party reading this as a post-hoc change of expectations -- answered by the two facts above (no run yet; in the pre-registration before S0) |
| 6 | 2026-09-30 | For part 3 (Codex, same thecure): the pre-S0 addendum changes the pre-registration's sha256, so `vzcorpus check` (`Sources/vzcorpus/main.swift:109-111`) will refuse corpus 3's freeze afterwards. Corpus 3's single check is complete under `e693654c…` (instrument plan section 8 row 12); part 3's plan must fix, before the addendum, that this freeze is not re-checked afterwards, or how the check's model is updated |

## Appendix. Review record

Round cap set before round 1: three.

### Round 1 (Codex gpt-5.6-terra): 5 P1, 1 P2

| finding | ruling | change |
|---|---|---|
| P1 any non-empty `kept`, unbound `frozen` | modified | exactly 4 kept, `frozen.agentFrames` = latest kept read, captures = frozen geometry (R1, R3). Rejected: deriving and dropping from 5 samples here -- that is U18, placed in part 3 by the owner |
| P1 empty references / empty pixel populations | accepted | `.regionUndefined` (R4) |
| P1 caller-selected `visible` | accepted, modified | non-empty, unique, same scale, references among them, oracle errors -> unmeasurable (R11) |
| P1 R15 redefines U5's "accepted" | rejected with evidence | pre-registration section 7 "each test names its rule"; U5's accepted cases are impossible whole-baseline under the texture bound (<= 24 apart), so deviation 2's "U1-U20 unchanged" holds only clause-level. Codex did not re-raise it in round 2 |
| P1 capture size vs frozen geometry | accepted | R3 |
| P2 `RegionClear` evaluated twice | accepted | `Claim.decide` evaluates once and returns it |

### Round 2: 1 P1, 1 P2

| finding | ruling | change |
|---|---|---|
| P1 `RegionClear` accepts any non-empty capture list | accepted | exactly 6 (R16), tests 0/5/6/7 |
| P2 no tests for the new refusals | accepted | T2 |

### Round 3 (the cap): 0 P0, 0 P1 -- CONVERGED

Trend: 5 P1 + 1 P2 -> 1 P1 + 1 P2 -> none. Codex confirmed both round-2 fixes close their findings.
