# Route C pre-registration, deviation 2 (draft): oracle identity vs sighting, texture, overlap

2026-10-01 · branch `wip/icebar-c` · **draft for review, not in force** ·
amends `2026-09-30-icebar-c-prereg.md` (sha256 `aefe1702…`, v3 + deviation 1)
sections 3 (slivers), 5, 6 and 7. Owner approved drafting it (2026-10-01); it
takes effect only when the owner approves the converged text, is copied into
the pre-registration's section 9, and the file is re-hashed.

Labels: MEASURED (run id, file) or INFERRED (reasoning).

## 1. Why (MEASURED: freeze 1, run `20260930-102852-icebar-corpus`, `check.json` sha256 recorded in the instrument plan section 8 row 4)

The oracle, implemented as registered, mislabelled 2144 of 5749 items. No
implementation defect was found (each class below was traced to the rule).

| cause | rows | what the rule does |
|---|---|---|
| F1 shared strokes at cuts | S2 412/912, S3 96/304, S5 23/76, S13 54/99, S10-S2 cases | a cut leaves a post or a bar end; every template with the same stroke on that side matches it `partial`/`edge`, so helpers not drawn are labelled drawn and D14/D15 make the capture inconclusive. `partial`/`edge` cannot carry identity |
| F2 overlap | S4 539/684 | 4 pt of overlap puts the neighbour's ink in the second glyph's Q (false > 10 %); that glyph is `none` |
| F3 heavy texture | S10 value noise A = 32 only: S1 cases 87/228 (phantoms at the strip start, references missed), S2 cases 314/456. A = 16, the diagonal and blue-orange gradients: S1 cases 0/684 | P hits and Q falses are both measured as distance from one median b; a backdrop varying by more than `T_o` inside a box produces both |
| F4 K2 | K2 | K1's chevron template hits 169/169 on-px in K2 but 76/577 off-px (13.2 %) are > `T_o` from b over the red grid texture |

Rows that passed entirely: S1, S6, S7, S8, S9, S11, S12, S14, K1, K4.

## 2. Changes

### C1. Identity only from full matches (F1)

- **Labels per capture**: for each helper, `drawn(full, x, zone)` at its best
  full placement, or `none`. `partial` and `edge` no longer label a helper.
- **Ambiguity** (two helpers at one placement; one helper at placements more
  than 2 pt apart): evaluated on full matches only.
- **Sightings**: every `partial` or `edge` placement of any helper template is a
  *sighting*, with the set H of its hit pixels. A sighting is *explained* only
  when every pixel of H lies on the ink of a helper identified `full` in the
  same capture, i.e. on a pixel where that helper's rendering, at its
  identified placement, has alpha > 0; otherwise it is *unexplained*.
  Proximity alone never explains a sighting: a member sliver next to an
  identified glyph puts hit pixels outside that glyph's ink and stays
  unexplained (Codex r1). Sightings are anonymous: which template produced
  them is recorded, never used.
- **Verdict per attempt** "oracle sees a member" = any capture has a member
  `drawn(full)` outside notch columns, **or any unexplained sighting**. This
  is fail-closed: a sighting can only add "sees a member", never remove it.
  Consequence stated, not fixed: an unexplained sighting of a visible helper's
  own sliver (e.g. a visible helper cut by an agent frame) reads as a member;
  such a helper also fails its positive control, so that attempt is
  inconclusive as well, and a granted attempt with it is NO-GO as registered.
- **Controls** (positive and member): unchanged, `drawn(full)` as registered.
- The edge rule's 4 px floor and the slivers residual of section 3 stand:
  below 4 visible on-px the rule guarantees nothing.

### C2. Texture: bounded by scope, not by a colour rule (F3, F4)

Round 2 (Codex) showed that no per-pixel colour rule separates weak
neighbouring ink (a 10 % antialias edge) from texture that moves the same way:
both are small displacements of b toward the ink. The hit and false tests
therefore stay **exactly as registered**, and texture is kept out of the
certified scope instead:

- **Texture bound (added to rule 1, fail-closed)**: a baseline is accepted
  only if every pixel of every kept capture's region, outside notch columns
  and agent frames, lies within `T_o` / 2 = 12 (max-channel) of one colour,
  the region median M_x. Otherwise no baseline (cause "texture", counted in
  the fallback rate like any refused baseline).
