# Route C pre-registration: hidden-state baseline, `RegionClear`, oracle

2026-09-30 · branch `wip/icebar-c` · v3, converged (Codex round 3); deviations 1-3 (2026-10-01) ·
the artifact required by `2026-09-30-icebar-route-c.md` section 4.0 rules 6 and 7.
Its sha256 is recorded in that plan's rule 6 once review has converged; from then
on, any change here is a deviation, logged in section 9 with its reason and a new
hash, and made before the run it affects, never after seeing its result.

Nothing here reopens a settled decision: C2 PROVISIONAL FAIL; O1-O4 (O4: the
hidden-state baseline and `RegionClear`, frozen files untouched); O3 (overnight,
Chinese result lines); F1-F4; appendix A of the route C plan. This document fixes
numbers and rules the plan left open; where it adds a rule, the rule only refuses
the claim (fail-closed) and is marked **added**.

Labels: **MEASURED** (with run id or file:line) or **INFERRED** (with the reasoning).
No threshold below is MEASURED on the bar it will be used on: C1 and C2 kept no
pixel captures (MEASURED: `20260928-202509-vzc1/captures` is empty; the C2 run
directories hold JSON only). S0 is the first run that produces them, and section 8
says what S0 may and may not change.

## 1. Environment conditions (recorded per run, not varied within a sitting)

| # | condition | basis |
|---|---|---|
| E1 | OS build recorded at the start of each sitting. This machine is now 27.0.1 26A434; C2 ran on 27.0 26A428. C2's geometry is carried over as INFERRED until S0 re-records it | MEASURED `sw_vers` 2026-09-30; C2 plan line 268 |
| E2 | Geometry recorded per run. Planning values: notch 771.5-956.5 pt, bar 1728 pt, scale 2 | MEASURED C2 `step3.baselineAttempt` (`notchHi` 956.5); FINDINGS (3456 x 64 at scale 2) |
| E3 | Desktop picture static for the whole sitting (no dynamic or time-of-day wallpaper, no rotation); its file path and sha256 recorded | probes/README.md "the wallpaper changes during the day" |
| E4 | No window of any app under the bar's region: `Menus` keeps its window in a corner away from x 956.5-(leftmost reference), as `swfront` did | FINDINGS "the bar's backdrop moves under the glyphs" (17-23 % of pixels, a terminal under the bar) |
| E5 | Bar appearance variant named by the baseline's own median luma (Ink's measure, outside the notch): **dark** < 118, **light** > 138. How the variant is produced (desktop picture) is recorded, not fixed here | `DetectorParameters.swift:57` (`inkDecisionBand` 118...138) |

## 2. Capture cadence

All captures go through the C1/C2 latching capturer (one serial path). A *sample*
is the frozen bracket: capture, AX read, capture (`StripAssessor.swift:3-17`).

| step | rule | basis |
|---|---|---|
| warm-up | 24 captures, 0.25 s apart, once per helper launch | `HidingVerification.swift:43-44` defaults; C1 plan section 2. MEASURED used in C1 |
| settle | the first baseline or observation sample starts >= 1.0 s after the last spacer write or helper change | FINDINGS "a toggle needs about a second" (0.47 s caught both states) |
| baseline | 5 samples, 1.0 s apart (span 4 s); the first sample dropped; **kept = samples 2-5, all 8 captures** | frozen minimum >= 4 samples over >= 3 s, 1 dropped (`DetectorParameters.swift:72-74`); one sample of margin INFERRED |
| observation | 3 samples, 0.5 s apart; every capture used, none dropped | frozen minimum >= 2 samples >= 0.3 s apart (`DetectorParameters.swift:70-71`); a third sample for a transient INFERRED |
| attempts | an observation is up to 3 attempts, 1.0 s apart, stopping at the first granted one. **The attempt is the atomic unit**: each attempt's claim is paired with the oracle on that attempt's own captures and reads (section 5) | C1 preflight "3 attempts within 10 s"; verifier retries 1.0 s apart (`HidingVerification.swift:45-46`) |
| timeout | a baseline taking > 10 s, or an observation (all attempts) taking > 10 s, is *not granted* (counted as a fallback when the oracle sees nothing, section 4) | C1 settle "within 10 s" |
| per S1 cycle | at rest: member control capture; push to L, settle, baseline, 4 observations started 5 s apart, collapse, settle, restore check with a second member control (section 5) | INFERRED: 4 x 5 cycles = 20 observations per length (section 4) |
| scale | live certification only at scale 2; the geometry guard aborts on any other scale | MEASURED icetest bar 3456 x 64 at scale 2 (FINDINGS); no validated 1x `«` pixel test exists (section 5) |

