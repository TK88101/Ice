# Route C instrument, part 1 of 3: glyphs, renderer, oracle, corpus

2026-10-01 · branch `wip/icebar-c` · final (Codex converged, round 2) ·
implements `2026-09-30-icebar-c-prereg.md` v3 (sha256
`d8bf04aacf519b21442a5df59e096145f4e7fcc963d58856776aa3c378853d6f`; after its deviation 1
of 2026-10-01, `aefe17021f14bd0076494b8365e051e09d40ed65ef984a088b4eccc11867946f`), sections 5-7.

The pre-registration is not changed by this plan. Where it leaves a detail open,
section 3 below fixes it **before** the oracle first runs on the corpus; each
entry only chooses among readings the pre-registration allows. A result that
would need a pre-registered rule changed stops the work: the finding goes to the
owner, and any change is a section 9 deviation there, never an edit here.

Labels as in the pre-registration: MEASURED (file:line or run id) or INFERRED.

## 1. The three parts (order settled, not reopened)

| part | content | pre-registration tests |
|---|---|---|
| **1 (this plan)** | 13 new VZGlyphs glyphs (19 in all, pairwise distinct); scale-parameterized coverage renderer (1x, 2x); coloured (255, 0, 0) variant; the oracle (full / partial / edge, `«` (a) and (b), positive and member controls, inconclusive rules); deterministic corpus generator; corpus S1-S14 and K1-K4 labelled 100 % | U21, U22, glyph and renderer tests |
| 2 | hidden-state baseline (rule 1, contrast gate, agent-frame pairing), `RegionClear` (rules 2-3), the claim (rule 4), threshold invariants | U1-U17, U23 |
| 3 | cadence, attempts and fallback accounting; the runner (S0, S-adv, S1 wiring; vzhelper's coloured flag; roster-to-glyph manifest); pre-S0 freeze manifest (section 9 addendum, re-hash); U24 in `build.sh` | U18-U20, U24 |

Not in part 1: anything of parts 2 and 3; any run in `icetest`; any push.

**Corpus freeze before the oracle's first corpus run (pre-registration section 6,
"generator source and each output's sha256 recorded, then frozen before the
oracle first runs on them").** Part 1 generates the whole corpus, writes its
freeze record (section 4, `vzcorpus freeze`) and checkpoints it on
`wip/icebar-c` **before** any oracle call on a corpus item. After that commit the
generator, the recipe, the glyphs, the renderer and the chevron template are not
changed; a change would be a new freeze and is reported. Oracle fixes after the
first corpus run are allowed only for implementation bugs against section 5's
text, each logged in this plan's section 8 with the item that exposed it; a rule
change is a pre-registration deviation (owner). The pre-S0 manifest (oracle
source included) and its section 9 addendum stay in part 3: the owner fixed that
the pre-registration is not edited in this part.

## 2. Goals, non-goals, constraints

Goal: an oracle whose labels on the pre-registered corpus are 100 % correct, with
the glyphs, renderings and generator that part 3's freeze manifest will hash.

Non-goals: baseline acceptance, `RegionClear`, contrast gate, runner, freeze
manifest, live helpers drawing the coloured variant (part 3 wires `vzhelper`).

Constraints (owner, 2026-09-30):
- Pre-registration v3 unchanged; its sha256 is checked at the end (A5).
- `Packages/MenuBarCapture` and the detector files byte-frozen: nothing under
  `Packages/` changes (A4). The oracle reads IceCore's public types only.
- Build scratch outside `~/Documents` (iCloud xattrs break codesign; CLAUDE.md).
- Generated corpus images only under `~/IceReverse-evidence/<run id>/`; tests
  build the corpus in memory and write nothing into the repository.
- K1-K4 are read-only inputs (owner's account evidence).

## 3. Details the pre-registration leaves open (fixed here, before any oracle run)

| # | detail | fixed as | why this reading |
|---|---|---|---|
| D1 | the helper roster in the corpus | 19 templates; visible V = `reference`, `alt`, `target` (the three existing visible-helper glyphs); members = the other 16 | `target`/`reference`/`alt` are the C1/C2 visible helpers' glyphs (MEASURED `Glyphs.swift`) |
| D2 | "references drawn at x 1317 and 1350" vs a strip whose test glyph is a reference's glyph (would be a twin, i.e. inconclusive, against S1's expected label) | identities fixed in every non-empty item: 1317 is `reference`'s slot, 1350 is `alt`'s. A glyph drawn anywhere else in an item vacates its own slot (that helper has moved; the slot is left as backdrop); no slot ever changes glyph. The context's leftmost-reference origin stays 1317 | section 5: "each helper draws a **unique** glyph", so one helper in two places cannot occur live; S9 is the only registered twin. r1 (Codex) rejected a glyph swap; this keeps identities fixed |
| D3 | "empty strips: every helper `none`" (S7, S10 empty) | empty = backdrop, black notch, capsule; no reference glyphs | "every helper `none`" cannot hold with references drawn |
| D4 | notch in synthetic strips | notch columns filled (0, 0, 0) (the camera housing "captures as pure black", `StripImage.swift` BarGeometry doc) | realistic; the oracle never reads them |
| D5 | notch columns | IceCore's formula: `floor(771.5 s) ..< ceil(956.5 s)` (re-implemented: `notchColumns` is internal); pinned by a test: 1x 771 ..< 957, 2x 1543 ..< 1913, and equal to `BarGeometry.allowsSpan` column by column | the same widened columns as `BarGeometry` |
| D6 | visibility of a template pixel | visible iff inside the strip, outside notch columns, and outside the columns of every agent frame used by the edge rule (canonical set union the attempt's on-bar frames), frame columns `floor(minX s) ..< ceil(maxX s)`, not widened | S5 "under: `drawn(partial)` iff visible P >= 16" requires occluded pixels to be not visible; widening would turn S5's touching case into a cut one |
| D7 | placement grid | box origin at every integer pixel x from `-(w-1)` to `W-1`; y from `(H-h)/2 - 4` to `+4` (pixels at each scale), rounding `(H-h)/2` down | "every x offset across the whole strip, including cut boxes"; "+-4 px" |
| D8 | local backdrop b | per-channel median of the visible Q pixels (lower median for even counts); a placement with no visible Q is skipped | "median colour" |
| D9 | distance | max channel distance, alpha ignored (the frozen `RGBA.distance`, re-implemented: it is internal) | section 3 of the pre-registration |
| D10 | edge eligibility | the box's pixel span intersects `[e - 1.5 pt, e + 1.5 pt]` for some edge e in: both notch edges, x = 0, x = strip width, both edges of every agent frame used (D6) | "each edge widened +-1.5 pt"; the strip ends added in r2 |
| D11 | full / partial / edge | exactly section 5; a placement is labelled with the highest class it meets (full > partial > edge) | -- |
| D12 | best placement | highest class, then higher hit fraction, then lower false fraction, then smaller y distance from centre, then smaller x | deterministic tie-break |
| D13 | reported x | box origin in pt + 1.5 pt (the glyph's inset, `Glyphs.image` `insetBy(dx: 1.5)`); zone from the box: `notchEdge` if it overlaps notch columns, else `leftOfNotch` if it ends at or left of the notch, else `rightOfReferences` if its origin >= the leftmost reference's origin, else `region` | the positive control compares with AX `minX` + 1.5 pt (section 5); item length 12 pt = image side (MEASURED `vzhelper/main.swift:157,235`) |
| D14 | "two helpers' glyphs matching one placement" | two different helpers each with some matched placement (any class) whose box origins are within 2 pt in x (any y) | a superset of "the same placement": every exact coincidence is inconclusive, and near-coincidences too (fail-closed, as the pre-registration's added rules) |
| D15 | "one helper matching two placements more than 2 pt apart" | a helper's matched placements (any class) span more than 2 pt in x | literal |
| D16 | chevron template from K1 | K1, scale 2, columns of its AX frame (x 976.5, w 17.5; `labels.json` "oracleValue", MEASURED) widened 2 px each side, all rows. Per pixel `a = clamp((min(r,g,b) - m) / (255 - m))`, m = median of `min(r,g,b)` over the cut; `a < 0.2` set to 0 (the red backdrop's texture); then cropped to the rows and columns with `a > 0` plus 2 px of margin. P: a >= 0.5, Q: a = 0 (section 5's sets) | a white chevron on a red textured bar (MEASURED, crop of K1); the 0.2 floor is recorded with the template |
| D17 | chevron at scale 1 | not evaluated; the oracle reports `«` (b) as `notEvaluable` at scale 1, and S14 is generated at scale 2 only | "No 1x chevron is on record" (section 5) |
| D18 | K items | the oracle runs with no helper templates (their markers are not VZGlyphs), no AX reads, the manifest's notch (771.5-956.5, MEASURED `manifest.json`); expected: only `«` | section 6 |
| D19 | generator choices the recipe leaves open | S1 all 19 x 3 zones x 4 colour cases (D20); S2 all 19 x 25/50/75 % x both notch edges x 4 colour cases; S3 all 19 x both ends x 4 colour cases; S4 all 342 ordered pairs (A left, B right, overlapping 4 pt), white on dark; S5 all 19 x touching/under, white on dark; S6 all 19, ordinary and coloured, on dark and light; S8 one strip per backdrop (dark, light); S9 each of the 19 as a twin (second copy 30 pt right), white on dark; S10 each of the 4 textured backdrops: empty, plus **every** S1 and S2 case with white and coloured ink (black ink is not drawn on these mid/dark backdrops; D22); S11 all 19 x 3 y offsets, white on dark; S12 the 19 cyclic roster triples 1 pt apart, and the 19 cyclic pairs (glyph i ordinary, glyph i+1 coloured) adjacent, on dark and light; S13 **every** glyph x cut x count for which the count is exactly reachable by an integer-pixel offset along the cut (y within +-4 px); unreachable combinations are listed in the manifest, and a (cut, count) reachable by no glyph is a generator failure, not a skip; S14 as written, at scale 2. Every S item at scale 1 and 2 unless stated | exhaustive where the recipe names a set, mechanical elsewhere; fixed before the corpus is generated (r1: Codex asked for all pairs, colours and glyphs) |
| D20 | colour cases | ordinary: white (255) on (40, 40, 40), black (0) on (235, 235, 235); coloured: (255, 0, 0) on both | S1 |
| D21 | half alpha | coverage x 0.5 before compositing | S6 |
| D22 | noise | SplitMix64, seed per item from its id; S7: +-6 uniform per pixel on (40, 40, 40); S10 value noise: lattice 8 pt, smoothstep interpolation, value in [-A, +A] on (90, 90, 90) grey, A = 16 and 32; diagonal gradient (40,40,40) -> (110,110,110) along x + y; blue -> orange as written, along x | amplitude read as the largest deviation (the stricter reading) |
| D24 | S2, S3 labels vs the edge rule and S13 | resolved by pre-registration **deviation 1** (owner approved 2026-10-01): by visible on-px n, all of P -> `full`; n >= 16 -> `partial`; 4 <= n < 16 -> `edge`; n < 4 -> `none`. S5 "under" follows the same rule as a reading (Codex r3) | Codex r3 P1: a change, so made as a deviation before the corpus exists |
| D25 | comparing a label with its expectation | class, zone and helper exact. x within the 2 pt position tolerance (registered for corpus labels by deviation 1). Where the recipe says only "drawn" or "found as itself" (S4, S8, S12) any class is accepted; S1, S5 touching, S6, S11 require `full` as written. S9 is checked for inconclusive only. K2 and K3 are one item (identical bytes, "kept as one item") | literal wording of each row |
| D23 | capsule | 20 pt x 18 pt violet (130, 90, 250) rounded rect (radius 9 pt), vertically centred, drawn over glyphs; its frame is the canonical agent frame given to the oracle; not chevron width, so no `«` (a) | stand-in, section 6 |

## 4. Design

New and changed code, all under `docs/macos-27/probes/visibility` (not linked into Ice):

- `Sources/VZGlyphs/Glyphs.swift` (changed): 13 new `Glyph` cases, drawn by the
  same `draw(_:in:)` rule (stroked, open, accented, `lineWidth` 1.6, round caps);
  `image(_:side:coloured:)`, where `coloured: true` returns a non-template
  image stroked in sRGB (255, 0, 0). Existing cases unchanged stroke for stroke.
- `Sources/VZGlyphs/GlyphRenderer.swift` (new): `GlyphRenderer.coverage(_:scale:coloured:)`
  renders `Glyphs.image` into a bitmap at scale 1 or 2 and returns
  `GlyphCoverage` (side in px, alpha per pixel top row first, and the rendered
  RGB for the coloured path). Derived from `GlyphCheck.coverage`, which now calls it.
- `Sources/VZGlyphs/GlyphCheck.swift` (changed): layout grows to the 19 glyphs
  (the frozen `StripAssessor.baseline` must still accept all and refuse the twin).
- `Sources/IceBarOracle/` (new target; standard library + IceCore's public
  `StripImage`, `AgentFrame`, `DetectorParameters`): `OracleTemplate` (P/Q masks
  from any alpha grid), `OracleContext` (scale, notch, agent frames, leftmost
  reference origin), `Oracle.label(image:templates:context:)` -> per-helper label
  plus `inconclusive` reasons, `ChevronRule` ((a) on AX reads, (b) with the
  template), `ChevronTemplate.cut(from:frame:)` (D16), `Controls` (positive and
  member), `AttemptVerdict` (sees member, sees `«`, inconclusive).
  Speed without changing the rule: a placement whose visible box pixels have a
  per-channel range <= `T_o` cannot have a hit (b lies within that range), so it
  is skipped; sound, and tested against the unpruned search.
- `Sources/IceBarCorpus/` (new target; VZGlyphs, IceBarOracle, IceCore,
  ImageIO): `CorpusRecipe` (S1-S14 per D19, K1-K4), `CorpusItem` (id, image,
  context, expected), `CorpusCheck` (runs the oracle, compares, lists
  mislabels), `PNGIO` (decode K items, encode outputs), `SplitMix64`.
- `Sources/vzcorpus/main.swift` (new executable), two subcommands, both refusing
  an output directory inside the repository:
  - `vzcorpus freeze --out <dir> [--k-dir <dir>]`: generates every item, writes
    its PNG and `freeze.json`; runs **no** oracle matching. `freeze.json` schema:
    `runId`, `gitRevision` (must be clean), `sources` (sha256 of every file of
    `VZGlyphs`, `IceBarCorpus`, `IceBarOracle`, `vzcorpus`, by path),
    `renderings` (per glyph, scale 1 and 2, ordinary and coloured: sha256 of the
    alpha bytes and of the coloured RGB bytes), `chevronTemplate` (source K1
    sha256, frame, floor 0.2, sha256 of the alpha grid), `kInputs` (path,
    expected sha256, measured sha256), `items` (id, recipe row, scale, expected
    labels, sha256 of PNG and of raw RGBA), `unreachable` (S13). A test checks
    every key is present and non-empty.
  - `vzcorpus check --freeze <dir>/freeze.json`: verifies every hash except the
    `IceBarOracle` and `vzcorpus` sources (recorded for provenance; oracle bug
    fixes are logged in section 8, not blocked), then runs
    the oracle on each item and writes `check.json` (id, expected, got);
    prints one line per mislabel and a total; exit 0 only when every item is
    correct and every hash matched.
- Tests: `VZGlyphsTests` (renderer, coloured, distinctness), `IceBarOracleTests`
  (rules, U22), `IceBarCorpusTests` (determinism, U21).

## 5. Tasks (TDD: each test written and seen failing before its code)

| # | task | DoD |
|---|---|---|
| T1 | renderer tests: scale 1 -> 12 x 12, scale 2 -> 24 x 24 alpha; scale 2 equals today's `GlyphCheck.coverage` output for the 6 existing glyphs; coloured alpha equals ordinary alpha, coloured RGB at alpha > 0.5 is (255, 0, 0) +-1; a scale other than 1 or 2 is refused | red, then green with `GlyphRenderer` |
| T2 | glyph tests: 19 cases; every glyph has P >= 16 px at scale 1 and Q > 0; no two glyphs match each other under the oracle's full rule at any relative offset where one's P is fully inside the other's box (scales 1 and 2, white on dark); `GlyphCheck.run()` passes with 19 | red, then green with the 13 glyphs (designs iterated only against this test) |
| T3 | oracle unit tests: full / partial / edge boundaries (90 %, 10 %, 16 px, 4 px, 100 %, 0 false); visibility (notch, strip ends, agent columns); edge eligibility window +-1.5 pt; b as median; zone and x (D13); inconclusive D14/D15; chevron (a) width 17.5 +- 0.5 on-bar only; (b) not evaluable at scale 1; pruning equals exhaustive search on random strips | red, then green |
| T4 | U22: a visible helper not `drawn(full)` within 2 pt of AX `minX` + 1.5 -> attempt inconclusive; a member not found at a rest control -> cycle inconclusive; edge rule at 3 / 4 visible on-px; attempt verdict: member seen in any capture, `«` in any capture or read | red, then green |
| T5 | corpus generator tests (no oracle matching): same seed -> byte-identical images; every S13 count reached exactly; S2/S5 expected labels follow the generator's own visible-P count (computed with the oracle's visibility function only); K items' sha256 equal the pre-registered ones; `freeze.json` schema complete | red, then green |
| T6 | freeze: `vzcorpus freeze` into `~/IceReverse-evidence/<run id>/`, `freeze.json` hash copied into section 8, checkpoint commit on `wip/icebar-c`. No oracle call on a corpus item before this commit | commit exists; section 8 row |
| T7 | U21: `vzcorpus check` and the `IceBarCorpusTests` U21 test (which regenerates in memory and asserts every hash equals `freeze.json`'s before labelling) | every S1-S14 and K1-K4 item labelled as expected, or stop (section 7) |

Parallel candidates: none (each task consumes the previous one's output).

## 6. Acceptance

| # | check | how |
|---|---|---|
| A1 | new suites green | `swift test --scratch-path /private/tmp/claude-501/icebar-c1 --filter 'VZGlyphsTests\|IceBarOracleTests\|IceBarCorpusTests'` (U21 may run in `-c release -Xswiftc -enable-testing` if debug takes > 10 min; recorded) |
| A2 | line coverage >= 80 % for `IceBarOracle`, `IceBarCorpus`, `GlyphRenderer.swift` | `--enable-code-coverage`, `llvm-cov report` |
| A3 | corpus frozen first, then 100 % | the freeze commit precedes the first `check.json`; `vzcorpus check` exit 0, "0 mislabels"; `git status` shows no image in the repository |
| A4 | freeze | `git diff --exit-code af4baf1 -- Packages/MenuBarCapture`; `git diff --exit-code 32d523a -- Packages` |
| A5 | pre-registration unchanged since deviation 4 | `shasum -a 256` = `e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3` |
| A6 | nothing else broken | full probe `swift test` (I7 group about 7 min); `build.sh <scratch>` builds |

Coverage: unit (T1-T4), integration (T5, T7 test: generator + renderer +
oracle), E2E (T6-T7: the executable writing real files, the freeze and the check).

## 7. Risks and what happens then

- **R1 (INFERRED, high): the edge rule and the ambiguity rule may collide.** A
  4 px sliver, or S2's 75 %-inside case, can be matched by another glyph with the
  same edge stroke (many glyphs end in a vertical post), making the capture
  inconclusive where S2/S13 expect `drawn`. Likewise S4's 4 pt overlap puts the
  neighbour's ink into each box's Q (false may exceed 10 %), and `«` (b)'s edge
  rule may fire on a glyph sliver. Glyph design can reduce shared edges but not
  remove them. **If U21 fails for such a case**, no rule and no corpus item is
  adjusted to pass: the failing items, their labels and the counts go to the
  owner, work stops, and any change is a section 9 deviation of the
  pre-registration, decided by the owner.
- R2: K2's textured red backdrop may put > 10 % of the chevron's Q over the
  texture (false). Same handling as R1.
- R3: search cost (about 6e5 placements per 2x strip). Mitigation: the sound
  range prune (section 4), release-mode U21 if needed. Not a rule change.
- R4: a new glyph fails IceCore's template rules in `GlyphCheck` (e.g.
  `tooLittleBackground`). Redesign the glyph (T2); the frozen rules are not touched.
- Rollback: everything is new files plus `Glyphs.swift`/`GlyphCheck.swift`
  additions on `wip/icebar-c`; `git checkout 32d523a -- docs/macos-27/probes/visibility`.

## 7a. Part 1 under deviation 2 (pre-registration section 9 row 2; `2026-10-01-icebar-c-deviation2.md`)

| # | task | DoD |
|---|---|---|
| T8 | oracle C1: `CaptureLabels.labels` from `full` only; D14/D15 on `full` only; `sightings` = every `partial`/`edge` placement of any helper template with its box and hit pixels; *explained* iff every hit pixel is on alpha > 0 of a `full`-identified helper at its best placement; `AttemptVerdict.seesMember` = member `full` or any unexplained sighting | existing rule tests rewritten to the new labels (edge/partial cases assert sightings), U22b (explained / unexplained; adversarial: full visible helper plus a >= 4 px member sliver touching it -> unexplained, sees a member) red then green |
| T9 | `TextureBound.evaluate(image, region, notch, agent frames)` -> accepted / refused(max deviation), every region pixel outside notch and agent columns within 12 of the per-channel lower median M_x | U9b: 12 accepted, 13 refused, deviations only in notch or agent columns accepted |
| T10 | `OverlapGuard.evaluate(roster, bounds)` -> clear / missing(id) / overlap(a, b); overlap = both axes intersect by > 0.5 pt; `AttemptVerdict` takes the guard outcome, inconclusive unless clear | U22d: 0.5 clear, 0.6 overlap, a roster helper with no bounds -> missing, a hidden (off-screen) helper listed -> clear |
| T11 | `BControl.evaluate([(episode, a, b)])` -> valid / mismatch(index) / insufficientCaptures(n) / insufficientEpisodes(n); only captures with (a) count; mismatch first; >= 10 captures, >= 2 episodes | U22e |
| T12 | corpus 2: seed salt `corpus-2` (dev salt `dev`), recorded per item. Per-item expectation: (i) identity labels exact (`full` or `none`); (ii) **for each** placed glyph with 4 <= n < all of P: at least one unexplained sighting whose box overlaps **that glyph's** visible columns; (iii) exact mode only (added strictness): every unexplained sighting's box overlaps the visible columns of some placed glyph (no widening); (iv) `seesMember`: yes if any member is identified or any placed glyph has 4 <= n < all of P; either only if neither holds and some placed glyph has n < 4; else no; (v) `inconclusive` exact; (vi) `«`: exact for S items (S14 present), K1 present, K4 absent, K2 not asserted. Mode per item from `TextureBound` on the item's backdrop-only rendering (region 956.5-1317 pt, capsule frame excluded): accepted -> exact; refused -> C4 predicate. **Guard input: all 19 helpers every item** -- placed glyphs at their boxes, every other helper listed off-screen (x < 0, disjoint); S4's pair overlaps by 4 pt -> expected inconclusive. **Positive controls**: each slot reference carries a synthetic AX `minX` = its slot x and is checked `drawn(full)` within 2 pt of `minX` + 1.5 pt. K2: rule 1's region for that run is notch right edge to the leftmost reference, x 956.5-1008 pt (1008 = the run's target helper, MEASURED `samples.jsonl` ownAX; fixed before any `TextureBound` run on K2), minus the chevron's AX frame (outside that span for K2); expected refused. The check evaluates the attempt verdict per item (one capture, no AX reads) | generator tests updated first; corpus 2 frozen and committed (section 8 row) before its single check |

Section 7a review (Codex): r1 4 P1 + 1 P2 (either scope, per-glyph sightings, full guard roster, K2 region and chevron assertion; synthetic AX controls) -> all accepted except the K2 region (kept at the run's own rule 1 region 956.5-1008 pt, fixed before evaluation; Codex r2 agreed) -> r2 CONVERGED.

Development runs of the new oracle: on the development corpus (salt `dev`) and freeze 1 only; never on corpus 2 before its freeze row.

## 8. Freeze and oracle-change log

| # | date | event | hash / item | reason |
|---|---|---|---|---|
| 1 | 2026-10-01 | stop before T5/T6: pre-registration deviation 1 proposed (D24, D25) | -- | S2/S3 literal labels contradict section 5 + S13 |
| 2 | 2026-10-01 | deviation 1 approved by the owner, written to the pre-registration's section 9 | `aefe17021f14bd0076494b8365e051e09d40ed65ef984a088b4eccc11867946f` | -- |
| 3 | 2026-10-01 | corpus frozen (T6): `vzcorpus freeze`, run `20260930-102852-icebar-corpus`, source commit 54f63b9, 5749 items (S1 456, S2 912, S3 304, S4 684, S5 76, S6 152, S7 8, S8 4, S9 38, S10 2744, S11 114, S12 152, S13 99, S14 3, K 3); 471 S13 (glyph, cut, count, scale) combinations unreachable, every (cut, count, scale) reached by some glyph. No oracle call on a corpus item before this row's commit | freeze.json `56950a141074c77aa97439330b35f5caad047f31bf838f1ff76899db98ef9550` | -- |
| 4 | 2026-10-01 | first oracle run on the frozen corpus (T7, `vzcorpus check`): **2144 of 5749 mislabelled; U21 fails; S0 blocked** (section 6). Passing rows: S1, S6, S7, S8, S9, S11, S12, S14, K1, K4 (all items). Failing: S2 412/912, S3 96/304, S4 539/684, S5 23/76, S10 1019/2744, S13 54/99, K2. Causes (MEASURED from `check.json`, no oracle bug found): (a) at a cut (notch, strip end, capsule) the visible part of one glyph is a shared stroke (a post, a bar end) that other glyphs' templates match as `partial`/`edge`, so those helpers are labelled drawn and the capture is inconclusive (D14/D15) -- risk R1; (b) S4: a 4 pt overlap puts the neighbour's ink in the second glyph's Q, false > 10 %, second glyph `none`; (c) S10 value noise A = 32: phantom `partial`/`edge` matches on bare texture at the strip start, and references missed; (d) K2: the K1 chevron template hits 169/169 on-px but 76/577 (13.2 %) off-px over the red grid texture, above the 10 % false limit -- risk R2. Work stopped for the owner; no rule, recipe or expectation changed | check.json `981530ae27e8709c0c563108632d1ffb7490392d877743aa992b0295388da062` | pre-registered rules, not implementation |
| 5 | 2026-10-01 | deviation 2 approved by the owner and written to the pre-registration's section 9; part 1 continues under it (C1, `TextureBound`, `OverlapGuard`, `BControl`, corpus 2) | `bb10b671205ce3a1fa8c5dcfb994a57558ee81424a5ee91ad45632c75f3de0f2` | freeze 1 kept as evidence |
| 6 | 2026-10-01 | development run (salt `dev`, run `20260930-113108-icebar-dev`): 7/5749 failing; deviation 3 drafted, approved by the owner, written to section 9 (D3.1 ambiguous chevron slivers, D3.2 cut-glyph identity, which also amends T12 (i)/(ii)) | `bde8a4bf5176249ae95c65de6f15abb3611a972202e0e31b55e3a46b08b8bfb8` | corpus 2 still not generated |
| 7 | 2026-10-01 | corpus 2 frozen (deviation 2 C6): `vzcorpus freeze --salt corpus-2`, run `20260930-121331-icebar-corpus2`, source commit 42fc538 (pre-registration `bde8a4bf…`), 5749 items, 471 S13 combinations unreachable; freeze 1 (row 3) kept as evidence. No oracle call on a corpus-2 item before this row's commit | freeze.json `027570dfa86a1a8c6de5ff906dabc3030d3856ba9e891ecb3431f6fa3f470260` | -- |
| 8 | 2026-10-01 | corpus 2's single check (`vzcorpus check`): **0 of 5749 items fail their expectation**; every hash verified before labelling. U21 (the same frozen items through the test target) re-run as the acceptance path, not as a second result | check.json `1844ac22b38a002ac26f4528af9a60b95a21cd3db3f483bdcc6887c1763c7c09` | -- |
| 9 | 2026-10-01 | **corpus 2's result withdrawn for 2780 items** (S10 fail-closed 2058, S4 684, S9 38): /simplify found `CorpusCheck.label` (`Freeze.swift:91`) gave the oracle no helper templates whenever `expected.helpers == nil`, a K-item sentinel also set for those items, so their verdict was inconclusive by construction (the references could not be found). The other 2969 items were checked with all templates and stand. Development corpus with the one-line fix (not committed; salt `dev`): 37/5749 fail, all S10 A = 32 fail-closed items, "clean while a member is drawn" (texture falses keep a cut member from being sighted). Freeze 2 and its check.json kept as evidence; deviation 4 drafted; work stopped for the owner | -- | implementation defect in the checker; C4 falsified on the development corpus |
| 10 | 2026-10-01 | deviation 4 approved by the owner, written to section 9 | `e693654c39f61313ce37fb36a547b3cf9a30083136960ea2cbdbcb39e63eb7e3` | corpus 3 next |

## Appendix. Review record

### Round 1 (Codex gpt-5.6-terra): 1 P0, 3 P1, 3 P2

| finding | ruling | change |
|---|---|---|
| P0 corpus must be frozen before the oracle first runs on it; plan deferred all freezing to part 3 | accepted, modified | `vzcorpus freeze` + checkpoint before any oracle call on a corpus item (section 1, T6, T7, A3, section 8). Rejected: appending the addendum to the pre-registration now (owner: no edits this part; the pre-registration puts it "before S0") |
| P1 D14 narrows "one placement" with a 2 pt tolerance | rejected | D14 is a superset of exact coincidence (more inconclusive, not less); y limit dropped. Codex r2 agreed |
| P1 S10 reduced to 3 glyphs' S2 cases | accepted | every S1 and S2 case on each textured backdrop |
| P1 D2 swaps a reference's glyph to pass | modified | fixed slots; a glyph drawn elsewhere vacates its own slot (unique-glyph premise of section 5). Codex r2 agreed |
| P2 S3/S4/S12/S13 thin selections | accepted | 4 colour cases; all 342 ordered pairs; cyclic sets over 19; every reachable S13 glyph |
| P2 manifest schema undefined | accepted | `freeze.json` schema, tested |
| P2 notch conversion not pinned | accepted | endpoint test at 1x and 2x vs `BarGeometry` |

### Round 2: 0 P0, 0 P1 -- CONVERGED

Trend: r1 1 P0 + 3 P1 + 3 P2 -> r2 none. Codex accepted both rejections/modifications.

### Round 3 (scoped to D24, D25, added before the corpus freeze): 1 P1, 1 P2

| finding | ruling | change |
|---|---|---|
| P1 D24 changes S2/S3's registered "else none" | accepted | D24 blocked; pre-registration deviation 1 proposed to the owner; work stopped before the freeze |
| P2 D25: 2 pt tolerance registered only for controls; S9 "no `«`" added | accepted | tolerance folded into deviation 1's proposal; S9 checks inconclusive only |
