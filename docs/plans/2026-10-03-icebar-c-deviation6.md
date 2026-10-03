# Route C deviation 6 (withdrawn): C3 on macOS 27, and section 8 numbers for S0

2026-10-03 · branch `wip/icebar-runner` · **withdrawn after debate (thecure, three rounds); never in force** · proposed against
`2026-09-30-icebar-c-prereg.md` sha256
`0780e997b7b5ed5eae6ea69f5df451413c99d48ec5e51a94c3e7617edb8e5420`. Nothing here is
in force until the owner approves it; then it is logged in the pre-registration's
section 9, re-hashed, and applies from the next sitting only.

Labels: MEASURED (run id, command, file:line) or INFERRED (reasoning).

## 0. Why

The first sitting (`20261003-134859-icebar`, macOS 27.0.1 26A434) ended in S0:
`結果：失敗｜S0 not shown: a cycle inconclusive three times`.

- F1 (MEASURED): every one of S0's 130 captures has `OverlapGuard` outcome
  `missing("reference")`; `s0.c3` = `notListed(reference)`. The deviation 2 C3 guard
  reads "the window server's list for every helper's status-item window (by the
  helper's PID)". On macOS 27 there is no such window: a read-only window list on
  26A434 (`~/IceReverse-evidence/20261003-135901-winlist-readonly`) has 0 windows shaped
  like a status item at any layer with the owner's third-party items on the bar, as on
  26A428 (FINDINGS 2026-09-19, "there are no per-item windows left at all";
  `MenuBarAgent` composites the bar into one window). The guard as registered can never
  be satisfied on macOS 27 (the runner plan's risk K4).
- F2 (MEASURED): all three S0 baselines refused at the frozen fold (`unreadable`) with
  Menus `long`, so `s0.section8` = `unmeasured(kept distance, row spread, texture,
  C_r)` (risk K1, claim plan R14: fold stops evaluation before the pixel clauses).
  Even with C3 satisfiable, S0 as registered cannot produce section 8's numbers on this
  bar, and Q16 stops the sitting.
- F3 (MEASURED, same run): at L = 728 pt both members were `none` in every baseline and
  attempt capture; the three visible helpers `full` at distinct positions 28 pt apart;
  no claim granted; no NO-GO.

## 1. What deviation 2 C3 is for, and why AX frames do not replace it as is

C3's purpose (deviation 2): "The oracle cannot see a glyph whose box holds another
glyph's ink (S4), so certification requires that no two helpers' drawn areas overlap,
checked per capture." It rejected AX frames because "a hidden item's AX frame overlaps
others" (spacer x 480 w 542 and target x 1008 in one read).

AX frames on macOS 27 (FINDINGS, MEASURED):
- adjacent drawn items at rest: AX frames overlap by **2.0 pt** (118 of 118 pairs) --
  above `OverlapGuard.toleratedOverlapPt` (0.5);
- an overflowed item's AX frame stays on the bar, "stacked at the same x as its
  neighbours"; "for overflowed items it does not [say where it is]";
- AX lags a jump by about 0.1 s.

So the unchanged guard fed AX frames would trip at rest on every adjacent pair.

## 2. Proposed changes

### D6.1 C3's geometry source on macOS 27: the sample's own AX read

- **Source**: for each capture, the helpers' frames from the same frozen bracket's AX
  read that the attempt verdict already uses (`ObservationSample`, the read paired with
  that capture), instead of the window-server list. `OverlapGuard.evaluate` itself is
  not changed (it is in `IceBarOracle`, bound by corpus 3's `freeze.json`); only its
  input changes.
- **Adjacency allowance**: before the guard, each helper's AX frame is narrowed by
  1.0 pt on each horizontal side (the MEASURED constant 2.0 pt overlap of adjacent drawn
  items split evenly); with the guard's 0.5 pt, two frames trip when their AX frames
  overlap by more than 2.5 pt horizontally. Vertical extent unchanged.
- **Unchanged**: every glyph helper of the roster must be listed (no frame in the read
  -> `missing` -> the attempt, control or step inconclusive); no helper exempt because
  it is expected hidden; the S4 corpus item and its expectation stand.
- **Overflow**: a member stacked by AX over a neighbour trips the guard -> inconclusive
  (fail-closed). INFERRED harmless to safety: overflow shows `«`, which already refuses
  the claim (fold present) and is seen by the oracle.
- **S0's measurement replaces C3's window-vs-AX check** (same stop rule: not met -> the
  sitting stops before S-adv, the owner decides): (a) every helper is listed in every
  S0 read; (b) for each visible helper and capture, the oracle's `full` match box lies
  within the helper's AX frame widened by 1.0 pt (AX validated against pixels, the role
  window bounds had); (c) at the rest and restore controls, adjacent drawn helpers' AX
  overlap is <= 2.5 pt.
- **Residual, stated (INFERRED)**: a hidden member's AX frame may not say where it is
  drawn. Drawn positions are validated for visible helpers only. A member that is drawn
  is either seen by the oracle (member seen: not granted, or NO-GO if granted) or lies
  wholly under another helper's ink, which needs `MenuBarAgent` to draw two items in
  overlapping slots; no stacking of drawn items has been observed (FINDINGS: 9
  collapses "no stacking"; S0: glyphs 28 pt apart). This was the gap the window-server
  guard was meant to measure; on macOS 27 no source measures it.

### D6.2 Section 8's numbers: an added S0 short-menu block (S0b)

- S0 (k = 2, Menus `long`, 5 cycles at 728 pt) unchanged: the question "does the claim
  stay ungranted with a long menu" and its pass rule are route C's.
- **S0b (added)**, run right after S0 and before section 8's check: k = 2, ordinary
  glyphs, 3 visible helpers, Menus `short`, the desktop picture unchanged; an upward
  sweep as Q17's up phase (16 pt steps from 16 pt, each step settle, baseline,
  one observation, oracle on every capture, NO-GO if granted while the oracle sees a
  member or `«`) to the first conclusive step with no member seen (cap 1000 pt: not
  found -> section 8 unmeasured, stop as Q16); then 5 cycles (Q8) at that length.
