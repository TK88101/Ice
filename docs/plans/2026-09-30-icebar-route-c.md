# Route C: IceBar on macOS 27 -- feasibility probes

2026-09-30 · branch `wip/icebar-c` (to be created) · v2 after Codex round 1 ·
**Nothing runs until the owner has approved this document, answered O1-O4, and
named a time.** A successor protocol: it does not reopen or reinterpret C2.

## Fold-free baseline (was BLOCKED; resolved on paper 2026-09-30, O4 approved 2026-09-30)

The frozen verifier refuses every item unless its baseline is taken with every
item drawn and the fold absent (`StripAssessor.swift:115-131`). In the owner's
case that state is never *legitimately* fold-free: with every item drawn the bar
overflows and `«` is up; a fold-free reading there would need a detector failure
(chevron missing from AX and outside the chosen region), which is a false
`absent`, not a baseline (INFERRED; code, and C2 geometry). IceBar mode never
needs that state anyway: its items live pushed off, and today Ice skips every
check in IceBar mode (`VerificationTrigger.swift:57-63`, STATUS "Not checked:
iceBarMode").

Chosen (thecure debate with Codex, four rounds, appendix A): **verify the hidden
state at bar level, against a baseline of the hidden state itself** (section
4.0). The ten detector files and `Packages/MenuBarCapture` stay byte-frozen; a
new pixel predicate, `RegionClear`, is added in unfrozen probe code. It is a
detector change in substance, so it needs the owner's approval (O4) and its own
pre-registration before any run. Rejected: (a) per-item templates from subsets
drawn fold-free (unfreeze, many visible relayouts, verifies a state IceBar mode
never uses); (b) no verification (no pixel evidence at all).

## 0. The owner's goal (2026-09-30)

Items that would otherwise push the bar left past the notch (and make macOS 27
show its `«` overflow) live in Ice's own panel below the bar (IceBar), so the bar
never grows past the notch and `«` never appears. The owner chooses which items
go into IceBar and can add or replace them. The owner saw an interactive mock-up
of routes A, B and C and chose C.

## 1. Relation to the hiding study, and the scope this protocol tests

- **C2 stands as recorded.** Sitting A `20260929-234942-c2A` (macOS 27.0 26A428,
  isolated account, evidence `~/IceReverse-evidence/20260929-234942-c2A`,
  `runner.final.json` sha256 prefix `85ddb372fa8998df`, verified by `vizprobe
  c2-read`): `provisionalFail(k1-long, not shown)`. Three processes, each with 5
  baseline attempts, fold `unreadable`, every item `foldNotAbsentAtBaseline`;
  Menus calibrated to 16 menus, last title edges 1012 and 1058 pt, right of the
  notch (771.5-956.5). MEASURED. The C2 protocol had predicted this as INFERRED
  (`2026-09-28-c2-protocol.md` 6.1 item 4). Whether the owner accepts that
  provisional result under C2's section 1 is a separate decision; nothing here
  depends on its answer, and nothing here changes C2's verdict.
- **The scope under test (O1), fixed before any Route C measurement:**
  1. With a short or mid frontmost menu (last title ends left of the notch),
     IceBar items are pushed off the bar and `«` does not appear.
  2. With a frontmost menu that reaches right of the notch, Ice cannot verify
     hiding (MEASURED above). It then shows every IceBar item on the bar and
     says so in its menu; `«` may appear while that lasts. This is a physical
     limit, not only a detector one: those menus occupy the room the items would
     need (INFERRED from the C2 geometry). The owner's goal holds in case 1 only.
  3. Ice never reports the IceBar set off the bar while `«` is up or any member
     is drawn between the notch and the visible section (**C-region**, section
     4.0). A member drawn right of the visible section is a membership-or-placement
     event (**C-order**), caught by membership tracking and checked against the
     whole-strip oracle in S4 and S5. Ice makes no per-item `hidden` claim.

## 2. What is known (desk, 2026-09-30)

| gate | evidence | status |
|---|---|---|
| G-hide | C1: one helper at Ice's rest, 616-840 pt every 16 pt step `hidden(folded: false)`, smoke 5/5 at 728 (`20260928-202509-vzc1`) | MEASURED for one item; room depends on the number of items, unmeasured (FINDINGS "Open"; feasibility section 2) |
| G-image | no per-item windows on 27; `MenuBarAgent`'s full-width windows capture alone as glyphs on transparent (FINDINGS, winlist probes) | MEASURED for visible glyphs; pushed-off items unmeasured; capturing changes the bar (FINDINGS "capturing the bar changes it") |
| G-click | AX items expose `AXPress` (FINDINGS:100) | unmeasured on a pushed-off item |
| G-move | human Command-drag swaps items (owner confirmed); synthetic Command-drag moved another process's item in 3 of 4 rounds (FINDINGS "The move primitive") | MEASURED; atomic target binding unsolved (FINDINGS "Open") |
| G-identity | item identity across Ice restart and app relaunch | unmeasured (FINDINGS "Open") |

Ice today refuses move and click for AX-discovered items
(`MenuBarItemManager.swift:752`, `unsupportedSource`). That is a fence, not a
measurement.

## 3. Verdicts

- **PASS**: every stage passes on its primary path.
- **PASS WITH FALLBACK**: every stage passes, some on a named fallback F1-F4
  (section 5), each accepted by the owner in O2 before its stage runs. The
  implementation plan inherits every fallback taken as a hard limit (for F1:
  IceBar holds at most the capacity S1 measured).
- **NO-GO**: a stage fails with no named fallback, or its fallback fails, or the
  owner rejects the needed fallback. Also NO-GO, with no fallback: any oracle
  disagreement with the claim (section 4.0 rule 5), and any adversarial case of
  S-adv read as clear. The study ends; later stages do not run.
- **SAFETY STOP**: any unexpected target, an owner item touched, a helper left
  running, or a guard tripping; terminal, no further stage, owner told first.
- Per repeat, as in C1/C2: pass, fail or inconclusive; an inconclusive repeat is
  re-run at most twice, a third is *not shown* (a failure). A failure is
  replicated once, in a separate run, before it decides NO-GO. A fallback to
  shown (the claim not granted) is not a failure of C-region; it counts against
  availability (S1 criterion 3).

## 4. Stages

### 4.0 The claim under test (replaces per-item verification in IceBar mode)

1. **Hidden-state baseline.** After the spacer has pushed the IceBar members
   off, call the frozen `StripAssessor.baseline` with the visible-section items
   only (the references). It must return fold `.absent`. Store the fold region
   (notch right edge to the leftmost reference template's origin, notch columns
   excluded) from every kept capture. The stored region is accepted only if
   (a) all kept captures have the same width, height and scale and agree pixel
   for pixel within tolerance `T_agree`, and (b) the region is uniform: outside
   notch columns and the current `MenuBarAgent` frames, no connected cluster of
   at least `foldClusterMinPx` pixels deviates from its row's median colour by
   more than `T_bg` (max-channel distance, `StripImage.swift:18-20`). Else no
   baseline: Ice shows every member (O1 case 2 behaviour). The stored image is
   the first kept capture's region; (a) bounds every other kept capture to
   within `T_agree` of it, and `T_diff` > `T_agree` is pre-registered.
2. **Observation.** Frozen `observe(targets: [], references: visible)` must
   return fold `.absent` (this also catches `«` anywhere on the bar: chevron
   candidates are every on-bar agent frame, `FoldWitness.swift:111-113`, and the
   non-chevron agent set must equal the baseline's, `FoldWitness.swift:115-117`).
3. **`RegionClear`** (new, unfrozen probe code): every capture of the
   observation has the baseline's width, height and scale, and in each, no
   connected cluster of at least `foldClusterMinPx` region pixels (notch columns
   excepted, agent frames included) differs from the stored baseline pixel by
   more than `T_diff` from the stored image. One capture not clear makes the
   observation not clear.
   Colour does not matter (a red glyph is ink-invisible, `Ink.swift:30-37`,
   but not change-invisible). A translucent bar over a changed backdrop reads
   not clear: fail-closed, counted as a fallback.
4. **The claim.** Ice says "IceBar set off the bar" only when 2 and 3 hold;
   otherwise it shows every member and says so. This is C-region (scope 1.3).
5. **Oracle (ground truth, harness only).** The helpers render known glyphs
   (VZGlyphs, plus a coloured-glyph variant), so for every capture the harness
   searches the whole strip -- left of the notch, the notch edge, the region,
   right of the leftmost reference -- for every helper. Any capture where the
   claim holds while the oracle finds a member drawn anywhere, or a `«`, is
   NO-GO with no fallback.
6. **Pre-registration, a hashed artifact reviewed before S0** (written after
   O4, not in this session): capture cadence (samples, spacing, settle time,
   timeout), kept-capture selection, `T_agree`, `T_bg`, `T_diff`, the
   fallback rate (numerator: observations not granted while the oracle sees no
   member and no `«`; denominator: all observations at that length) and its
   ceiling, and the oracle's match rule. Unit tests (TDD) for rules 1-3: a red
   glyph, a glyph under an agent frame, a straddle at the notch edge, a size
   mismatch, one discrepant capture, baseline variation within `T_agree`.
   The frozen files stay byte-identical (A3/A4 check).
   **Registered 2026-09-30:** `2026-09-30-icebar-c-prereg.md` v3, sha256
   `d8bf04aacf519b21442a5df59e096145f4e7fcc963d58856776aa3c378853d6f`
   (Codex converged in round 3). Its pre-S0 freeze manifest is still owed.
   **Deviation 1, 2026-10-01** (owner approved; S2/S3 labels follow the edge
   rule): sha256 `aefe17021f14bd0076494b8365e051e09d40ed65ef984a088b4eccc11867946f`.
   **Deviation 2, 2026-10-01** (owner approved; oracle identity vs sightings,
   texture bound, overlap guard, live (b) control; `2026-10-01-icebar-c-deviation2.md`):
   sha256 `bb10b671205ce3a1fa8c5dcfb994a57558ee81424a5ee91ad45632c75f3de0f2`.
   **Deviation 3, 2026-10-01** (owner approved; ambiguous chevron slivers,
   cut-glyph identity; `2026-10-01-icebar-c-deviation3.md`): sha256 `bde8a4bf5176249ae95c65de6f15abb3611a972202e0e31b55e3a46b08b8bfb8`.
   **Deviation 4, 2026-10-01** (owner approved; out-of-scope textures refused,
   corpus 3; `2026-10-01-icebar-c-deviation4.md`): sha256 `e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3`.
7. **The oracle is validated before it certifies anything.** Offline: a frozen
   corpus of labelled strip images (every zone including left of the notch and
   right of the references, ordinary and coloured glyphs, 1x and 2x, partial
   overlap, a `«`) with expected labels in the pre-registration; any
   mislabel blocks S0. Live, every capture carries built-in positive controls:
   the visible helpers must be found where they are, and in S-adv every drawn
   member at rest must be found; one miss makes the capture inconclusive.

### 4.1 Stage table

All stages run in the isolated account `icetest`, reusing the C1/C2 instrument
(allowlisted roster guard, console guard, geometry guard, hashed final
manifests, clean teardown, progress lines). Helpers only (`com.icespike4.*`,
VZGlyphs templates); nothing touches the owner's account or bar. Each profile
records the full bar population: every visible and hidden item, each width, the
control item, the capture indicator's frame when present. The oracle (4.0 rule
5) runs on every capture of every stage.

| # | question | pass (N) | failure | time |
|---|---|---|---|---|
| S0 | Long menu first: with Menus calibrated `long`, k = 2 members, does the claim stay ungranted (baseline refused or not clear), are both members then drawn on the bar, and is the bar restored after Menus quits? | 5/5 claim not granted, both drawn, restored | the claim granted once: NO-GO | ~10 min |
| S-adv | Adversarial sweep, band-independent: k = 4 members plus 3 visible helpers, short menu, dark and light bar, ordinary and coloured glyph. The spacer steps up from rest in 16 pt (as C1) until the oracle sees every member gone, and back down. At every step the oracle labels each capture: a member in the region, straddling the notch edge, or under the capture indicator's frame when present. Also a rest state with `«` up (members added until it appears) | at every step where the oracle sees any member drawn or a `«`, the claim is not granted; two sweeps each way per variant | the claim granted once while the oracle sees a member or `«`: NO-GO | ~40 min |
| S1 | Profiles k = 1, 2, 4, 8 with 3 visible helpers, each at short and mid menus. Coarse scan and refinement as C2 section 4. Is there one length per profile where (1) the claim is granted, (2) the oracle finds no member drawn anywhere and no `«`, (3) the fallback rate stays under the pre-registered ceiling, and are all k drawn again on collapse? | a band per profile, then N = 5 full cycles at its midpoint | capacity search (F1): k = 1, 2, 4, 8, then 12 and 16 while each passes; after the first failure (replicated), every integer k between the last pass and it is tested (no bisection: passing is not known to be monotonic in k). The capacity is the largest k such that it and every tested smaller k passed; k above the first replicated failure are not tested and not claimed. k = 3 is confirmed in the same sitting right after S1, before S2 (it gates S2-S5, which need capacity at least 4). The other integers skipped by the doubling (5-7, 9-11 ...) are untested until a confirmation sitting after S5 and before the implementation plan runs each of them (coarse scan, then N = 5 at the band midpoint); a count that fails there lowers the capacity to the largest k below it with every smaller k passed. No band at k = 1: NO-GO. Capacity below 4: the sitting ends and the owner decides before S2. Any member seen left of the notch: NO-GO | ~3-4 h |
| S2 | Images: with k = 2 pushed off, can `MenuBarAgent` windows or ScreenCaptureKit show their glyphs? Else, snapshots taken while visible. | each IceBar cell shows the glyph of the right item (identity checked against the visible snapshot), legible at 1x and 2x; a helper whose glyph changes is shown as stale, never as current | neither: F2 if O2 accepted it, else NO-GO | ~30 min |
| S3 | Click: `AXPress` on a pushed-off helper. | its own menu opens on screen within 1 s, no other item moves, the claim granted again after close, 5/5 | F3 (single item), tested after S4 (a) passes: 5/5, only the clicked item appears (oracle), the claim granted again after it returns. S4 (a) fails or F3 fails: NO-GO | ~40 min |
| S4 | Membership: the owner's add/replace. (a) synthetic Command-drag moves a helper across the spacer (in and out), 10/10 onto the intended slot; (b) after each move, Ice's section model lists the helper in the right section, IceBar shows it, and the oracle agrees (a member moved out is drawn in the visible section and not counted in IceBar). | (a) and (b) 10/10 | (a) fails: F4 if O2 accepted it, then (b) run with a manual Command-drag (owner, 5 moves); else NO-GO. (b) or the oracle fails: NO-GO | ~40 min |
| S5 | Robustness, N = 5 each, k = 4: (a) frontmost app switch short <-> mid; (b) an item appears and one leaves while hidden; (c) an IceBar helper relaunches; (d) Space switch, into and out of a full-screen Space; (e) menu bar auto-hide as the owner has it; (f) display sleep and wake, lock and unlock; (g) Ice quits and relaunches: the same items return to IceBar, none to the wrong section. For (d)-(f) IceBar closes (`IceBar.swift:56`) and reopens with the same membership. In (b), (c), (g) a member appearing right of the visible section is a membership-or-placement event: the section model must list it where the oracle sees it. | every repeat keeps scope 1.1-1.3, the oracle agrees, and restores | the claim granted while the oracle disagrees, or a lost or misplaced item: NO-GO. Second display: waived (V4) | ~2 h |

Order: S0, S-adv, then S1, S2, S3, S4, S5; each only if the previous passed,
with one exception: if S3's primary path (`AXPress`) fails, S3's verdict is held
open, S4 (a) runs next, then F3 is tested (S3 passes or fails on it), then S4
(b). If S4 (a) fails, F3 is unavailable and S3 fails: NO-GO. S0 and S-adv come
first because they are the cheap ways for the claim to be wrong.

## 5. Fallbacks, named before any run

- **F1** (capacity): IceBar holds at most the capacity S1 measures and the
  confirmation sitting upholds for every integer count up to it (the owner's
  hope: 8 or more). Items beyond it stay on the bar, where `«` can appear. S2-S5
  keep their fixed k (2, 2, 2, 4), so they run only when the capacity is at
  least 4; a smaller capacity ends the study unless the owner approves a written
  amendment of this plan that re-parameterizes those stages.
- **F2** (images): IceBar shows the owning app's icon and name instead of the
  glyph, the icon rendered monochrome (desaturated, tinted to the bar's text
  color) so it matches the bar (owner's condition, 2026-09-30). No capture.
  Dynamic glyphs (a CPU graph, a timer) are lost. S2 checks, when F2 is taken,
  that each monochrome icon is still distinguishable from the others at 1x.
- **F4** (move): the owner arranges items with a manual Command-drag on the bar
  (native, MEASURED); Ice only detects and records membership (S4 b, with the
  oracle, still mandatory).
- **F3** (click, owner's condition 2026-09-30: only the clicked item, as original
  Ice did): clicking an IceBar item moves only that item across the spacer into
  the visible section (the S4 synthetic Command-drag under section 6), presses
  it, and moves it back after its menu closes. Other hidden items never appear
  (oracle). Needs S4 (a) to pass, so when S3 fails its F3 test runs after S4 (a);
  if S4 (a) fails, F3 is unavailable and S3's failure is NO-GO. Pass also
  requires the claim granted again after the item returns (a fresh hidden-state
  baseline is allowed, since the visible set changed while it was out); a
  transient `«` while it is out is recorded.
- There is **no fallback for C-region**: an oracle disagreement or an S-adv case
  read clear ends the study.

## 6. Safety for synthetic input (S3, S4 a)

Each run needs the owner's explicit go for that run (feasibility section 5).
Before every `mouseDown` or `AXPress`: re-read the target's identity and frame
from AX, AX hit test at the point returns the target's PID, the point is covered
by no other item, the layout version is unchanged since the read; any mismatch
cancels. `mouseUp` watchdog 2 s; the Command key released on every exit path.
Console and roster guards run before each event burst. On any wrong target:
SAFETY STOP, helpers quit, preferences domains checked empty, bar compared with
the run's baseline.

## 7. Owner decisions before S0

- **O1** (answered 2026-09-30: accepted): the scope of section 1 (the goal holds
  with short and mid menus; with a menu right of the notch the items show and
  `«` may appear).
- **O2** (answered): accept each of F1-F4 in advance, or reject it (then
  the stage that would need it ends as NO-GO). F4 accepted 2026-09-30; F2
  accepted 2026-09-30 with monochrome icons (section 5); F1 answered 2026-09-30: measure the maximum
  (S1 capacity search), accept the measured capacity; F3 accepted 2026-09-30 only in its
  single-item form (section 5). All of O2 is answered.
- **O4** (answered 2026-09-30: approved): approve the new pixel predicate of section 4.0 (`RegionClear`
  and the hidden-state baseline invariant) as a detector change in substance,
  written in unfrozen probe code with the ten detector files and
  `Packages/MenuBarCapture` byte-frozen, under its own pre-registration (4.0
  rule 6) reviewed before S0. Rejecting O4 ends route C on paper: neither
  rejected option (a) nor (b) is proposed instead.
- **O3** (answered 2026-09-30: overnight; S-adv added to the first sitting, ~40
  min, by the O4 design): S0 + S-adv + S1 in one sitting (~4-5 h), S2-S4 in
  one (~2 h), S5 in one (~2 h), each in `icetest` without switching away. Each
  sitting's start time is still named by the owner.

## 7a. Runner output for an unattended night

The owner reads the Terminal in the morning, so the runner prints in Chinese:
one line per step start and end (step, profile, wall time, elapsed), and a final
line `<result>｜<reason, one sentence>｜<evidence directory>` whose `<result>` is
exactly one of `結果：完成`, `結果：失敗`, `結果：中斷`, `結果：安全停止`. Mapping: PASS or PASS WITH FALLBACK -> 完成; NO-GO -> 失敗; the
session left the console, a signal, or the watchdog -> 中斷; SAFETY STOP -> 安全停止.
The evidence files stay in English (they are read by the tools).

## 8. Deliverables

- Evidence per run under `~/IceReverse-evidence/<run id>/`, verified before the
  shared copy is deleted; `STATUS.md` and `FINDINGS.md` rows, MEASURED or
  INFERRED with build and date.
- On PASS or PASS WITH FALLBACK: a separate implementation plan for IceBar on 27
  (control item, section model, panel, click path, membership settings), with its
  own review. No Ice code changes under this plan beyond the probe instrument
  (which includes `RegionClear`, the hidden-state baseline and the oracle).
  The implementation plan must also carry scope 1.2's disclosure (Ice says in
  its menu that IceBar items are shown); the probe records only the claim
  state, so this plan does not measure it.

## Appendix A. Debate record: fold-free baseline (thecure, Codex gpt-5.6-terra, 2026-09-30)

Every file:line Codex cited was checked before it was accepted.

| # | point | raised by | outcome | evidence |
|---|---|---|---|---|
| 1 | Q1 "never fold-free" as an absolute code claim | Codex r1 | Codex won: restated as "never legitimately fold-free"; a fold-free reading there needs a detector failure | `FoldWitness.swift:105-134`, `StripAssessor.swift:321-327` |
| 2 | Missed mechanism: IceBar mode already skips checks | Claude r1 | agreed | `VerificationTrigger.swift:57-63`, STATUS.md:32 |
| 3 | Missed mechanism: `RoomGuard` and baseline reuse block the existing prepare path | Codex r1 | Codex won: a separate IceBar path | `VerificationGuards.swift:9-22`, `HidingVerification.swift:153-170` |
| 4 | "fold absent => every member hidden" | Codex r1 | Codex won: renamed to a region claim; whole-strip oracle added | `StripAssessor.swift:226`, `:321-327` |
| 5 | Coloured glyph invisible to ink; first `RegionClear` (not clearly background) also misses red | Codex r1, r2 | Codex won: predicate redefined as change from a hidden-state baseline | `Ink.swift:30-37`, `StripImage.swift:18-20`, `DetectorParameters.swift:55-56` |
| 6 | A new predicate outside frozen files is still a detector change | Codex r2 | Codex won: owner decision O4 | `2026-09-23-ax-discovery.md:197-200` |
| 7 | Passive S1 zero-count cannot prove coverage | Codex r2 | Codex won: S-adv added | -- |
| 8 | C-region + C-order split legitimate? | Claude r3 | agreed, renamed "membership-or-placement event"; oracle mandatory in S4, S5 (b)(c)(g) | plan 4.1 |
| 9 | "fold absent => region empty" false (explained spans) | Codex r3 | Codex won: baseline invariant 4.0 rule 1 (b) | `StripAssessor.swift:104-129` |
| 10 | Excluded spans are blind areas (agent frames) | Codex r3 | Codex won: no exclusion at observation; S-adv (iii) | `FoldWitness.swift:111-129`, `:115-117` |
| 11 | Multi-capture rule undefined | Codex r3 | Codex won: every capture must be clear | -- |
| 12 | Observation captures lack a size/scale guard | Codex r4 | Codex won: 4.0 rule 3 | `StripAssessor.swift:204` |

Rejected options: (a) per-item templates from subsets drawn fold-free; (b) no
verification. Codex's standing worry after r3: a region-local predicate against a
whole-strip safety claim -- answered by the C-region/C-order split and the
mandatory oracle, not by argument.

### Plan review, round 1 (Codex, 2026-09-30)

| finding | ruling | reason |
|---|---|---|
| P1 S-adv needs a band S1 has not measured | accepted, modified | S-adv made a band-independent staircase judged by the oracle at every step |
| P1 capacity bisection assumes monotonicity | accepted | every integer k between last pass and first failure |
| P1 thresholds and cadence deferred | accepted, modified | a hashed pre-registration before S0 (after O4, since O4 approves the concept) |
| P1 oracle unvalidated | accepted | 4.0 rule 7: offline labelled corpus + live positive controls |
| P1 S0 does not check scope 1.2's menu disclosure | rejected | no Ice code runs under this plan; carried to the implementation plan (section 8) |
| P2 stored baseline pixel singular vs every capture | accepted | first kept capture, others bounded by `T_agree` |
| P2 7a "exactly one of" vs reason and directory | accepted | grammar fixed; the O3 decision itself unchanged |

### Plan review, round 2 (Codex, 2026-09-30)

| finding | ruling | reason |
|---|---|---|
| (r1 rejection of the S0 disclosure check) | Codex accepted the rejection | section 8 carries it |
| P1 doubling skips integer k; capacity claimed for untested counts | accepted | confirmation sitting for every skipped integer up to the capacity, before the implementation plan (S1 row, F1) |

### Plan review, round 3 (Codex, 2026-09-30; the pre-set cap of three rounds)

Trend: r1 5 P1 + 2 P2, r2 1 P1, r3 1 P1, 0 P0 throughout.

| finding | ruling | reason |
|---|---|---|
| P1 a skipped k = 3 failing after S5 would void the "capacity at least 4" gate of S2-S5 | accepted | k = 3 confirmed right after S1, before S2; applied after the capped round, not re-reviewed |