- Why it suffices (INFERRED, by the triangle inequality): in the hidden state
  the region is backdrop; if every backdrop pixel is within 12 of M_x, so is
  the per-channel median b of any subset of them, so no backdrop off-pixel is
  farther than 24 = `T_o` from b: texture yields no false and no phantom hit.
  An observation whose backdrop changed is already not clear (`RegionClear`,
  U16), and the oracle is not needed to grant it.
- Consequence: bars like K2's (red grid wallpaper) are refused, never
  certified. S10 items are split by the bound computed on the item's own
  backdrop (without glyphs): in scope -> the exact expectations of C6; out of
  scope -> C4's fail-closed expectation.

### C3. Overlap (F2): enforced for every helper, not assumed

The oracle cannot see a glyph whose box holds another glyph's ink (S4), so
certification requires that no two helpers' drawn areas overlap, checked per
capture. AX frames cannot check it (a hidden item's AX frame overlaps others:
MEASURED `20260918-204150-m-mid/samples.jsonl`, spacer x 480 w 542 and target
x 1008 in one read). Instead:
- **Overlap guard (added, fail-closed)**: at each capture the runner reads
  the window server's list for **every** helper's status-item window (by the
  helper's PID). The attempt is inconclusive if any helper has no listed
  window, or any two helpers' on-screen bounds overlap by more than 0.5 pt.
  No helper is exempt because it is expected hidden.
- S0 must MEASURE, for visible and hidden helpers alike, that each helper's
  status-item window is listed and that visible helpers' bounds match their AX
  frames within 1 pt. If hidden helpers are not listed, or bounds do not
  match, the guard cannot be satisfied: the sitting stops before S-adv and
  the owner decides (no certification without the guard).
- S4 stays; each item carries the pair's window bounds (overlapping by 4 pt)
  and its expectation is the attempt verdict: **inconclusive**. The S12
  adjacent pairs stay conclusive and fully identified.

### C4. Out-of-scope textures (F3)

For S10 items outside the texture bound (C2), including value noise A = 32:
**never clean when a member is visibly drawn** -- for every item with a member
placed with at least 4 visible on-pixels, the attempt verdict sees a member or
is inconclusive; for the other items, any outcome except `«` present. Exact
labels are not required there.

### C5. `«` (b): validated live, in scope (F4)

Every recorded chevron is on a textured bar outside the C2 scope (K1-K3, and
the unlabelled m-narrow / m-wide captures of the same sitting), so no recorded
capture can validate (b) where it is used. Instead:
- K1 stays the template source. K2 stays in the corpus with expectation
  "outside the texture bound" (the bound computed on K2's region with its
  chevron's AX frame removed), no longer `«` present; K4 keeps `«` absent.
- **Live (b) control (added)**: in S0 and S-adv, every capture whose read
  shows `«` by (a) must also show it by (b). One miss: (b) is invalid, the
  sitting stops before S1 and the owner decides. At least 10 such captures
  from at least 2 separate `«` episodes are required before S1; fewer: the
  sitting stops (the S-adv rest state with `«` up is extended until they are
  collected, within its time box).
- (b)'s other direction (a chevron drawn before AX lists it) stays what the
  rule is for, and is not certified by this control.

### C6. Corpus and tests

- Corpus 2: the recipe of the instrument plan with S2/S3/S5/S13 and in-scope
  S10 expected per C1 (identity for n = all of P; for 4 <= n, at least one
  unexplained sighting whose box overlaps the glyph's visible columns; for
  n < 4, a sighting allowed, not required; no other helper identified;
  capture conclusive), S4 per C3, out-of-scope S10 per C4, K per C5. **New
  seeds** (seed salt `corpus-2` in every item's seed).
- Development: while implementing C1-C3 the oracle may be run on a
  development corpus (salt `dev`) and on freeze 1, never on corpus 2. Corpus
  2 is frozen and committed before its first oracle run; that single run is
  the result.
- Unit tests added before the code: U22b (sightings: explained only by ink
  pixels of a full helper, anonymous, verdict fail-closed; the adversarial
  case of a full visible helper with a >= 4 px member sliver touching it ->
  unexplained); U9b (texture bound: 12 accepted, 13 refused, notch and agent
  columns excluded); U22d (overlap guard: overlap 0.5 / 0.6 pt, a helper not
  listed, a hidden helper listed); U22e (live (b) control: a miss invalidates,
  9 captures or 1 episode insufficient); U21 over corpus 2.
- Freeze 1 and its `check.json` are kept unchanged as evidence.
- Audit: the instrument plan's section 8 gets a row, committed before any
  oracle call on corpus 2, with corpus 2's `freeze.json` sha256, the source
  commit, and a reference to freeze 1; the single result is a separate row.
- Order (thecure, Codex converged 2026-10-01; the owner's 3-part split kept):
  1. owner approval -> copied into the pre-registration's section 9, re-hashed;
  2. part 1: TDD of C1 (U22b) and of the pure decision functions corpus 2
     needs, all in `IceBarOracle`, standard library: `TextureBound` (C2, U9b),
     `OverlapGuard` (C3, U22d), `BControl` (C5, U22e) -- `BControl` returns a
     reasoned outcome (valid / insufficient captures / insufficient episodes /
     mismatch), not a Boolean, so the runner can apply C5's stops; corpus 2
     generator using them; freeze corpus 2 + section 8 row; one check;
  3. part 2 wires rule 1 to that same `TextureBound` symbol (no copy), with an
     integration test of the call site;
  4. part 3 wires the runner to `OverlapGuard` (window-server bounds per
     capture) and `BControl` (S0, S-adv), each with an integration test; the
     pre-S0 freeze manifest hashes all of them;
  5. S0 / S-adv live controls (C3 availability, C5), then S1.

### C7. Explicit amendments to section 6's gate (Codex r3: owner decisions)

1. **"Must label 100 % correctly before S0"** now reads: every corpus-2 item
   meets its expectation as written in C1-C6, where the expectation of
   out-of-scope S10 items (C4) and of S4 (C3) is a verdict predicate, not an
   exact label per helper. Any item failing its expectation blocks S0, as
   registered.
2. **`«` (b) is qualified in two steps**: before S0, the corpus items S14
   (synthetic, flat dark backdrop, in scope; expected `«` present by (b), as
   registered) and K1 (`«` present; tautological, kept as registered), K4
   (`«` absent) and K2 (outside the texture bound, C5); then live, in scope,
   by C5's control during S0 and S-adv, before S1. (b) certifies nothing in S1
   or later unless both steps passed. K3 stays one item with K2.

## 3. What does not change

`T_o` = 24 and every threshold of sections 3 and 5; the hit and false tests;
the placement search; the edge rule's eligibility; `«` (a); positive and
member controls; sections 2, 4 and 8; U1-U20, U23, U24 (rule 1 gains the
texture bound as an added refusal, tested by U9b).

## Review record (Codex gpt-5.6-terra; cap of three rounds set in round 2)

| round | findings | outcome |
|---|---|---|
| 1 | 6 P1 (C1 proximity explanation; C2 ink-side hits; C3 inferred boundary; C4 sub-4 px; C5 labelling independence and vacuous set; C6 audit rows) | C1 pixel-level explanation; C2 hits unchanged; C3 window guard; C4 >= 4 px; C5 blinded selection; C6 section 8 rows |
| 2 | 3 P1 (C2 falses rule still inequivalent on flat backdrops -- counterexample, weak neighbouring antialias; C3 hidden helpers exempt; C5 model labels not ground truth, set may be vacuous) | C2 colour rule withdrawn, texture bound in rule 1 instead; C3 no exemptions, S0 measures hidden helpers too; C5 live (b)-vs-(a) control in scope |
| 3 | 2 P1, both "amend section 6 explicitly, owner decides" (predicate expectations for out-of-scope items; (b) qualified partly live) | written as C7; the decision is the owner's. Codex confirmed the texture-bound argument and the closed C3 gap |

Trend: 6 -> 3 -> 2 P1, the last two being owner decisions, not defects.

thecure (2026-10-01, owner-invoked): Codex judged C7.1 and C7.2 **right** on
the evidence; whole-package check: no contradiction across C1-C7, one order
error (corpus 2 needs C2/C3/C5's decision functions before its freeze) --
accepted, fixed as the order in C6 with the part split kept; Codex added a
single shared `TextureBound` symbol and a reasoned `BControl` outcome, both
adopted. Converged.