**Kept-capture selection is mechanical**: exactly the rule above. No capture is
dropped for looking wrong; a capture that fails the latch or a guard aborts per
C1/C2, it is never silently excluded.

**Added (fail-closed):** the kept baseline samples' `MenuBarAgent` frames must pair
one to one; otherwise no baseline. Reason: rule 1 (b) excludes agent frames, and a
frame that moved between samples would make that exclusion ambiguous. Exactly:
each sample has one AX read shared by its two captures (the frozen bracket); take
each kept read's on-bar frames (`minY` in [0, bar height), as
`FoldWitness.swift:111`); any chevron-width frame (17.5 +- 0.5 pt) in any kept read
refuses the baseline; the canonical set is the first kept read's; every other kept
read must satisfy the frozen `agentSetMatches(current:baseline:)` against it
(`FoldWitness.swift:92-96`, x +- 1 pt, width +- 0.5 pt, `DetectorParameters.swift:79-80`).
Rule 1 (b)'s exclusion uses the canonical set.

## 3. Thresholds

All distances are the frozen max-channel distance, alpha ignored
(`StripImage.swift:18-21`). A *cluster* is 8-connected, as in
`FoldWitness.swift:185-207`, with the frozen minimum `foldClusterMinPx` = 16 px
(`DetectorParameters.swift:81`). The *region* is rule 1's: notch right edge to the
leftmost reference template's origin, notch columns excluded (`BarGeometry`'s own
widened notch columns).