- Section 8's report and its contradiction rule (Q16, unchanged) take every S0 and S0b
  baseline that has the number. S0b's granted / not-granted counts are recorded, not
  gated. S0b's captures feed `BControl` as S0's do (Q14).
- Why short: S-adv and S1 run with `short` and `mid` menus (route C); section 8 checks
  thresholds on the bar they will be used on. S0's long menu answers a different
  question and cannot reach the pixel clauses (F2).

### D6.3 How run `20261003-134859-icebar` is read

Its captures were inconclusive only through the C3 guard, whose own registered text
says that an unsatisfiable guard stops the sitting before S-adv and the owner decides.
It is recorded as it ran (the frozen `Sitting.afterS0` ordered the S0 outcome first and
printed 失敗); under this deviation it is **not** counted as S0's failure for route C
section 3's replication rule (no claim was granted and no capture was judged on the
claim). S0 runs again, in full, in the next sitting under this deviation.

## 3. Consequences (implementation, a later part)

- Sources changed (manifest v2 lists them; a third pre-S0 addendum and manifest v3
  needed): the capture decorator and `C3Capture` (`IceBarStage/Probe.swift`), the C3
  check (`StageRules`), `StatusWindows` replaced by an AX-frame source, `SittingDriver`
  and `StepKind` (S0b), the S0b step body (`Step.swift`), their tests. Unchanged:
  `IceBarOracle` (incl. `OverlapGuard`), `VZGlyphs`, `IceBarCorpus`, `IceBarClaim`,
  `MenuBarCapture`, detector files.
- The order: owner approves this text -> section 9 entry and re-hash -> implementation
  plan (TDD, Codex) -> manifest v3 + addendum (owner) -> next sitting.

## Appendix. Debate record (thecure, Codex gpt-5.6-terra)

Round cap: none set (thecure: until judged); three rounds.

| # | point | raised by | ruling | evidence |
|---|---|---|---|---|
| 1 | C3 is structurally unsatisfiable on macOS 27; an unchanged re-run is pointless | me | Codex: RIGHT | S0 `missing("reference")` in 130/130; read-only window list 26A434, 0 bar-shaped windows; FINDINGS 2026-09-19 |
| 2 | AX frames (narrowed 1 pt per side) replace window bounds | me | **Codex won** (P0 + P1): hidden members' AX frames do not say where they are drawn, AX is stale vs each capture, 2.0 pt is an at-rest constant only | FINDINGS 122, 357-366, 621, 662; `Probe.swift` bracket order |
| 3 | the residual "member wholly under another helper's ink" is acceptable as INFERRED | me | **Codex won**: it is the exact case C3 exists for; then MEASURED by my own offline sweep: 16,874 of 160,740 pairwise overlap composites (10.5 %) leave the visible helper `full` and the member unseen, 0 sightings, even at 7 px of overlap (`~/IceReverse-evidence/20261003-occlusion-sweep`; one ink colour, union coverage, so draw order does not matter) | sweep, sanity cases |
| 4 | S0b supplies section 8's numbers | me | **Codex won**: it changes section 8's object (S0's captures only) and pools an outcome-selected population; moot after 2-3 | prereg section 8 |
| 5 | run `20261003-134859-icebar` not counted as an S0 failure | me | **Codex won**: no retroactive carve-out; it stays a provisional S0 failure (route C section 3), replication not run | route C 76-93; `Sitting.afterS0` |
| 6 | a red-glyph colour channel as the redesign | me | **Codex won**: a wholly covered member stays unseen; it would also change S1's stimulus (new pre-registration) | `Ink.swift:30-37` |
| 7 | whole package (below) | -- | Codex: "無い"; record first, owner decision second | round 3 |

## Converged conclusion (for the owner)

1. This deviation is withdrawn; the pre-registration stays `0780e997…` unchanged.
2. Under the registered design route C cannot proceed on macOS 27: C3 is structurally
   unsatisfiable, no trustworthy per-item geometry exists for hidden members, and
   without C3 the frozen oracle has a MEASURED occlusion false-negative mode.
3. Record, kept as separate facts: the run's final line `S0 not shown (失敗)` is a
   provisional S0 failure (not NO-GO, not SAFETY STOP); its replication has not been
   run; and, separately, this instrument cannot certify a route C result on macOS 27.
4. The owner decides whether to halt route C (then the record adds that replication was
   not performed because the owner halted the study after the infeasibility was
   established, and, per the route C plan, this fork states macOS 27 support is
   read-only) or to commission a new study under a new pre-registration. No redesign is
   endorsed here.
5. Nothing is re-run and no code or pre-registration changes until the owner decides.
