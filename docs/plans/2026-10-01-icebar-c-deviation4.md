# Route C pre-registration, deviation 4 (draft): out-of-scope textures; corpus 3

2026-10-01 · branch `wip/icebar-c` · **draft for the owner, not in force** ·
amends `2026-09-30-icebar-c-prereg.md` (sha256 `bde8a4bf…`, v3 + deviations 1-3):
deviation 2's C4 and C6 (corpus 2 -> corpus 3).

## Why (MEASURED)

- **F1, checker defect** (found by /simplify in the post-implementation review):
  `CorpusCheck.label` (`Sources/IceBarCorpus/Freeze.swift:91`) gave the oracle no
  helper templates whenever `expected.helpers == nil`, a sentinel meant for K
  items but also set for S4, S9 and every out-of-scope S10 item. For those 2780
  of corpus 2's 5749 items the references could not be found, the positive
  control missed, and the verdict was inconclusive by construction: their pass
  is vacuous. Corpus 2's result is withdrawn for them (instrument plan section 8
  row 9); the other 2969 items were checked with all templates.
- **F2, C4 falsified** (development corpus, salt `dev`, one-line fix not
  committed): 37/5749 fail, all S10 value-noise A = 32 items: a cut member with
  >= 4 visible on-px is neither identified nor sighted (texture falses exceed the
  partial/edge limits) while the references are found, so the verdict is clean.
  S4 (overlap guard) and S9 (D15) pass once templates are given.

## Changes

**D4.1 (replaces deviation 2's C4)**: for a corpus item whose backdrop is outside
the texture bound, the expectation is **that the texture bound refuses it**: the
same `TextureBound` over the same region (notch right edge to the leftmost
reference, notch and agent columns excluded) that rule 1 applies to a live
baseline. Such a bar is never certified (no baseline, claim not granted). **No
oracle behaviour is expected or validated on refused textures**; corpus 3 shows
only that the live claim is blocked there. Reason: C2 already holds that the
oracle cannot be trusted on such backdrops; F2 shows "never clean" is false.

**D4.2 (C6 amended)**: corpus 2 is superseded by **corpus 3** (salt `corpus-3`),
frozen before its single check; freezes 1 and 2 are kept as evidence.

## Before corpus 3 is frozen (Codex, thecure 2026-10-01)

1. Fix F1: templates for every synthetic item, none for K items, chosen from
   `spec.recorded`, never from an expectation field; tests that S4, S9 and
   out-of-scope S10 items get all 19 templates and K items none.
2. `vzcorpus check` verifies the manifest's pre-registration sha256 against the
   file (recorded at freeze, not enforced so far).
3. `vzcorpus dev` refuses every frozen salt (`corpus-*`), not only `corpus-2`.
4. `--k-dir`: dropped from the documentation; `ICEBAR_K_DIR` is the only override.
5. A test that the corpus's backdrop-only `TextureBound` call uses rule 1's
   region and exclusions; part 2 adds the integration test that its live rule-1
   call site uses the same arguments.
6. This deviation approved, written to section 9 and re-hashed before corpus 3
   is generated.

## Review

Codex (gpt-5.6-terra, thecure): withdrawing corpus 2's affected result rather
than re-checking it -- right (a re-check would be a different experiment under
C6's single-check rule); replacing C4 by the texture-bound refusal -- right (a
stronger oracle expectation there would be post-hoc fitting). Biggest worry:
adaptive narrowing after a development result; answered by D4.1 stating plainly
that refused textures are no longer validated for oracle behaviour, only
blocked from certification.