| name | value | used in | label and reasoning |
|---|---|---|---|
| `T_agree` | **8** | rule 1 (a): every region pixel of every kept capture within 8 of the stored image (the first kept capture), agent frames included; no cluster allowance, one pixel over refuses | INFERRED. A static backdrop with no window under it and no animation should re-composite to identical pixels; 8 absorbs rounding and dithering. The only MEASURED backdrop number (17-23 % of pixels > 24 apart, a terminal under the bar) is the case this must refuse, and does |
| `T_bg` | **32** | rule 1 (b): no cluster >= 16 px, outside notch columns and the baseline's agent frames, deviates from its row's median colour by more than 32 | INFERRED, equal to `T_diff` so the baseline admits nothing `RegionClear` would call a change. A gradient backdrop whose row spread exceeds 32 over >= 16 connected px is refused: fail-closed, counted in the fallback rate |
| `T_diff` | **32** | rule 3: no cluster >= 16 px (agent frames included, notch columns excepted) differs from the stored image by more than 32 | INFERRED; 4 x `T_agree`, so baseline variation cannot read as change. Its sensitivity is not argued from ink tolerances (Codex r1: a local backdrop pixel is not the bar median); it is enforced per baseline by the contrast gate below |
| contrast gate (**added**) | **C_r > 128**, i.e. >= 129 = `T_diff` + 3 x `T_bg` + 1 | rule 1 | Per baseline, measured on the visible helpers (same glyph design and rendering path as the members): C_r = the smallest max-channel distance between a core pixel (coverage alpha >= 0.9 at the oracle's placement) and M_r, the median colour of those helpers' off-pixels Q. Also required: the region's overall median M_x within `T_bg` of M_r, and every region row median within `T_bg` of M_x. Then, for a member glyph drawn in the region with the references' ink G, at any region pixel p outside sub-16 clusters: dist(G, p) >= C_r - dist(M_r, M_x) - dist(M_x, row median) - dist(row median, p) >= 129 - 96 = 33 > `T_diff` (integer distances; `RegionClear` rejects only more than `T_diff`), so a 16-px core cluster changes by more than `T_diff` unless G itself differs between references and members. That one assumption (same ink for the same rendering path) is INFERRED and is what S-adv tests against the oracle. Gate failed -> no baseline, counted as a fallback |
| `T_o` | **24** | oracle, section 5 | INFERRED: the per-pixel distance of the oracle's hit test; 24 is the tolerance of the FINDINGS backdrop measurement. The oracle and `RegionClear` are different tests (shape vs change) and neither is claimed more sensitive than the other; the oracle's false-`none` rate is bounded by the corpus (section 6) and the live member controls (section 5), not by this number |

Invariants the harness asserts at start (a violation aborts before any capture):
`T_agree < T_diff`; `T_bg <= T_diff`; contrast gate = `T_diff + 3 * T_bg + 1`;
`DetectorParameters.preRegistered.isValid`. (v1's band rule on the median luma is
withdrawn: the contrast gate replaces the argument it protected.)

**Slivers.** `RegionClear` cannot see a change of fewer than 16 connected pixels
(the frozen `foldClusterMinPx`, fixed by rule 3). Whether 27 ever draws an item cut
by the notch is TBD: no record either way (FINDINGS and safewidth RESULTS searched
2026-09-30). The oracle therefore has an **edge rule** (section 5) that sees
slivers down to 4 px where they can occur (at the notch edge and at agent-frame
edges, and the strip's own ends); a sliver it sees while the claim is granted is NO-GO like any other
member (route C rule 5). Residual, stated not fixed: a sliver of fewer than 4
visible on-pixels is invisible to both.

## 4. Fallback rate

Per profile (k, menu length) and per spacer length L:

- **Attempt outcomes**: *granted* (frozen fold `.absent` and `RegionClear` clear
  in that attempt), *not granted*, or *inconclusive* (an oracle positive control
  missed, or an oracle ambiguity, in any capture of that attempt).
- **Safety, per attempt**: an attempt granted while the oracle, on that attempt's
  captures and reads, sees a member or `«` is NO-GO at once (route C rule 5), on
  any attempt, whatever the others say.
- **Observation outcome** (up to 3 attempts): *granted* if an attempt is granted
  and oracle-clean; *inconclusive* if any attempt is inconclusive and none is
  granted and clean; otherwise *not granted*.
- **Numerator**: observations not granted while the oracle sees no member and no
  `«` in any of their attempts, **plus every inconclusive observation**. A refused
  baseline or a failed contrast gate does not skip the cycle's observations: all 4
  are still taken (samples, attempts, oracle) with the claim not granted by
  definition, and each enters the numerator only on the same oracle-clean
  condition.
- **Denominator**: all observations at that length (20 = 4 per cycle x N = 5), as
  route C rule 6 says. Separately, more than 2 inconclusive of 20 makes the repeat
  inconclusive (route C section 3: re-run at most twice).
- **Ceiling**: **6 of 20 (30 %)** at the band midpoint. Route C S1 criterion (3)
  says the rate stays *under* the ceiling, so 5/20 passes and 6/20 fails at that
  length.
  INFERRED: on 2026-09-19 about half of consecutive fold readings were unreadable
  from the capture indicator's flicker (FINDINGS, "capturing the bar summons an
  indicator"); with 3 attempts, independent attempts at 0.5 would leave 12.5 %
  per observation (2.5 of 20), and the ceiling allows about twice that. This is
  an engineering gate on 20 observations, not an estimate of the owner's everyday
  rate; the implementation plan re-measures on the owner's bar.
- Also recorded, not gated: every attempt's outcome and captures, attempts per
  granted observation, and the rate split by cause (baseline refused / contrast
  gate / fold unreadable / not clear / timeout / inconclusive).

## 5. Oracle (ground truth, harness only)

A method independent of `RegionClear` and of the frozen matcher: it looks for the
**known rendering** of each helper's glyph, not for change and not for bar ink.

- **Glyph set.** Each helper draws a unique VZGlyphs glyph (12 pt, `Glyphs.swift`;
  `GlyphCheck.swift:11-13`). The ordinary variant is a template image (the bar
  inks it); the coloured variant is the same shape as a non-template image in
  sRGB (255, 0, 0), which is ink-invisible (`Ink.swift:30-37`: 255 > 70 from white,
  and from black by 255 > 100). Route C needs up to 16 members + 3 visible = **19
  distinct glyphs**; VZGlyphs has 6 today (MEASURED, `Glyphs.swift`), so 13 more
  are drawn before S0 under the same design rule (stroked, open, accented).
- **Rendering.** Each glyph's coverage alpha is rendered offline at scale 1 and 2
  by the helper's own drawing code, through a scale-parameterized renderer derived
  from `GlyphCheck.coverage` (today fixed at scale 2, `GlyphCheck.swift:11-12`,
  `:90-106`); the renderer is part of the pre-S0 freeze manifest. On-set P: alpha
  >= 0.5. Off-set Q: alpha = 0 inside the glyph's box.
- **Placement search.** Every x offset across the whole strip, including offsets
  where the box is cut by notch columns or the strip edge; y offsets within
  +-4 px of vertical centre.
- **Per placement.** Local backdrop b = median colour of the capture over the
  visible part of Q. A visible on-pixel is a *hit* if its distance from b > `T_o`;
  a visible off-pixel is *false* if its distance from b > `T_o`.
  - **full**: all of P visible, hits >= 90 % of P, false <= 10 % of Q.
  - **partial**: visible part of P >= 16 px (and < all of P), hits >= 90 % of it,
    false <= 10 % of the visible part of Q.
  - **edge** (slivers, section 3): only placements whose box is cut by a notch
    edge, by either end of the strip, or by an edge of an agent frame, where the
    agent frames are the union of the canonical set (section 2) and the attempt's
    own on-bar AX frames, each edge widened by +-1.5 pt (the frozen pairing allows
    x +- 1 pt and width +- 0.5 pt); visible part of P >= 4 px, hits
    = 100 % of it, false = 0 of the visible part of Q. The constrained x range is
    what makes the looser size safe from backdrop noise (corpus S2, S5, S7, S10).
- **Labels per capture.** For each helper: `drawn(full|partial|edge, x, zone)` at its
  best placement, or `none`. Zones: `leftOfNotch`, `notchEdge` (box cut by notch
  columns), `region`, `rightOfReferences`. Two helpers' glyphs matching one
  placement, or one helper matching two placements more than 2 pt apart, makes the
  capture **inconclusive**.
- **`«`.** Present if (a) any AX read of the attempt lists an on-bar
  `MenuBarAgent` frame 17.5 +- 0.5 pt wide (the frozen width rule), or (b) the
  chevron template cut from corpus item K1 (scale 2) matches full, partial or edge
  anywhere in the strip under the rules above. (b) exists because a chevron can be
  drawn before AX lists it (`FoldWitness.swift:119-126`). No 1x chevron is on
  record, so no live run certifies at scale 1 (section 2, scale).
- **Positive controls.** Every visible helper must be `drawn(full)` within 2 pt of
  its AX `minX` plus the glyph's 1.5 pt inset, in every capture; one miss makes
  that attempt inconclusive. **Member controls**: every member must be
  `drawn(full)` at rest before each push and after each collapse (S0, S-adv, S1,
  S5 cycles), in the same appearance variant, colour variant and indicator state
  as the hold between them; a miss makes the whole cycle inconclusive. The manifest
  records the roster-to-glyph mapping per helper.
- **Verdict per attempt.** "Oracle sees a member" = any capture of the attempt has
  any member `drawn(full|partial|edge)` anywhere outside notch columns. "Oracle
  sees `«`" = (a) or (b) in any capture or read of the attempt.

## 6. Offline corpus (rule 7): must label 100 % correctly before S0

Synthetic strips are generated deterministically by a corpus generator from the
recipe below (seeded; generator source and each output's sha256 recorded, then
frozen before the oracle first runs on them). Geometry: 1728 x 32 pt, notch
771.5-956.5, references drawn at x 1317 and 1350, a stand-in agent frame (a
20 pt violet (130, 90, 250) capsule) at x 1380, each at scale 1 and 2.

| id | content | expected |
|---|---|---|
| S1 | each of the 19 glyphs, alone, in each zone (x 700, 1100, 1450), ordinary white on (40, 40, 40) and black on (235, 235, 235), coloured on both | `drawn(full)` in that zone, correct glyph |
| S2 | notch straddle: glyph box 25 / 50 / 75 % inside notch columns | `drawn(partial, notchEdge)` iff visible P >= 16 px (the generator computes the count), else `none` |
| S3 | strip-edge cut at x = 0 and at the right edge, 50 % visible | as S2 |
| S4 | two glyphs overlapping by 4 pt | both `drawn`; neither inconclusive |
| S5 | glyph touching the agent capsule (0 pt gap) and 2 pt under it | touching: `drawn(full)`; under: `drawn(partial)` iff visible P >= 16 px |
| S6 | glyph at half alpha (0.5 blend) | `drawn(full)` |
| S7 | empty strips: dark, light, horizontal gradient 40 -> 80, uniform with seeded +-6 noise | every helper `none`, no `«` |
| S8 | all 19 glyphs side by side | each found as itself only (pairwise distinct under the oracle's rule) |
| S9 | the same glyph twice (twin control) | capture inconclusive |
| S10 | textured backdrops (seeded value noise, amplitude 16 and 32; a two-colour diagonal gradient; a saturated blue (40, 80, 200) to orange (220, 120, 40) gradient), each empty and with glyphs of S1 and S2 | empty: every helper `none`, no `«`; with glyphs: as S1 / S2 |
| S11 | each glyph at the y offsets -4, 0, +4 px | `drawn(full)` |
| S12 | three glyphs 1 pt apart, and an ordinary and a coloured glyph adjacent | each found as itself |
| S13 | edge rule: glyph cut by the notch edge / by the capsule's edge / by the capsule's edge after a 1 pt shift from its canonical x / by x = 0 / by the right end, leaving 3, 4 and 15 visible on-px | 3: `none`; 4 and 15: `drawn(edge)` |
| S14 | K1's chevron with its AX frame removed; K1's chevron cut 50 % by the notch edge; K1's chevron under the capsule by 4 pt | `«` present by (b) in all three |

Recorded captures (read-only, `~/IceReverse-evidence/20260918-204150-m-mid/captures/`,
owner's account; used for `«` only, their marker helpers are not VZGlyphs):

| id | file | sha256 | expected |
|---|---|---|---|
| K1 | `00011-probe-mid-20.png` | `a3bcce60c95dc037ca2085cb6acc6f51539d749d69d2c3871d707639a36739e6` | `«` present (labels.json, AX 17.5 pt); source of the chevron template |
| K2 | `00015-probe-mid-648.png` | `763ecc099fd04c89db630b9571abaea0e1433c0c246259749806efd8675021e2` | `«` present |
| K3 | `00017-probe-mid-652.png` | same bytes as K2 (MEASURED: identical sha256) | `«` present; kept as one item |
| K4 | `00041-probe-mid-4.png` | `e720dbe781d20c9fc4bbe67d61056c6494e043de29d5eaebb7c548a7ef70279e` | `«` absent (labels.json `targetDrawn`) |

K1 is both the chevron template's source and a test item, so (b) on K1 is
tautological; K2 is the real test of (b). The capture indicator is a stand-in
capsule: no icetest image of it exists (C1/C2 kept no captures). Any mislabel in
S1-S14 or K1-K4 blocks S0.

**Pre-S0 freeze manifest.** Before S0, a manifest lists the sha256 of: the 13 new
glyphs' source (VZGlyphs) and their 1x/2x coverage renderings, the coloured
rendering path, the corpus generator source, every generated corpus image, and
the oracle source. It is appended to section 9 as an addendum (a change of this
document), reviewed, and this document re-hashed. Until then the corpus is a
recipe, not an artifact.

## 7. Unit tests (TDD, written before `RegionClear`, the baseline gate and the oracle)

Synthetic strips as in `StripAssessorTests`/`GlyphCheck`; each test names its rule.

Rule 1, hidden-state baseline:
- U1 identical kept captures, uniform region -> accepted; stored image = first kept capture's region.
- U2 one pixel of one kept capture off by exactly `T_agree` -> accepted; by `T_agree + 1` -> refused.
- U3 kept captures of different width, height or scale -> refused.
- U4 frozen baseline fold not `.absent` -> refused, `RegionClear` never evaluated.
- U5 row-median deviation: 16-px cluster at `T_bg + 1` -> refused; 15-px cluster -> accepted; 16 px at exactly `T_bg` -> accepted.
- U6 a deviating cluster wholly inside a baseline agent frame -> accepted; the same cluster extending >= 16 px outside it -> refused.
- U7 deviation inside notch columns only -> accepted.
- U8 contrast gate: C_r = 129 -> accepted, 128 -> refused; M_x off M_r by `T_bg + 1` -> refused; one region row median off M_x by `T_bg + 1` -> refused.
- U9 agent frames across kept reads: identical -> accepted; one frame shifted 1.5 pt, one added, one removed -> refused; an off-bar frame (minY outside the bar) added -> accepted; a chevron-width frame in any kept read -> refused.

Rules 2-3, observation and `RegionClear`:
- U10 an observation capture of a different width, height or scale -> not clear.
- U11 red (255, 0, 0) glyph, >= 16 px, in the region on a dark bar -> not clear, while the frozen `observe` on the same samples reads fold `.absent` (proves the gap it closes).
- U12 a glyph inside an agent frame at observation -> not clear.
- U13 notch straddle: >= 16 changed px right of the notch -> not clear; all changed px within notch columns -> clear.
- U14 three samples, one capture of six discrepant -> not clear.
- U15 an observation equal to a kept capture that differs from the stored one by `T_agree` -> clear; a 16-px cluster at `T_diff` -> clear, at `T_diff + 1` -> not clear; a 15-px cluster at 255 -> clear for `RegionClear` (pins its limit; the oracle's edge rule is tested in U22).
- U16 a uniform +40 shift of the whole region (backdrop change) -> not clear.

Rule 4, the claim:
- U17 fold `.absent` and clear -> granted; fold `.unreadable` or `.present` with clear -> not granted; fold `.absent` with not clear -> not granted; no baseline -> not granted.

Cadence and accounting:
- U18 baseline with 5 samples 1.0 s apart -> first dropped, 8 captures kept; 4 samples -> no baseline (below the plan's cadence, although the frozen minimum is met).
- U19 attempts: granted and clean on attempt 2 -> observation granted, attempts = 2; 3 not granted -> not granted; > 10 s -> not granted by timeout; attempt 1 granted while the oracle sees a member -> NO-GO even if attempt 2 is clean; a control miss on attempt 1 and a granted clean attempt 2 -> granted; a control miss on attempt 1 and nothing granted -> inconclusive.
- U20 fallback rate: denominator 20; numerator counts not-granted with oracle clean plus inconclusive; refused baseline counts every observation of the cycle; 3 inconclusive of 20 -> repeat inconclusive; 5/20 passes, 6/20 fails; a refused-baseline cycle's 4 observations are taken and counted only when oracle-clean.

Oracle:
- U21 the corpus: every S and K item yields its expected label.
- U22 a visible helper not found -> attempt inconclusive; a member not found at a rest control -> cycle inconclusive; edge rule at 3 / 4 visible on-px (S13).
- U23 threshold invariants of section 3 checked at start; a violation aborts; a scale other than 2 aborts.

Freeze:
- U24 A3/A4: `git diff --exit-code af4baf1 -- Packages/MenuBarCapture` and the detector files (as in `2026-09-23-ax-discovery.md:533-534`) run in the build script; any diff fails the build.

Coverage target >= 80 % lines for the new probe code (testing.md).

## 8. What S0 may change, and what it may not

S0 produces the first icetest pixel captures. After S0 and before S-adv, the
harness reports, from S0's captures only: the maximum kept-capture pixel distance
(against `T_agree`), the region's row spread (against `T_bg`), and and C_r (against the contrast gate).

- If any reported number contradicts a section 3 inequality, the sitting
  stops before S-adv. A new value is a deviation (section 9), reviewed, re-hashed,
  and applies from the next sitting; S0 is then re-run. Example contradictions:
  C_r < 128 in every S0 baseline, or kept captures never within 8.
- A number that merely makes the fallback rate high is not a contradiction and
  changes nothing.
- A sliver the oracle sees while the claim is granted is NO-GO (section 3), never
  a recorded exception.

## 9. Deviation ledger

| # | date | change | reason | new sha256 |
|---|---|---|---|---|
| 1 | 2026-10-01 | S2 and S3 expected labels: "`drawn(partial, notchEdge)` iff visible P >= 16 px, else `none`" becomes, by the generator's visible on-px count n: n = all of P -> `drawn(full)`; n >= 16 -> `drawn(partial)`; 4 <= n < 16 -> `drawn(edge)`; n < 4 -> `none` (zone as the cut gives it). Corpus labels are compared with their expected x within section 5's 2 pt position tolerance. Approved by the owner 2026-10-01 | S2/S3 predate the edge rule (r1) and S13 (r2), which label the same cut `drawn(edge)` at 4-15 px; the literal text registered a mislabel for any oracle implementing section 5. Found by Codex (instrument plan review r3, P1) before the corpus was generated and before any oracle run on it | recorded in `2026-09-30-icebar-route-c.md` rule 6 (a file cannot hold its own hash) |
| 2 | 2026-10-01 | Oracle and corpus revised by `2026-10-01-icebar-c-deviation2.md` (sha256 `7b44dfc24e98ec2b9dcfbf206ef88c91016bbf6e3245b191c29eca209356126e`), whose text is part of this document: C1 identity only from `full`, `partial`/`edge` as anonymous sightings, unexplained sightings count as a member seen; C2 hit/false tests unchanged, texture bound added to rule 1 (every region pixel within `T_o`/2 of M_x); C3 overlap guard on window-server bounds of every helper, S0 measures it; C4 fail-closed predicate for out-of-scope textures; C5 `«` (b) qualified by S14/K1/K4 before S0 and live ((a) implies (b), >= 10 captures, >= 2 episodes) before S1; C6 corpus 2 with new seeds, frozen before its single check, freeze 1 kept; C7 section 6's gate reads "every item meets its written expectation". Approved by the owner 2026-10-01 | freeze 1 (run `20260930-102852-icebar-corpus`): 2144/5749 mislabelled from rule-level causes (shared strokes at cuts, overlap, heavy texture, K2 texture); Codex 3 rounds + thecure converged | recorded in `2026-09-30-icebar-route-c.md` rule 6 |
| 3 | 2026-10-01 | `2026-10-01-icebar-c-deviation3.md` (sha256 `493fb02e042c8e89138f2863f0500cb5ef5f251b92a99c5f3a39fcaf1f1b17c6`), part of this document: D3.1 a chevron `partial`/`edge` match sharing a hit pixel with a helper-template sighting is not `«` but an unexplained sighting by definition (never explained); D3.2 a glyph with 4 <= n < all of P meets its expectation by being identified `full` as itself within 2 pt or by an overlapping unexplained sighting. Approved by the owner 2026-10-01 | development corpus run `20260930-113108-icebar-dev` (allowed by deviation 2 C6): 7/5749 failing from these two gaps; corpus 2 not yet generated; Codex thecure converged |  recorded in `2026-09-30-icebar-route-c.md` rule 6 |

## Appendix. Review record (Codex gpt-5.6-terra)

### Round 1 (2026-09-30): 6 P1, 4 P2

| finding | ruling | change |
|---|---|---|
| P1 `T_diff`'s ink-vs-median argument fails for local pixels | accepted, modified | argument withdrawn; per-baseline contrast gate C_r >= 128 derived by triangle inequality (section 3); band rule withdrawn |
| P1 the < 16 px sliver was allowed through as "not NO-GO" | accepted, modified | oracle edge rule (>= 4 px at notch and agent-frame edges); any sliver seen with the claim granted is NO-GO; < 4 px stated as residual. Whether 27 draws cut items at all: TBD |
| P1 denominator excluded inconclusive observations, against route C rule 6 | accepted | denominator = all 20; inconclusive counted as fallback |
| P1 "`T_o < T_diff` makes the oracle more sensitive" | accepted | claim removed; textured corpus S10; live member controls per cycle |
| P1 1x `«` relies on AX alone | accepted, modified | live certification at scale 2 only (MEASURED icetest scale 2); AX-absent, cut and occluded chevron cases S14. The corpus keeps 1x glyph cases |
| P1 attempt accounting ambiguous | accepted | attempt is the atomic unit; NO-GO on any granted attempt the oracle contradicts; U19 cases |
| P2 no live control for hidden members | accepted | member controls at rest before push and after collapse |
| P2 19 glyphs and corpus not yet artifacts | accepted | pre-S0 freeze manifest, hashed, reviewed |
| P2 agent-frame pairing underspecified | accepted | canonical set and comparison spelled out; U9 cases |
| P2 corpus gaps (y offsets, crowding, mixed, colour backdrops, chevrons) | accepted | S11-S14; indicator stays a stand-in (no icetest image exists) |

### Round 2 (2026-09-30): 5 P1, 1 P2 (trend r1 6 P1 -> r2 5 P1, all boundary details of r1's fixes)

| finding | ruling | change |
|---|---|---|
| P1 C_r = 128 proves only >= 32, `RegionClear` needs > 32 | accepted | gate C_r >= 129; U8 |
| P1 edge rule omits the strip ends | accepted | strip ends added; S13 |
| P1 edge rule on canonical frames misses a 1 pt shifted frame | accepted | union of canonical and current frames, edges widened +-1.5 pt; S13 |
| P1 refused-baseline observations counted without the oracle | accepted (Codex option 1) | the 4 observations are still taken and oracle-checked |
| P1 "under the ceiling" vs 5/20 passing | accepted, modified | ceiling 6/20; the route C text stays as is |
| P2 `GlyphCheck.coverage` is fixed at scale 2 | accepted | wording; renderer in the freeze manifest |

### Round 3 (2026-09-30; the pre-set cap of three rounds): 0 P0, 0 P1 -- CONVERGED

Trend: r1 6 P1 + 4 P2, r2 5 P1 + 1 P2, r3 none. Codex confirmed each round-2 fix
closes its finding and none contradicts the route C plan.
